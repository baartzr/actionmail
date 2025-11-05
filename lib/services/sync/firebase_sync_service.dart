import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:actionmail/data/repositories/message_repository.dart';
import 'package:actionmail/services/sync/firebase_init.dart';

// Helper to log in both debug and release modes
void _logFirebaseSync(String message) {
  // In release mode, debugPrint is a no-op, so use print for critical errors
  debugPrint(message);
  if (kReleaseMode) {
    // In release builds, print critical errors to console
    print('[FirebaseSync] $message');
  }
}

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
      // Wait for Firebase initialization to complete if it's still in progress
      await FirebaseInit.instance.whenReady;
      
      // Check if Firebase apps are initialized
      final apps = Firebase.apps;
      if (apps.isEmpty) {
        _logFirebaseSync('ERROR: Firebase apps is empty - Firebase not initialized');
        _logFirebaseSync('On desktop, you MUST run: flutterfire configure');
        _logFirebaseSync('This generates lib/firebase_options.dart');
        _logFirebaseSync('Working directory: ${Directory.current.path}');
        return false;
      }
      
      // Try to get Firestore instance - this might throw if initialization failed
      try {
        _firestore = FirebaseFirestore.instance;
        _logFirebaseSync('Initialized successfully, _firestore: ${_firestore != null}');
        _logFirebaseSync('Firebase app name: ${apps.first.name}');
        _logFirebaseSync('Firebase project ID: ${apps.first.options.projectId}');
        return _firestore != null;
      } catch (firestoreError) {
        _logFirebaseSync('ERROR: Failed to get Firestore instance: $firestoreError');
        _logFirebaseSync('Firebase apps exist but Firestore cannot be accessed');
        _logFirebaseSync('This may indicate a network or permissions issue');
        return false;
      }
    } catch (e, stackTrace) {
      _logFirebaseSync('Initialization error (Firebase may not be configured): $e');
      _logFirebaseSync('Stack trace: $stackTrace');
      _logFirebaseSync('On desktop, run: flutterfire configure');
      _logFirebaseSync('Working directory: ${Directory.current.path}');
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
    _logFirebaseSync('initializeUser called with userId: $userId');
    
    if (userId == null) {
      _userId = null;
      _userDoc = null;
      _userCollection = null;
      await _stopSync();
      _logFirebaseSync('User ID is null, stopping sync');
      return;
    }

    _userId = userId;
    final enabled = await isSyncEnabled();
    _syncEnabled = enabled;
    _logFirebaseSync('Sync enabled: $enabled, _firestore: ${_firestore != null}');
    
    // If _firestore is null, try to initialize Firebase (in case initialize() wasn't called yet)
    if (_firestore == null) {
      _logFirebaseSync('_firestore is null, attempting to initialize Firebase...');
      final initialized = await initialize();
      if (!initialized) {
        _logFirebaseSync('Cannot initialize user: Firebase initialization failed');
        // Schedule a short retry to allow background Firebase.initializeApp to complete
        if (_initRetryCount < _maxInitRetries) {
          _initRetryTimer?.cancel();
          _initRetryCount++;
          final delay = Duration(milliseconds: 300 * _initRetryCount);
          _logFirebaseSync('Scheduling initializeUser retry #$_initRetryCount in ${delay.inMilliseconds}ms');
          _initRetryTimer = Timer(delay, () async {
            // Make this async and await properly
            await initializeUser(userId);
          });
        } else {
          _logFirebaseSync('Max initializeUser retries reached; giving up');
        }
        return;
      } else {
        _logFirebaseSync('Firebase initialization succeeded in initializeUser, _firestore is now set');
      }
    }
    
    // Double-check enabled state after potential Firebase initialization
    if (!enabled) {
      _logFirebaseSync('Sync is disabled, cannot initialize user');
      return;
    }
    
    if (_firestore != null && enabled) {
      // Reset retry state on success
      _initRetryTimer?.cancel();
      _initRetryTimer = null;
      _initRetryCount = 0;
      _logFirebaseSync('Setting up user collections for userId: $userId');
      _userCollection = _firestore!.collection('users');
      _userDoc = _userCollection!.doc(userId);
            _emailMetaCollection = _userDoc!.collection('emailMeta'); // Subcollection for each email
      _logFirebaseSync('Collections set up, _userDoc: ${_userDoc != null}, _emailMetaCollection: ${_emailMetaCollection != null}');

      // Load initial values in the background - don't block startup
      // ignore: unawaited_futures
      unawaited(_loadInitialValues());

      await _startListening();
      _logFirebaseSync('Started listening/polling');
      
      _logFirebaseSync('User initialized successfully: $userId, _userDoc: ${_userDoc != null}, _emailMetaCollection: ${_emailMetaCollection != null}');
    } else {
      _logFirebaseSync('Cannot initialize user: _firestore is ${_firestore != null ? "set" : "null"}, enabled is $enabled');
    }
  }

  /// Load initial values from Firebase to avoid syncing unchanged data
  /// Loads from emailMeta subcollection
  /// Also applies Firebase values to local database if they differ
  /// Ensures query is executed on the platform thread to avoid threading errors
  Future<void> _loadInitialValues() async {
    if (_emailMetaCollection == null) return;
    
    try {
      // Defer query execution until after the current frame to ensure we're on the main thread
      await SchedulerBinding.instance.endOfFrame;
      
      // Load all documents from the emailMeta subcollection
      final snapshot = await _emailMetaCollection!.get();
      
      // First pass: Store in _initialValues for comparison
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
      
      // Second pass: Apply Firebase values to local database if they differ (non-blocking)
      // We do this in the background so it doesn't delay startup
      // We do this by temporarily clearing _initialValues entries, then calling
      // _handleSingleEmailMetaUpdate which will apply values when lastKnown is null
      // ignore: unawaited_futures
      unawaited(Future(() async {
        final initialValuesCopy = Map<String, Map<String, dynamic>>.from(
          _initialValues.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)))
        );
        
        // Clear _initialValues temporarily so _handleSingleEmailMetaUpdate treats these as new
        _initialValues.clear();
        
        // Apply each Firebase value to local database
        for (final doc in snapshot.docs) {
          final messageId = doc.id;
          final data = doc.data() as Map<String, dynamic>?;
          if (data != null) {
            final current = data['current'] as Map<String, dynamic>?;
            if (current != null) {
              await _handleSingleEmailMetaUpdate(messageId, current);
            }
          }
        }
        
        // Restore _initialValues to prevent re-syncing these values
        _initialValues.clear();
        _initialValues.addAll(initialValuesCopy);
        
        debugPrint('[FirebaseSync] Applied initial Firebase values to local database');
      }));
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
          } catch (e, stackTrace) {
            _logFirebaseSync('Error polling emailMeta: $e');
            if (kReleaseMode) {
              _logFirebaseSync('Stack trace: $stackTrace');
            }
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
      // Load initial values in the background - don't block startup
      // ignore: unawaited_futures
      unawaited(_loadInitialValues());
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
    try {
      // Only log in debug mode to reduce noise in release
      if (kDebugMode) {
        _logFirebaseSync('syncEmailMeta called for $messageId, localTagPersonal=$localTagPersonal');
      }
      
      if (!_syncEnabled) {
        _logFirebaseSync('Sync is disabled, skipping sync for $messageId');
        return;
      }
      
      if (_userDoc == null) {
        _logFirebaseSync('_userDoc is null, cannot sync. Firebase may not be initialized. UserId: $_userId');
        // Try to re-initialize user if we have a userId
        if (_userId != null) {
          _logFirebaseSync('Attempting to re-initialize user: $_userId');
          await initializeUser(_userId);
          // Check again after re-initialization
          if (_userDoc == null) {
            _logFirebaseSync('Re-initialization failed, _userDoc still null');
            return;
          }
          _logFirebaseSync('Re-initialization succeeded, _userDoc is now set');
        } else {
          return;
        }
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
      
      // Check if we're explicitly removing the action (both are null)
      // This happens when the user clicks "Remove Action" button
      final isExplicitRemoval = actionDate == null && actionInsightText == null &&
                                (localMessage?.actionDate != null || localMessage?.actionInsightText != null);
      
      // Check actionDate: provided if non-null OR if both are null OR if explicitly removing
      final actionDateProvided = actionDate != null || localMessage?.actionDate == null || isExplicitRemoval;
      bool actionDateChanged = false;
      if (actionDateProvided) {
        final initialDateStr = initial['actionDate'] as String?;
        final hasInitialValue = initial.containsKey('actionDate');
        final newDateStr = actionDate?.toIso8601String();
        
        // Only sync if it's different from initial
        // IMPORTANT: If initial values haven't been loaded yet (empty initial map),
        // don't sync null to avoid overwriting Firebase values that we haven't loaded
        if (hasInitialValue) {
          // We have initial values loaded
          // If we're trying to sync null and Firebase has a value, only allow if it's an explicit removal
          if (actionDate == null && initialDateStr != null && !isExplicitRemoval) {
            debugPrint('[FirebaseSync]   actionDate not synced: Firebase has value "$initialDateStr" and this is not an explicit removal');
          } else if (newDateStr != initialDateStr) {
            current['actionDate'] = newDateStr;
            hasChanges = true;
            actionDateChanged = true;
            debugPrint('[FirebaseSync]   actionDate changed: $initialDateStr -> $newDateStr');
          } else {
            debugPrint('[FirebaseSync]   actionDate unchanged: $initialDateStr');
          }
        } else {
          // Initial values not loaded yet - only sync if we're setting a value (not clearing to null)
          // This prevents overwriting Firebase with null before we know what's in Firebase
          if (actionDate != null) {
            current['actionDate'] = newDateStr;
            hasChanges = true;
            actionDateChanged = true;
            debugPrint('[FirebaseSync]   actionDate set (initial values not loaded yet): $newDateStr');
          } else {
            debugPrint('[FirebaseSync]   actionDate not synced: initial values not loaded yet, preventing null overwrite');
          }
        }
      } else {
        debugPrint('[FirebaseSync]   actionDate not provided (null param with local value), skipping');
      }
      
      // Check actionInsightText: provided if non-null OR if both are null OR if explicitly removing
      final actionTextProvided = actionInsightText != null || localMessage?.actionInsightText == null || isExplicitRemoval;
      bool actionTextChanged = false;
      if (actionTextProvided) {
        final initialText = initial['actionInsightText'] as String?;
        final hasInitialValue = initial.containsKey('actionInsightText');
        
        // Only sync if it's different from initial
        // IMPORTANT: If initial values haven't been loaded yet (empty initial map),
        // don't sync null to avoid overwriting Firebase values that we haven't loaded
        if (hasInitialValue) {
          // We have initial values loaded
          // If we're trying to sync null and Firebase has a value, only allow if it's an explicit removal
          if (actionInsightText == null && initialText != null && !isExplicitRemoval) {
            debugPrint('[FirebaseSync]   actionInsightText not synced: Firebase has value "$initialText" and this is not an explicit removal');
          } else if (actionInsightText != initialText) {
            current['actionInsightText'] = actionInsightText;
            hasChanges = true;
            actionTextChanged = true;
            debugPrint('[FirebaseSync]   actionInsightText changed: $initialText -> $actionInsightText');
          } else {
            debugPrint('[FirebaseSync]   actionInsightText unchanged: $initialText');
          }
        } else {
          // Initial values not loaded yet - only sync if we're setting a value (not clearing to null)
          // This prevents overwriting Firebase with null before we know what's in Firebase
          if (actionInsightText != null) {
            current['actionInsightText'] = actionInsightText;
            hasChanges = true;
            actionTextChanged = true;
            debugPrint('[FirebaseSync]   actionInsightText set (initial values not loaded yet): $actionInsightText');
          } else {
            debugPrint('[FirebaseSync]   actionInsightText not synced: initial values not loaded yet, preventing null overwrite');
          }
        }
      } else {
        debugPrint('[FirebaseSync]   actionInsightText not provided (null param with local value), skipping');
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
        _logFirebaseSync('No changes for message $messageId, skipping sync');
        return;
      }

      if (_emailMetaCollection == null) {
        _logFirebaseSync('_emailMetaCollection is null, cannot sync. Firebase may not be initialized.');
        return;
      }

      // Defer Firestore operations until after the current frame to ensure we're on the main thread
      await SchedulerBinding.instance.endOfFrame;
      
      // Write to the subcollection - each email is its own document
      final emailDoc = _emailMetaCollection!.doc(messageId);
      
      // Check if document exists
      final existingDoc = await emailDoc.get();
      
      _logFirebaseSync('Updating fields: ${current.keys.toList()}');
      
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
      
      if (kDebugMode) {
        _logFirebaseSync('Synced email meta for $messageId successfully');
      }
    } catch (e) {
      _logFirebaseSync('Error syncing email meta for $messageId: $e');
      if (kReleaseMode) {
        print('[FirebaseSync] ERROR syncing $messageId: $e');
      }
      rethrow; // Re-throw so caller knows it failed
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
      
      final firebaseTag = current['localTagPersonal']?.toString();
      final localTagInDb = existingMessage?.localTagPersonal;
      
      // Log for debugging (only in debug mode to reduce noise)
      if (kDebugMode) {
        _logFirebaseSync('_handleSingleEmailMetaUpdate: messageId=$messageId, firebaseTag=$firebaseTag, localTagInDb=$localTagInDb');
      }
      
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
      
      // For localTag: update if Firebase value differs from LOCAL database value
      // Compare against actual local DB value, not against lastKnown (which is from Firebase)
      // Also handle null case: if Firebase has null but local has a tag, clear it
      final tagChanged = firebaseTag != localTagInDb;
      
      if (tagChanged) {
        // Firebase value differs from local - apply it (even if null, to clear the tag)
        if (kDebugMode) {
          _logFirebaseSync('Applying localTag update for $messageId: localTagInDb=$localTagInDb -> firebaseTag=$firebaseTag');
        }
        needsUpdate = true;
        updatedLocalTag = firebaseTag; // Can be null to clear tag
        await repo.updateLocalTag(messageId, firebaseTag);
        
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
            await repo.setSenderDefaultLocalTag(senderEmail.trim(), firebaseTag);
            debugPrint('[FirebaseSync] Updated sender preference for $senderEmail to $firebaseTag (from emailMeta update)');
          }
        }
        
        // Update initial values to track this change (so we don't re-sync it)
        if (!_initialValues.containsKey(initialKey)) {
          _initialValues[initialKey] = <String, dynamic>{};
        }
        (_initialValues[initialKey] as Map<String, dynamic>)['localTagPersonal'] = firebaseTag;
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
        if (kDebugMode) {
          _logFirebaseSync('Applied update for message $messageId: localTag=$updatedLocalTag');
        }
        
        // Notify UI to update the provider state
        if (onUpdateApplied != null) {
          onUpdateApplied!(messageId, updatedLocalTag, updatedActionDate, updatedActionText);
        } else if (kDebugMode) {
          _logFirebaseSync('onUpdateApplied callback is null, UI will not be updated');
        }
      } else if (kDebugMode) {
        _logFirebaseSync('No changes detected for message $messageId (already up to date)');
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

