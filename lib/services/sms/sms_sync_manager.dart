import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:domail/services/sms/sms_sync_service.dart';
import 'package:domail/services/sms/pushbullet_websocket_service.dart';
import 'package:domail/services/sms/pushbullet_message_parser.dart';
import 'package:domail/services/sms/sms_message_converter.dart';
import 'package:domail/data/repositories/message_repository.dart';
import 'package:domail/data/models/message_index.dart';

/// Main manager for SMS sync functionality
/// Orchestrates WebSocket connection, message parsing, and storage
class SmsSyncManager {
  static final SmsSyncManager _instance = SmsSyncManager._internal();
  factory SmsSyncManager() => _instance;
  SmsSyncManager._internal();

  final SmsSyncService _syncService = SmsSyncService();
  final MessageRepository _messageRepository = MessageRepository();
  
  PushbulletWebSocketService? _webSocketService;
  bool _isRunning = false;
  Timer? _checkStateTimer;

  /// Callback when a new SMS message is received and saved
  void Function(MessageIndex message)? onSmsReceived;

  /// Start SMS sync if enabled
  /// Checks sync state and token, then establishes WebSocket connection
  Future<void> start() async {
    if (_isRunning) {
      debugPrint('[SmsSyncManager] Already running');
      return;
    }

    final isEnabled = await _syncService.isSyncEnabled();
    if (!isEnabled) {
      debugPrint('[SmsSyncManager] SMS sync is disabled');
      return;
    }

    final token = await _syncService.getToken();
    if (token == null || token.isEmpty) {
      debugPrint('[SmsSyncManager] No access token available');
      return;
    }

    _isRunning = true;
    debugPrint('[SmsSyncManager] Starting SMS sync...');

    // Create and configure WebSocket service
    _webSocketService = PushbulletWebSocketService(
      accessToken: token,
      onEvent: _handleWebSocketEvent,
      onError: _handleWebSocketError,
      onConnected: _handleWebSocketConnected,
      onDisconnected: _handleWebSocketDisconnected,
    );

    // Start periodic state checking
    _startStateChecking();

    // Connect to WebSocket
    await _webSocketService!.connect();
  }

  /// Stop SMS sync and disconnect WebSocket
  Future<void> stop() async {
    if (!_isRunning) {
      return;
    }

    _isRunning = false;
    debugPrint('[SmsSyncManager] Stopping SMS sync...');

    _checkStateTimer?.cancel();
    _checkStateTimer = null;

    await _webSocketService?.disconnect();
    _webSocketService = null;
  }

  /// Handle WebSocket events
  void _handleWebSocketEvent(Map<String, dynamic> event) {
    try {
      // Check if this is an SMS event
      if (!PushbulletMessageParser.isSmsEvent(event)) {
        return;
      }

      // Parse SMS event
      final smsEvent = PushbulletMessageParser.parseSmsEvent(event);
      if (smsEvent == null || !smsEvent.isValid) {
        debugPrint('[SmsSyncManager] Invalid SMS event');
        return;
      }

      debugPrint('[SmsSyncManager] Received SMS from ${smsEvent.phoneNumber}');

      // Convert to MessageIndex
      final message = SmsMessageConverter.toMessageIndex(smsEvent);

      // Save to repository
      _saveSmsMessage(message);
    } catch (e, stackTrace) {
      debugPrint('[SmsSyncManager] Error handling WebSocket event: $e');
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
      debugPrint('[SmsSyncManager] Saved SMS message: ${message.id}');

      // Notify callback
      onSmsReceived?.call(message);
    } catch (e) {
      debugPrint('[SmsSyncManager] Error saving SMS message: $e');
    }
  }

  /// Handle WebSocket connection established
  void _handleWebSocketConnected() {
    debugPrint('[SmsSyncManager] WebSocket connected');
  }

  /// Handle WebSocket disconnection
  void _handleWebSocketDisconnected() {
    debugPrint('[SmsSyncManager] WebSocket disconnected');
    
    // If still supposed to be running, it will reconnect automatically
    // But we should check if sync is still enabled
    if (_isRunning) {
      _checkSyncState();
    }
  }

  /// Handle WebSocket errors
  void _handleWebSocketError(String error) {
    debugPrint('[SmsSyncManager] WebSocket error: $error');
    
    // If it's an authentication error, stop trying
    if (error.contains('401') || error.contains('unauthorized') || error.contains('invalid')) {
      debugPrint('[SmsSyncManager] Authentication error, stopping sync');
      stop();
    }
  }

  /// Start periodic state checking
  void _startStateChecking() {
    // Check state every 30 seconds to ensure sync is still enabled
    _checkStateTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkSyncState();
    });
  }

  /// Check if sync should still be running
  Future<void> _checkSyncState() async {
    if (!_isRunning) return;

    final isEnabled = await _syncService.isSyncEnabled();
    if (!isEnabled) {
      debugPrint('[SmsSyncManager] Sync disabled, stopping...');
      await stop();
      return;
    }

    final token = await _syncService.getToken();
    if (token == null || token.isEmpty) {
      debugPrint('[SmsSyncManager] Token missing, stopping...');
      await stop();
      return;
    }

    // If WebSocket is not connected and we should be, try to reconnect
    if (_webSocketService != null && !_webSocketService!.isConnected && !_webSocketService!.isConnecting) {
      debugPrint('[SmsSyncManager] WebSocket not connected, attempting reconnect...');
      await _webSocketService!.connect();
    }
  }

  /// Check if SMS sync is currently running
  bool get isRunning => _isRunning;

  /// Check if WebSocket is connected
  bool get isConnected => _webSocketService?.isConnected ?? false;
}

