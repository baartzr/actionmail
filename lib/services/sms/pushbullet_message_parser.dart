import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Parsed Pushbullet SMS event data
class PushbulletSmsEvent {
  final String? phoneNumber;
  final String? message;
  final DateTime? timestamp;
  final String? notificationId;
  final String? deviceId;

  PushbulletSmsEvent({
    this.phoneNumber,
    this.message,
    this.timestamp,
    this.notificationId,
    this.deviceId,
  });

  bool get isValid => phoneNumber != null && message != null;
}

/// Parser for Pushbullet WebSocket events
/// Extracts SMS-related data from Pushbullet push events
class PushbulletMessageParser {
  /// Parse a Pushbullet push event and extract SMS data if applicable
  /// Returns null if the event is not an SMS notification
  static PushbulletSmsEvent? parseSmsEvent(Map<String, dynamic> event) {
    try {
      // Pushbullet sends events with type 'push'
      if (event['type'] != 'push') {
        return null;
      }

      final push = event['push'] as Map<String, dynamic>?;
      if (push == null) {
        return null;
      }

      // Check if this is a mirror notification (SMS notifications come as mirror type)
      final pushType = push['type'] as String?;
      if (pushType != 'mirror') {
        return null;
      }

      // Extract notification data
      final notification = push['notification'] as Map<String, dynamic>?;
      if (notification == null) {
        return null;
      }

      // Check if it's an SMS notification
      final notificationType = notification['type'] as String?;
      if (notificationType != 'sms_changed') {
        return null;
      }

      // Extract SMS data from notification body
      final body = notification['body'] as String?;
      final title = notification['title'] as String?;
      
      // For SMS, Pushbullet sends the phone number in the title and message in the body
      // Format may vary, but typically:
      // - title: phone number or contact name
      // - body: SMS message content
      
      String? phoneNumber;
      String? message;

      // Try to extract phone number from title
      if (title != null && title.isNotEmpty) {
        // Remove common prefixes/suffixes
        phoneNumber = _extractPhoneNumber(title);
      }

      // Message is in the body
      message = body;

      // Extract timestamp (use current time if not available)
      DateTime? timestamp;
      final created = push['created'] as num?;
      if (created != null) {
        timestamp = DateTime.fromMillisecondsSinceEpoch((created * 1000).toInt());
      } else {
        timestamp = DateTime.now();
      }

      // Extract IDs
      final notificationId = notification['notification_id'] as String?;
      final deviceId = push['device_iden'] as String?;

      return PushbulletSmsEvent(
        phoneNumber: phoneNumber,
        message: message,
        timestamp: timestamp,
        notificationId: notificationId,
        deviceId: deviceId,
      );
    } catch (e) {
      debugPrint('[PushbulletParser] Error parsing SMS event: $e');
      debugPrint('[PushbulletParser] Event data: ${jsonEncode(event)}');
      return null;
    }
  }

  /// Extract phone number from a string (removes common prefixes/suffixes)
  static String? _extractPhoneNumber(String text) {
    // Remove common SMS prefixes
    final cleaned = text
        .replaceAll(RegExp(r'^SMS from\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'^Text from\s*', caseSensitive: false), '')
        .trim();

    // If it looks like a phone number (contains digits), return it
    if (RegExp(r'[\d\+\-\(\)\s]+').hasMatch(cleaned)) {
      return cleaned;
    }

    // Otherwise, return as-is (might be a contact name)
    return cleaned.isNotEmpty ? cleaned : null;
  }

  /// Check if an event is an SMS-related event
  static bool isSmsEvent(Map<String, dynamic> event) {
    try {
      if (event['type'] != 'push') return false;
      final push = event['push'] as Map<String, dynamic>?;
      if (push == null) return false;
      if (push['type'] != 'mirror') return false;
      final notification = push['notification'] as Map<String, dynamic>?;
      if (notification == null) return false;
      return notification['type'] == 'sms_changed';
    } catch (e) {
      return false;
    }
  }
}

