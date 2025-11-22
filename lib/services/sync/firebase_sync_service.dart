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
        
        // Group documents by messageId and type
        final statusDocs = <String, DocumentSnapshot>{};
        final actionDocs = <String, DocumentSnapshot>{};
        
        for (final doc in snapshot.docs) {
          final docId = doc.id;
          
          if (docId.endsWith('_status')) {
            final messageId = docId.substring(0, docId.length - '_status'.length);
            statusDocs[messageId] = doc;
          } else if (docId.endsWith('_action')) {
            final messageId = docId.substring(0, docId.length - '_action'.length);
            actionDocs[messageId] = doc;
          } else {
            // Legacy document format - skip for now
            if (kDebugMode) {
              _logFirebaseSync('[LOAD_INITIAL] Skipping legacy document: $docId');
            }
          }
        }
        
        // Get all unique messageIds
        final allMessageIds = <String>{...statusDocs.keys, ...actionDocs.keys};
        
        for (final messageId in allMessageIds) {
          final localMessage = await repo.getById(messageId);
          final localTimestamp = localMessage != null 
              ? await _getLocalLastUpdated(messageId)
              : null;
          
          // Process status document
          final statusDoc = statusDocs[messageId];
          if (statusDoc != null) {
            final statusData = statusDoc.data() as Map<String, dynamic>?;
            if (statusData != null) {
              final firebaseTimestamp = _extractTimestamp(statusData['lastModified']);
              
              if (localTimestamp != null && firebaseTimestamp != null) {
                if (localTimestamp > firebaseTimestamp) {
                  // Local is newer - push local → Firebase (but only if we have local message)
                  if (localMessage != null) {
                    await _pushLocalToFirebase(messageId, localMessage);
                    continue; // Skip pulling this document
                  }
                }
              }
              
              // Pull Firebase → local (or apply if no local timestamp)
              await _handleStatusUpdate(messageId, statusData);
            }
          }
          
          // Process action document
          final actionDoc = actionDocs[messageId];
          if (actionDoc != null) {
            final actionData = actionDoc.data() as Map<String, dynamic>?;
            if (actionData != null) {
              final firebaseTimestamp = _extractTimestamp(actionData['lastModified']);
              
              if (localTimestamp != null && firebaseTimestamp != null) {
                if (localTimestamp > firebaseTimestamp) {
                  // Local is newer - push local → Firebase (but only if we have local message)
                  if (localMessage != null) {
                    await _pushLocalToFirebase(messageId, localMessage);
                    continue; // Skip pulling this document
                  }
                }
              }
              
              // Pull Firebase → local (or apply if no local timestamp)
              await _handleActionUpdate(messageId, actionData);
            }
          }
          
          // If local has data but Firebase doesn't have either document, push local → Firebase
          if (localMessage != null && statusDoc == null && actionDoc == null) {
            await _pushLocalToFirebase(messageId, localMessage);
          }
        }
        
        debugPrint('[FirebaseSync] Completed reconciliation of Firebase and local values');
      });
    } catch (e) {
      _logFirebaseSync('Error loading initial values: $e');
    }
  }
  
  /// Extract timestamp from Firebase lastModified field (returns Unix milliseconds)
  int? _extractTimestamp(dynamic lastModifiedObj) {
    if (lastModifiedObj == null) return null;
    
    if (lastModifiedObj is Timestamp) {
      return lastModifiedObj.millisecondsSinceEpoch;
    } else if (lastModifiedObj is int) {
      return lastModifiedObj;
    } else if (lastModifiedObj is String) {
      try {
        final dt = DateTime.parse(lastModifiedObj);
        return dt.millisecondsSinceEpoch;
      } catch (_) {}
    }
    return null;
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
  /// Pushes to separate documents: {messageId}_status and {messageId}_action
  Future<void> _pushLocalToFirebase(String messageId, MessageIndex localMessage) async {
    try {
      if (!_syncEnabled || _emailMetaCollection == null) return;
      
      await _runOnMainThread(() async {
        // Push status document
        final statusDocId = '${messageId}_status';
        final statusDoc = _emailMetaCollection!.doc(statusDocId);
        final statusData = <String, dynamic>{
          'localTagPersonal': localMessage.localTagPersonal,
          'lastModified': FieldValue.serverTimestamp(),
        };
        
        final statusDocExists = (await statusDoc.get()).exists;
        if (!statusDocExists) {
          await statusDoc.set(statusData, SetOptions(merge: true));
        } else {
          await statusDoc.update(statusData);
        }
        
        // Push action document
        final actionDocId = '${messageId}_action';
        final actionDoc = _emailMetaCollection!.doc(actionDocId);
        
        if (localMessage.hasAction && localMessage.actionInsightText != null && localMessage.actionInsightText!.isNotEmpty) {
          // Action exists - push action fields
          final actionData = <String, dynamic>{
            'actionInsightText': localMessage.actionInsightText,
            'lastModified': FieldValue.serverTimestamp(),
          };
          if (localMessage.actionDate != null) {
            actionData['actionDate'] = localMessage.actionDate!.toIso8601String();
          }
          actionData['actionComplete'] = localMessage.actionComplete;
          
          final actionDocExists = (await actionDoc.get()).exists;
          if (!actionDocExists) {
            await actionDoc.set(actionData, SetOptions(merge: true));
          } else {
            await actionDoc.update(actionData);
          }
        } else {
          // Action removed - delete fields in Firebase
          final actionData = <String, dynamic>{
            'actionInsightText': FieldValue.delete(),
            'actionDate': FieldValue.delete(),
            'actionComplete': FieldValue.delete(),
            'lastModified': FieldValue.serverTimestamp(),
          };
          
          final actionDocExists = (await actionDoc.get()).exists;
          if (actionDocExists) {
            await actionDoc.update(actionData);
          }
          // If document doesn't exist, no need to create it just to delete fields
          
          if (kDebugMode) {
            _logFirebaseSync('Removing action in Firebase (_pushLocalToFirebase): messageId=$messageId (using FieldValue.delete())');
          }
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
                final docId = docChange.doc.id;
                final changeType = docChange.type.toString();
                final data = docChange.doc.data() as Map<String, dynamic>?;
                
                if (kDebugMode) {
                  _logFirebaseSync('[LISTENER] docId=$docId, changeType=$changeType, hasMetadata=${docChange.doc.metadata.hasPendingWrites}, isFromCache=${docChange.doc.metadata.isFromCache}');
                }
                
                if (data == null) continue;
                
                // Determine document type and extract messageId
                final String messageId;
                bool isActionDoc = false;
                bool isStatusDoc = false;
                
                if (docId.endsWith('_action')) {
                  messageId = docId.substring(0, docId.length - '_action'.length);
                  isActionDoc = true;
                } else if (docId.endsWith('_status')) {
                  messageId = docId.substring(0, docId.length - '_status'.length);
                  isStatusDoc = true;
                } else {
                  // Legacy document format (old structure) - skip for now or handle migration
                  if (kDebugMode) {
                    _logFirebaseSync('[LISTENER] Skipping legacy document format: $docId');
                  }
                  continue;
                }
                
                // Check if this is a pending write from our own local update
                if (docChange.doc.metadata.hasPendingWrites) {
                  if (kDebugMode) {
                    _logFirebaseSync('[LISTENER] SKIP_PENDING_WRITE docId=$docId, messageId=$messageId (local pending write)');
                  }
                  // This is our own pending write - skip it since we already processed it locally
                  continue;
                }
                
                if (kDebugMode) {
                  _logFirebaseSync('[LISTENER] Processing docId=$docId, messageId=$messageId, isAction=$isActionDoc, isStatus=$isStatusDoc');
                }
                
                // Process this email change based on document type
                try {
                  if (isStatusDoc) {
                    await _handleStatusUpdate(messageId, data);
                  } else if (isActionDoc) {
                    await _handleActionUpdate(messageId, data);
                  }
                } catch (e) {
                  _logFirebaseSync('Error processing update for $docId: $e');
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
  /// Uses separate documents: {messageId}_action and {messageId}_status
  /// Only updates the documents for which parameters are provided
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

        if (targetCollection == null) return;

        // Determine which documents to update based on provided parameters
        // Since Dart can't distinguish "parameter not provided" from "parameter is null",
        // we use this heuristic: 
        // - Update action if action params are provided
        // - Update status if localTagPersonal is provided (even if null) OR if no action params
        //   (meaning caller is doing status-only update)
        final hasActionParams = actionInsightText != null || clearAction || actionDate != null || actionComplete != null;
        
        // Update status document if:
        // 1. localTagPersonal is not null (explicit value), OR
        // 2. No action params are provided (caller is doing status-only update, even if null)
        // This handles: status updates (with or without null), but skips if only action is being updated
        // Note: If both are provided, we update both (caller wants to update both)
        final shouldUpdateStatus = localTagPersonal != null || !hasActionParams;
        
        if (shouldUpdateStatus) {
          final statusDocId = '${messageId}_status';
          final statusDoc = targetCollection.doc(statusDocId);
          final statusData = <String, dynamic>{
            'lastModified': FieldValue.serverTimestamp(),
            'localTagPersonal': localTagPersonal, // Can be null to clear the field
          };
          
          final statusDocExists = (await statusDoc.get()).exists;
          if (!statusDocExists) {
            await statusDoc.set(statusData, SetOptions(merge: true));
          } else {
            await statusDoc.update(statusData);
          }
          
          if (kDebugMode) {
            _logFirebaseSync('[FIREBASE_PUSH_STATUS] messageId=$messageId, localTagPersonal=$localTagPersonal');
          }
        }
        
        // Update action document if action parameters are provided
        if (hasActionParams) {
          final actionDocId = '${messageId}_action';
          final actionDoc = targetCollection.doc(actionDocId);
          final hasAction = actionInsightText != null && actionInsightText.isNotEmpty;
          
          final actionData = <String, dynamic>{
            'lastModified': FieldValue.serverTimestamp(),
          };
          
          if (clearAction || !hasAction) {
            // Action removed - delete fields
            actionData['actionInsightText'] = FieldValue.delete();
            actionData['actionDate'] = FieldValue.delete();
            actionData['actionComplete'] = FieldValue.delete();
            if (kDebugMode) {
              _logFirebaseSync('Removing action in Firebase: messageId=$messageId (using FieldValue.delete())');
            }
          } else if (hasAction) {
            // Action exists - push all fields
            actionData['actionInsightText'] = actionInsightText;
            if (actionDate != null) {
              actionData['actionDate'] = actionDate.toIso8601String();
            }
            actionData['actionComplete'] = actionComplete ?? false;
          }
          
          final actionDocExists = (await actionDoc.get()).exists;
          if (!actionDocExists) {
            // For new documents, only include fields if action exists
            final newActionData = <String, dynamic>{
              'lastModified': FieldValue.serverTimestamp(),
            };
            if (hasAction) {
              newActionData['actionInsightText'] = actionInsightText;
              if (actionDate != null) {
                newActionData['actionDate'] = actionDate.toIso8601String();
              }
              newActionData['actionComplete'] = actionComplete ?? false;
            }
            await actionDoc.set(newActionData, SetOptions(merge: true));
          } else {
            await actionDoc.update(actionData);
          }
          
          if (kDebugMode) {
            _logFirebaseSync('[FIREBASE_PUSH_ACTION] messageId=$messageId, actionInsightText=$actionInsightText, clearAction=$clearAction');
          }
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

  /// Handle a status document update from Firebase
  Future<void> _handleStatusUpdate(String messageId, Map<String, dynamic> data) async {
    try {
      final repo = MessageRepository();
      final localMessage = await repo.getById(messageId);
      
      // Get localTagPersonal from Firebase document (direct fields, not nested in 'current')
      final firebaseTagValue = data['localTagPersonal'];
      final hasFirebaseField = data.containsKey('localTagPersonal');
      
      String? firebaseTag;
      if (hasFirebaseField) {
        if (firebaseTagValue == null) {
          firebaseTag = null;
        } else {
          firebaseTag = firebaseTagValue.toString();
          if (firebaseTag.isEmpty) {
            firebaseTag = null;
          }
        }
      } else {
        firebaseTag = null;
      }
      
      final localTag = localMessage?.localTagPersonal;
      final shouldUpdate = firebaseTag != localTag;
      
      if (kDebugMode) {
        _logFirebaseSync('[FIREBASE_SYNC_STATUS] messageId=$messageId, firebase=${hasFirebaseField ? firebaseTag : "missing (→null)"}, local=$localTag, shouldUpdate=$shouldUpdate');
      }
      
      if (shouldUpdate) {
        await repo.updateLocalTag(messageId, firebaseTag, updateTimestamp: false);
        
        // Update sender preference locally
        if (localMessage != null && localMessage.from.isNotEmpty) {
          final fromStr = localMessage.from;
          final emailMatch = RegExp(r'<([^>]+)>').firstMatch(fromStr);
          final senderEmail = emailMatch?.group(1) ?? fromStr;
          if (senderEmail.contains('@')) {
            await repo.setSenderDefaultLocalTag(senderEmail.trim(), firebaseTag);
          }
        }
        
        if (onUpdateApplied != null) {
          onUpdateApplied!(
            messageId,
            firebaseTag,
            localMessage?.actionDate,
            localMessage?.actionInsightText,
            localMessage?.actionComplete ?? false,
            preserveExisting: true, // Preserve action fields when updating status
          );
        }
      }
    } catch (e) {
      _logFirebaseSync('Error applying status update for $messageId: $e');
    }
  }
  
  /// Handle an action document update from Firebase
  Future<void> _handleActionUpdate(String messageId, Map<String, dynamic> data) async {
    try {
      final repo = MessageRepository();
      final localMessage = await repo.getById(messageId);
      
      // Get action fields from Firebase document (direct fields, not nested in 'current')
      final hasFirebaseActionText = data.containsKey('actionInsightText');
      final hasFirebaseActionDate = data.containsKey('actionDate');
      final hasFirebaseActionComplete = data.containsKey('actionComplete');
      
      String? firebaseActionText;
      if (hasFirebaseActionText) {
        final firebaseValue = data['actionInsightText'];
        if (firebaseValue != null) {
          final textStr = firebaseValue.toString();
          firebaseActionText = textStr.isEmpty ? null : textStr;
        } else {
          firebaseActionText = null;
        }
      } else {
        firebaseActionText = null;
      }
      
      final firebaseHasAction = firebaseActionText != null && firebaseActionText.isNotEmpty;
      
      DateTime? firebaseActionDate;
      if (hasFirebaseActionDate && data['actionDate'] != null) {
        try {
          firebaseActionDate = DateTime.parse(data['actionDate'].toString());
        } catch (_) {}
      }
      
      final firebaseActionComplete = hasFirebaseActionComplete
          ? data['actionComplete'] as bool?
          : null;
      
      final localActionDate = localMessage?.actionDate;
      final localActionText = localMessage?.actionInsightText;
      final localActionComplete = localMessage?.actionComplete ?? false;
      final localHasAction = localActionText != null && localActionText.isNotEmpty;
      
      if (kDebugMode) {
        _logFirebaseSync('[FIREBASE_SYNC_ACTION] messageId=$messageId, firebaseText=$firebaseActionText, localText=$localActionText, firebaseComplete=$firebaseActionComplete, localComplete=$localActionComplete');
      }
      
      bool needsUpdate = false;
      
      // Update actionInsightText based on Firebase state
      if (!firebaseHasAction && !localHasAction) {
        // Both are null - action text is in sync, but check other fields
        if (kDebugMode) {
          _logFirebaseSync('[FIREBASE_SYNC_ACTION] actionText in sync (both null)');
        }
      } else if (firebaseHasAction && localHasAction && firebaseActionText == localActionText) {
        // Both have same action text - text is in sync, but check other fields
        if (kDebugMode) {
          _logFirebaseSync('[FIREBASE_SYNC_ACTION] actionText in sync (same text: $firebaseActionText)');
        }
      } else if (!firebaseHasAction && localHasAction) {
        // Firebase removed action - remove locally
        needsUpdate = true;
        if (kDebugMode) {
          _logFirebaseSync('[FIREBASE_SYNC_ACTION] REMOVE messageId=$messageId (Firebase null, local has action)');
        }
      } else if (firebaseHasAction && !localHasAction) {
        // Firebase has action, local doesn't - add it
        needsUpdate = true;
        if (kDebugMode) {
          _logFirebaseSync('[FIREBASE_SYNC_ACTION] ADD messageId=$messageId (Firebase: $firebaseActionText, local null)');
        }
      } else if (firebaseHasAction && firebaseActionText != localActionText) {
        // Firebase has different action - update
        needsUpdate = true;
        if (kDebugMode) {
          _logFirebaseSync('[FIREBASE_SYNC_ACTION] UPDATE messageId=$messageId (Firebase: $firebaseActionText, local: $localActionText)');
        }
      }
      
      // Update actionDate if Firebase has it and different
      if (hasFirebaseActionDate && firebaseActionDate?.toIso8601String() != localActionDate?.toIso8601String()) {
        needsUpdate = true;
        if (kDebugMode) {
          _logFirebaseSync('[FIREBASE_SYNC_ACTION] actionDate changed: firebase=$firebaseActionDate, local=$localActionDate');
        }
      }
      
      // Update complete if key present and different (check this even if action text is the same)
      if (hasFirebaseActionComplete && firebaseActionComplete != localActionComplete) {
        needsUpdate = true;
        if (kDebugMode) {
          _logFirebaseSync('[FIREBASE_SYNC_ACTION] actionComplete changed: firebase=$firebaseActionComplete, local=$localActionComplete');
        }
      }
      
      if (!needsUpdate) {
        if (kDebugMode) {
          _logFirebaseSync('[FIREBASE_SYNC_ACTION] NO_CHANGE messageId=$messageId (all fields in sync)');
        }
        return; // No changes needed
      }
      
      if (needsUpdate) {
        // Determine final values: use Firebase values when provided, otherwise preserve local values
        final finalActionDate = !firebaseHasAction 
            ? null  // No action in Firebase - clear date
            : (hasFirebaseActionDate ? firebaseActionDate : localActionDate);  // Use Firebase date if provided, else preserve local
        final finalActionText = !firebaseHasAction 
            ? null  // No action in Firebase - clear text
            : firebaseActionText;  // Use Firebase text (we know it's not null because firebaseHasAction is true)
        final finalActionComplete = !firebaseHasAction 
            ? false  // No action in Firebase - set complete to false
            : (hasFirebaseActionComplete ? firebaseActionComplete : localActionComplete);  // Use Firebase complete if provided, else preserve local
        
        if (kDebugMode) {
          _logFirebaseSync('[FIREBASE_SYNC_ACTION] DB_UPDATE messageId=$messageId, actionText=$finalActionText, actionComplete=$finalActionComplete');
        }
        
        await repo.updateAction(
          messageId,
          finalActionDate,
          finalActionText,
          null, // confidence
          finalActionComplete,
          false, // updateTimestamp = false
        );
        
        if (onUpdateApplied != null) {
          onUpdateApplied!(
            messageId,
            localMessage?.localTagPersonal,
            finalActionDate,
            finalActionText,
            finalActionComplete,
            preserveExisting: true, // Preserve status fields when updating action
          );
        }
      }
    } catch (e) {
      _logFirebaseSync('Error applying action update for $messageId: $e');
    }
  }
  

  /// Sender preferences are no longer synced from Firebase
  /// This method is kept for backward compatibility but does nothing
  // ignore: unused_element
  @Deprecated('Sender preferences are no longer synced. They are derived from emailMeta.')
  // ignore: unused_element
  Future<void> _handleSenderPrefsUpdate(Map<Object?, Object?> data) async {}

}

