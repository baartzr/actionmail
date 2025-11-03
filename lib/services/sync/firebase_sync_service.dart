import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:actionmail/data/repositories/message_repository.dart';

/// Firebase sync service for cross-device data synchronization using Firestore
/// Minimal traffic design: only syncs changed metadata, not full emails
/// Singleton pattern to ensure single instance across the app
class FirebaseSyncService {
  static final FirebaseSyncService _instance = FirebaseSyncService._internal();
  factory FirebaseSyncService() => _instance;
  FirebaseSyncService._internal();
  
  static const String _prefsKeySyncEnabled = 'firebase_sync_enabled';
  static const String _prefsKeyUserId = 'firebase_user_id';
  
  FirebaseFirestore? _firestore;
  CollectionReference? _userCollection;
  DocumentReference? _userDoc;
  CollectionReference? _emailMetaCollection; // Subcollection for email metadata
  String? _userId;
  bool _syncEnabled = false;
  final Map<String, StreamSubscription> _subscriptions = {};
  final Map<String, dynamic> _initialValues = {}; // Track initial values to avoid syncing on load
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
        return;
      }
    }
    
    if (_firestore != null && enabled) {
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
  Future<void> _loadInitialValues() async {
    if (_emailMetaCollection == null) return;
    
    try {
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

  /// Start listening to Firebase changes
  Future<void> _startListening() async {
    if (_emailMetaCollection == null || !_syncEnabled) return;

    try {
      // Listen to the emailMeta subcollection - each email is its own document
      // This way, only changed emails trigger the listener
      _subscriptions['emailMeta'] = _emailMetaCollection!
          .snapshots()
          .listen(
            (snapshot) {
              for (final change in snapshot.docChanges) {
                final messageId = change.doc.id;
                final doc = change.doc;
                
                // Skip if this is a local write (pending writes from this device)
                // Firestore's hasPendingWrites flag handles this automatically
                if (doc.metadata.hasPendingWrites) {
                  continue;
                }
                
                // Handle the change
                if (change.type == DocumentChangeType.removed) {
                  // Email metadata was deleted - we don't handle this currently
                  continue;
                }
                
                final data = doc.data() as Map<String, dynamic>?;
                if (data == null) continue;
                
                final current = data['current'] as Map<String, dynamic>?;
                if (current == null) continue;
                
                // Process this single email change
                _handleSingleEmailMetaUpdate(messageId, current);
              }
            },
            onError: (error) {
              debugPrint('[FirebaseSync] Error in emailMeta subcollection listener: $error');
            },
          );

      debugPrint('[FirebaseSync] Started listening to emailMeta subcollection');
    } catch (e) {
      debugPrint('[FirebaseSync] Error starting listeners: $e');
    }
  }

  /// Stop all Firebase listeners
  Future<void> _stopSync() async {
    for (final sub in _subscriptions.values) {
      await sub.cancel();
    }
    _subscriptions.clear();
    debugPrint('[FirebaseSync] Stopped listening');
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

  /// Sync email metadata (personal/business tag, action date, action message)
  /// Only syncs fields that are explicitly provided and have changed from initial value
  /// Note: Pass values to sync, null to clear (if previously set)
  Future<void> syncEmailMeta(String messageId, {
    String? localTagPersonal,
    DateTime? actionDate,
    String? actionInsightText,
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
    if (actionDateProvided) {
      final initialDateStr = initial['actionDate'] as String?;
      final newDateStr = actionDate?.toIso8601String();
      if (newDateStr != initialDateStr) {
        current['actionDate'] = newDateStr;
        hasChanges = true;
        debugPrint('[FirebaseSync]   actionDate changed: $initialDateStr -> $newDateStr');
      } else {
        debugPrint('[FirebaseSync]   actionDate unchanged: $initialDateStr');
      }
    } else {
      debugPrint('[FirebaseSync]   actionDate not provided (null param with local value), skipping');
    }
    
    // Check actionInsightText: provided if non-null OR if both are null
    final actionTextProvided = actionInsightText != null || localMessage?.actionInsightText == null;
    if (actionTextProvided) {
      final initialText = initial['actionInsightText'] as String?;
      if (actionInsightText != initialText) {
        current['actionInsightText'] = actionInsightText;
        hasChanges = true;
        debugPrint('[FirebaseSync]   actionInsightText changed: $initialText -> $actionInsightText');
      } else {
        debugPrint('[FirebaseSync]   actionInsightText unchanged: $initialText');
      }
    } else {
      debugPrint('[FirebaseSync]   actionInsightText not provided (null param with local value), skipping');
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
      
      // Only update if values actually changed
      bool needsUpdate = false;
      String? updatedLocalTag;
      DateTime? updatedActionDate;
      String? updatedActionText;
      
      if (localTag != lastKnownTag) {
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
      
      // Update action if actionDate or actionText is present and different
      // IMPORTANT: Only update fields that are actually in the 'current' map from Firebase
      // Read existing local values first to preserve fields not included in the update
      final existingMessage = await repo.getById(messageId);
      DateTime? finalActionDate = existingMessage?.actionDate;
      String? finalActionText = existingMessage?.actionInsightText;
      
      final currentDateStr = actionDate?.toIso8601String();
      bool actionChanged = false;
      
      if (current.containsKey('actionDate')) {
        // Only update if this field is actually in the update
        if (currentDateStr != lastKnownDateStr) {
          finalActionDate = actionDate;
          actionChanged = true;
        }
      }
      
      if (current.containsKey('actionInsightText')) {
        // Only update if this field is actually in the update
        if (actionText != lastKnownText) {
          finalActionText = actionText;
          actionChanged = true;
        }
      }
      
      if (actionChanged) {
        needsUpdate = true;
        updatedActionDate = finalActionDate;
        updatedActionText = finalActionText;
        // Update with preserved existing values + new values
        await repo.updateAction(messageId, finalActionDate, finalActionText);
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
  @Deprecated('Sender preferences are no longer synced. They are derived from emailMeta.')
  Future<void> _handleSenderPrefsUpdate(Map<Object?, Object?> data) async {
    // No-op: sender preferences are derived locally from emailMeta changes
    return;
  }

  /// Helper to compare two maps for equality (deep comparison)
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

