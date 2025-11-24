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
    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) {
      throw ArgumentError('Message cannot be empty');
    }

    final token = await _smsSyncService.getToken();
    if (token == null || token.isEmpty) {
      throw StateError('Pushbullet access token is missing');
    }

    final deviceId = await _smsSyncService.getDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw StateError('Phone connection unavailable. Receive an SMS first to link your device.');
    }

    final sanitizedNumber = _sanitizePhoneNumber(phoneNumber);
    if (sanitizedNumber.isEmpty) {
      throw ArgumentError('Invalid phone number: $phoneNumber');
    }

    final payload = jsonEncode({
      'data': {
        'addresses': [sanitizedNumber],
        'message': trimmedMessage,
      },
      'target_device_iden': deviceId,
    });

    final resp = await http.post(
      Uri.parse('https://api.pushbullet.com/v2/texts'),
      headers: {
        'Access-Token': token,
        'Content-Type': 'application/json',
      },
      body: payload,
    );

    if (resp.statusCode != 200) {
      debugPrint('[PushbulletSmsSender] Failed response: ${resp.statusCode} ${resp.body}');
      throw StateError('Pushbullet SMS failed (status ${resp.statusCode})');
    }

    debugPrint('[PushbulletSmsSender] SMS queued for $sanitizedNumber (account $accountId)');
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

