import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';

/// WebSocket service for Pushbullet real-time events
/// Handles connection, reconnection, and message streaming
class PushbulletWebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnecting = false;
  bool _isConnected = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _reconnectDelay = Duration(seconds: 5);

  final String accessToken;
  final void Function(Map<String, dynamic> event)? onEvent;
  final void Function(String error)? onError;
  final void Function()? onConnected;
  final void Function()? onDisconnected;

  PushbulletWebSocketService({
    required this.accessToken,
    this.onEvent,
    this.onError,
    this.onConnected,
    this.onDisconnected,
  });

  /// Connect to Pushbullet WebSocket stream
  Future<void> connect() async {
    if (_isConnecting || _isConnected) {
      debugPrint('[PushbulletWS] Already connected or connecting');
      return;
    }

    _isConnecting = true;
    _reconnectAttempts = 0;

    try {
      final uri = Uri.parse('wss://stream.pushbullet.com/websocket/$accessToken');
      debugPrint('[PushbulletWS] Connecting to: wss://stream.pushbullet.com/websocket/...');
      
      _channel = WebSocketChannel.connect(uri);
      _isConnecting = false;
      _isConnected = true;
      _reconnectAttempts = 0;

      debugPrint('[PushbulletWS] Connected successfully');
      onConnected?.call();

      // Listen to incoming messages
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
        cancelOnError: false,
      );
    } catch (e) {
      _isConnecting = false;
      _isConnected = false;
      debugPrint('[PushbulletWS] Connection error: $e');
      onError?.call('Connection failed: $e');
      _scheduleReconnect();
    }
  }

  /// Disconnect from WebSocket
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;

    await _subscription?.cancel();
    _subscription = null;

    await _channel?.sink.close();
    _channel = null;

    _isConnected = false;
    _isConnecting = false;

    debugPrint('[PushbulletWS] Disconnected');
    onDisconnected?.call();
  }

  /// Handle incoming WebSocket message
  void _handleMessage(dynamic message) {
    try {
      final data = message is String ? jsonDecode(message) : message;
      
      if (data is Map<String, dynamic>) {
        // Pushbullet sends different message types
        // We're interested in 'push' events with type 'mirror' (SMS notifications)
        if (data['type'] == 'push') {
          final push = data['push'] as Map<String, dynamic>?;
          final pushType = push?['type'];
          final notification = push?['notification'] as Map<String, dynamic>?;
          final notificationType = notification?['type'];
          debugPrint('[PushbulletWS] Received push event: pushType=$pushType notificationType=$notificationType');
          onEvent?.call(data);
        } else if (data['type'] == 'tickle') {
          // Tickle events indicate something changed, but we get the actual data via push
          debugPrint('[PushbulletWS] Received tickle event');
        } else if (data['type'] == 'nop') {
          // Keep-alive message
          debugPrint('[PushbulletWS] Received keep-alive');
        } else {
          debugPrint('[PushbulletWS] Received event: ${data['type']}');
          onEvent?.call(data);
        }
      }
    } catch (e) {
      debugPrint('[PushbulletWS] Error parsing message: $e');
      onError?.call('Parse error: $e');
    }
  }

  /// Handle WebSocket errors
  void _handleError(dynamic error) {
    debugPrint('[PushbulletWS] WebSocket error: $error');
    _isConnected = false;
    onError?.call('WebSocket error: $error');
    _scheduleReconnect();
  }

  /// Handle WebSocket disconnect
  void _handleDisconnect() {
    debugPrint('[PushbulletWS] WebSocket disconnected');
    _isConnected = false;
    onDisconnected?.call();
    _scheduleReconnect();
  }

  /// Schedule reconnection attempt
  void _scheduleReconnect() {
    if (_reconnectTimer != null || _reconnectAttempts >= _maxReconnectAttempts) {
      if (_reconnectAttempts >= _maxReconnectAttempts) {
        debugPrint('[PushbulletWS] Max reconnection attempts reached');
        onError?.call('Max reconnection attempts reached');
      }
      return;
    }

    _reconnectAttempts++;
    debugPrint('[PushbulletWS] Scheduling reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts in ${_reconnectDelay.inSeconds}s');

    _reconnectTimer = Timer(_reconnectDelay, () {
      if (!_isConnected && !_isConnecting) {
        debugPrint('[PushbulletWS] Attempting reconnection...');
        connect();
      }
    });
  }

  /// Check if currently connected
  bool get isConnected => _isConnected;

  /// Check if currently connecting
  bool get isConnecting => _isConnecting;
}

