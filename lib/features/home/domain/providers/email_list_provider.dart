import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:actionmail/data/models/message_index.dart';
import 'package:actionmail/services/gmail/gmail_sync_service.dart';

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
  static const List<String> _allFolders = ['INBOX', 'SENT', 'SPAM', 'TRASH', 'ARCHIVE'];

  EmailListNotifier(this._ref, this._syncService) : super(const AsyncValue.loading());

  /// Load emails for an account: show local immediately, then background sync
  Future<void> loadEmails(String accountId, {String folderLabel = 'INBOX'}) async {
    _currentAccountId = accountId;
    _folderLabel = folderLabel;

    // 1) Load Inbox from local DB (display immediately - will be empty if no historyID)
    try {
      if (folderLabel == 'INBOX') {
        // ignore: avoid_print
        print('[sync] loadEmails account=$accountId folder=$folderLabel (local first)');
        _ref.read(emailLoadingLocalProvider.notifier).state = true;
        final local = await _syncService.loadLocal(accountId, folderLabel: _folderLabel);
        state = AsyncValue.data(local);
        _ref.read(emailLoadingLocalProvider.notifier).state = false;
      } else {
        state = const AsyncValue.data([]);
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }

    // 2) Background sync: check historyID and perform appropriate sync (INBOX only on startup)
    if (folderLabel == 'INBOX') {
      unawaited(_syncInboxOnStartup(accountId));
    }

    // 3) Background sync other folders (save to DB only)
    unawaited(_syncOtherFolders());
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
      final local = await _syncService.loadLocal(accountId, folderLabel: _folderLabel);
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
      try {
        // Incremental sync always uses the latest historyID from DB
        // ignore: avoid_print
        print('[sync] incremental tick account=$_currentAccountId');
        _ref.read(emailSyncingProvider.notifier).state = true;
        await _syncService.processPendingOps();
        // Run incremental sync (always uses latest historyID from DB)
        await _syncService.incrementalSync(_currentAccountId!);
        // Reload Inbox from local DB to show updated emails
        if (_folderLabel == 'INBOX') {
          final local = await _syncService.loadLocal(_currentAccountId!, folderLabel: 'INBOX');
          state = AsyncValue.data(local);
          // ignore: avoid_print
          print('[sync] incremental done count=${local.length}');
        }
      } catch (_) {}
      _ref.read(emailSyncingProvider.notifier).state = false;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Sync INBOX on startup: check historyID and perform appropriate sync
  Future<void> _syncInboxOnStartup(String accountId) async {
    try {
      // ignore: avoid_print
      print('[sync] syncInboxOnStartup account=$accountId');
      _ref.read(emailSyncingProvider.notifier).state = true;
      await _syncService.processPendingOps();
      
      // Check for historyID in DB
      final hasHistory = await _syncService.hasHistoryId(accountId);
      
      if (hasHistory) {
        // If historyID exists: run incremental sync using that historyID
        // ignore: avoid_print
        print('[sync] historyID exists, doing incremental sync');
        await _syncService.incrementalSync(accountId);
      } else {
        // If no historyID: do initial sync (fetch from Gmail)
        // ignore: avoid_print
        print('[sync] no historyID, doing initial sync');
        await _syncService.syncMessages(accountId, folderLabel: 'INBOX');
      }
      
      // Reload Inbox from local DB to show updated emails
      if (_currentAccountId == accountId && _folderLabel == 'INBOX') {
        final local = await _syncService.loadLocal(accountId, folderLabel: 'INBOX');
        state = AsyncValue.data(local);
        // ignore: avoid_print
        print('[sync] syncInboxOnStartup done count=${local.length}');
      }
      
      // Start the 2-minute incremental sync timer after sync completes
      _startIncremental();
    } catch (_) {}
    _ref.read(emailSyncingProvider.notifier).state = false;
  }

  Future<void> _syncFolderAndUpdateCurrent() async {
    if (_currentAccountId == null) return;
    final accountId = _currentAccountId!;
    final currentFolder = _folderLabel;
    try {
      // ignore: avoid_print
      print('[sync] sync current account=$accountId folder=$currentFolder');
      _ref.read(emailSyncingProvider.notifier).state = true;
      await _syncService.processPendingOps();
      await _syncService.syncMessages(accountId, folderLabel: currentFolder);
      
      // Reload local for current folder only if still on same folder
      if (_currentAccountId == accountId && _folderLabel == currentFolder) {
        final local = await _syncService.loadLocal(accountId, folderLabel: currentFolder);
        state = AsyncValue.data(local);
        // ignore: avoid_print
        print('[sync] sync current done count=${local.length}');
      }
    } catch (_) {}
    _ref.read(emailSyncingProvider.notifier).state = false;
  }

  Future<void> _syncOtherFolders() async {
    if (_currentAccountId == null) return;
    final accountId = _currentAccountId!;
    for (final f in _allFolders) {
      if (f == _folderLabel) continue;
      try {
        _ref.read(emailSyncingProvider.notifier).state = true;
        await _syncService.processPendingOps();
        await _syncService.syncMessages(accountId, folderLabel: f);
      } catch (_) {}
    }
    _ref.read(emailSyncingProvider.notifier).state = false;
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

  void setAction(String messageId, DateTime? actionDate, String? actionText) {
    final current = state;
    if (current is AsyncData<List<MessageIndex>>) {
      final list = current.value;
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        final updated = List<MessageIndex>.from(list);
        updated[idx] = updated[idx].copyWith(actionDate: actionDate, actionInsightText: actionText);
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
}

