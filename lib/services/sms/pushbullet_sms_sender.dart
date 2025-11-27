import 'dart:async';
import 'dart:convert';
import 'package:domail/services/sms/sms_sync_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Sends SMS replies via Pushbullet's texting API.
class PushbulletSmsSender {
  PushbulletSmsSender();

  final SmsSyncService _smsSyncService = SmsSyncService();

  Future<void> sendSms({
    required String accountId,
    required String phoneNumber,
    required String message,
  }) async {
    debugPrint('[PushbulletSmsSender] Starting SMS send for account $accountId');
    debugPrint('[PushbulletSmsSender] Phone number: $phoneNumber');
    debugPrint('[PushbulletSmsSender] Message length: ${message.length} characters');
    
    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) {
      debugPrint('[PushbulletSmsSender] Error: Message cannot be empty');
      throw ArgumentError('Message cannot be empty');
    }

    debugPrint('[PushbulletSmsSender] Retrieving access token for account $accountId...');
    final token = await _smsSyncService.getToken(accountId);
    if (token == null || token.isEmpty) {
      debugPrint('[PushbulletSmsSender] Error: Pushbullet access token is missing for account $accountId');
      throw StateError('Pushbullet access token is missing for account $accountId');
    }
    debugPrint('[PushbulletSmsSender] Access token found for account $accountId');

    debugPrint('[PushbulletSmsSender] Retrieving device ID for account $accountId...');
    final deviceId = await _smsSyncService.getDeviceId(accountId);
    if (deviceId == null || deviceId.isEmpty) {
      debugPrint('[PushbulletSmsSender] Error: Phone connection unavailable. Device ID missing for account $accountId');
      throw StateError('Phone connection unavailable. Receive an SMS first to link your device.');
    }
    debugPrint('[PushbulletSmsSender] Device ID found for account $accountId: $deviceId');

    debugPrint('[PushbulletSmsSender] Sanitizing phone number: $phoneNumber');
    final sanitizedNumber = _sanitizePhoneNumber(phoneNumber);
    if (sanitizedNumber.isEmpty) {
      debugPrint('[PushbulletSmsSender] Error: Invalid phone number after sanitization: $phoneNumber');
      throw ArgumentError('Invalid phone number: $phoneNumber');
    }
    debugPrint('[PushbulletSmsSender] Sanitized phone number: $sanitizedNumber');
    
    // Note: Pushbullet typically expects E.164 format with + (e.g., +61491680024)
    // If this doesn't work, the desktop app might be using a different format
    // Check logs to see what format incoming SMS uses

    // Generate a unique GUID to prevent duplicate messages
    final guid = 'sms_${DateTime.now().millisecondsSinceEpoch}_$sanitizedNumber';
    
    // Note: target_device_iden should be INSIDE the data object, not at top level
    final payload = jsonEncode({
      'data': {
        'target_device_iden': deviceId,
        'addresses': [sanitizedNumber],
        'message': trimmedMessage,
        'guid': guid,
      },
    });
    debugPrint('[PushbulletSmsSender] Sending SMS to Pushbullet API...');
    debugPrint('[PushbulletSmsSender] Request URI: https://api.pushbullet.com/v2/texts');
    debugPrint('[PushbulletSmsSender] Request payload: $payload');
    debugPrint('[PushbulletSmsSender] Message preview: ${trimmedMessage.length > 50 ? "${trimmedMessage.substring(0, 50)}..." : trimmedMessage}');

    final resp = await http.post(
      Uri.parse('https://api.pushbullet.com/v2/texts'),
      headers: {
        'Access-Token': token,
        'Content-Type': 'application/json',
      },
      body: payload,
    );

    debugPrint('[PushbulletSmsSender] Response status: ${resp.statusCode}');
    debugPrint('[PushbulletSmsSender] Response body: ${resp.body}');
    
    if (resp.statusCode != 200) {
      debugPrint('[PushbulletSmsSender] Failed response: ${resp.statusCode} ${resp.body}');
      throw StateError('Pushbullet SMS failed (status ${resp.statusCode})');
    }

    // Parse response to check for errors even on 200 status
    // Note: Pushbullet returns the push object directly, not wrapped in a "push" field
    try {
      final responseData = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (responseData != null) {
        final error = responseData['error'];
        if (error != null) {
          debugPrint('[PushbulletSmsSender] ⚠️ Error in response: $error');
          throw StateError('Pushbullet SMS error: $error');
        }
        // Log push details (response IS the push object)
        final pushId = responseData['iden'] as String?;
        final pushType = responseData['type'] as String?;
        final active = responseData['active'] as bool?;
        final data = responseData['data'] as Map<String, dynamic>?;
        debugPrint('[PushbulletSmsSender] Push created: iden=$pushId, type=$pushType, active=$active');
        if (data != null) {
          debugPrint('[PushbulletSmsSender] Push data: addresses=${data['addresses']}, message length=${(data['message'] as String?)?.length ?? 0}');
        }
        // Store push ID for tracking (in case we get error events via WebSocket)
        if (pushId != null) {
          debugPrint('[PushbulletSmsSender] Push ID: $pushId');
        }
      }
    } catch (e) {
      debugPrint('[PushbulletSmsSender] Error parsing response: $e');
      // Don't throw - response might be valid even if parsing fails
    }

    debugPrint('[PushbulletSmsSender] SMS successfully queued for $sanitizedNumber (account $accountId)');
  }

  String _sanitizePhoneNumber(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    final digits = trimmed.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.startsWith('00')) {
      return '+${digits.substring(2)}';
    }
    return digits;
  }
}

