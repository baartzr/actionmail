import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domail/data/models/message_index.dart';
import 'package:domail/data/models/gmail_message.dart';
import 'package:domail/services/gmail/gmail_sync_service.dart';
import 'package:domail/services/sync/firebase_sync_service.dart';
import 'package:domail/services/sync/firebase_init.dart';
import 'package:domail/services/auth/google_auth_service.dart';

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

/// Auth failure flag - set when incremental sync fails due to invalid token
/// HomeScreen watches this and shows re-auth dialog
final authFailureProvider = StateProvider<String?>((ref) => null);

/// Network error flag - set when sync fails due to network issues
/// HomeScreen watches this and shows network error message
final networkErrorProvider = StateProvider<bool>((ref) => false);

/// Provider for conversation mode state (persists during app runtime only)
final conversationModeProvider = StateProvider<bool>((ref) => false);

class EmailListNotifier extends StateNotifier<AsyncValue<List<MessageIndex>>> {
  final GmailSyncService _syncService;
  final Ref _ref;
  String? _currentAccountId;
  String _folderLabel = 'INBOX';
  Timer? _timer;
  bool _isInitialSyncing = false;
  bool _isViewingLocalFolder = false; // Track if viewing local folder (prevents sync overwrites)
  DateTime? _lastKnownDate; // Track last known date for overdue status updates
  static const List<String> _allFolders = ['INBOX', 'SENT', 'SPAM', 'TRASH', 'ARCHIVE'];
  static String? _lastFirebaseAccountId; // Track which account Firebase was initialized for

  EmailListNotifier(this._ref, this._syncService) : super(const AsyncValue.loading()) {
    _lastKnownDate = DateTime.now();
  }

  /// Load emails for an account: show local immediately, then background sync
  Future<void> loadEmails(String accountId, {String folderLabel = 'INBOX'}) async {
    _currentAccountId = accountId;
    _folderLabel = folderLabel;
    _isViewingLocalFolder = false; // Reset flag when loading Gmail folder
    // 1) Load folder from local DB (display immediately - will be empty if no historyID)
    try {
      _ref.read(emailLoadingLocalProvider.notifier).state = true;
      final t0 = DateTime.now();
      final local = await _syncService.loadLocal(accountId, folderLabel: _folderLabel);
      final dt = DateTime.now().difference(t0).inMilliseconds;
      if (kDebugMode) {
        // ignore: avoid_print
        print('[perf] loadLocal($_folderLabel) returned ${local.length} in ${dt}ms');
      }
      state = AsyncValue.data(local);
      // Update last known date when emails are loaded
      _lastKnownDate = DateTime.now();

      if (folderLabel == 'INBOX') {
        // Start Firebase listening immediately for INBOX (regardless of history or email count)
        // This ensures we receive real-time updates from other devices even if inbox is empty
        // For existing accounts: start listening now (data sync happens in background)
        // For new accounts: listening will also start after initial sync completes (as backup)
        unawaited(_startFirebaseAfterLocalLoad(accountId));
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
    _ref.read(emailLoadingLocalProvider.notifier).state = false;

    // 2) Background sync: check historyID and perform appropriate sync
    // This handles ALL folders via incremental sync (or initial full sync if no history)
    unawaited(_syncInboxOnStartup(accountId));
  }

  Future<void> _startFirebaseAfterLocalLoad(String accountId) async {
    // Only initialize if this is a different account or Firebase hasn't been initialized yet
    if (_lastFirebaseAccountId == accountId) {
      // Already initialized for this account
      return;
    }
    
    try {
      // Wait for Firebase initialization to complete (handled by main.dart)
      // Don't try to initialize here - main.dart already handles it
      await FirebaseInit.instance.whenReady;
      
      final syncService = FirebaseSyncService();
      final initialized = await syncService.initialize();
      final enabled = await syncService.isSyncEnabled();
      if (initialized && enabled) {
        // Use account email as user ID
        final acct = await GoogleAuthService().ensureValidAccessToken(accountId);
        final email = acct?.email;
        if (email != null && email.isNotEmpty) {
          await syncService.initializeUser(email);
          _lastFirebaseAccountId = accountId; // Track that we initialized for this account
          if (kDebugMode) {
            // ignore: avoid_print
            print('[FirebaseInit] Firebase user initialized for $email (account: $accountId)');
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
      // Update last known date when emails are loaded
      _lastKnownDate = DateTime.now();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
    _ref.read(emailLoadingLocalProvider.notifier).state = false;
  }

  /// Refresh emails: load from local immediately, then background sync
  Future<void> refresh(String accountId, {String? folderLabel}) async {
    // ignore: avoid_print
    print('[sync] ===== refresh() CALLED ===== account=$accountId folder=$folderLabel');
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
      // Update last known date when emails are refreshed
      _lastKnownDate = DateTime.now();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
    _ref.read(emailLoadingLocalProvider.notifier).state = false;
    // ignore: avoid_print
    print('[sync] refresh: calling _syncFolderAndUpdateCurrent() asynchronously');
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
        // Check if date has changed (for overdue status updates)
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final lastDate = _lastKnownDate != null
            ? DateTime(_lastKnownDate!.year, _lastKnownDate!.month, _lastKnownDate!.day)
            : null;
        
        if (lastDate != null && today != lastDate) {
          // Date changed - trigger UI rebuild for overdue status update
          // No database reload needed since data hasn't changed, only the comparison
          final current = state;
          if (current is AsyncData<List<MessageIndex>> && current.value.isNotEmpty) {
            // Re-emit the same list reference (no cloning) to notify listeners
            state = AsyncValue.data(current.value);
            if (kDebugMode) {
              // ignore: avoid_print
              print('[sync] date changed from $lastDate to $today, triggering overdue status update');
            }
          }
          _lastKnownDate = now;
        }
        
        // Incremental sync always uses the latest historyID from DB
        final syncStart = DateTime.now();
        // ignore: avoid_print
        print('[sync] incremental tick account=$_currentAccountId');
        _ref.read(emailSyncingProvider.notifier).state = true;
        
        // Check token validity before syncing - if invalid, trigger auth failure
        // Note: For background sync, we don't show network error popup - only for manual refresh
        final auth = GoogleAuthService();
        final account = await auth.ensureValidAccessToken(_currentAccountId!);
        if (account == null || account.accessToken.isEmpty) {
          // Check if this is a network error or auth error
          final isNetworkError = auth.isLastErrorNetworkError(_currentAccountId!) == true;
          if (isNetworkError) {
            // ignore: avoid_print
            print('[sync] incremental tick: network error detected, silently skipping (background sync)');
            // Don't show popup for background sync - just skip silently
            _ref.read(emailSyncingProvider.notifier).state = false;
            return;
          }
          // Auth error (no refresh token or refresh failed) - trigger auth failure
          // ignore: avoid_print
          print('[sync] incremental tick: account needs re-authentication account=$_currentAccountId');
          _ref.read(authFailureProvider.notifier).state = _currentAccountId;
          _ref.read(emailSyncingProvider.notifier).state = false;
          return;
        }
        
        // Clear any previous auth failure for this account
        if (_ref.read(authFailureProvider) == _currentAccountId) {
          _ref.read(authFailureProvider.notifier).state = null;
        }
        
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
          // Update last known date after successful sync
          _lastKnownDate = now;
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
          // Update last known date after reload
          _lastKnownDate = DateTime.now();
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
              // Update last known date after reload
              _lastKnownDate = DateTime.now();
              final dt = DateTime.now().difference(t0).inMilliseconds;
              if (kDebugMode) {
                // ignore: avoid_print
                print('[perf] initial sync reload $_folderLabel in ${dt}ms');
              }
            }
          }
          
        // After initial sync completes for new account, start Firebase sync
        // This ensures emails are downloaded before Firebase sync begins
        if (_currentAccountId == accountId) {
          unawaited(_startFirebaseAfterLocalLoad(accountId));
        }
        } finally {
          _isInitialSyncing = false;
        }
      }
      
      // Update last known date after sync completes
      _lastKnownDate = DateTime.now();
      
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
    // ignore: avoid_print
    print('[sync] _syncFolderAndUpdateCurrent: starting, _currentAccountId=$_currentAccountId, _isInitialSyncing=$_isInitialSyncing');
    if (_currentAccountId == null) {
      // ignore: avoid_print
      print('[sync] _syncFolderAndUpdateCurrent: _currentAccountId is null, returning');
      return;
    }
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
      
      // Check if account needs re-authentication before syncing
      final auth = GoogleAuthService();
      // ignore: avoid_print
      print('[sync] sync current: checking token validity for account=$accountId');
      // Clear any previous network error state before checking
      // ignore: avoid_print
      print('[sync] sync current: lastErrorType before check=${auth.isLastErrorNetworkError(accountId)}');
      final account = await auth.ensureValidAccessToken(accountId);
      // ignore: avoid_print
      print('[sync] sync current: ensureValidAccessToken returned account=${account != null ? 'valid' : 'null'}, accessToken=${account?.accessToken.isNotEmpty ?? false}');
      if (account == null || account.accessToken.isEmpty) {
        // Check if this is a network error or auth error
        final isNetworkError = auth.isLastErrorNetworkError(accountId) == true;
        // ignore: avoid_print
        print('[sync] sync current: token check failed, isNetworkError=$isNetworkError, accountId=$accountId');
        if (isNetworkError) {
          // ignore: avoid_print
          print('[sync] sync current: network error detected, setting networkErrorProvider');
          _ref.read(networkErrorProvider.notifier).state = true;
          // ignore: avoid_print
          print('[sync] sync current: networkErrorProvider set to true');
          _ref.read(emailSyncingProvider.notifier).state = false;
          return;
        }
        // Auth error (no refresh token or refresh failed) - trigger auth failure
        // ignore: avoid_print
        print('[sync] sync current: account needs re-authentication account=$accountId, setting authFailureProvider');
        _ref.read(authFailureProvider.notifier).state = accountId;
        // ignore: avoid_print
        print('[sync] sync current: authFailureProvider set to $accountId, current value=${_ref.read(authFailureProvider)}');
        _ref.read(emailSyncingProvider.notifier).state = false;
        return;
      }
      // ignore: avoid_print
      print('[sync] sync current: token valid, proceeding with sync account=$accountId');
      
      // Clear any previous auth failure for this account
      if (_ref.read(authFailureProvider) == accountId) {
        _ref.read(authFailureProvider.notifier).state = null;
      }
      
      _ref.read(emailSyncingProvider.notifier).state = true;
      await _syncService.processPendingOps();
      
      // Use incremental sync if history exists, otherwise fall back to full sync
      List<GmailMessage> newMessages = [];
      final hasHistory = await _syncService.hasHistoryId(accountId);
      if (hasHistory) {
        // ignore: avoid_print
        print('[sync] history exists, using incremental sync');
        // Clear any previous network error state before calling incrementalSync
        final auth = GoogleAuthService();
        auth.clearLastError(accountId);
        // ignore: avoid_print
        print('[sync] sync current: cleared previous error state before incrementalSync');
        
        newMessages = await _syncService.incrementalSync(accountId);
        
        // Check if incrementalSync failed due to network error
        // Only check if incrementalSync actually failed (returned empty due to error, not just no new messages)
        final isNetworkError = auth.isLastErrorNetworkError(accountId) == true;
        // ignore: avoid_print
        print('[sync] sync current: after incrementalSync, isNetworkError=$isNetworkError, newMessages.length=${newMessages.length}');
        
        // Only show network error if incrementalSync actually failed (not just no new messages)
        // incrementalSync returns empty list on network error, but we need to distinguish from "no new messages"
        // If isNetworkError is true AFTER incrementalSync, it means the sync failed
        if (isNetworkError) {
          // ignore: avoid_print
          print('[sync] sync current: incrementalSync failed with network error, setting networkErrorProvider');
          _ref.read(networkErrorProvider.notifier).state = true;
          _ref.read(emailSyncingProvider.notifier).state = false;
          return;
        }
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
        // Update last known date after reload
        _lastKnownDate = DateTime.now();
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
        final existing = updated[idx];
        // Handle null explicitly - copyWith treats null as "not provided", so we need to manually construct
        // when setting to null to ensure the UI updates correctly
        if (localTag == null) {
          // Explicitly set to null - manually construct to override copyWith's null handling
          updated[idx] = MessageIndex(
            id: existing.id,
            threadId: existing.threadId,
            accountId: existing.accountId,
            accountEmail: existing.accountEmail,
            historyId: existing.historyId,
            internalDate: existing.internalDate,
            from: existing.from,
            to: existing.to,
            subject: existing.subject,
            snippet: existing.snippet,
            hasAttachments: existing.hasAttachments,
            gmailCategories: existing.gmailCategories,
            gmailSmartLabels: existing.gmailSmartLabels,
            localTagPersonal: null, // Explicitly set to null
            subsLocal: existing.subsLocal,
            shoppingLocal: existing.shoppingLocal,
            unsubscribedLocal: existing.unsubscribedLocal,
            actionDate: existing.actionDate,
            actionConfidence: existing.actionConfidence,
            actionInsightText: existing.actionInsightText,
            actionComplete: existing.actionComplete,
            hasAction: existing.hasAction,
            isRead: existing.isRead,
            isStarred: existing.isStarred,
            isImportant: existing.isImportant,
            folderLabel: existing.folderLabel,
            prevFolderLabel: existing.prevFolderLabel,
          );
        } else {
          // Set to a value - copyWith works fine for non-null values
          updated[idx] = existing.copyWith(localTagPersonal: localTag);
        }
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

  void setUnsubscribed(String messageId, bool unsubscribed) {
    final current = state;
    if (current is AsyncData<List<MessageIndex>>) {
      final list = current.value;
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        final updated = List<MessageIndex>.from(list);
        updated[idx] = updated[idx].copyWith(unsubscribedLocal: unsubscribed);
        state = AsyncValue.data(updated);
      }
    }
  }

  /// Mark all messages from a sender as unsubscribed in the provider state
  void setSenderUnsubscribed(String senderEmail, bool unsubscribed) {
    final current = state;
    if (current is AsyncData<List<MessageIndex>>) {
      final list = current.value;
      final updated = list.map((m) {
        // Extract email from fromAddr field (handles "Name <email@domain.com>" format)
        final match = RegExp(r'<([^>]+)>').firstMatch(m.from);
        final email = match != null 
            ? match.group(1)!.trim().toLowerCase()
            : (m.from.contains('@') ? m.from.trim().toLowerCase() : '');
        if (email == senderEmail.toLowerCase()) {
          return m.copyWith(unsubscribedLocal: unsubscribed);
        }
        return m;
      }).toList();
      state = AsyncValue.data(updated);
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

  /// Update action for a message in provider state
  /// actionInsightText is the source of truth: if null or empty, no action exists
  void setAction(String messageId, DateTime? actionDate, String? actionText, {bool? actionComplete, bool preserveExisting = false}) {
    final current = state;
    if (current is AsyncData<List<MessageIndex>>) {
      final list = current.value;
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        final updated = List<MessageIndex>.from(list);
        final currentMessage = updated[idx];

        // Apply preserveExisting logic
        final newActionDate = preserveExisting && actionDate == null
            ? currentMessage.actionDate
            : actionDate;

        final newActionText = preserveExisting && actionText == null
            ? currentMessage.actionInsightText
            : actionText; // If preserveExisting=false, this will be null (explicitly removing action)

        // Handle actionComplete: if explicitly provided (even if false), use it
        // If null and preserveExisting=true, keep current value
        // If null and preserveExisting=false, keep current value (don't change it)
        final newActionComplete = actionComplete ?? currentMessage.actionComplete;

        // Source of truth: actionInsightText determines if action exists
        final hasAction = newActionText != null && newActionText.isNotEmpty;
        
        // When removing action (hasAction is false), ensure actionComplete is also false
        final finalActionComplete = hasAction ? newActionComplete : false;

        if (kDebugMode) {
          debugPrint('[PROVIDER] setAction messageId=$messageId');
          debugPrint('[PROVIDER] Input: actionText=$actionText, actionComplete=$actionComplete, preserveExisting=$preserveExisting');
          debugPrint('[PROVIDER] Current: actionText=${currentMessage.actionInsightText}, actionComplete=${currentMessage.actionComplete}, hasAction=${currentMessage.hasAction}');
          debugPrint('[PROVIDER] Result: newActionText=$newActionText, finalActionComplete=$finalActionComplete, hasAction=$hasAction');
        }

        // Handle null explicitly - copyWith treats null as "not provided", so we need to manually construct
        // when setting actionText to null to ensure the UI updates correctly
        if (newActionText == null && !preserveExisting) {
          // Explicitly set to null - manually construct to override copyWith's null handling
          updated[idx] = MessageIndex(
            id: currentMessage.id,
            threadId: currentMessage.threadId,
            accountId: currentMessage.accountId,
            accountEmail: currentMessage.accountEmail,
            historyId: currentMessage.historyId,
            internalDate: currentMessage.internalDate,
            from: currentMessage.from,
            to: currentMessage.to,
            subject: currentMessage.subject,
            snippet: currentMessage.snippet,
            hasAttachments: currentMessage.hasAttachments,
            gmailCategories: currentMessage.gmailCategories,
            gmailSmartLabels: currentMessage.gmailSmartLabels,
            localTagPersonal: currentMessage.localTagPersonal,
            subsLocal: currentMessage.subsLocal,
            shoppingLocal: currentMessage.shoppingLocal,
            unsubscribedLocal: currentMessage.unsubscribedLocal,
            actionDate: null, // Explicitly set to null
            actionConfidence: null, // Explicitly set to null
            actionInsightText: null, // Explicitly set to null
            actionComplete: false, // Explicitly set to false when no action
            hasAction: false, // Explicitly set to false when no action
            isRead: currentMessage.isRead,
            isStarred: currentMessage.isStarred,
            isImportant: currentMessage.isImportant,
            folderLabel: currentMessage.folderLabel,
            prevFolderLabel: currentMessage.prevFolderLabel,
          );
        } else {
          // Set to a value or preserve existing - copyWith works fine
          updated[idx] = currentMessage.copyWith(
            actionDate: newActionDate,
            actionInsightText: newActionText,
            actionComplete: finalActionComplete,
            hasAction: hasAction,
          );
        }
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
        // Update last known date when emails are reloaded
        _lastKnownDate = DateTime.now();
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

