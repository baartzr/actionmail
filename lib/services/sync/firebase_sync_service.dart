import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:device_info_plus/device_info_plus.dart';
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
  static const String _prefsKeySmsSyncToDesktop = 'firebase_sms_sync_to_desktop';
  // ignore: unused_field
  static const String _prefsKeyUserId = 'firebase_user_id';
  static String _prefsKeyLastSyncTimestamp(String userId) => 'firebase_last_sync_$userId';
  
  FirebaseFirestore? _firestore;
  CollectionReference? _userCollection;
  DocumentReference? _userDoc;
  CollectionReference? _emailMetaCollection; // Subcollection for email metadata
  CollectionReference? _smsMessagesCollection; // Subcollection for SMS messages
  String? _userId;
  bool _syncEnabled = false;
  StreamSubscription<QuerySnapshot>? _emailMetaSubscription; // Real-time listener subscription
  StreamSubscription<QuerySnapshot>? _smsMessagesSubscription; // Real-time listener for SMS messages
  
  /// Callback when a new SMS message is received from Firebase and saved locally
  void Function(MessageIndex message)? onSmsReceived;
  // Retry state for delayed initialization when Firebase isn't ready yet
  Timer? _initRetryTimer;
  int _initRetryCount = 0;
  static const int _maxInitRetries = 5;
  static const Object _paramNotProvided = Object();
  DateTime? _lastCursorLoadTime; // Track when we last did incremental cursor load to prevent duplicate processing
  final Set<String> _cursorProcessedMessageIds = {}; // Track messageIds processed by cursor to prevent duplicate listener updates
  String? _cachedDeviceId; // Cache device ID to avoid repeated lookups
  
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
        
        // Configure Firestore settings to enable offline persistence and reduce connection attempts
        // This helps reduce warnings when offline
        // Settings can only be set once, so wrap in try-catch
        try {
          _firestore!.settings = const Settings(
            persistenceEnabled: true, // Enable offline persistence
            cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED, // Allow unlimited cache
          );
        } catch (e) {
          // Settings may have already been set - this is fine
          _logFirebaseSync('Settings already configured or error setting: $e');
        }
        
        _logFirebaseSync('Initialized successfully, _firestore: ${_firestore != null}');
        _logFirebaseSync('Firebase app name: ${apps.first.name}');
        _logFirebaseSync('Firebase project ID: ${apps.first.options.projectId}');
        return _firestore != null;
      } catch (firestoreError) {
        _logFirebaseSync('ERROR: Failed to get Firestore instance: $firestoreError');
        _logFirebaseSync('Firebase apps exist but Firestore cannot be accessed');
        _logFirebaseSync('This may indicate a network or permissions issue');
        _logFirebaseSync('Firestore will work in offline mode when network is unavailable');
        // Don't return false - allow Firestore to work offline
        _firestore = FirebaseFirestore.instance;
        return _firestore != null;
      }
    } catch (e, stackTrace) {
      _logFirebaseSync('Initialization error (Firebase may not be configured): $e');
      _logFirebaseSync('Stack trace: $stackTrace');
      _logFirebaseSync('On desktop, run: flutterfire configure');
      _logFirebaseSync('Working directory: ${Directory.current.path}');
      return false;
    }
  }

  /// Get unique device ID for sourceDevice tracking
  /// Caches the result to avoid repeated lookups
  Future<String> _getDeviceId() async {
    if (_cachedDeviceId != null) {
      return _cachedDeviceId!;
    }
    
    try {
      final deviceInfo = DeviceInfoPlugin();
      String deviceId;
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id; // Android ID (persistent, resets on factory reset)
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? 'ios-unknown';
      } else if (Platform.isWindows) {
        // For Windows, use a combination of machine GUID and user
        final windowsInfo = await deviceInfo.windowsInfo;
        deviceId = windowsInfo.computerName;
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        deviceId = macInfo.computerName;
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        deviceId = linuxInfo.machineId ?? 'linux-unknown';
      } else {
        deviceId = 'unknown-platform';
      }
      
      _cachedDeviceId = deviceId;
      return deviceId;
    } catch (e) {
      _logFirebaseSync('Error getting device ID: $e');
      // Fallback to a generated ID stored in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final fallbackKey = 'firebase_device_id_fallback';
      String? fallbackId = prefs.getString(fallbackKey);
      if (fallbackId == null) {
        fallbackId = 'device-${DateTime.now().millisecondsSinceEpoch}';
        await prefs.setString(fallbackKey, fallbackId);
      }
      _cachedDeviceId = fallbackId;
      return fallbackId;
    }
  }

  /// Check if sync is enabled
  Future<bool> isSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeySyncEnabled) ?? false;
  }

  /// Check if SMS sync to desktop is enabled
  Future<bool> isSmsSyncToDesktopEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeySmsSyncToDesktop) ?? false;
  }

  /// Enable or disable SMS sync to desktop
  Future<void> setSmsSyncToDesktopEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeySmsSyncToDesktop, enabled);
    debugPrint('[FirebaseSync] SMS sync to desktop ${enabled ? "enabled" : "disabled"}');
    
    // If user is already initialized and Firebase sync is enabled, restart SMS listener
    if (_userId != null && _syncEnabled && _smsMessagesCollection != null) {
      if (enabled) {
        await _startSmsListening();
      } else {
        await _stopSmsListening();
      }
    }
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
          _smsMessagesCollection = _userDoc!.collection('smsMessages'); // Subcollection for SMS messages
          _logFirebaseSync('Collections set up, _userDoc: ${_userDoc != null}, _emailMetaCollection: ${_emailMetaCollection != null}, _smsMessagesCollection: ${_smsMessagesCollection != null}');

          // Start listening (must be on platform thread)
          await _startListening();
          await _startSmsListening();
          _logFirebaseSync('Started listening');
          
          // Load initial values in background (must also be on platform thread)
          unawaited(_loadInitialValues());
          
          _logFirebaseSync('User initialized successfully: $userId, _userDoc: ${_userDoc != null}, _emailMetaCollection: ${_emailMetaCollection != null}');
        });
    } else {
      _logFirebaseSync('Cannot initialize user: _firestore is ${_firestore != null ? "set" : "null"}, enabled is $enabled');
    }
  }

  /// Check if a document was written by this device (to prevent feedback loops)
  /// Returns true if sourceDevice field matches current device ID
  Future<bool> _isFromCurrentDevice(Map<String, dynamic>? data) async {
    if (data == null) return false;
    final sourceDevice = data['sourceDevice'] as String?;
    if (sourceDevice == null) return false;
    final currentDeviceId = await _getDeviceId();
    return sourceDevice == currentDeviceId;
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
  /// Uses incremental cursor: only processes documents modified since last sync
  /// Uses timestamp comparison: if local.lastUpdated > firebase.lastModified, push local → Firebase
  /// Otherwise, pull Firebase → local
  /// NOTE: This must be called from the main thread context
  Future<void> _loadInitialValues() async {
    if (_emailMetaCollection == null || _userId == null) return;
    
    try {
      // Get last sync timestamp from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final lastSyncTimestampMs = prefs.getInt(_prefsKeyLastSyncTimestamp(_userId!));
      final lastSyncTimestamp = lastSyncTimestampMs != null 
          ? DateTime.fromMillisecondsSinceEpoch(lastSyncTimestampMs)
          : null;
      
      if (kDebugMode) {
        _logFirebaseSync('[LOAD_INITIAL] Starting incremental load, lastSync=${lastSyncTimestamp?.toIso8601String() ?? "never"}');
      }
      
      // Clear processed messageIds set for this cursor load
      _cursorProcessedMessageIds.clear();
      
      // Query documents - if we have a timestamp, filter by lastModified
      // Note: This requires a Firestore index on lastModified, but will work without it (just slower)
      Query query = _emailMetaCollection!;
      if (lastSyncTimestamp != null) {
        // Query documents modified since last sync
        query = query.where('lastModified', isGreaterThan: Timestamp.fromDate(lastSyncTimestamp));
      }
      
      // Load documents from Firebase - ensure .get() is called on platform thread
      final snapshot = await _runOnMainThread(() => query.get());
      
      if (kDebugMode) {
        _logFirebaseSync('[LOAD_INITIAL] Found ${snapshot.docs.length} document(s) to process');
      }
      
      // Reconcile each document (non-blocking, but ensure Firebase operations on main thread)
      // Use scheduleMicrotask to ensure immediate execution on main thread
      scheduleMicrotask(() async {
        final repo = MessageRepository();
        int processedCount = 0;
        int skippedCount = 0;
        
        // Group documents by messageId and type
        final statusDocs = <String, DocumentSnapshot>{};
        final actionDocs = <String, DocumentSnapshot>{};
        int legacyDocCount = 0;
        
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
            legacyDocCount++;
          }
        }
        
        // Log summary of legacy documents instead of one per document
        if (kDebugMode && legacyDocCount > 0) {
          _logFirebaseSync('[LOAD_INITIAL] Skipped $legacyDocCount legacy document(s)');
        }
        
        // Get all unique messageIds
        final allMessageIds = <String>{...statusDocs.keys, ...actionDocs.keys};
        
        // Track all messageIds we're processing in this cursor load
        _cursorProcessedMessageIds.addAll(allMessageIds);
        
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
              
              // Skip if this document is older than last sync (shouldn't happen with query, but safety check)
              if (lastSyncTimestamp != null && firebaseTimestamp != null) {
                final docTimestamp = DateTime.fromMillisecondsSinceEpoch(firebaseTimestamp);
                if (docTimestamp.isBefore(lastSyncTimestamp) || docTimestamp.isAtSameMomentAs(lastSyncTimestamp)) {
                  skippedCount++;
                  continue;
                }
              }
              
              if (localTimestamp != null && firebaseTimestamp != null) {
                if (localTimestamp > firebaseTimestamp) {
                  // Local is newer - push local → Firebase (but only if we have local message)
                  if (localMessage != null) {
                    await _pushLocalToFirebase(messageId, localMessage);
                    processedCount++;
                    continue; // Skip pulling this document
                  }
                }
              }
              
              // Pull Firebase → local (or apply if no local timestamp)
              await _handleStatusUpdate(messageId, statusData);
              processedCount++;
            }
          }
          
          // Process action document
          final actionDoc = actionDocs[messageId];
          if (actionDoc != null) {
            final actionData = actionDoc.data() as Map<String, dynamic>?;
            if (actionData != null) {
              final firebaseTimestamp = _extractTimestamp(actionData['lastModified']);
              
              // Skip if this document is older than last sync (shouldn't happen with query, but safety check)
              if (lastSyncTimestamp != null && firebaseTimestamp != null) {
                final docTimestamp = DateTime.fromMillisecondsSinceEpoch(firebaseTimestamp);
                if (docTimestamp.isBefore(lastSyncTimestamp) || docTimestamp.isAtSameMomentAs(lastSyncTimestamp)) {
                  skippedCount++;
                  continue;
                }
              }
              
              if (localTimestamp != null && firebaseTimestamp != null) {
                if (localTimestamp > firebaseTimestamp) {
                  // Local is newer - push local → Firebase (but only if we have local message)
                  if (localMessage != null) {
                    await _pushLocalToFirebase(messageId, localMessage);
                    processedCount++;
                    continue; // Skip pulling this document
                  }
                }
              }
              
              // Pull Firebase → local (or apply if no local timestamp)
              await _handleActionUpdate(messageId, actionData);
              processedCount++;
            }
          }
          
          // If local has data but Firebase doesn't have either document, push local → Firebase
          if (localMessage != null && statusDoc == null && actionDoc == null) {
            await _pushLocalToFirebase(messageId, localMessage);
            processedCount++;
          }
        }
        
        // Update last sync timestamp to now
        final now = DateTime.now();
        await prefs.setInt(_prefsKeyLastSyncTimestamp(_userId!), now.millisecondsSinceEpoch);
        
        // Track cursor load time to prevent duplicate processing in listener
        _lastCursorLoadTime = now;
        
        // Clear processed messageIds after a delay to allow listener to skip stale cache updates
        // This prevents the set from growing indefinitely
        Future.delayed(const Duration(seconds: 5), () {
          _cursorProcessedMessageIds.clear();
          if (kDebugMode) {
            _logFirebaseSync('[LOAD_INITIAL] Cleared cursor processed messageIds set');
          }
        });
        
        if (kDebugMode) {
          _logFirebaseSync('[LOAD_INITIAL] Completed: processed $processedCount, skipped $skippedCount, updated cursor to ${now.toIso8601String()}');
        }
        debugPrint('[FirebaseSync] Completed reconciliation of Firebase and local values');
      });
    } catch (e) {
      _logFirebaseSync('Error loading initial values: $e');
      // If query fails (e.g., missing index), fall back to full scan
      if (kDebugMode) {
        _logFirebaseSync('[LOAD_INITIAL] Query failed, falling back to full scan');
      }
      await _loadInitialValuesFullScan();
    }
  }
  
  /// Fallback: Load all documents (used if incremental query fails)
  Future<void> _loadInitialValuesFullScan() async {
    if (_emailMetaCollection == null || _userId == null) return;
    
    try {
      // Load all documents from Firebase - ensure .get() is called on platform thread
      final snapshot = await _runOnMainThread(() => _emailMetaCollection!.get());
      
      // Reconcile each document (non-blocking, but ensure Firebase operations on main thread)
      // Use scheduleMicrotask to ensure immediate execution on main thread
      scheduleMicrotask(() async {
        final repo = MessageRepository();
        final prefs = await SharedPreferences.getInstance();
        
        // Group documents by messageId and type
        final statusDocs = <String, DocumentSnapshot>{};
        final actionDocs = <String, DocumentSnapshot>{};
        int legacyDocCount = 0;
        
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
            legacyDocCount++;
          }
        }
        
        // Log summary of legacy documents instead of one per document
        if (kDebugMode && legacyDocCount > 0) {
          _logFirebaseSync('[LOAD_INITIAL_FULL] Skipped $legacyDocCount legacy document(s)');
        }
        
        // Get all unique messageIds
        final allMessageIds = <String>{...statusDocs.keys, ...actionDocs.keys};
        
        // Track all messageIds we're processing in this cursor load
        _cursorProcessedMessageIds.addAll(allMessageIds);
        
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
        
        // Update last sync timestamp to now
        final now = DateTime.now();
        await prefs.setInt(_prefsKeyLastSyncTimestamp(_userId!), now.millisecondsSinceEpoch);
        
        // Track cursor load time to prevent duplicate processing in listener
        _lastCursorLoadTime = now;
        
        // Clear processed messageIds after a delay to allow listener to skip stale cache updates
        Future.delayed(const Duration(seconds: 5), () {
          _cursorProcessedMessageIds.clear();
          if (kDebugMode) {
            _logFirebaseSync('[LOAD_INITIAL_FULL] Cleared cursor processed messageIds set');
          }
        });
        
        debugPrint('[FirebaseSync] Completed reconciliation of Firebase and local values (full scan)');
      });
    } catch (e) {
      _logFirebaseSync('Error loading initial values (full scan): $e');
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
          'lastModified': FieldValue.serverTimestamp(),
        };
        final localTag = localMessage.localTagPersonal;
        if (localTag == null || localTag.isEmpty) {
          statusData['localTagPersonal'] = FieldValue.delete();
        } else {
          statusData['localTagPersonal'] = localTag;
        }
        
        await _writeDoc(statusDoc, statusData);
        
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
          
          await _writeDoc(actionDoc, actionData);
        } else {
          // Action removed - delete fields in Firebase
          final actionData = <String, dynamic>{
            'actionInsightText': FieldValue.delete(),
            'actionDate': FieldValue.delete(),
            'actionComplete': FieldValue.delete(),
            'lastModified': FieldValue.serverTimestamp(),
          };
          
          await _writeDoc(actionDoc, actionData);
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
                
                // Skip cache updates that happened right after a cursor load to prevent duplicate processing
                // This prevents flicker when resuming from background, especially for deletions
                if (docChange.doc.metadata.isFromCache) {
                  // Check if this messageId was just processed by cursor (most precise check)
                  if (_cursorProcessedMessageIds.contains(messageId)) {
                    if (kDebugMode) {
                      _logFirebaseSync('[LISTENER] SKIP_CACHE_CURSOR_PROCESSED docId=$docId, messageId=$messageId (already processed by cursor)');
                    }
                    continue;
                  }
                  // Fallback: also skip cache updates within 2 seconds of cursor load (time-based check)
                  if (_lastCursorLoadTime != null) {
                    final timeSinceCursorLoad = DateTime.now().difference(_lastCursorLoadTime!);
                    if (timeSinceCursorLoad.inSeconds < 2) {
                      if (kDebugMode) {
                        _logFirebaseSync('[LISTENER] SKIP_CACHE_AFTER_CURSOR docId=$docId, messageId=$messageId (cursor load ${timeSinceCursorLoad.inMilliseconds}ms ago)');
                      }
                      continue;
                    }
                  }
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
    await _stopSmsListening();
    debugPrint('[FirebaseSync] Stopped listening');
  }

  /// Pause Firestore when app goes to background (disables network to prevent reconnection attempts)
  Future<void> pauseWhenBackgrounded() async {
    if (_firestore != null && _syncEnabled) {
      _logFirebaseSync('Pausing Firestore (app backgrounded) - disabling network');
      try {
        // Cancel listeners first
        await _emailMetaSubscription?.cancel();
        _emailMetaSubscription = null;
        await _smsMessagesSubscription?.cancel();
        _smsMessagesSubscription = null;
        
        // Disable network to prevent Firestore from trying to reconnect
        // This stops the gRPC layer from attempting DNS resolution and connection
        await _firestore!.disableNetwork();
        _logFirebaseSync('Firestore network disabled');
      } catch (e) {
        _logFirebaseSync('Error pausing Firestore: $e');
      }
    }
  }

  /// Resume Firestore when app comes to foreground (enables network and restarts listeners)
  Future<void> resumeWhenForegrounded() async {
    if (_firestore != null && _syncEnabled) {
      _logFirebaseSync('Resuming Firestore (app foregrounded) - enabling network');
      try {
        // Enable network - Firestore will automatically retry when network is ready
        await _firestore!.enableNetwork();
        _logFirebaseSync('Firestore network enabled');
        
        // Then catch up on missed changes and restart listeners if user is initialized
        if (_userId != null && _emailMetaCollection != null) {
          // First, run incremental cursor load to catch up on changes missed while backgrounded
          // This prevents flicker by processing updates before the listener starts
          unawaited(_loadInitialValues());
          
          // Small delay to let cursor load start, then restart listeners
          // The listener will skip cache updates that were just processed by cursor
          await Future.delayed(const Duration(milliseconds: 100));
          await _startListening();
          await _startSmsListening();
          _logFirebaseSync('Firestore listeners restarted');
        }
      } catch (e) {
        _logFirebaseSync('Error resuming Firestore: $e');
      }
    }
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
    Object? localTagPersonal = _paramNotProvided,
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
        final hasLocalTagParam = localTagPersonal != _paramNotProvided;
        final String? localTagValue = hasLocalTagParam ? localTagPersonal as String? : null;
        
        // Update status document if:
        // 1. localTagPersonal is not null (explicit value), OR
        // 2. No action params are provided (caller is doing status-only update, even if null)
        // This handles: status updates (with or without null), but skips if only action is being updated
        // Note: If both are provided, we update both (caller wants to update both)
        final shouldUpdateStatus = hasLocalTagParam;
        
        if (shouldUpdateStatus) {
          final statusDocId = '${messageId}_status';
          final statusDoc = targetCollection.doc(statusDocId);
          final statusData = <String, dynamic>{
            'lastModified': FieldValue.serverTimestamp(),
          };
          if (localTagValue == null || localTagValue.isEmpty) {
            statusData['localTagPersonal'] = FieldValue.delete();
          } else {
            statusData['localTagPersonal'] = localTagValue;
          }
          
          await _writeDoc(statusDoc, statusData);
          
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
          
          await _writeDoc(actionDoc, actionData);
          
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

  Future<void> _writeDoc(DocumentReference doc, Map<String, dynamic> data) async {
    final Map<String, dynamic> setData = {};
    final Map<String, dynamic> deleteData = {};

    data.forEach((key, value) {
      if (_isFieldValueDelete(value)) {
        deleteData[key] = value;
      } else {
        setData[key] = value;
      }
    });

    if (setData.isNotEmpty) {
      await doc.set(setData, SetOptions(merge: true));
    }

    if (deleteData.isNotEmpty) {
      try {
        await doc.update(deleteData);
      } on FirebaseException catch (e) {
        if (e.code != 'not-found') {
          rethrow;
        }
        // Nothing to delete if doc doesn't exist
      }
    }
  }

  bool _isFieldValueDelete(dynamic value) {
    if (value is FieldValue) {
      return value == FieldValue.delete();
    }
    return false;
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
            preserveExisting: false, // Remote action is source of truth; allow clears to propagate
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

  // ========== SMS Sync Methods ==========

  /// Sync SMS message to Firebase
  /// Only syncs SMS messages (identified by id starting with 'sms_')
  /// Includes sourceDevice to prevent feedback loops
  Future<void> syncSmsMessage(MessageIndex smsMessage) async {
    if (kDebugMode) {
      _logFirebaseSync('[FIREBASE_SYNC_SMS] >>> syncSmsMessage CALLED: messageId=${smsMessage.id}, from=${smsMessage.from}, timestamp=${smsMessage.internalDate.toIso8601String()}');
    }
    try {
      if (!_syncEnabled) {
        _syncEnabled = await isSyncEnabled();
        if (!_syncEnabled) {
          if (kDebugMode) {
            _logFirebaseSync('[FIREBASE_SYNC_SMS] Skipping: Firebase sync not enabled');
          }
          return;
        }
      }

      // Check if SMS sync to desktop is enabled
      final smsSyncToDesktop = await isSmsSyncToDesktopEnabled();
      if (!smsSyncToDesktop) {
        if (kDebugMode) {
          _logFirebaseSync('[FIREBASE_SYNC_SMS] Skipping: SMS sync to desktop not enabled');
        }
        return;
      }

      // Only sync SMS messages
      if (!smsMessage.id.startsWith('sms_')) {
        if (kDebugMode) {
          _logFirebaseSync('[FIREBASE_SYNC_SMS] Skipping: Not an SMS message (id=${smsMessage.id})');
        }
        return;
      }

      if (_firestore == null) {
        final initialized = await initialize();
        if (!initialized) {
          if (kDebugMode) {
            _logFirebaseSync('[FIREBASE_SYNC_SMS] Skipping: Firebase not initialized');
          }
          return;
        }
      }

      // Auto-initialize user if not already initialized
      if (_userId == null || _smsMessagesCollection == null) {
        // Try to get account email from the SMS message
        final accountEmail = smsMessage.accountEmail;
        if (accountEmail != null && accountEmail.isNotEmpty) {
          if (kDebugMode) {
            _logFirebaseSync('[FIREBASE_SYNC_SMS] User not initialized, initializing with accountEmail=$accountEmail');
          }
          await initializeUser(accountEmail);
          // Wait a bit for initialization to complete
          await Future.delayed(const Duration(milliseconds: 500));
        }
        
        // Check again after initialization attempt
        if (_userId == null || _smsMessagesCollection == null) {
          if (kDebugMode) {
            _logFirebaseSync('[FIREBASE_SYNC_SMS] Skipping: User still not initialized after attempt (userId=$_userId, collection=${_smsMessagesCollection != null})');
          }
          return;
        }
      }

      await _runOnMainThread(() async {
        final deviceId = await _getDeviceId();
        final docRef = _smsMessagesCollection!.doc(smsMessage.id);
        
        final data = <String, dynamic>{
          'id': smsMessage.id,
          'threadId': smsMessage.threadId,
          'accountId': smsMessage.accountId,
          'accountEmail': smsMessage.accountEmail,
          'internalDate': smsMessage.internalDate.toIso8601String(),
          'from': smsMessage.from,
          'to': smsMessage.to,
          'subject': smsMessage.subject,
          'snippet': smsMessage.snippet,
          'hasAttachments': smsMessage.hasAttachments,
          'isRead': smsMessage.isRead,
          'isStarred': smsMessage.isStarred,
          'folderLabel': smsMessage.folderLabel,
          'localTagPersonal': smsMessage.localTagPersonal ?? FieldValue.delete(),
          'actionDate': smsMessage.actionDate?.toIso8601String() ?? FieldValue.delete(),
          'actionInsightText': smsMessage.actionInsightText ?? FieldValue.delete(),
          'actionComplete': smsMessage.actionComplete ? true : FieldValue.delete(),
          'hasAction': smsMessage.hasAction ? true : FieldValue.delete(),
          'sourceDevice': deviceId, // Track which device wrote this
          'lastModified': FieldValue.serverTimestamp(),
        };

        try {
          // Split data into set and delete operations
          final Map<String, dynamic> setData = {};
          final Map<String, dynamic> deleteData = {};

          data.forEach((key, value) {
            if (_isFieldValueDelete(value)) {
              deleteData[key] = value;
            } else {
              setData[key] = value;
            }
          });

          if (kDebugMode) {
            _logFirebaseSync('[FIREBASE_SYNC_SMS] Writing SMS: messageId=${smsMessage.id}, setFields=${setData.keys.join(", ")}, deleteFields=${deleteData.keys.join(", ")}');
          }

          // Write set data first (creates document if needed)
          if (setData.isNotEmpty) {
            await docRef.set(setData, SetOptions(merge: true));
            if (kDebugMode) {
              _logFirebaseSync('[FIREBASE_SYNC_SMS] Set operation completed for ${smsMessage.id}');
            }
          }

          // Then handle deletes (only if document exists)
          if (deleteData.isNotEmpty) {
            try {
              await docRef.update(deleteData);
              if (kDebugMode) {
                _logFirebaseSync('[FIREBASE_SYNC_SMS] Update (delete) operation completed for ${smsMessage.id}');
              }
            } on FirebaseException catch (e) {
              if (e.code != 'not-found') {
                rethrow;
              }
              // Document doesn't exist yet - that's fine, deletes aren't needed
              if (kDebugMode) {
                _logFirebaseSync('[FIREBASE_SYNC_SMS] Document ${smsMessage.id} doesn\'t exist yet, skipping delete operations');
              }
            }
          }
          
          // Verify the write succeeded
          final docSnapshot = await docRef.get();
          if (docSnapshot.exists) {
            if (kDebugMode) {
              _logFirebaseSync('[FIREBASE_SYNC_SMS] ✓ Verified SMS written to Firebase: messageId=${smsMessage.id}, phone=${smsMessage.from}, deviceId=$deviceId, collection=${_smsMessagesCollection!.path}');
            }
          } else {
            _logFirebaseSync('[FIREBASE_SYNC_SMS] ✗ ERROR: Document ${smsMessage.id} does not exist after write!');
          }
        } catch (writeError, stackTrace) {
          _logFirebaseSync('[FIREBASE_SYNC_SMS] ✗ Error writing SMS to Firebase: messageId=${smsMessage.id}, error=$writeError');
          _logFirebaseSync('[FIREBASE_SYNC_SMS] Stack trace: $stackTrace');
          rethrow;
        }
      });
    } catch (e, stackTrace) {
      _logFirebaseSync('Error syncing SMS message ${smsMessage.id}: $e');
      _logFirebaseSync('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Start listening to SMS messages from Firebase
  Future<void> _startSmsListening() async {
    if (_smsMessagesCollection == null || !_syncEnabled) {
      if (kDebugMode) {
        _logFirebaseSync('[SMS_LISTENER] Not starting: collection=${_smsMessagesCollection != null}, syncEnabled=$_syncEnabled');
      }
      return;
    }

    // Check if SMS sync to desktop is enabled
    final smsSyncToDesktop = await isSmsSyncToDesktopEnabled();
    if (!smsSyncToDesktop) {
      if (kDebugMode) {
        _logFirebaseSync('[SMS_LISTENER] Not starting: SMS sync to desktop is disabled');
      }
      return;
    }

    try {
      // Cancel any existing subscription
      await _smsMessagesSubscription?.cancel();
      
      if (kDebugMode) {
        _logFirebaseSync('[SMS_LISTENER] Starting SMS messages listener');
      }
      
      // The .snapshots() call creates a platform channel that must be created on the platform thread
      final binding = WidgetsBinding.instance;
      final completer = Completer<void>();
      binding.addPostFrameCallback((_) {
        // Create the listener on the platform thread
        _smsMessagesSubscription = _smsMessagesCollection!.snapshots().listen(
          (snapshot) {
            // Process on main thread - use scheduleMicrotask for async operations
            scheduleMicrotask(() async {
              if (kDebugMode) {
                _logFirebaseSync('[SMS_LISTENER] Received snapshot with ${snapshot.docChanges.length} changes');
              }
              
              for (final docChange in snapshot.docChanges) {
                final docId = docChange.doc.id;
                final dataNullable = docChange.doc.data() as Map<String, dynamic>?;
                
                if (dataNullable == null) continue;
                
                // At this point, data is guaranteed to be non-null
                final data = dataNullable;
                
                // Skip pending writes (our own writes)
                if (docChange.doc.metadata.hasPendingWrites) {
                  if (kDebugMode) {
                    _logFirebaseSync('[SMS_LISTENER] SKIP_PENDING_WRITE docId=$docId (local pending write)');
                  }
                  continue;
                }
                
                // Skip if this SMS was written by this device (prevent feedback loop)
                final isFromCurrentDevice = await _isFromCurrentDevice(data);
                if (isFromCurrentDevice) {
                  if (kDebugMode) {
                    _logFirebaseSync('[SMS_LISTENER] SKIP_SOURCE_DEVICE docId=$docId (from current device)');
                  }
                  continue;
                }
                
                // Process the SMS update
                try {
                  await _handleSmsUpdate(docId, data);
                } catch (e) {
                  _logFirebaseSync('Error processing SMS update for $docId: $e');
                }
              }
            });
          },
          onError: (error) {
            _logFirebaseSync('Error in SMS messages listener: $error');
          },
        );
        debugPrint('[FirebaseSync] Started real-time listener for SMS messages');
        if (kDebugMode) {
          _logFirebaseSync('[SMS_LISTENER] Listener created successfully for collection: ${_smsMessagesCollection!.path}');
        }
        completer.complete();
      });
      await completer.future;
    } catch (e) {
      _logFirebaseSync('Error starting SMS listener: $e');
    }
  }

  /// Handle an SMS message update from Firebase
  Future<void> _handleSmsUpdate(String messageId, Map<String, dynamic> data) async {
    try {
      final repo = MessageRepository();
      
      // Check if message already exists locally
      final existing = await repo.getById(messageId);
      
      // Parse SMS data from Firebase
      final internalDateStr = data['internalDate'] as String?;
      if (internalDateStr == null) {
        _logFirebaseSync('Error handling SMS update for $messageId: missing internalDate');
        return;
      }
      final internalDate = DateTime.parse(internalDateStr);
      final from = data['from'] as String? ?? '';
      final to = data['to'] as String? ?? '';
      final subject = data['subject'] as String? ?? '';
      final snippet = data['snippet'] as String?;
      final hasAttachments = (data['hasAttachments'] as bool?) ?? false;
      final isRead = (data['isRead'] as bool?) ?? false;
      final isStarred = (data['isStarred'] as bool?) ?? false;
      final folderLabel = data['folderLabel'] as String? ?? 'INBOX';
      final localTagPersonal = data['localTagPersonal'] as String?;
      
      // Parse action fields
      DateTime? actionDate;
      if (data.containsKey('actionDate') && data['actionDate'] != null) {
        try {
          actionDate = DateTime.parse(data['actionDate'] as String);
        } catch (_) {}
      }
      
      final actionInsightText = data['actionInsightText'] as String?;
      final actionComplete = (data['actionComplete'] as bool?) ?? false;
      final hasAction = (data['hasAction'] as bool?) ?? false;
      
      // Create MessageIndex from Firebase data
      final accountId = data['accountId'] as String;
      if (kDebugMode) {
        _logFirebaseSync('[SMS_LISTENER] Processing SMS: messageId=$messageId, accountId=$accountId, folderLabel=$folderLabel');
      }
      
      final smsMessage = MessageIndex(
        id: messageId,
        threadId: data['threadId'] as String,
        accountId: accountId,
        accountEmail: data['accountEmail'] as String?,
        internalDate: internalDate,
        from: from,
        to: to,
        subject: subject,
        snippet: snippet,
        hasAttachments: hasAttachments,
        gmailCategories: [],
        gmailSmartLabels: [],
        localTagPersonal: localTagPersonal,
        subsLocal: false,
        shoppingLocal: false,
        unsubscribedLocal: false,
        actionDate: actionDate,
        actionInsightText: actionInsightText,
        actionComplete: actionComplete,
        hasAction: hasAction,
        isRead: isRead,
        isStarred: isStarred,
        isImportant: false,
        folderLabel: folderLabel,
      );
      
      // Upsert the message (will update if exists, insert if new)
      await repo.upsertMessages([smsMessage]);
      
      // Verify it was saved
      final saved = await repo.getById(messageId);
      if (kDebugMode) {
        _logFirebaseSync('[SMS_LISTENER] Processed SMS messageId=$messageId, from=$from, isNew=${existing == null}, saved=${saved != null}, accountId=$accountId, folderLabel=$folderLabel');
        if (saved == null) {
          _logFirebaseSync('[SMS_LISTENER] ⚠️ WARNING: SMS message $messageId was not saved to database!');
        }
      }
      
      // Notify callback if message was newly saved
      if (saved != null && existing == null) {
        onSmsReceived?.call(saved);
      }
    } catch (e) {
      _logFirebaseSync('Error handling SMS update for $messageId: $e');
    }
  }

  /// Stop SMS listener
  Future<void> _stopSmsListening() async {
    await _smsMessagesSubscription?.cancel();
    _smsMessagesSubscription = null;
    debugPrint('[FirebaseSync] Stopped SMS listening');
  }

  /// Debug method: List all SMS messages in Firebase
  /// This helps verify that SMS messages are actually being written
  Future<void> debugListSmsMessages() async {
    if (_smsMessagesCollection == null) {
      _logFirebaseSync('[DEBUG_SMS] SMS collection is null');
      return;
    }

    try {
      final snapshot = await _smsMessagesCollection!.limit(10).get();
      _logFirebaseSync('[DEBUG_SMS] Found ${snapshot.docs.length} SMS messages in Firebase:');
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null) {
          _logFirebaseSync('[DEBUG_SMS]   - ${doc.id}: from=${data['from']}, subject=${data['subject']}, timestamp=${data['internalDate']}');
        } else {
          _logFirebaseSync('[DEBUG_SMS]   - ${doc.id}: (no data)');
        }
      }
    } catch (e) {
      _logFirebaseSync('[DEBUG_SMS] Error listing SMS messages: $e');
    }
  }

}

