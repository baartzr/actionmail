import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:domail/services/whatsapp/whatsapp_sync_service.dart';
import 'package:domail/services/whatsapp/whatsapp_api_service.dart';
import 'package:domail/services/whatsapp/whatsapp_message_converter.dart';
import 'package:domail/data/repositories/message_repository.dart';
import 'package:domail/data/models/message_index.dart';
import 'package:domail/services/auth/google_auth_service.dart';

/// Main manager for WhatsApp sync functionality
/// Polls for new messages or receives them via webhook
/// Note: This implementation uses polling. For production, consider using webhooks.
class WhatsAppSyncManager {
  static final WhatsAppSyncManager _instance = WhatsAppSyncManager._internal();
  factory WhatsAppSyncManager() => _instance;
  WhatsAppSyncManager._internal();

  final WhatsAppSyncService _syncService = WhatsAppSyncService();
  final MessageRepository _messageRepository = MessageRepository();
  final GoogleAuthService _googleAuthService = GoogleAuthService();
  
  Timer? _pollTimer;
  bool _isRunning = false;
  String? _activeAccountId;
  String? _activeAccountEmail;

  /// Callback when a new WhatsApp message is received and saved
  void Function(MessageIndex message)? onWhatsAppReceived;

  /// Start WhatsApp sync if enabled
  /// Checks sync state and credentials, then starts polling for messages
  Future<void> start() async {
    if (_isRunning) {
      debugPrint('[WhatsAppSyncManager] Already running');
      return;
    }

    final isEnabled = await _syncService.isSyncEnabled();
    if (!isEnabled) {
      debugPrint('[WhatsAppSyncManager] WhatsApp sync is disabled');
      return;
    }

    final token = await _syncService.getToken();
    if (token == null || token.isEmpty) {
      debugPrint('[WhatsAppSyncManager] No access token available');
      return;
    }

    final phoneNumberId = await _syncService.getPhoneNumberId();
    if (phoneNumberId == null || phoneNumberId.isEmpty) {
      debugPrint('[WhatsAppSyncManager] No phone number ID available');
      return;
    }

    final accountId = await _syncService.getAccountId();
    if (accountId == null || accountId.isEmpty) {
      debugPrint('[WhatsAppSyncManager] No account selected for WhatsApp sync');
      return;
    }

    final account = await _googleAuthService.getAccountById(accountId);
    if (account == null) {
      debugPrint('[WhatsAppSyncManager] Selected account is no longer available');
      return;
    }

    _activeAccountId = account.id;
    _activeAccountEmail = account.email;

    _isRunning = true;
    debugPrint('[WhatsAppSyncManager] Starting WhatsApp sync...');

    // Start polling for messages (poll every 30 seconds)
    _startPolling(token, phoneNumberId);
  }

  /// Stop WhatsApp sync
  Future<void> stop() async {
    if (!_isRunning) {
      return;
    }

    _isRunning = false;
    debugPrint('[WhatsAppSyncManager] Stopping WhatsApp sync...');

    _pollTimer?.cancel();
    _pollTimer = null;
    _activeAccountId = null;
    _activeAccountEmail = null;
  }

  /// Start polling for new messages
  void _startPolling(String token, String phoneNumberId) {
    // Poll immediately
    _pollForMessages(token, phoneNumberId);

    // Then poll every 30 seconds
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isRunning) {
        _pollForMessages(token, phoneNumberId);
      }
    });
  }

  /// Poll the WhatsApp API for new messages
  /// Note: WhatsApp Business API doesn't have a direct "get messages" endpoint
  /// In production, you should use webhooks instead of polling
  /// This is a simplified implementation for demonstration
  Future<void> _pollForMessages(String token, String phoneNumberId) async {
    if (_activeAccountId == null || _activeAccountEmail == null) {
      return;
    }

    try {
      // Note: WhatsApp Business API doesn't provide a polling endpoint for messages
      // This is a placeholder. In production, you should:
      // 1. Set up webhooks to receive messages in real-time
      // 2. Process webhook events via WhatsAppApiService.parseWebhookEvent()
      
      debugPrint('[WhatsAppSyncManager] Polling for messages...');
      // TODO: Implement webhook receiver endpoint or use WhatsApp Cloud API webhooks
      // For now, we'll rely on manual webhook processing via processWebhookEvent()
      
    } catch (e, stackTrace) {
      debugPrint('[WhatsAppSyncManager] Error polling for messages: $e');
      debugPrint('[WhatsAppSyncManager] Stack trace: $stackTrace');
    }
  }

  /// Process a webhook event (call this from your webhook endpoint)
  /// This method should be called when your server receives a webhook from WhatsApp
  Future<void> processWebhookEvent(Map<String, dynamic> event) async {
    if (!_isRunning) {
      debugPrint('[WhatsAppSyncManager] Not running, ignoring webhook event');
      return;
    }

    if (_activeAccountId == null || _activeAccountEmail == null) {
      debugPrint('[WhatsAppSyncManager] Missing active account context, ignoring webhook event');
      return;
    }

    try {
      // Parse the webhook event
      final messageEvents = WhatsAppApiService.parseWebhookEvent(event);

      for (final messageEvent in messageEvents) {
        if (!messageEvent.isValid) {
          debugPrint('[WhatsAppSyncManager] Invalid message event, skipping');
          continue;
        }

        debugPrint('[WhatsAppSyncManager] Received WhatsApp message from ${messageEvent.phoneNumber}');

        // Convert to MessageIndex
        final message = WhatsAppMessageConverter.toMessageIndex(
          messageEvent,
          accountId: _activeAccountId!,
          accountEmail: _activeAccountEmail!,
        );

        // Save to repository
        await _saveWhatsAppMessage(message);
      }
    } catch (e, stackTrace) {
      debugPrint('[WhatsAppSyncManager] Error processing webhook event: $e');
      debugPrint('[WhatsAppSyncManager] Stack trace: $stackTrace');
    }
  }

  /// Save WhatsApp message to repository
  Future<void> _saveWhatsAppMessage(MessageIndex message) async {
    try {
      // Check if message already exists (avoid duplicates)
      final existing = await _messageRepository.getById(message.id);
      if (existing != null) {
        debugPrint('[WhatsAppSyncManager] Message ${message.id} already exists, skipping');
        return;
      }

      // Save message
      await _messageRepository.upsertMessages([message]);
      debugPrint('[WhatsAppSyncManager] Saved WhatsApp message: ${message.id}');

      // Notify callback
      onWhatsAppReceived?.call(message);
    } catch (e) {
      debugPrint('[WhatsAppSyncManager] Error saving WhatsApp message: $e');
    }
  }

  /// Check if WhatsApp sync is currently running
  bool get isRunning => _isRunning;
}

