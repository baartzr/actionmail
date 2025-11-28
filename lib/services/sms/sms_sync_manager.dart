import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:domail/services/sms/sms_sync_service.dart';
import 'package:domail/services/sms/companion_sms_service.dart';
import 'package:domail/services/sms/sms_message_converter.dart';
import 'package:domail/data/repositories/message_repository.dart';
import 'package:domail/data/db/app_database.dart';
import 'package:domail/data/models/message_index.dart';
import 'package:domail/services/auth/google_auth_service.dart';
import 'package:domail/services/sync/firebase_sync_service.dart';
import 'package:domail/services/sync/firebase_init.dart';

/// Account-specific sync state
class _AccountSyncState {
  final String accountId;
  final String accountEmail;

  _AccountSyncState({
    required this.accountId,
    required this.accountEmail,
  });
}

/// Main manager for SMS sync functionality
/// Syncs SMS messages from the SMS Companion app via ContentProvider
class SmsSyncManager {
  static final SmsSyncManager _instance = SmsSyncManager._internal();
  factory SmsSyncManager() => _instance;
  SmsSyncManager._internal();

  final SmsSyncService _syncService = SmsSyncService();
  final MessageRepository _messageRepository = MessageRepository();
  final GoogleAuthService _googleAuthService = GoogleAuthService();
  final CompanionSmsService _companionService = CompanionSmsService();
  
  final Map<String, _AccountSyncState> _accountStates = {};
  Timer? _companionSyncTimer;
  bool _isSyncing = false; // Guard to prevent concurrent syncs

  /// Callback when a new SMS message is received and saved
  void Function(MessageIndex message)? onSmsReceived;

  /// Start SMS sync for all accounts
  Future<void> start() async {
    final isEnabled = await _syncService.isSyncEnabled();
    if (!isEnabled) {
      debugPrint('[SmsSyncManager] SMS sync is disabled');
      return;
    }

    // Check if companion app is available
    final isAvailable = await _companionService.isCompanionAppAvailable();
    if (!isAvailable) {
      debugPrint('[SmsSyncManager] SMS Companion app is not available');
      return;
    }

    // Get selected account ID
    var selectedAccountId = await _syncService.getSelectedAccountId();
    if (selectedAccountId == null) {
      debugPrint('[SmsSyncManager] No account selected for SMS sync');
      return;
    }

    // Verify account still exists - if not, try to migrate from old timestamp-based ID to email-based ID
    var account = await _googleAuthService.getAccountById(selectedAccountId);
    if (account == null) {
      debugPrint('[SmsSyncManager] Selected account $selectedAccountId not found, attempting migration...');
      // Try to find account by email (since accountId is now email-based)
      // The stored ID might be the old timestamp, so try to find by email
      final allAccounts = await _googleAuthService.loadAccounts();
      if (allAccounts.isNotEmpty) {
        // Use the first account (or could use currently selected account)
        account = allAccounts.first;
        selectedAccountId = account.id; // Update to new email-based ID
        await _syncService.setSelectedAccountId(selectedAccountId);
        debugPrint('[SmsSyncManager] Migrated account ID to ${account.email} ($selectedAccountId)');
      } else {
        debugPrint('[SmsSyncManager] No accounts available for SMS sync');
        return;
      }
    }

    debugPrint('[SmsSyncManager] Starting SMS sync for account ${account.email} ($selectedAccountId)...');

    // Initialize Firebase user if SMS sync to desktop is enabled
    final firebaseSync = FirebaseSyncService();
    final smsSyncToDesktop = await firebaseSync.isSmsSyncToDesktopEnabled();
    if (smsSyncToDesktop) {
      try {
        await FirebaseInit.instance.whenReady;
        final syncInitialized = await firebaseSync.initialize();
        final syncEnabled = await firebaseSync.isSyncEnabled();
        if (syncInitialized && syncEnabled) {
          await firebaseSync.initializeUser(account.email);
          debugPrint('[SmsSyncManager] Firebase user initialized for SMS sync: ${account.email}');
        }
      } catch (e) {
        debugPrint('[SmsSyncManager] Error initializing Firebase user: $e');
      }
    }

    // Start sync for selected account
    await _startForAccount(selectedAccountId);
  }

  /// Start SMS sync for a specific account
  Future<void> _startForAccount(String accountId) async {
    // Skip if already running for this account
    if (_accountStates.containsKey(accountId)) {
      debugPrint('[SmsSyncManager] Already running for account $accountId');
      return;
    }

    // Verify account exists - if not, try to migrate from old timestamp-based ID to email-based ID
    var account = await _googleAuthService.getAccountById(accountId);
    if (account == null) {
      debugPrint('[SmsSyncManager] Account $accountId not found, attempting migration...');
      // Try to find account by email (since accountId is now email-based)
      final allAccounts = await _googleAuthService.loadAccounts();
      if (allAccounts.isNotEmpty) {
        // Use the first account (or could use currently selected account)
        account = allAccounts.first;
        final newAccountId = account.id; // New email-based ID
        // Update stored account ID if this was the selected one
        final storedAccountId = await _syncService.getSelectedAccountId();
        if (storedAccountId == accountId) {
          await _syncService.setSelectedAccountId(newAccountId);
        }
        accountId = newAccountId; // Update to use new ID
        debugPrint('[SmsSyncManager] Migrated account ID to ${account.email} ($accountId)');
      } else {
        debugPrint('[SmsSyncManager] Account $accountId is no longer available and no accounts found');
        return;
      }
    }

    debugPrint('[SmsSyncManager] Starting SMS sync for account ${account.email} ($accountId)...');

    // Store account state
    _accountStates[accountId] = _AccountSyncState(
      accountId: accountId,
      accountEmail: account.email,
    );

    // Start periodic sync from companion app
    startCompanionSync(accountId);
  }

  /// Stop SMS sync for a specific account
  Future<void> _stopForAccount(String accountId) async {
    final state = _accountStates.remove(accountId);
    if (state == null) {
      return;
    }

    debugPrint('[SmsSyncManager] Stopping SMS sync for account ${state.accountEmail} ($accountId)...');
    
    // Stop companion sync if this was the last account
    if (_accountStates.isEmpty) {
      stopCompanionSync();
    }
  }

  /// Stop SMS sync for all accounts
  Future<void> stop() async {
    debugPrint('[SmsSyncManager] Stopping SMS sync for all accounts...');

    stopCompanionSync();

    // Clear all account states
    _accountStates.clear();
  }

  /// Check if SMS sync is currently running for any account
  bool get isRunning => _accountStates.isNotEmpty;

  /// Start sync for a specific account (public method for external use)
  Future<void> startForAccount(String accountId) async {
    final isEnabled = await _syncService.isSyncEnabled();
    if (!isEnabled) {
      debugPrint('[SmsSyncManager] SMS sync is disabled, cannot start for account $accountId');
      return;
    }

    await _startForAccount(accountId);
  }

  /// Stop sync for a specific account (public method for external use)
  Future<void> stopForAccount(String accountId) async {
    await _stopForAccount(accountId);
  }

  /// Sync SMS messages from the Companion app
  /// This reads directly from the companion app's ContentProvider
  Future<void> syncFromCompanionApp(String accountId) async {
    // Prevent concurrent syncs
    if (_isSyncing) {
      debugPrint('[SmsSyncManager] ⚠️ Sync already in progress, skipping duplicate call');
      return;
    }
    
    _isSyncing = true;
    try {
      final isAvailable = await _companionService.isCompanionAppAvailable();
      if (!isAvailable) {
        debugPrint('[SmsSyncManager] Companion app not available, skipping sync');
        return;
      }

      final account = await _googleAuthService.getAccountById(accountId);
      if (account == null) {
        debugPrint('[SmsSyncManager] Account $accountId not found');
        return;
      }

      debugPrint('[SmsSyncManager] Syncing SMS from Companion app for account ${account.email}...');
      
      // Fetch all messages from companion app
      final messages = await _companionService.fetchAllMessages(
        accountId: accountId,
        accountEmail: account.email,
      );

      debugPrint('[SmsSyncManager] Companion app returned ${messages.length} messages');
      
      // Debug: Log all messages received from companion
      for (int i = 0; i < messages.length; i++) {
        final msg = messages[i];
        debugPrint('[SmsSyncManager] [$i] Message from companion:');
        debugPrint('    ID: ${msg.id}');
        debugPrint('    From: ${msg.from}');
        debugPrint('    To: ${msg.to}');
        debugPrint('    Folder: ${msg.folderLabel}');
        debugPrint('    Timestamp: ${msg.internalDate.millisecondsSinceEpoch}');
        debugPrint('    ThreadId: ${msg.threadId}');
        debugPrint('    Subject: ${msg.subject.substring(0, msg.subject.length > 50 ? 50 : msg.subject.length)}');
      }

      // Save messages to repository and track IDs for deletion
      int savedCount = 0;
      int skippedCount = 0;
      final fetchedMessageIds = <String>[];
      
      // First pass: Check for existing messages and collect new ones
      final newMessages = <MessageIndex>[];
      for (int i = 0; i < messages.length; i++) {
        final message = messages[i];
        debugPrint('[SmsSyncManager] Processing message: ${message.id} (${message.folderLabel})');
        
        // Check if message already exists by ID
        final existingById = await _messageRepository.getById(message.id);
        if (existingById != null) {
          debugPrint('[SmsSyncManager]   -> Skipped: Already exists in Domail DB by ID');
          skippedCount++;
          // Still delete from companion DB even if duplicate (already in Domail)
          fetchedMessageIds.add(message.id);
          continue;
        }
        
        // For SMS messages, check for duplicates:
        // 1. Against existing messages in DB
        // 2. Against other messages in the current batch (to catch Android storing same message twice)
        if (SmsMessageConverter.isSmsMessage(message)) {
          final normalizedPhone = _normalizePhoneForDedup(message);
          final messageTimestamp = message.internalDate.millisecondsSinceEpoch;
          final messageBody = message.subject.toLowerCase().trim();
          debugPrint('[SmsSyncManager]   -> Normalized phone: $normalizedPhone, timestamp: $messageTimestamp, body: ${messageBody.substring(0, messageBody.length > 30 ? 30 : messageBody.length)}');
          
          // Check against existing messages in DB (with time window of ±2 seconds)
          final allMessages = await _messageRepository.getAll(accountId);
          final duplicateInDb = allMessages.where((existing) {
            if (!SmsMessageConverter.isSmsMessage(existing)) return false;
            final existingNormalizedPhone = _normalizePhoneForDedup(existing);
            final existingTimestamp = existing.internalDate.millisecondsSinceEpoch;
            final existingBody = existing.subject.toLowerCase().trim();
            final timeDiff = (existingTimestamp - messageTimestamp).abs();
            return existingNormalizedPhone == normalizedPhone &&
                   existing.folderLabel == message.folderLabel &&
                   timeDiff <= 2000 && // Within 2 seconds
                   existingBody == messageBody; // Same message body
          }).firstOrNull;
          
          if (duplicateInDb != null) {
            debugPrint('[SmsSyncManager]   -> Skipped: Duplicate found in DB by phone/body/direction (existing ID: ${duplicateInDb.id}, time diff: ${(duplicateInDb.internalDate.millisecondsSinceEpoch - messageTimestamp).abs()}ms)');
            skippedCount++;
            fetchedMessageIds.add(message.id);
            continue;
          }
          
          // Check against other messages in current batch (with time window of ±2 seconds)
          final duplicateInBatch = newMessages.where((existing) {
            if (!SmsMessageConverter.isSmsMessage(existing)) return false;
            final existingNormalizedPhone = _normalizePhoneForDedup(existing);
            final existingTimestamp = existing.internalDate.millisecondsSinceEpoch;
            final existingBody = existing.subject.toLowerCase().trim();
            final timeDiff = (existingTimestamp - messageTimestamp).abs();
            return existingNormalizedPhone == normalizedPhone &&
                   existing.folderLabel == message.folderLabel &&
                   timeDiff <= 2000 && // Within 2 seconds
                   existingBody == messageBody; // Same message body
          }).firstOrNull;
          
          if (duplicateInBatch != null) {
            debugPrint('[SmsSyncManager]   -> Skipped: Duplicate found in current batch by phone/body/direction (existing ID: ${duplicateInBatch.id}, time diff: ${(duplicateInBatch.internalDate.millisecondsSinceEpoch - messageTimestamp).abs()}ms)');
            skippedCount++;
            fetchedMessageIds.add(message.id);
            continue;
          }
        }
        
        debugPrint('[SmsSyncManager]   -> Adding as new message');
        newMessages.add(message);
        fetchedMessageIds.add(message.id);
      }
      
      // Note: All messages now come from Android's system SMS database, which provides
      // the correct threadId for both sent and received messages. No threadId matching/updating needed.
      
      // Save all new messages
      if (newMessages.isNotEmpty) {
        await _messageRepository.upsertMessages(newMessages);
        savedCount = newMessages.length;
        
        // Sync to Firebase (only for SMS messages, and only if SMS sync to desktop is enabled)
        try {
          final firebaseSync = FirebaseSyncService();
          final syncEnabled = await firebaseSync.isSyncEnabled();
          final smsSyncToDesktopEnabled = await firebaseSync.isSmsSyncToDesktopEnabled();
          
          debugPrint('[SmsSyncManager] Firebase sync check: syncEnabled=$syncEnabled, smsSyncToDesktopEnabled=$smsSyncToDesktopEnabled');
          
          if (syncEnabled && smsSyncToDesktopEnabled) {
            final smsMessages = newMessages.where((m) => SmsMessageConverter.isSmsMessage(m)).toList();
            debugPrint('[SmsSyncManager] Syncing ${smsMessages.length} SMS message(s) to Firebase');
            debugPrint('[SmsSyncManager] Message IDs to sync: ${smsMessages.map((m) => m.id).join(", ")}');
            for (final message in smsMessages) {
              try {
                debugPrint('[SmsSyncManager] >>> About to call syncSmsMessage for ${message.id}');
                await firebaseSync.syncSmsMessage(message);
                debugPrint('[SmsSyncManager] Successfully synced SMS to Firebase: ${message.id}');
              } catch (e, stackTrace) {
                debugPrint('[SmsSyncManager] Error syncing SMS ${message.id} to Firebase: $e');
                debugPrint('[SmsSyncManager] Stack trace: $stackTrace');
              }
            }
          } else {
            debugPrint('[SmsSyncManager] Skipping Firebase sync: syncEnabled=$syncEnabled, smsSyncToDesktopEnabled=$smsSyncToDesktopEnabled');
          }
        } catch (e, stackTrace) {
          debugPrint('[SmsSyncManager] Error in Firebase sync block: $e');
          debugPrint('[SmsSyncManager] Stack trace: $stackTrace');
        }
        
        // Notify callback for new messages
        for (final message in newMessages) {
          onSmsReceived?.call(message);
        }
      }

      // Delete fetched messages from companion DB after successful save
      if (fetchedMessageIds.isNotEmpty) {
        final deletedCount = await _companionService.deleteMessages(fetchedMessageIds);
        debugPrint('[SmsSyncManager] Deleted $deletedCount messages from companion DB');
      }

      debugPrint('[SmsSyncManager] Companion sync completed: saved $savedCount messages, skipped $skippedCount duplicates');
      
      // Debug: Log what was saved
      if (newMessages.isNotEmpty) {
        debugPrint('[SmsSyncManager] Saved ${newMessages.length} new messages:');
        for (final msg in newMessages) {
          debugPrint('    - ${msg.id} (${msg.folderLabel}): ${msg.from} -> ${msg.to}');
        }
      }
    } catch (e, stackTrace) {
      debugPrint('[SmsSyncManager] Companion sync error: $e');
      debugPrint('[SmsSyncManager] Stack trace: $stackTrace');
    } finally {
      _isSyncing = false;
    }
  }

  /// Start periodic sync from Companion app (runs every 15 seconds)
  void startCompanionSync(String accountId) {
    _companionSyncTimer?.cancel();
    _companionSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(syncFromCompanionApp(accountId));
    });
    
    // Do initial sync immediately
    unawaited(syncFromCompanionApp(accountId));
  }

  /// Stop periodic sync from Companion app
  void stopCompanionSync() {
    _companionSyncTimer?.cancel();
    _companionSyncTimer = null;
  }
  
  /// Normalize phone number for deduplication
  /// Extracts phone number from message and normalizes it
  String _normalizePhoneForDedup(MessageIndex message) {
    // Extract phone number from from/to fields (SMS format: phone@sms.gmail.com or just phone)
    final phone = message.folderLabel == 'SENT' 
        ? message.to.replaceAll(RegExp(r'@.*'), '').trim()
        : message.from.replaceAll(RegExp(r'@.*'), '').trim();
    
    // Normalize using same logic as companion app
    var normalized = phone
        .replaceAll(RegExp(r'[\s\-\(\)\.]'), '')
        .replaceAll(RegExp(r'^\+'), '');
    
    // Convert Australian mobile format: 04... to 614...
    if (normalized.startsWith('04') && normalized.length == 10) {
      normalized = '61${normalized.substring(1)}';
    }
    
    return normalized.toLowerCase();
  }
  
  /// Clean up duplicate SMS messages in Domail's database
  /// Removes duplicates based on normalized phone number, timestamp, and direction
  /// Keeps the message with the normalized phone number (or the first one if both are non-normalized)
  Future<void> cleanupDuplicateSms(String accountId) async {
    try {
      debugPrint('[SmsSyncManager] Starting SMS duplicate cleanup for account: $accountId');
      final allMessages = await _messageRepository.getAll(accountId);
      final smsMessages = allMessages.where(SmsMessageConverter.isSmsMessage).toList();
      
      if (smsMessages.isEmpty) {
        debugPrint('[SmsSyncManager] No SMS messages to clean up');
        return;
      }
      
      // Group messages by normalized phone, timestamp, and direction
      final groups = <String, List<MessageIndex>>{};
      for (final message in smsMessages) {
        final normalizedPhone = _normalizePhoneForDedup(message);
        final key = '${normalizedPhone}_${message.internalDate.millisecondsSinceEpoch}_${message.folderLabel}';
        groups.putIfAbsent(key, () => []).add(message);
      }
      
      // Find duplicates and mark for deletion
      final idsToDelete = <String>[];
      for (final group in groups.values) {
        if (group.length > 1) {
          // Multiple messages with same normalized phone/timestamp/direction
          // Keep the one with normalized phone number (or first one if all are non-normalized)
          group.sort((a, b) {
            final aPhone = _normalizePhoneForDedup(a);
            final bPhone = _normalizePhoneForDedup(b);
            // Prefer normalized format (starts with 61, no leading 0, no +)
            final aNormalized = !aPhone.startsWith('0') && !aPhone.startsWith('+') && aPhone.startsWith('61');
            final bNormalized = !bPhone.startsWith('0') && !bPhone.startsWith('+') && bPhone.startsWith('61');
            if (aNormalized && !bNormalized) return -1;
            if (!aNormalized && bNormalized) return 1;
            return 0; // Keep original order if both normalized or both not
          });
          
          // Keep first, delete rest
          for (int i = 1; i < group.length; i++) {
            idsToDelete.add(group[i].id);
            debugPrint('[SmsSyncManager] Marking duplicate for deletion: ${group[i].id} (phone: ${group[i].folderLabel == 'SENT' ? group[i].to : group[i].from})');
          }
        }
      }
      
      if (idsToDelete.isNotEmpty) {
        // Delete duplicates - need to access database directly
        // Import AppDatabase to access database
        final appDb = AppDatabase();
        final db = await appDb.database;
        final placeholders = List.filled(idsToDelete.length, '?').join(',');
        await db.delete(
          'messages',
          where: 'id IN ($placeholders)',
          whereArgs: idsToDelete,
        );
        debugPrint('[SmsSyncManager] Cleaned up ${idsToDelete.length} duplicate SMS messages');
      } else {
        debugPrint('[SmsSyncManager] No duplicate SMS messages found');
      }
    } catch (e, stackTrace) {
      debugPrint('[SmsSyncManager] Error cleaning up duplicate SMS: $e');
      debugPrint('[SmsSyncManager] Stack trace: $stackTrace');
    }
  }
}
