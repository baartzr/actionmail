import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:actionmail/data/models/message_index.dart';
import 'package:actionmail/data/models/gmail_message.dart';
import 'package:actionmail/services/gmail/gmail_sync_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:actionmail/firebase_options.dart';
import 'package:actionmail/services/sync/firebase_sync_service.dart';
import 'package:actionmail/services/auth/google_auth_service.dart';

/// Provider for Gmail sync service
final gmailSyncServiceProvider = Provider<GmailSyncService>((ref) {
  return GmailSyncService();
});

/// Provider for email list state
final emailListProvider = StateNotifierProvider<EmailListNotifier, AsyncValue<List<MessageIndex>>>((ref) {
  final syncService = ref.watch(gmailSyncServiceProvider);
  return EmailListNotifier(ref, syncService);
});

/// Loading flags for UI
final emailSyncingProvider = StateProvider<bool>((ref) => false);
final emailLoadingLocalProvider = StateProvider<bool>((ref) => false);

class EmailListNotifier extends StateNotifier<AsyncValue<List<MessageIndex>>> {
  final GmailSyncService _syncService;
  final Ref _ref;
  String? _currentAccountId;
  String _folderLabel = 'INBOX';
  Timer? _timer;
  bool _isInitialSyncing = false;
  bool _isViewingLocalFolder = false; // Track if viewing local folder (prevents sync overwrites)
  static const List<String> _allFolders = ['INBOX', 'SENT', 'SPAM', 'TRASH', 'ARCHIVE'];
  static bool _firebaseInitStarted = false;

  EmailListNotifier(this._ref, this._syncService) : super(const AsyncValue.loading());

  /// Load emails for an account: show local immediately, then background sync
  Future<void> loadEmails(String accountId, {String folderLabel = 'INBOX'}) async {
    _currentAccountId = accountId;
    _folderLabel = folderLabel;
    _isViewingLocalFolder = false; // Reset flag when loading Gmail folder

    // 1) Load Inbox from local DB (display immediately - will be empty if no historyID)
    try {
      if (folderLabel == 'INBOX') {
        // ignore: avoid_print
        print('[sync] loadEmails account=$accountId folder=$folderLabel (local first)');
        _ref.read(emailLoadingLocalProvider.notifier).state = true;
        final t0 = DateTime.now();
        final local = await _syncService.loadLocal(accountId, folderLabel: _folderLabel);
        final dt = DateTime.now().difference(t0).inMilliseconds;
        if (kDebugMode) {
          // ignore: avoid_print
          print('[perf] loadLocal($_folderLabel) returned ${local.length} in ${dt}ms');
        }
        state = AsyncValue.data(local);
        // Start Firebase init in background after local emails are visible
        unawaited(_startFirebaseAfterLocalLoad(accountId));
        _ref.read(emailLoadingLocalProvider.notifier).state = false;
      } else {
        state = const AsyncValue.data([]);
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }

    // 2) Background sync: check historyID and perform appropriate sync
    // This handles ALL folders via incremental sync (or initial full sync if no history)
    unawaited(_syncInboxOnStartup(accountId));
  }

  Future<void> _startFirebaseAfterLocalLoad(String accountId) async {
    if (_firebaseInitStarted) return;
    _firebaseInitStarted = true;
    try {
      final t0 = DateTime.now();
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      final ms = DateTime.now().difference(t0).inMilliseconds;
      if (kDebugMode) {
        // ignore: avoid_print
        print('[FirebaseInit] Firebase.initializeApp completed in ${ms}ms (post-local-load)');
      }
      final syncService = FirebaseSyncService();
      final initialized = await syncService.initialize();
      final enabled = await syncService.isSyncEnabled();
      if (initialized && enabled) {
        // Use account email as user ID
        final acct = await GoogleAuthService().ensureValidAccessToken(accountId);
        final email = acct?.email;
        if (email != null && email.isNotEmpty) {
          await syncService.initializeUser(email);
          if (kDebugMode) {
            // ignore: avoid_print
            print('[FirebaseInit] Firebase user initialized for $email');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[FirebaseInit] Post-local-load initialization error: $e');
      }
    }
  }

  /// Load emails for a folder: only reload from local DB, no sync
  Future<void> loadFolder(String accountId, {String? folderLabel}) async {
    _currentAccountId = accountId;
    if (folderLabel != null) {
      _folderLabel = folderLabel;
    }
    _isViewingLocalFolder = false; // Reset flag when loading Gmail folder
    try {
      // ignore: avoid_print
      print('[sync] loadFolder account=$accountId folder=$_folderLabel');
      _ref.read(emailLoadingLocalProvider.notifier).state = true;
      final t0 = DateTime.now();
      final local = await _syncService.loadLocal(accountId, folderLabel: _folderLabel);
      final dt = DateTime.now().difference(t0).inMilliseconds;
      if (kDebugMode) {
        // ignore: avoid_print
        print('[perf] loadFolder $_folderLabel returned ${local.length} in ${dt}ms');
      }
      state = AsyncValue.data(local);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
    _ref.read(emailLoadingLocalProvider.notifier).state = false;
  }

  /// Refresh emails: load from local immediately, then background sync
  Future<void> refresh(String accountId, {String? folderLabel}) async {
    _currentAccountId = accountId;
    if (folderLabel != null) {
      _folderLabel = folderLabel;
    }
    try {
      // ignore: avoid_print
      print('[sync] refresh account=$accountId folder=$_folderLabel');
      _ref.read(emailLoadingLocalProvider.notifier).state = true;
      final t0 = DateTime.now();
      final local = await _syncService.loadLocal(accountId, folderLabel: _folderLabel);
      final dt = DateTime.now().difference(t0).inMilliseconds;
      if (kDebugMode) {
        // ignore: avoid_print
        print('[perf] refresh loadLocal $_folderLabel returned ${local.length} in ${dt}ms');
      }
      state = AsyncValue.data(local);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
    _ref.read(emailLoadingLocalProvider.notifier).state = false;
    unawaited(_syncFolderAndUpdateCurrent());
  }

  void _startIncremental() {
    _timer?.cancel();
    if (_currentAccountId == null) return;
    _timer = Timer.periodic(const Duration(minutes: 2), (_) async {
      // Skip if initial sync is in progress
      if (_isInitialSyncing) {
        // ignore: avoid_print
        print('[sync] incremental tick skipped, initial sync in progress');
        return;
      }
      try {
        // Incremental sync always uses the latest historyID from DB
        final syncStart = DateTime.now();
        // ignore: avoid_print
        print('[sync] incremental tick account=$_currentAccountId');
        _ref.read(emailSyncingProvider.notifier).state = true;
        await _syncService.processPendingOps();
        // Run incremental sync (always uses latest historyID from DB)
        final newInboxMessages = await _syncService.incrementalSync(_currentAccountId!);
        // Reload Inbox from local DB to show updated emails
        // Only update if we're viewing INBOX and NOT viewing a local folder
        if (_folderLabel == 'INBOX' && !_isViewingLocalFolder) {
          final t0 = DateTime.now();
          final local = await _syncService.loadLocal(_currentAccountId!, folderLabel: 'INBOX');
          state = AsyncValue.data(local);
          final dt = DateTime.now().difference(t0).inMilliseconds;
          if (kDebugMode) {
            // ignore: avoid_print
            print('[perf] incremental reload INBOX ${local.length} in ${dt}ms');
          }
          final syncDuration = DateTime.now().difference(syncStart);
          // ignore: avoid_print
          print('[sync] incremental done count=${local.length}, total time=${syncDuration.inMilliseconds}ms');
        } else if (_isViewingLocalFolder) {
          // ignore: avoid_print
          print('[sync] incremental sync skipped - viewing local folder');
        }
        // Turn off loading indicator
        _ref.read(emailSyncingProvider.notifier).state = false;
        // Run Phase 1 and Phase 2 tagging in background
        if (newInboxMessages.isNotEmpty) {
          unawaited(_runBackgroundTagging(_currentAccountId!, newInboxMessages));
        }
      } catch (_) {
        _ref.read(emailSyncingProvider.notifier).state = false;
      }
    });
  }

  Future<void> _runBackgroundTagging(String accountId, List<GmailMessage> gmailMessages) async {
    // ignore: avoid_print
    print('[sync] starting background tagging for ${gmailMessages.length} messages');
    try {
      // Phase 1 tagging on message headers (INBOX emails only) - non-blocking
      unawaited(_syncService.phase1Tagging(accountId, gmailMessages));
      // Phase 2 tagging on payload in background (INBOX emails only) - non-blocking
      unawaited(_syncService.phase2TaggingNewMessages(accountId, gmailMessages));
    } catch (e) {
      // ignore: avoid_print
      print('[sync] background tagging error: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Sync all folders on startup: check historyID and perform appropriate sync
  Future<void> _syncInboxOnStartup(String accountId) async {
    try {
      // ignore: avoid_print
      print('[sync] syncInboxOnStartup account=$accountId');
      _ref.read(emailSyncingProvider.notifier).state = true;
      await _syncService.processPendingOps();
      
      // Check for historyID in DB
      final hasHistory = await _syncService.hasHistoryId(accountId);
      // ignore: avoid_print
      print('[sync] hasHistoryId check result: $hasHistory');
      List<GmailMessage> newInboxMessages = [];
      
      if (hasHistory) {
        // If historyID exists: run incremental sync using that historyID (handles all folders)
        // ignore: avoid_print
        print('[sync] historyID exists, doing incremental sync');
        newInboxMessages = await _syncService.incrementalSync(accountId);
        // Reload from local DB after incremental sync to show updated emails in UI
        // Only update if we're viewing INBOX and NOT viewing a local folder
        if (_currentAccountId == accountId && _folderLabel == 'INBOX' && !_isViewingLocalFolder) {
          final t0 = DateTime.now();
          final local = await _syncService.loadLocal(accountId, folderLabel: 'INBOX');
          // ignore: avoid_print
          print('[sync] incremental sync done, reloading INBOX, count=${local.length}');
          state = AsyncValue.data(local);
          final dt = DateTime.now().difference(t0).inMilliseconds;
          if (kDebugMode) {
            // ignore: avoid_print
            print('[perf] post-incremental reload INBOX in ${dt}ms');
          }
        }
      } else {
        // If no historyID: do initial full sync for all folders sequentially
        // ignore: avoid_print
        print('[sync] no historyID, doing initial full sync for all folders');
        _isInitialSyncing = true;
        try {
          for (final folder in _allFolders) {
            // ignore: avoid_print
            print('[sync] initial sync: fetching folder=$folder');
            await _syncService.syncMessages(accountId, folderLabel: folder);
            // After each folder sync, reload current folder from local DB to show updated emails in UI
            if (_currentAccountId == accountId) {
              final t0 = DateTime.now();
              final local = await _syncService.loadLocal(accountId, folderLabel: _folderLabel);
              // ignore: avoid_print
              print('[sync] initial sync: synced $folder, reloading $_folderLabel, count=${local.length}');
              state = AsyncValue.data(local);
              final dt = DateTime.now().difference(t0).inMilliseconds;
              if (kDebugMode) {
                // ignore: avoid_print
                print('[perf] initial sync reload $_folderLabel in ${dt}ms');
              }
            }
          }
        } finally {
          _isInitialSyncing = false;
        }
      }
      
      // Turn off loading indicator
      _ref.read(emailSyncingProvider.notifier).state = false;
      
      // Start the 2-minute incremental sync timer after sync completes
      _startIncremental();
      
      // Run Phase 1 and Phase 2 tagging in background
      if (newInboxMessages.isNotEmpty) {
        unawaited(_runBackgroundTagging(accountId, newInboxMessages));
      }
    } catch (_) {
      _ref.read(emailSyncingProvider.notifier).state = false;
    }
  }

  Future<void> _syncFolderAndUpdateCurrent() async {
    if (_currentAccountId == null) return;
    // Skip if initial sync is in progress
    if (_isInitialSyncing) {
      // ignore: avoid_print
      print('[sync] sync current skipped, initial sync in progress');
      return;
    }
    final accountId = _currentAccountId!;
    final currentFolder = _folderLabel;
    try {
      // ignore: avoid_print
      print('[sync] sync current account=$accountId folder=$currentFolder');
      _ref.read(emailSyncingProvider.notifier).state = true;
      await _syncService.processPendingOps();
      
      // Use incremental sync if history exists, otherwise fall back to full sync
      List<GmailMessage> newMessages = [];
      final hasHistory = await _syncService.hasHistoryId(accountId);
      if (hasHistory) {
        // ignore: avoid_print
        print('[sync] history exists, using incremental sync');
        newMessages = await _syncService.incrementalSync(accountId);
      } else {
        // ignore: avoid_print
        print('[sync] no history, using full sync for current folder');
        await _syncService.syncMessages(accountId, folderLabel: currentFolder);
      }
      
      // Reload local for current folder only if still on same folder
      if (_currentAccountId == accountId && _folderLabel == currentFolder) {
        final t0 = DateTime.now();
        final local = await _syncService.loadLocal(accountId, folderLabel: currentFolder);
        state = AsyncValue.data(local);
        // ignore: avoid_print
        print('[sync] sync current done count=${local.length}');
        final dt = DateTime.now().difference(t0).inMilliseconds;
        if (kDebugMode) {
          // ignore: avoid_print
          print('[perf] sync current reload $currentFolder in ${dt}ms');
        }
      }
      
      // Turn off loading indicator
      _ref.read(emailSyncingProvider.notifier).state = false;
      
      // Run Phase 1 and Phase 2 tagging in background for INBOX only
      if (currentFolder == 'INBOX' && newMessages.isNotEmpty) {
        unawaited(_runBackgroundTagging(accountId, newMessages));
      }
    } catch (_) {
      _ref.read(emailSyncingProvider.notifier).state = false;
    }
  }


  /// Update a message's local tag in-memory without triggering loading state
  void setLocalTag(String messageId, String? localTag) {
    final current = state;
    if (current is AsyncData<List<MessageIndex>>) {
      final list = current.value;
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        final updated = List<MessageIndex>.from(list);
        updated[idx] = updated[idx].copyWith(localTagPersonal: localTag);
        state = AsyncValue.data(updated);
      }
    }
  }

  void setStarred(String messageId, bool isStarred) {
    final current = state;
    if (current is AsyncData<List<MessageIndex>>) {
      final list = current.value;
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        final updated = List<MessageIndex>.from(list);
        updated[idx] = updated[idx].copyWith(isStarred: isStarred);
        state = AsyncValue.data(updated);
      }
    }
  }

  void setRead(String messageId, bool isRead) {
    final current = state;
    if (current is AsyncData<List<MessageIndex>>) {
      final list = current.value;
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        final updated = List<MessageIndex>.from(list);
        updated[idx] = updated[idx].copyWith(isRead: isRead);
        state = AsyncValue.data(updated);
      }
    }
  }

  void setFolder(String messageId, String newFolderLabel) {
    final current = state;
    if (current is AsyncData<List<MessageIndex>>) {
      final list = current.value;
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        final updated = List<MessageIndex>.from(list);
        updated[idx] = updated[idx].copyWith(folderLabel: newFolderLabel);
        state = AsyncValue.data(updated);
      }
    }
  }

  void restoreFolder(String messageId, String newFolderLabel) {
    // Update to restored folder in-memory
    setFolder(messageId, newFolderLabel);
  }

  void setAction(String messageId, DateTime? actionDate, String? actionText, {bool? actionComplete}) {
    final current = state;
    if (current is AsyncData<List<MessageIndex>>) {
      final list = current.value;
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        final updated = List<MessageIndex>.from(list);
        // Determine if action exists (has date or text)
        final hasAction = actionDate != null || (actionText != null && actionText.isNotEmpty);
        updated[idx] = updated[idx].copyWith(
          actionDate: actionDate,
          actionInsightText: actionText,
          actionComplete: actionComplete,
          hasAction: hasAction,
        );
        state = AsyncValue.data(updated);
      }
    }
  }

  void removeMessage(String messageId) {
    final current = state;
    if (current is AsyncData<List<MessageIndex>>) {
      final list = current.value;
      final updated = list.where((m) => m.id != messageId).toList();
      state = AsyncValue.data(updated);
    }
  }

  /// Silently reload emails from local DB (without showing loading state)
  /// Used after Phase 2 tagging completes to update action dates in UI
  Future<void> reloadLocalEmails() async {
    if (_currentAccountId == null) return;
    try {
      final local = await _syncService.loadLocal(_currentAccountId!, folderLabel: _folderLabel);
      if (state is AsyncData<List<MessageIndex>>) {
        state = AsyncValue.data(local);
        // ignore: avoid_print
        print('[EmailList] Silently reloaded ${local.length} emails after Phase 2');
      }
    } catch (e) {
      // ignore: avoid_print
      print('[EmailList] Failed to silently reload: $e');
    }
  }

  /// Clear the email list (e.g., when no accounts are selected)
  void clearEmails() {
    state = const AsyncValue.data([]);
    _currentAccountId = null;
  }

  /// Set emails directly (used for local folder emails)
  void setEmails(List<MessageIndex> emails) {
    state = AsyncValue.data(emails);
    _isViewingLocalFolder = true; // Mark that we're viewing local folder
  }
}

