import 'dart:async';
// import 'dart:io'; // unused
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:actionmail/data/repositories/message_repository.dart';

/// Firebase sync service for cross-device data synchronization using Firestore
/// Minimal traffic design: only syncs changed metadata, not full emails
/// Singleton pattern to ensure single instance across the app
class FirebaseSyncService {
  static final FirebaseSyncService _instance = FirebaseSyncService._internal();
  factory FirebaseSyncService() => _instance;
  FirebaseSyncService._internal();
  
  static const String _prefsKeySyncEnabled = 'firebase_sync_enabled';
  // ignore: unused_field
  static const String _prefsKeyUserId = 'firebase_user_id';
  
  FirebaseFirestore? _firestore;
  CollectionReference? _userCollection;
  DocumentReference? _userDoc;
  CollectionReference? _emailMetaCollection; // Subcollection for email metadata
  String? _userId;
  bool _syncEnabled = false;
  final Map<String, StreamSubscription> _subscriptions = {};
  Timer? _pollTimer; // Polling timer instead of real-time listener
  final Map<String, dynamic> _initialValues = {}; // Track initial values to avoid syncing on load
  final Map<String, Map<String, dynamic>> _lastKnownDocs = {}; // Track last known document versions for polling
  // Retry state for delayed initialization when Firebase isn't ready yet
  Timer? _initRetryTimer;
  int _initRetryCount = 0;
  static const int _maxInitRetries = 5;
  // No longer need to track last processed emailMeta - each document change is independent
  // Sender preferences are no longer synced, so no tracking needed
  
  // Callback to notify UI when updates are applied from Firebase
  void Function(String messageId, String? localTag, DateTime? actionDate, String? actionText)? onUpdateApplied;

  /// Initialize Firebase (call this early in app lifecycle)
  /// Returns false if Firebase is not configured
  Future<bool> initialize() async {
    try {
      // Check if Firebase apps are initialized
      final apps = Firebase.apps;
      if (apps.isEmpty) {
        debugPrint('[FirebaseSync] ERROR: Firebase apps is empty - Firebase not initialized');
        debugPrint('[FirebaseSync] On desktop, you MUST run: flutterfire configure');
        debugPrint('[FirebaseSync] This generates lib/firebase_options.dart');
        return false;
      }
      
      _firestore = FirebaseFirestore.instance;
      debugPrint('[FirebaseSync] Initialized successfully, _firestore: ${_firestore != null}');
      return _firestore != null;
    } catch (e) {
      debugPrint('[FirebaseSync] Initialization error (Firebase may not be configured): $e');
      debugPrint('[FirebaseSync] On desktop, run: flutterfire configure');
      return false;
    }
  }

  /// Check if sync is enabled
  Future<bool> isSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeySyncEnabled) ?? false;
  }

  /// Enable or disable sync
  Future<void> setSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeySyncEnabled, enabled);
    _syncEnabled = enabled;
    
    if (enabled) {
      await _initializeUserSync();
    } else {
      await _stopSync();
    }
    debugPrint('[FirebaseSync] Sync ${enabled ? "enabled" : "disabled"}');
  }

  /// Initialize user-specific sync (requires user ID)
  Future<void> initializeUser(String? userId) async {
    debugPrint('[FirebaseSync] initializeUser called with userId: $userId');
    
    if (userId == null) {
      _userId = null;
      _userDoc = null;
      _userCollection = null;
      await _stopSync();
      debugPrint('[FirebaseSync] User ID is null, stopping sync');
      return;
    }

    _userId = userId;
    final enabled = await isSyncEnabled();
    _syncEnabled = enabled;
    debugPrint('[FirebaseSync] Sync enabled: $enabled, _firestore: ${_firestore != null}');
    
    // If _firestore is null, try to initialize Firebase (in case initialize() wasn't called yet)
    if (_firestore == null) {
      debugPrint('[FirebaseSync] _firestore is null, attempting to initialize Firebase...');
      final initialized = await initialize();
      if (!initialized) {
        debugPrint('[FirebaseSync] Cannot initialize user: Firebase initialization failed');
        // Schedule a short retry to allow background Firebase.initializeApp to complete
        if (_initRetryCount < _maxInitRetries) {
          _initRetryTimer?.cancel();
          _initRetryCount++;
          final delay = Duration(milliseconds: 300 * _initRetryCount);
          debugPrint('[FirebaseSync] Scheduling initializeUser retry #$_initRetryCount in ${delay.inMilliseconds}ms');
          _initRetryTimer = Timer(delay, () {
            // Ignore await; fire and forget retry
            initializeUser(userId);
          });
        } else {
          debugPrint('[FirebaseSync] Max initializeUser retries reached; giving up');
        }
        return;
      }
    }
    
    if (_firestore != null && enabled) {
      // Reset retry state on success
      _initRetryTimer?.cancel();
      _initRetryTimer = null;
      _initRetryCount = 0;
      _userCollection = _firestore!.collection('users');
      _userDoc = _userCollection!.doc(userId);
      _emailMetaCollection = _userDoc!.collection('emailMeta'); // Subcollection for each email
      await _loadInitialValues();
      await _startListening();
      debugPrint('[FirebaseSync] User initialized: $userId, _userDoc: ${_userDoc != null}, _emailMetaCollection: ${_emailMetaCollection != null}');
    } else {
      if (!enabled) {
        debugPrint('[FirebaseSync] Cannot initialize user: sync is disabled');
      }
    }
  }

  /// Load initial values from Firebase to avoid syncing unchanged data
  /// Loads from emailMeta subcollection
  /// Ensures query is executed on the platform thread to avoid threading errors
  Future<void> _loadInitialValues() async {
    if (_emailMetaCollection == null) return;
    
    try {
      // Defer query execution until after the current frame to ensure we're on the main thread
      await SchedulerBinding.instance.endOfFrame;
      
      // Load all documents from the emailMeta subcollection
      final snapshot = await _emailMetaCollection!.get();
      
      for (final doc in snapshot.docs) {
        final messageId = doc.id;
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null) {
          final current = data['current'] as Map<String, dynamic>?;
          if (current != null) {
            final initialKey = 'emailMeta.$messageId.current';
            _initialValues[initialKey] = Map<String, dynamic>.from(current);
          }
        }
      }

      debugPrint('[FirebaseSync] Loaded initial values: ${_initialValues.keys.length} email metadata entries');
    } catch (e) {
      debugPrint('[FirebaseSync] Error loading initial values: $e');
    }
  }

  /// Start listening to Firebase changes using polling instead of real-time listeners
  /// This avoids the threading error that occurs with Firestore snapshot listeners
  /// Polls every 5 seconds to check for changes
  Future<void> _startListening() async {
    if (_emailMetaCollection == null || !_syncEnabled) return;

    try {
      // Defer polling setup until after the current frame to ensure we're on the main thread
      SchedulerBinding.instance.addPostFrameCallback((_) {
        // Double-check we're still enabled and have collection
        if (_emailMetaCollection == null || !_syncEnabled) return;
        
        // Cancel any existing timer
        _pollTimer?.cancel();
        
        // Clear last known docs when restarting
        _lastKnownDocs.clear();
        
        // Poll every 5 seconds for changes
        _pollTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
          if (_emailMetaCollection == null || !_syncEnabled) {
            timer.cancel();
            return;
          }
          
          try {
            // Poll for all documents - this is safe to do on any thread
            final snapshot = await _emailMetaCollection!.get();
            
            // Process on main thread
            scheduleMicrotask(() {
              final updatedDocs = <String, Map<String, dynamic>>{};
              
              for (final doc in snapshot.docs) {
                final messageId = doc.id;
                final data = doc.data() as Map<String, dynamic>?;
                
                if (data == null) continue;
                
                final current = data['current'] as Map<String, dynamic>?;
                if (current == null) continue;
                
                // Check if this document changed
                final lastKnown = _lastKnownDocs[messageId];
                final isChanged = lastKnown == null || 
                    !_mapsEqual(Map<String, dynamic>.from(lastKnown), Map<String, dynamic>.from(current));
                
                if (isChanged) {
                  updatedDocs[messageId] = current;
                  _lastKnownDocs[messageId] = Map<String, dynamic>.from(current);
                  
                  // Process this single email change
                  _handleSingleEmailMetaUpdate(messageId, current);
                }
              }
              
              // Remove documents that no longer exist
              final existingIds = snapshot.docs.map((d) => d.id).toSet();
              final removedIds = _lastKnownDocs.keys.where((id) => !existingIds.contains(id)).toList();
              for (final id in removedIds) {
                _lastKnownDocs.remove(id);
              }
              
              if (updatedDocs.isNotEmpty) {
                debugPrint('[FirebaseSync] Poll detected ${updatedDocs.length} changed documents');
              }
            });
          } catch (e) {
            debugPrint('[FirebaseSync] Error polling emailMeta: $e');
          }
        });

        debugPrint('[FirebaseSync] Started polling emailMeta subcollection (every 5 seconds)');
      });
    } catch (e) {
      debugPrint('[FirebaseSync] Error scheduling polling: $e');
    }
  }

  /// Stop all Firebase listeners and polling
  Future<void> _stopSync() async {
    for (final sub in _subscriptions.values) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _pollTimer?.cancel();
    _pollTimer = null;
    _lastKnownDocs.clear();
    debugPrint('[FirebaseSync] Stopped listening and polling');
  }

  /// Initialize user sync if enabled
  Future<void> _initializeUserSync() async {
    if (_userId != null && _firestore != null) {
      _userCollection = _firestore!.collection('users');
      _userDoc = _userCollection!.doc(_userId!);
      await _loadInitialValues();
      await _startListening();
    }
  }

  /// Sync email metadata (personal/business tag, action date, action message, action complete)
  /// Only syncs fields that are explicitly provided and have changed from initial value
  /// Note: Pass values to sync, null to clear (if previously set)
  Future<void> syncEmailMeta(String messageId, {
    String? localTagPersonal,
    DateTime? actionDate,
    String? actionInsightText,
    bool? actionComplete,
  }) async {
    debugPrint('[FirebaseSync] syncEmailMeta called for $messageId');
    debugPrint('[FirebaseSync]   _syncEnabled: $_syncEnabled');
    debugPrint('[FirebaseSync]   _userDoc: ${_userDoc != null ? "set" : "null"}');
    debugPrint('[FirebaseSync]   _firestore: ${_firestore != null ? "set" : "null"}');
    debugPrint('[FirebaseSync]   _userId: $_userId');
    
    if (!_syncEnabled) {
      debugPrint('[FirebaseSync] Sync is disabled, skipping');
      return;
    }
    
    if (_userDoc == null) {
      debugPrint('[FirebaseSync] _userDoc is null, cannot sync. Firebase may not be initialized.');
      return;
    }

    // Get current initial value for this message
    final initialKey = 'emailMeta.$messageId.current';
    final initial = _initialValues[initialKey] as Map<String, dynamic>? ?? {};

    // Read current local values to determine which parameters were explicitly provided
    // Strategy: If parameter is null AND local has a value, it wasn't provided (skip)
    //           If parameter is non-null OR both are null, it was provided (check against initial)
    final repo = MessageRepository();
    final localMessage = await repo.getById(messageId);
    
    // Track which fields to update - only include fields that were explicitly provided
    bool hasChanges = false;
    final current = <String, dynamic>{};
    
    // Check localTagPersonal: provided if non-null OR if both are null
    final localTagProvided = localTagPersonal != null || localMessage?.localTagPersonal == null;
    if (localTagProvided) {
      final initialTag = initial['localTagPersonal'];
      if (localTagPersonal != initialTag) {
        current['localTagPersonal'] = localTagPersonal;
        hasChanges = true;
        debugPrint('[FirebaseSync]   localTagPersonal changed: $initialTag -> $localTagPersonal');
      } else {
        debugPrint('[FirebaseSync]   localTagPersonal unchanged: $initialTag');
      }
    } else {
      debugPrint('[FirebaseSync]   localTagPersonal not provided (null param with local value: ${localMessage?.localTagPersonal}), skipping');
    }
    
    // Check actionDate: provided if non-null OR if both are null
    final actionDateProvided = actionDate != null || localMessage?.actionDate == null;
    bool actionDateChanged = false;
    if (actionDateProvided) {
      final initialDateStr = initial['actionDate'] as String?;
      final newDateStr = actionDate?.toIso8601String();
      if (newDateStr != initialDateStr) {
        current['actionDate'] = newDateStr;
        hasChanges = true;
        actionDateChanged = true;
        debugPrint('[FirebaseSync]   actionDate changed: $initialDateStr -> $newDateStr');
      } else {
        debugPrint('[FirebaseSync]   actionDate unchanged: $initialDateStr');
      }
    } else {
      debugPrint('[FirebaseSync]   actionDate not provided (null param with local value), skipping');
    }
    
    // Check actionInsightText: provided if non-null OR if both are null
    final actionTextProvided = actionInsightText != null || localMessage?.actionInsightText == null;
    bool actionTextChanged = false;
    if (actionTextProvided) {
      final initialText = initial['actionInsightText'] as String?;
      if (actionInsightText != initialText) {
        current['actionInsightText'] = actionInsightText;
        hasChanges = true;
        actionTextChanged = true;
        debugPrint('[FirebaseSync]   actionInsightText changed: $initialText -> $actionInsightText');
      } else {
        debugPrint('[FirebaseSync]   actionInsightText unchanged: $initialText');
      }
    } else {
      debugPrint('[FirebaseSync]   actionInsightText not provided (null param with local value), skipping');
    }
    
    // Safeguard: If either actionDate or actionInsightText is being updated, ensure both are synced together
    // to prevent inconsistent state (e.g., text without date or date without text)
    if (actionDateChanged || actionTextChanged) {
      // If one was updated but the other wasn't explicitly provided, include the current local value
      if (actionDateChanged && !actionTextProvided) {
        // Date was updated, include current text from local
        current['actionInsightText'] = localMessage?.actionInsightText;
        debugPrint('[FirebaseSync]   Safeguard: Including current actionInsightText: ${localMessage?.actionInsightText}');
      }
      if (actionTextChanged && !actionDateProvided) {
        // Text was updated, include current date from local
        current['actionDate'] = localMessage?.actionDate?.toIso8601String();
        debugPrint('[FirebaseSync]   Safeguard: Including current actionDate: ${localMessage?.actionDate?.toIso8601String()}');
      }
    }
    
    // Check actionComplete: provided if non-null OR if both are false
    final actionCompleteProvided = actionComplete != null || (localMessage?.actionComplete ?? false) == false;
    if (actionCompleteProvided) {
      final initialComplete = initial['actionComplete'] as bool? ?? false;
      if (actionComplete != initialComplete) {
        current['actionComplete'] = actionComplete ?? false;
        hasChanges = true;
        debugPrint('[FirebaseSync]   actionComplete changed: $initialComplete -> ${actionComplete ?? false}');
      } else {
        debugPrint('[FirebaseSync]   actionComplete unchanged: $initialComplete');
      }
    } else {
      debugPrint('[FirebaseSync]   actionComplete not provided (null param with local value), skipping');
    }

    if (!hasChanges) {
      debugPrint('[FirebaseSync] No changes for message $messageId, skipping sync');
      return;
    }

    if (_emailMetaCollection == null) {
      debugPrint('[FirebaseSync] _emailMetaCollection is null, cannot sync. Firebase may not be initialized.');
      return;
    }

    try {
      // Defer Firestore operations until after the current frame to ensure we're on the main thread
      await SchedulerBinding.instance.endOfFrame;
      
      // Write to the subcollection - each email is its own document
      final emailDoc = _emailMetaCollection!.doc(messageId);
      
      // Check if document exists
      final existingDoc = await emailDoc.get();
      
      debugPrint('[FirebaseSync] Updating fields: ${current.keys.toList()}');
      
      // Use update() with field paths to update ONLY the changed fields
      // Firestore will preserve other fields in the nested 'current' object automatically
      final updateData = <String, dynamic>{
        'lastModified': FieldValue.serverTimestamp(),
      };
      
      // Update only the fields that changed using field paths
      for (final key in current.keys) {
        updateData['current.$key'] = current[key];
      }
      
      // If document doesn't exist, use set() with merge to create it
      if (!existingDoc.exists) {
        await emailDoc.set({
          'current': current,
          'lastModified': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        // Use update() with field paths - Firestore preserves other nested fields
        await emailDoc.update(updateData);
      }
      
      // Update initial values to prevent re-syncing
      if (!_initialValues.containsKey(initialKey)) {
        _initialValues[initialKey] = <String, dynamic>{};
      }
      final initialMap = _initialValues[initialKey] as Map<String, dynamic>;
      
      // Update only the fields that were synced
      if (current.containsKey('localTagPersonal')) {
        initialMap['localTagPersonal'] = localTagPersonal;
      }
      if (current.containsKey('actionDate')) {
        initialMap['actionDate'] = actionDate?.toIso8601String();
      }
      if (current.containsKey('actionInsightText')) {
        initialMap['actionInsightText'] = actionInsightText;
      }
      if (current.containsKey('actionComplete')) {
        initialMap['actionComplete'] = actionComplete ?? false;
      }
      
      debugPrint('[FirebaseSync] Synced email meta for $messageId');
    } catch (e) {
      debugPrint('[FirebaseSync] Error syncing email meta: $e');
    }
  }

  /// Sender preferences are no longer synced to Firebase
  /// They are derived locally from emailMeta changes
  /// This method is kept for backward compatibility but does nothing
  @Deprecated('Sender preferences are no longer synced. They are derived from emailMeta.')
  Future<void> syncSenderPrefs(Map<String, String?> prefs) async {
    // No-op: sender preferences are derived locally from emailMeta changes
    return;
  }

  /// Handle a single email metadata update from Firebase
  /// Called when a single email document changes in the subcollection
  Future<void> _handleSingleEmailMetaUpdate(String messageId, Map<String, dynamic> current) async {
    try {
      final repo = MessageRepository();
      
      // Check what we have locally for this message to avoid unnecessary updates
      final initialKey = 'emailMeta.$messageId.current';
      final lastKnown = _initialValues[initialKey] as Map<String, dynamic>?;
      
      // Read existing local message to check if it exists and has data
      final existingMessage = await repo.getById(messageId);
      final hasLocalData = existingMessage != null;
      
      final localTag = current['localTagPersonal']?.toString();
      final lastKnownTag = lastKnown?['localTagPersonal']?.toString();
      
      DateTime? actionDate;
      String? lastKnownDateStr;
      if (current['actionDate'] != null) {
        try {
          actionDate = DateTime.parse(current['actionDate'].toString());
        } catch (_) {}
      }
      if (lastKnown?['actionDate'] != null) {
        lastKnownDateStr = lastKnown!['actionDate'].toString();
      }
      
      final actionText = current['actionInsightText']?.toString();
      final lastKnownText = lastKnown?['actionInsightText']?.toString();
      
      final actionComplete = current['actionComplete'] as bool? ?? false;
      final lastKnownComplete = lastKnown?['actionComplete'] as bool? ?? false;
      
      // Only update if values actually changed
      // IMPORTANT: For fresh installs (no local data), always apply Firebase data
      bool needsUpdate = false;
      String? updatedLocalTag;
      DateTime? updatedActionDate;
      String? updatedActionText;
      
      // For localTag: update if changed OR if no local data exists
      if (localTag != lastKnownTag || (!hasLocalData && localTag != null)) {
        needsUpdate = true;
        updatedLocalTag = localTag;
        await repo.updateLocalTag(messageId, localTag);
        
        // Derive and update sender preference locally (don't sync to Firebase)
        final message = await repo.getById(messageId);
        if (message != null && message.from.isNotEmpty) {
          // Extract email from "Name <email@domain.com>" or "email@domain.com"
          final fromStr = message.from;
          String senderEmail = fromStr;
          
          // Try to extract email from angle brackets
          final emailMatch = RegExp(r'<([^>]+)>').firstMatch(fromStr);
          if (emailMatch != null) {
            senderEmail = emailMatch.group(1) ?? fromStr;
          }
          
          // Only update if we have a valid email
          if (senderEmail.contains('@')) {
            await repo.setSenderDefaultLocalTag(senderEmail.trim(), localTag);
            debugPrint('[FirebaseSync] Updated sender preference for $senderEmail to $localTag (from emailMeta update)');
          }
        }
        
        // Update initial values to track this change
        if (!_initialValues.containsKey(initialKey)) {
          _initialValues[initialKey] = <String, dynamic>{};
        }
        (_initialValues[initialKey] as Map<String, dynamic>)['localTagPersonal'] = localTag;
      }
      
      // Update action if actionDate, actionText, or actionComplete is present and different
      // IMPORTANT: Only update fields that are actually in the 'current' map from Firebase
      // For fresh installs (no local data), always apply Firebase action data
      DateTime? finalActionDate = existingMessage?.actionDate;
      String? finalActionText = existingMessage?.actionInsightText;
      bool finalActionComplete = existingMessage?.actionComplete ?? false;
      
      final currentDateStr = actionDate?.toIso8601String();
      bool actionChanged = false;
      bool dateUpdated = false;
      bool textUpdated = false;
      
      // For actions: if no local action data exists, apply all Firebase action data
      // Otherwise, only update if values changed
      final hasLocalAction = existingMessage?.hasAction ?? false;
      
      if (current.containsKey('actionDate')) {
        // Update if changed OR if no local action data exists (even if message exists, it might not have action)
        if (!hasLocalAction || currentDateStr != lastKnownDateStr) {
          finalActionDate = actionDate;
          actionChanged = true;
          dateUpdated = true;
        }
      }
      
      if (current.containsKey('actionInsightText')) {
        // Update if changed OR if no local action data exists
        if (!hasLocalAction || actionText != lastKnownText) {
          finalActionText = actionText;
          actionChanged = true;
          textUpdated = true;
        }
      }
      
      if (current.containsKey('actionComplete')) {
        // Update if changed OR if no local action data exists
        if (!hasLocalAction || actionComplete != lastKnownComplete) {
          finalActionComplete = actionComplete;
          actionChanged = true;
        }
      }
      
      // Safeguard: If either actionDate or actionInsightText was updated, ensure both are set
      // to prevent inconsistent state (e.g., text without date or date without text)
      if (dateUpdated && !textUpdated) {
        // Date was updated but text wasn't - preserve existing text
        finalActionText = existingMessage?.actionInsightText;
        debugPrint('[FirebaseSync]   Safeguard: Preserving existing actionInsightText: $finalActionText');
      }
      if (textUpdated && !dateUpdated) {
        // Text was updated but date wasn't - preserve existing date
        finalActionDate = existingMessage?.actionDate;
        debugPrint('[FirebaseSync]   Safeguard: Preserving existing actionDate: $finalActionDate');
      }
      
      if (actionChanged) {
        needsUpdate = true;
        updatedActionDate = finalActionDate;
        updatedActionText = finalActionText;
        // Update with preserved existing values + new values
        await repo.updateAction(messageId, finalActionDate, finalActionText, null, finalActionComplete);
        // Update initial values
        if (!_initialValues.containsKey(initialKey)) {
          _initialValues[initialKey] = <String, dynamic>{};
        }
        final initialMap = _initialValues[initialKey] as Map<String, dynamic>;
        if (current.containsKey('actionDate')) {
          initialMap['actionDate'] = finalActionDate?.toIso8601String();
        }
        if (current.containsKey('actionInsightText')) {
          initialMap['actionInsightText'] = finalActionText;
        }
        if (current.containsKey('actionComplete')) {
          initialMap['actionComplete'] = finalActionComplete;
        }
      }
      
      if (needsUpdate) {
        debugPrint('[FirebaseSync] Applied update for message $messageId');
        
        // Notify UI to update the provider state
        if (onUpdateApplied != null) {
          onUpdateApplied!(messageId, updatedLocalTag, updatedActionDate, updatedActionText);
        }
      } else {
        debugPrint('[FirebaseSync] No changes detected for message $messageId (already up to date)');
      }
    } catch (e) {
      debugPrint('[FirebaseSync] Error applying email meta update for $messageId: $e');
    }
  }

  /// Sender preferences are no longer synced from Firebase
  /// This method is kept for backward compatibility but does nothing
  // ignore: unused_element
  @Deprecated('Sender preferences are no longer synced. They are derived from emailMeta.')
  // ignore: unused_element
  Future<void> _handleSenderPrefsUpdate(Map<Object?, Object?> data) async {}

  /// Helper to compare two maps for equality (deep comparison)
  // ignore: unused_element
  bool _mapsEqual(Map<String, dynamic> map1, Map<String, dynamic> map2) {
    if (map1.length != map2.length) return false;
    
    for (final entry in map1.entries) {
      if (!map2.containsKey(entry.key)) return false;
      if (entry.value != map2[entry.key]) {
        // Deep compare for nested maps
        if (entry.value is Map && map2[entry.key] is Map) {
          if (!_mapsEqual(
            Map<String, dynamic>.from(entry.value as Map),
            Map<String, dynamic>.from(map2[entry.key] as Map),
          )) {
            return false;
          }
        } else {
          return false;
        }
      }
    }
    return true;
  }
}

