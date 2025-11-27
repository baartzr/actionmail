import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:domail/services/sms/sms_sync_service.dart';
import 'package:domail/services/sms/pushbullet_websocket_service.dart';
import 'package:domail/services/sms/pushbullet_message_parser.dart';
import 'package:domail/services/sms/pushbullet_rest_service.dart';
import 'package:domail/services/sms/sms_message_converter.dart';
import 'package:domail/data/repositories/message_repository.dart';
import 'package:domail/data/models/message_index.dart';
import 'package:domail/services/auth/google_auth_service.dart';

/// Account-specific sync state
class _AccountSyncState {
  final String accountId;
  final String accountEmail;
  final PushbulletWebSocketService webSocketService;
  Timer? checkStateTimer;
  bool isRestCatchUpRunning = false;
  DateTime? lastRestCatchUp;
  static const Duration restCatchUpMinInterval = Duration(minutes: 2);

  _AccountSyncState({
    required this.accountId,
    required this.accountEmail,
    required this.webSocketService,
  });
}

/// Main manager for SMS sync functionality
/// Orchestrates multiple WebSocket connections (one per account with token)
class SmsSyncManager {
  static final SmsSyncManager _instance = SmsSyncManager._internal();
  factory SmsSyncManager() => _instance;
  SmsSyncManager._internal();

  final SmsSyncService _syncService = SmsSyncService();
  final MessageRepository _messageRepository = MessageRepository();
  final GoogleAuthService _googleAuthService = GoogleAuthService();
  final PushbulletRestService _restService = PushbulletRestService();
  
  final Map<String, _AccountSyncState> _accountStates = {};
  Timer? _checkAllAccountsTimer;

  /// Callback when a new SMS message is received and saved
  void Function(MessageIndex message)? onSmsReceived;

  /// Start SMS sync for all accounts with tokens
  Future<void> start() async {
    final isEnabled = await _syncService.isSyncEnabled();
    if (!isEnabled) {
      debugPrint('[SmsSyncManager] SMS sync is disabled');
      return;
    }

    final accountsWithTokens = await _syncService.getAccountsWithTokens();
    if (accountsWithTokens.isEmpty) {
      debugPrint('[SmsSyncManager] No accounts with tokens found');
      return;
    }

    debugPrint('[SmsSyncManager] Starting SMS sync for ${accountsWithTokens.length} account(s)...');

    // Start sync for each account
    for (final accountId in accountsWithTokens) {
      await _startForAccount(accountId);
    }

    // Start periodic state checking for all accounts
    _startStateChecking();
  }

  /// Start SMS sync for a specific account
  Future<void> _startForAccount(String accountId) async {
    // Skip if already running for this account
    if (_accountStates.containsKey(accountId)) {
      debugPrint('[SmsSyncManager] Already running for account $accountId');
      return;
    }

    final token = await _syncService.getToken(accountId);
    if (token == null || token.isEmpty) {
      debugPrint('[SmsSyncManager] No access token available for account $accountId');
      return;
    }

    final account = await _googleAuthService.getAccountById(accountId);
    if (account == null) {
      debugPrint('[SmsSyncManager] Account $accountId is no longer available');
      return;
    }

    debugPrint('[SmsSyncManager] Starting SMS sync for account ${account.email} ($accountId)...');

    // Create and configure WebSocket service for this account
    final webSocketService = PushbulletWebSocketService(
      accessToken: token,
      onEvent: (event) => _handleWebSocketEvent(accountId, event),
      onError: (error) => _handleWebSocketError(accountId, error),
      onConnected: () => _handleWebSocketConnected(accountId),
      onDisconnected: () => _handleWebSocketDisconnected(accountId),
    );

    // Store account state
    _accountStates[accountId] = _AccountSyncState(
      accountId: accountId,
      accountEmail: account.email,
      webSocketService: webSocketService,
    );

    // Connect to WebSocket
    // Note: catch-up will be triggered by _handleWebSocketConnected callback
    await webSocketService.connect();
  }

  /// Stop SMS sync for a specific account
  Future<void> _stopForAccount(String accountId) async {
    final state = _accountStates.remove(accountId);
    if (state == null) {
      return;
    }

    debugPrint('[SmsSyncManager] Stopping SMS sync for account ${state.accountEmail} ($accountId)...');

    state.checkStateTimer?.cancel();
    await state.webSocketService.disconnect();
  }

  /// Stop SMS sync for all accounts
  Future<void> stop() async {
    debugPrint('[SmsSyncManager] Stopping SMS sync for all accounts...');

    _checkAllAccountsTimer?.cancel();
    _checkAllAccountsTimer = null;

    // Stop all account syncs
    final accountIds = _accountStates.keys.toList();
    for (final accountId in accountIds) {
      await _stopForAccount(accountId);
    }
  }

  /// Handle WebSocket events for a specific account
  void _handleWebSocketEvent(String accountId, Map<String, dynamic> event) {
    try {
      final state = _accountStates[accountId];
      if (state == null) {
        debugPrint('[SmsSyncManager] Received event for unknown account $accountId');
        return;
      }

      // Log all push events to detect errors (even non-SMS ones)
      // This helps us catch SMS send failures that come through as push events
      final push = event['push'] as Map<String, dynamic>?;
      if (push != null) {
        final pushId = push['iden'] as String?;
        final pushType = push['type'] as String?;
        final active = push['active'] as bool?;
        final error = push['error'] as Map<String, dynamic>?;
        final data = push['data'] as Map<String, dynamic>?;
        
        // Log push events that might be related to SMS sending
        if (data != null && data.containsKey('addresses')) {
          debugPrint('[SmsSyncManager] 📱 SMS-related push event: iden=$pushId, type=$pushType, active=$active');
          if (error != null) {
            debugPrint('[SmsSyncManager] ⚠️ ERROR in SMS push event: $error');
            debugPrint('[SmsSyncManager] Full push data: ${jsonEncode(push)}');
          } else if (active == false) {
            debugPrint('[SmsSyncManager] ⚠️ SMS push marked as inactive (may indicate failure)');
            debugPrint('[SmsSyncManager] Push data: ${jsonEncode(data)}');
          }
        }
        
        // Log any error in any push event
        if (error != null) {
          debugPrint('[SmsSyncManager] ⚠️ ERROR in push event: $error');
          debugPrint('[SmsSyncManager] Push type: $pushType, iden: $pushId');
          debugPrint('[SmsSyncManager] Full push data: ${jsonEncode(push)}');
        }
      }

      // Check if this is an SMS event
      debugPrint('[SmsSyncManager] Processing WebSocket event for account $accountId: ${PushbulletMessageParser.describeEvent(event)}');
      if (!PushbulletMessageParser.isSmsEvent(event)) {
        debugPrint('[SmsSyncManager] Ignoring non-SMS event: ${PushbulletMessageParser.describeEvent(event)}');
        return;
      }
      debugPrint('[SmsSyncManager] Event is SMS event, parsing...');

      // Check if this is a sms_changed event with no notifications (just a change notification)
      // In this case, we need to fetch the actual SMS data via REST API
      if (push != null && push['type'] == 'sms_changed') {
        final notifications = push['notifications'];
        final hasNotifications = notifications is List && notifications.isNotEmpty;
        debugPrint('[SmsSyncManager] sms_changed event detected: hasNotifications=$hasNotifications');
        debugPrint('[SmsSyncManager] sms_changed event push keys: ${push.keys.toList()}');
        if (!hasNotifications) {
          debugPrint('[SmsSyncManager] sms_changed event has no notifications, triggering REST catch-up (force=true) to fetch SMS data');
          // Force the catch-up to ignore the time limit and try fetching without modified_after
          // This helps when the permanent object was just created
          unawaited(_catchUpWithRest(accountId, force: true));
          return;
        } else {
          debugPrint('[SmsSyncManager] sms_changed event has ${notifications.length} notification(s), parsing...');
        }
      }

      // Parse SMS event
      final smsEvent = PushbulletMessageParser.parseSmsEvent(event);
      if (smsEvent == null || !smsEvent.isValid) {
        debugPrint('[SmsSyncManager] Invalid SMS event payload: ${PushbulletMessageParser.describeEvent(event)}');
        return;
      }

      debugPrint('[SmsSyncManager] Received SMS from ${smsEvent.phoneNumber} (account: ${state.accountEmail})');

      if (smsEvent.deviceId != null && smsEvent.deviceId!.isNotEmpty) {
        unawaited(_syncService.setDeviceId(accountId, smsEvent.deviceId!));
      }

      // Convert to MessageIndex
      final message = SmsMessageConverter.toMessageIndex(
        smsEvent,
        accountId: accountId,
        accountEmail: state.accountEmail,
      );

      // Save to repository
      _saveSmsMessage(message);
    } catch (e, stackTrace) {
      debugPrint('[SmsSyncManager] Error handling WebSocket event for account $accountId: $e');
      debugPrint('[SmsSyncManager] Stack trace: $stackTrace');
    }
  }

  /// Save SMS message to repository
  Future<void> _saveSmsMessage(MessageIndex message) async {
    try {
      // Check if message already exists (avoid duplicates)
      final existing = await _messageRepository.getById(message.id);
      if (existing != null) {
        debugPrint('[SmsSyncManager] Message ${message.id} already exists, skipping');
        return;
      }

      // Save message
      await _messageRepository.upsertMessages([message]);
      debugPrint('[SmsSyncManager] Saved SMS message: ${message.id} (account: ${message.accountEmail})');

      // Notify callback
      onSmsReceived?.call(message);
    } catch (e) {
      debugPrint('[SmsSyncManager] Error saving SMS message: $e');
    }
  }

  /// Handle WebSocket connection established for a specific account
  void _handleWebSocketConnected(String accountId) {
    debugPrint('[SmsSyncManager] WebSocket connected for account $accountId');
    // Force catch-up on initial connection to ensure we get any missed messages
    unawaited(_catchUpWithRest(accountId, force: true));
  }

  /// Handle WebSocket disconnection for a specific account
  void _handleWebSocketDisconnected(String accountId) {
    debugPrint('[SmsSyncManager] WebSocket disconnected for account $accountId');
    
    // Check if sync should still be running for this account
    final state = _accountStates[accountId];
    if (state != null) {
      unawaited(_checkAccountSyncState(accountId));
    }
  }

  /// Handle WebSocket errors for a specific account
  void _handleWebSocketError(String accountId, String error) {
    debugPrint('[SmsSyncManager] WebSocket error for account $accountId: $error');
    
    // If it's an authentication error, stop trying for this account
    if (error.contains('401') || error.contains('unauthorized') || error.contains('invalid')) {
      debugPrint('[SmsSyncManager] Authentication error for account $accountId, stopping sync');
      unawaited(_stopForAccount(accountId));
    }
  }

  /// Start periodic state checking for all accounts
  void _startStateChecking() {
    // Check state every 30 seconds to ensure sync is still enabled
    _checkAllAccountsTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkAllAccountsState();
    });
  }

  /// Check sync state for all accounts
  Future<void> _checkAllAccountsState() async {
    final isEnabled = await _syncService.isSyncEnabled();
    if (!isEnabled) {
      debugPrint('[SmsSyncManager] Sync disabled, stopping all accounts...');
      await stop();
      return;
    }

    // Get current accounts with tokens
    final accountsWithTokens = await _syncService.getAccountsWithTokens();
    final currentAccountIds = _accountStates.keys.toSet();
    final tokenAccountIds = accountsWithTokens.toSet();

    // Stop sync for accounts that no longer have tokens
    for (final accountId in currentAccountIds) {
      if (!tokenAccountIds.contains(accountId)) {
        debugPrint('[SmsSyncManager] Token removed for account $accountId, stopping sync...');
        await _stopForAccount(accountId);
      }
    }

    // Start sync for new accounts with tokens
    for (final accountId in tokenAccountIds) {
      if (!currentAccountIds.contains(accountId)) {
        debugPrint('[SmsSyncManager] New token found for account $accountId, starting sync...');
        await _startForAccount(accountId);
      } else {
        // Check individual account state
        await _checkAccountSyncState(accountId);
      }
    }
  }

  /// Check if sync should still be running for a specific account
  Future<void> _checkAccountSyncState(String accountId) async {
    final state = _accountStates[accountId];
    if (state == null) return;

    final isEnabled = await _syncService.isSyncEnabled();
    if (!isEnabled) {
      await _stopForAccount(accountId);
      return;
    }

    final token = await _syncService.getToken(accountId);
    if (token == null || token.isEmpty) {
      debugPrint('[SmsSyncManager] Token missing for account $accountId, stopping...');
      await _stopForAccount(accountId);
      return;
    }

    final account = await _googleAuthService.getAccountById(accountId);
    if (account == null) {
      debugPrint('[SmsSyncManager] Account $accountId no longer available, stopping...');
      await _stopForAccount(accountId);
      return;
    }

    // If WebSocket is not connected and we should be, try to reconnect
    if (!state.webSocketService.isConnected && !state.webSocketService.isConnecting) {
      debugPrint('[SmsSyncManager] WebSocket not connected for account $accountId, attempting reconnect...');
      await state.webSocketService.connect();
    }
  }

  /// Check if SMS sync is currently running for any account
  bool get isRunning => _accountStates.isNotEmpty;

  /// Check if WebSocket is connected for any account
  bool get isConnected {
    for (final state in _accountStates.values) {
      if (state.webSocketService.isConnected) {
        return true;
      }
    }
    return false;
  }

  /// Public entry point for forcing a REST catch-up (e.g., on app resume).
  /// Catches up for all accounts
  Future<void> catchUpMissedMessages({bool force = false}) async {
    if (_accountStates.isEmpty) {
      debugPrint('[SmsSyncManager] catchUpMissedMessages skipped (no accounts running)');
      return;
    }

    for (final accountId in _accountStates.keys) {
      unawaited(_catchUpWithRest(accountId, force: force));
    }
  }

  Future<void> _catchUpWithRest(String accountId, {bool force = false}) async {
    final state = _accountStates[accountId];
    if (state == null) {
      debugPrint('[SmsSyncManager] REST catch-up skipped for account $accountId (not running)');
      return;
    }

    if (state.isRestCatchUpRunning) {
      debugPrint('[SmsSyncManager] REST catch-up already running for account $accountId');
      return;
    }

    if (!force &&
        state.lastRestCatchUp != null &&
        DateTime.now().difference(state.lastRestCatchUp!) < _AccountSyncState.restCatchUpMinInterval) {
      debugPrint('[SmsSyncManager] REST catch-up skipped for account $accountId (too soon since last catch-up: ${DateTime.now().difference(state.lastRestCatchUp!)} < ${_AccountSyncState.restCatchUpMinInterval})');
      return;
    }

    debugPrint('[SmsSyncManager] Starting REST catch-up for account $accountId (force=$force)');
    state.isRestCatchUpRunning = true;
    try {
      // Use modified_after to only fetch messages modified since last catch-up (unless forced)
      final modifiedAfter = force ? null : state.lastRestCatchUp;
      if (modifiedAfter != null) {
        debugPrint('[SmsSyncManager] Using modified_after: ${modifiedAfter.toIso8601String()}');
      }
      final events = await _restService.fetchRecentSmsEvents(
        accountId,
        modifiedAfter: modifiedAfter,
      );
      debugPrint('[SmsSyncManager] REST catch-up fetched ${events.length} SMS events for account $accountId');
      if (events.isEmpty) {
        debugPrint('[SmsSyncManager] REST catch-up: no events to process for account $accountId');
        state.lastRestCatchUp = DateTime.now();
        debugPrint('[SmsSyncManager] REST catch-up completed for account $accountId: no new messages found');
        return;
      }
      int savedCount = 0;
      int skippedCount = 0;
      for (final smsEvent in events) {
        if (!smsEvent.isValid) {
          skippedCount++;
          continue;
        }
        final message = SmsMessageConverter.toMessageIndex(
          smsEvent,
          accountId: accountId,
          accountEmail: state.accountEmail,
        );
        await _saveSmsMessage(message);
        savedCount++;
      }
      state.lastRestCatchUp = DateTime.now();
      debugPrint('[SmsSyncManager] REST catch-up completed for account $accountId: saved $savedCount messages, skipped $skippedCount invalid events');
    } catch (e, stackTrace) {
      debugPrint('[SmsSyncManager] REST catch-up error for account $accountId: $e');
      debugPrint('[SmsSyncManager] Stack trace: $stackTrace');
    } finally {
      state.isRestCatchUpRunning = false;
    }
  }

  /// Start sync for a specific account (public method for external use)
  Future<void> startForAccount(String accountId) async {
    final isEnabled = await _syncService.isSyncEnabled();
    if (!isEnabled) {
      debugPrint('[SmsSyncManager] SMS sync is disabled, cannot start for account $accountId');
      return;
    }

    final hasToken = await _syncService.hasToken(accountId);
    if (!hasToken) {
      debugPrint('[SmsSyncManager] No token for account $accountId, cannot start sync');
      return;
    }

    await _startForAccount(accountId);
  }

  /// Stop sync for a specific account (public method for external use)
  Future<void> stopForAccount(String accountId) async {
    await _stopForAccount(accountId);
  }
}
