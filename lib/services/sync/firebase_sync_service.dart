import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:domail/data/repositories/message_repository.dart';
import 'package:domail/data/models/message_index.dart';
import 'package:domail/services/sync/firebase_init.dart';

// Helper to log in both debug and release modes
void _logFirebaseSync(String message) {
  // In release mode, debugPrint is a no-op, so use print for critical errors
  debugPrint(message);
  if (kReleaseMode) {
    // In release builds, print critical errors to console
    // ignore: avoid_print
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
  StreamSubscription<QuerySnapshot>? _emailMetaSubscription; // Real-time listener subscription
  // Retry state for delayed initialization when Firebase isn't ready yet
  Timer? _initRetryTimer;
  int _initRetryCount = 0;
  static const int _maxInitRetries = 5;
  
  // Callback to notify UI when updates are applied from Firebase
  void Function(String messageId, String? localTag, DateTime? actionDate, String? actionText, bool? actionComplete, {bool preserveExisting})? onUpdateApplied;

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
      
      // Collection references and all Firebase operations must be created/called on platform thread
      // Since this is called after local email load completes, we're on a stable thread context
      // Use a single frame callback to ensure platform thread execution
      final scheduler = SchedulerBinding.instance;
      scheduler.addPostFrameCallback((_) async {
          // Create collection references (synchronous, but must be on platform thread)
          _userCollection = _firestore!.collection('users');
          _userDoc = _userCollection!.doc(userId);
          _emailMetaCollection = _userDoc!.collection('emailMeta'); // Subcollection for each email
          _logFirebaseSync('Collections set up, _userDoc: ${_userDoc != null}, _emailMetaCollection: ${_emailMetaCollection != null}');

          // Start listening (must be on platform thread)
          await _startListening();
          _logFirebaseSync('Started listening');
          
          // Load initial values in background (must also be on platform thread)
          unawaited(_loadInitialValues());
          
          _logFirebaseSync('User initialized successfully: $userId, _userDoc: ${_userDoc != null}, _emailMetaCollection: ${_emailMetaCollection != null}');
        });
    } else {
      _logFirebaseSync('Cannot initialize user: _firestore is ${_firestore != null ? "set" : "null"}, enabled is $enabled');
    }
  }

  /// Helper to ensure Firebase operations run on the platform thread
  /// Uses SchedulerBinding.scheduleFrameCallback to ensure platform thread execution
  Future<T> _runOnMainThread<T>(Future<T> Function() operation) async {
    final scheduler = SchedulerBinding.instance;
    final completer = Completer<T>();
    // scheduleFrameCallback ensures execution on the platform thread
    scheduler.scheduleFrameCallback((_) async {
      try {
        final result = await operation();
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      }
    });
    return completer.future;
  }

  /// Load initial values from Firebase and reconcile with local changes
  /// Uses timestamp comparison: if local.lastUpdated > firebase.lastModified, push local → Firebase
  /// Otherwise, pull Firebase → local
  /// NOTE: This must be called from the main thread context
  Future<void> _loadInitialValues() async {
    if (_emailMetaCollection == null) return;
    
    try {
      // Load all documents from Firebase - ensure .get() is called on platform thread
      final snapshot = await _runOnMainThread(() => _emailMetaCollection!.get());
      
      // Reconcile each document (non-blocking, but ensure Firebase operations on main thread)
      // Use scheduleMicrotask to ensure immediate execution on main thread
      scheduleMicrotask(() async {
        final repo = MessageRepository();
        
        for (final doc in snapshot.docs) {
          final messageId = doc.id;
          final data = doc.data() as Map<String, dynamic>?;
          if (data == null) continue;
          
          final current = data['current'] as Map<String, dynamic>?;
          if (current == null) continue;
          
          // Get Firebase lastModified timestamp (Unix milliseconds)
          final lastModifiedObj = data['lastModified'];
          int? firebaseTimestamp;
          if (lastModifiedObj != null) {
            if (lastModifiedObj is Timestamp) {
              firebaseTimestamp = lastModifiedObj.millisecondsSinceEpoch;
            } else if (lastModifiedObj is int) {
              firebaseTimestamp = lastModifiedObj;
            } else if (lastModifiedObj is String) {
              // Try parsing ISO string
              try {
                final dt = DateTime.parse(lastModifiedObj);
                firebaseTimestamp = dt.millisecondsSinceEpoch;
              } catch (_) {}
            }
          }
          
          // Get local message with lastUpdated timestamp
          final localMessage = await repo.getById(messageId);
          final localTimestamp = localMessage != null 
              ? await _getLocalLastUpdated(messageId)
              : null;
          
          // Compare timestamps (Unix milliseconds)
          if (localTimestamp != null && firebaseTimestamp != null) {
            if (localTimestamp > firebaseTimestamp) {
              // Local is newer - push local → Firebase
              await _pushLocalToFirebase(messageId, localMessage!);
              continue;
            }
            // Firebase is newer or equal - pull Firebase → local
            await _handleSingleEmailMetaUpdate(messageId, current, parentData: data);
          } else if (firebaseTimestamp != null) {
            // Only Firebase has timestamp - pull Firebase → local
            await _handleSingleEmailMetaUpdate(messageId, current, parentData: data);
          } else if (localTimestamp != null && localMessage != null) {
            // Only local has timestamp - push local → Firebase
            await _pushLocalToFirebase(messageId, localMessage);
          } else {
            // Neither has timestamp - just apply Firebase values
            await _handleSingleEmailMetaUpdate(messageId, current, parentData: data);
          }
        }
        
        debugPrint('[FirebaseSync] Completed reconciliation of Firebase and local values');
      });
    } catch (e) {
      _logFirebaseSync('Error loading initial values: $e');
    }
  }
  
  /// Get local lastUpdated timestamp for a message (Unix milliseconds)
  Future<int?> _getLocalLastUpdated(String messageId) async {
    try {
      final repo = MessageRepository();
      return await repo.getLastUpdated(messageId);
    } catch (_) {
      return null;
    }
  }
  
  /// Push all local fields to Firebase (used when local.lastUpdated > firebase.lastModified)
  Future<void> _pushLocalToFirebase(String messageId, MessageIndex localMessage) async {
    try {
      if (!_syncEnabled || _emailMetaCollection == null) return;
      
      await _runOnMainThread(() async {
        final emailDoc = _emailMetaCollection!.doc(messageId);
        final updateData = <String, dynamic>{
          'lastModified': FieldValue.serverTimestamp(),
        };
        
        // Push all local fields to Firebase
        updateData['current.localTagPersonal'] = localMessage.localTagPersonal;
        
        // Use actionInsightText only as source of truth
        // Use null to represent "no action" - Firebase omits null values in sync pings
        if (localMessage.hasAction && localMessage.actionInsightText != null && localMessage.actionInsightText!.isNotEmpty) {
          // Action exists - push actionInsightText and optionally actionDate
          updateData['current.actionInsightText'] = localMessage.actionInsightText;
          if (localMessage.actionDate != null) {
            updateData['current.actionDate'] = localMessage.actionDate!.toIso8601String();
          }
          updateData['current.actionComplete'] = localMessage.actionComplete;
        } else {
          // Action removed - delete fields in Firebase (use FieldValue.delete() to actually remove)
          updateData['current.actionInsightText'] = FieldValue.delete();
          updateData['current.actionDate'] = FieldValue.delete();
          updateData['current.actionComplete'] = FieldValue.delete();
          if (kDebugMode) {
            _logFirebaseSync('Removing action in Firebase (_pushLocalToFirebase): messageId=$messageId (using FieldValue.delete())');
          }
        }
        
        final existingDoc = await emailDoc.get();
        
        if (!existingDoc.exists) {
          final current = <String, dynamic>{
            'localTagPersonal': localMessage.localTagPersonal,
          };
          // Use actionInsightText only as source of truth
          // Use null to represent "no action" - don't include fields for new documents
          if (localMessage.hasAction && localMessage.actionInsightText != null && localMessage.actionInsightText!.isNotEmpty) {
            current['actionInsightText'] = localMessage.actionInsightText;
            if (localMessage.actionDate != null) {
              current['actionDate'] = localMessage.actionDate?.toIso8601String();
            }
            current['actionComplete'] = localMessage.actionComplete;
          } else {
            // Action removed - don't include fields for new documents
          }
          await emailDoc.set({
            'current': current,
            'lastModified': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else {
          await emailDoc.update(updateData);
        }
        
        if (kDebugMode) {
          _logFirebaseSync('[FIREBASE_PUSH] messageId=$messageId (from _pushLocalToFirebase), actionInsightText=${localMessage.actionInsightText}');
        }
      });
    } catch (e) {
      _logFirebaseSync('Error pushing local to Firebase for $messageId: $e');
    }
  }

  /// Start listening to Firebase changes using real-time listener
  /// Processes changes on main thread to avoid threading errors
  Future<void> _startListening() async {
    if (_emailMetaCollection == null || !_syncEnabled) return;

    try {
      // Cancel any existing subscription
      await _emailMetaSubscription?.cancel();
      
      // The .snapshots() call creates a platform channel that must be created on the platform thread
      // Use WidgetsBinding to ensure we're on the platform thread when creating the listener
      final binding = WidgetsBinding.instance;
      final completer = Completer<void>();
      binding.addPostFrameCallback((_) {
        // Create the listener on the platform thread
        _emailMetaSubscription = _emailMetaCollection!.snapshots().listen(
          (snapshot) {
            // Process on main thread - use scheduleMicrotask for async operations
            scheduleMicrotask(() async {
              if (kDebugMode) {
                _logFirebaseSync('Listener received snapshot with ${snapshot.docChanges.length} changes');
              }
              for (final docChange in snapshot.docChanges) {
                final messageId = docChange.doc.id;
                final changeType = docChange.type.toString();
                final data = docChange.doc.data() as Map<String, dynamic>?;
                
                if (kDebugMode) {
                  _logFirebaseSync('[LISTENER] messageId=$messageId, changeType=$changeType, hasMetadata=${docChange.doc.metadata.hasPendingWrites}, isFromCache=${docChange.doc.metadata.isFromCache}');
                }
                
                if (data == null) continue;
                
                final current = data['current'] as Map<String, dynamic>?;
                if (current == null) {
                  if (kDebugMode) {
                    _logFirebaseSync('[LISTENER] Skipping $messageId: current is null');
                  }
                  continue;
                }
                
                // Check if this is a pending write from our own local update
                // If it has pending writes, it's our own update and we should already have the latest state locally
                if (docChange.doc.metadata.hasPendingWrites) {
                  if (kDebugMode) {
                    final hasAction = current.containsKey('actionInsightText') && current['actionInsightText'] != null;
                    _logFirebaseSync('[LISTENER] SKIP_PENDING_WRITE messageId=$messageId (local pending write, hasAction=$hasAction)');
                  }
                  // This is our own pending write - skip it since we already processed it locally
                  continue;
                }
                
                if (kDebugMode) {
                  final hasTag = current.containsKey('localTagPersonal');
                  final tagValue = current['localTagPersonal'];
                  final hasAction = current.containsKey('actionInsightText');
                  final actionText = current['actionInsightText'];
                  _logFirebaseSync('[LISTENER] Processing $messageId: hasTag=$hasTag, tag=$tagValue, hasAction=$hasAction, actionText=$actionText');
                }
                
                // Process this email change (await to ensure errors are caught)
                // Pass parent data so we can check timestamps to ignore stale updates
                try {
                  await _handleSingleEmailMetaUpdate(messageId, current, parentData: data);
                } catch (e) {
                  _logFirebaseSync('Error processing update for $messageId: $e');
                }
              }
            });
          },
          onError: (error) {
            _logFirebaseSync('Error in emailMeta listener: $error');
          },
        );
        debugPrint('[FirebaseSync] Started real-time listener for emailMeta subcollection');
        completer.complete();
      });
      await completer.future;
    } catch (e) {
      _logFirebaseSync('Error starting listener: $e');
    }
  }

  /// Stop all Firebase listeners
  Future<void> _stopSync() async {
    await _emailMetaSubscription?.cancel();
    _emailMetaSubscription = null;
    debugPrint('[FirebaseSync] Stopped listening');
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

  /// Sync email metadata (personal/business tag, action) to Firebase
  /// actionInsightText is the source of truth: if null or empty, no action exists
  Future<void> syncEmailMeta(String messageId, {
    String? localTagPersonal,
    DateTime? actionDate,
    String? actionInsightText,
    bool? actionComplete,
    String? accountEmail,
    bool clearAction = false,
  }) async {
    try {
      if (!_syncEnabled) {
        _syncEnabled = await isSyncEnabled();
        if (!_syncEnabled) return;
      }

      if (_firestore == null) {
        final initialized = await initialize();
        if (!initialized) return;
      }

      final targetEmail = accountEmail ?? _userId;
      if (targetEmail == null || targetEmail.isEmpty) {
        return;
      }

      if ((accountEmail == null || accountEmail == _userId) && _userId != null && _emailMetaCollection == null) {
          await initializeUser(_userId);
        if (_emailMetaCollection == null) {
          return;
        }
      }

      await _runOnMainThread(() async {
        CollectionReference? targetCollection;
        if (accountEmail != null && accountEmail != _userId) {
          targetCollection = _firestore!
              .collection('users')
              .doc(accountEmail)
              .collection('emailMeta');
        } else {
          _emailMetaCollection ??= _firestore!
              .collection('users')
              .doc(targetEmail)
              .collection('emailMeta');
          targetCollection = _emailMetaCollection;
        }

        final emailDoc = targetCollection?.doc(messageId);
        if (emailDoc == null) return;
        final updateData = <String, dynamic>{
          'lastModified': FieldValue.serverTimestamp(),
        };
        
        bool hasUpdates = false;
        
        // Update tag if provided
        if (localTagPersonal != null) {
          updateData['current.localTagPersonal'] = localTagPersonal;
          hasUpdates = true;
        }
        
        // Update action - source of truth: actionInsightText determines if action exists
        final hasAction = actionInsightText != null && actionInsightText.isNotEmpty;
        if (clearAction || !hasAction) {
          // Action removed - delete fields
          updateData['current.actionInsightText'] = FieldValue.delete();
          updateData['current.actionDate'] = FieldValue.delete();
          updateData['current.actionComplete'] = FieldValue.delete();
          hasUpdates = true;
          if (kDebugMode) {
            _logFirebaseSync('Removing action in Firebase: messageId=$messageId (using FieldValue.delete())');
          }
        } else if (hasAction) {
          // Action exists - push all fields
          updateData['current.actionInsightText'] = actionInsightText;
          if (actionDate != null) {
            updateData['current.actionDate'] = actionDate.toIso8601String();
          }
          updateData['current.actionComplete'] = actionComplete ?? false;
          hasUpdates = true;
        }
        
        if (!hasUpdates) return;
        
        final existingDoc = await emailDoc.get();
        
        if (!existingDoc.exists) {
          final current = <String, dynamic>{};
          if (localTagPersonal != null) {
            current['localTagPersonal'] = localTagPersonal;
          }
          if (hasAction) {
            // Action exists - include all fields
            current['actionInsightText'] = actionInsightText;
            if (actionDate != null) {
              current['actionDate'] = actionDate.toIso8601String();
            }
            current['actionComplete'] = actionComplete ?? false;
          }
          // If action doesn't exist, don't include action fields
          await emailDoc.set({
            'current': current,
            'lastModified': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else {
          await emailDoc.update(updateData);
        }
        
        if (kDebugMode) {
          _logFirebaseSync('[FIREBASE_PUSH] messageId=$messageId, actionInsightText=$actionInsightText, clearAction=$clearAction');
        }
      });
    } catch (e) {
      _logFirebaseSync('Error syncing email meta for $messageId: $e');
      rethrow;
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
  /// Simple: compare Firebase values to local, update if different
  Future<void> _handleSingleEmailMetaUpdate(String messageId, Map<String, dynamic> current, {Map<String, dynamic>? parentData}) async {
    try {
      final repo = MessageRepository();
      final localMessage = await repo.getById(messageId);
      
      bool needsUpdate = false;
      bool tagWasUpdated = false; // Track if tag was explicitly updated (even if to null)
      String? updatedLocalTag;
      DateTime? updatedActionDate;
      String? updatedActionText;
      bool? updatedActionComplete;
      bool actionTextWasUpdated = false; // Track if actionText was explicitly updated (even if to null)
      
      // Compare and update localTagPersonal
      // Handle missing fields: if Firebase field is missing, treat as null (cleared)
      final firebaseTagValue = current['localTagPersonal'];
      // Check if Firebase has the field
      final hasFirebaseField = current.containsKey('localTagPersonal');
      
      // Get the actual value from Firebase
      String? firebaseTag;
      if (hasFirebaseField) {
        // Field exists in Firebase - get value (could be null, empty string, or actual tag)
        if (firebaseTagValue == null) {
          firebaseTag = null; // Explicitly null in Firebase
        } else {
          firebaseTag = firebaseTagValue.toString();
          // Treat empty string as null for consistency
          if (firebaseTag.isEmpty) {
            firebaseTag = null;
          }
        }
      } else {
        // Field is missing in Firebase - treat as null (user cleared it or it was never set)
        firebaseTag = null;
      }
      
      final localTag = localMessage?.localTagPersonal;
      
      // Determine what value to apply
      // If field is missing in Firebase, we set local to null (treat missing as cleared)
      final tagToApply = firebaseTag;
      
      // Update if values differ
      // This handles: null != "Personal", "Personal" != null, "Personal" != "Business", etc.
      final shouldUpdate = tagToApply != localTag;
      
      if (kDebugMode) {
        _logFirebaseSync('localTagPersonal update check: firebase=${hasFirebaseField ? firebaseTag : "missing (→null)"}, local=$localTag, shouldUpdate=$shouldUpdate');
      }
      
      if (shouldUpdate) {
        updatedLocalTag = tagToApply;
        tagWasUpdated = true; // Mark that tag was updated (even if to null)
        // Don't update lastUpdated when applying Firebase changes (not a user change)
        await repo.updateLocalTag(messageId, tagToApply, updateTimestamp: false);
        needsUpdate = true;
        
        // Update sender preference locally
        if (localMessage != null && localMessage.from.isNotEmpty) {
          final fromStr = localMessage.from;
          final emailMatch = RegExp(r'<([^>]+)>').firstMatch(fromStr);
          final senderEmail = emailMatch?.group(1) ?? fromStr;
          if (senderEmail.contains('@')) {
            await repo.setSenderDefaultLocalTag(senderEmail.trim(), tagToApply);
          }
        }
      }
      
      // Compare and update action fields
      // Simplified: use actionInsightText only as source of truth for action existence
      // Note: Firebase omits null values in sync pings, so missing key = null (action removed)
      final hasFirebaseActionText = current.containsKey('actionInsightText');
      final hasFirebaseActionDate = current.containsKey('actionDate');
      final hasFirebaseActionComplete = current.containsKey('actionComplete');
      
      // Get actionInsightText from Firebase
      // If key is missing from sync ping, it means actionInsightText was set to null (deleted) in Firebase
      String? firebaseActionText;
      if (hasFirebaseActionText) {
        final firebaseValue = current['actionInsightText'];
        if (firebaseValue != null) {
          final textStr = firebaseValue.toString();
          // Handle both null and empty string as "no action" (for backwards compatibility)
          firebaseActionText = textStr.isEmpty ? null : textStr;
        } else {
          // Key exists but value is null (backwards compatibility with old data) - treat as no action
          firebaseActionText = null;
        }
      } else {
        // Key missing from sync ping = actionInsightText was deleted (set to null) in Firebase
        firebaseActionText = null;
      }
      
      final firebaseHasAction = firebaseActionText != null && firebaseActionText.isNotEmpty;
      
      DateTime? firebaseActionDate;
      if (hasFirebaseActionDate && current['actionDate'] != null) {
        try {
          firebaseActionDate = DateTime.parse(current['actionDate'].toString());
        } catch (_) {}
      }
      
      final firebaseActionComplete = hasFirebaseActionComplete
          ? current['actionComplete'] as bool?
          : null;
      
      final localActionDate = localMessage?.actionDate;
      final localActionText = localMessage?.actionInsightText;
      final localActionComplete = localMessage?.actionComplete ?? false;
      final localHasAction = localActionText != null && localActionText.isNotEmpty;
      
      if (kDebugMode) {
        _logFirebaseSync('[FIREBASE_SYNC] COMPARE messageId=$messageId, firebase=$firebaseActionText, local=$localActionText');
      }
      
      // Update actionInsightText based on Firebase state
      // Source of truth: actionInsightText determines if action exists
      // If actionInsightText key is missing from Firebase sync (was deleted), set local to null
      // If Firebase has action and it's different from local → update
      
      // Update actionInsightText based on Firebase state
      if (!firebaseHasAction && !localHasAction) {
        // Both are null - already in sync
        if (kDebugMode) {
          _logFirebaseSync('[FIREBASE_SYNC] NO_CHANGE messageId=$messageId (both null)');
        }
      } else if (firebaseHasAction && localHasAction && firebaseActionText == localActionText) {
        // Both have same action text - already in sync
        if (kDebugMode) {
          _logFirebaseSync('[FIREBASE_SYNC] NO_CHANGE messageId=$messageId (same text: $firebaseActionText)');
        }
      } else if (!firebaseHasAction && localHasAction) {
        // Firebase removed action - remove locally
        updatedActionText = null;
        actionTextWasUpdated = true;
        needsUpdate = true;
        if (kDebugMode) {
          _logFirebaseSync('[FIREBASE_SYNC] REMOVE messageId=$messageId (Firebase null, local has action)');
        }
      } else if (firebaseHasAction && !localHasAction) {
        // Firebase has action, local doesn't - add it
        updatedActionText = firebaseActionText;
        actionTextWasUpdated = true;
        needsUpdate = true;
        if (kDebugMode) {
          _logFirebaseSync('[FIREBASE_SYNC] ADD messageId=$messageId (Firebase: $firebaseActionText, local null)');
        }
      } else if (firebaseHasAction && firebaseActionText != localActionText) {
        // Firebase has different action - update
        updatedActionText = firebaseActionText;
        actionTextWasUpdated = true;
        needsUpdate = true;
        if (kDebugMode) {
          _logFirebaseSync('[FIREBASE_SYNC] UPDATE messageId=$messageId (Firebase: $firebaseActionText, local: $localActionText)');
        }
      }
      
      // Update actionDate if Firebase has it and different
      if (hasFirebaseActionDate && firebaseActionDate?.toIso8601String() != localActionDate?.toIso8601String()) {
        updatedActionDate = firebaseActionDate;
        needsUpdate = true;
      }
      
      // Update complete if key present and different
      if (hasFirebaseActionComplete && firebaseActionComplete != localActionComplete) {
        updatedActionComplete = firebaseActionComplete;
        needsUpdate = true;
      }
      
      if (needsUpdate && actionTextWasUpdated) {
        // Don't update lastUpdated when applying Firebase changes (not a user change)
        final finalActionDate = actionTextWasUpdated && !firebaseHasAction 
            ? null // If action was removed, clear date
            : (updatedActionDate ?? localActionDate);
        final finalActionText = updatedActionText; // Use updated text (may be null)
        final finalActionComplete = !firebaseHasAction 
            ? false // If action was removed, set complete to false
            : (updatedActionComplete ?? localActionComplete);
        
        if (kDebugMode) {
          _logFirebaseSync('[FIREBASE_SYNC] DB_UPDATE messageId=$messageId, actionText=$finalActionText');
        }
        
        await repo.updateAction(
          messageId,
          finalActionDate,
          finalActionText, // Can be null when removing action
          null, // confidence
          finalActionComplete,
          false, // updateTimestamp = false
        );
      }
      
      if (needsUpdate && onUpdateApplied != null) {
        // Use updated values if they were explicitly updated (even if to null), otherwise keep local values
        final finalTag = tagWasUpdated ? updatedLocalTag : localTag;
        final finalActionDate = actionTextWasUpdated && !firebaseHasAction
            ? null
            : (updatedActionDate ?? localActionDate);
        final finalActionText = actionTextWasUpdated ? updatedActionText : localActionText;
        final finalActionComplete = !firebaseHasAction || (actionTextWasUpdated && !firebaseHasAction)
            ? false
            : (updatedActionComplete ?? localActionComplete);
        
        if (kDebugMode) {
          _logFirebaseSync('[FIREBASE_SYNC] CALLBACK messageId=$messageId, actionText=$finalActionText');
        }
        
        onUpdateApplied!(
          messageId,
          finalTag,
          finalActionDate,
          finalActionText,
          finalActionComplete,
          preserveExisting: !actionTextWasUpdated && !tagWasUpdated, // Don't preserve if explicitly updated (even if null)
        );
      } else if (needsUpdate && onUpdateApplied == null) {
        if (kDebugMode) {
          _logFirebaseSync('needsUpdate=true but onUpdateApplied is null - UI callback not set');
        }
      }
    } catch (e) {
      _logFirebaseSync('Error applying email meta update for $messageId: $e');
    }
  }

  /// Sender preferences are no longer synced from Firebase
  /// This method is kept for backward compatibility but does nothing
  // ignore: unused_element
  @Deprecated('Sender preferences are no longer synced. They are derived from emailMeta.')
  // ignore: unused_element
  Future<void> _handleSenderPrefsUpdate(Map<Object?, Object?> data) async {}

}

