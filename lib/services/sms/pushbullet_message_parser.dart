import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Parsed Pushbullet SMS event data
class PushbulletSmsEvent {
  final String? phoneNumber;
  final String? message;
  final DateTime? timestamp;
  final String? notificationId;
  final String? deviceId;
  final String? conversationId;
  final String? sourceUserId;
  final String? title;

  PushbulletSmsEvent({
    this.phoneNumber,
    this.message,
    this.timestamp,
    this.notificationId,
    this.deviceId,
    this.conversationId,
    this.sourceUserId,
    this.title,
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

      final pushType = push['type'] as String?;
      if (pushType == 'mirror') {
        return _parseMirrorEvent(push, sourceUserId: push['source_user_iden'] as String?);
      }
      if (pushType == 'sms_changed') {
        return _parseSmsChangedEvent(push, sourceUserId: push['source_user_iden'] as String?);
      }
      return null;
    } catch (e) {
      debugPrint('[PushbulletParser] Error parsing SMS event: $e');
      debugPrint('[PushbulletParser] Event data: ${jsonEncode(event)}');
      return null;
    }
  }

  static PushbulletSmsEvent? _parseMirrorEvent(
    Map<String, dynamic> push, {
    String? sourceUserId,
  }) {
    final notification = push['notification'] as Map<String, dynamic>?;
    if (notification == null) return null;

    final notificationType = notification['type'] as String?;
    if (notificationType != 'sms_changed') {
      return null;
    }

    final title = notification['title'] as String?;
    final body = notification['body'] as String?;

    final phoneNumber = _chooseBestPhone(
      fallback: title,
      primary: notification['address'] as String?,
      addresses: notification['addresses'],
      conversationId: notification['conversation_iden'] as String?,
    );
    final timestamp = _timestampFromSeconds(push['created'] as num?);
    final notificationId = notification['notification_id'] as String?;
    final deviceId = notification['source_device_iden'] as String? ?? push['device_iden'] as String?;
    final conversationId = notification['conversation_iden'] as String?;

    return PushbulletSmsEvent(
      phoneNumber: phoneNumber,
      message: body,
      timestamp: timestamp,
      notificationId: notificationId,
      deviceId: deviceId,
      conversationId: conversationId ?? phoneNumber,
      sourceUserId: sourceUserId,
      title: title,
    );
  }

  static PushbulletSmsEvent? _parseSmsChangedEvent(
    Map<String, dynamic> push, {
    String? sourceUserId,
  }) {
    final notifications = push['notifications'];
    if (notifications is! List || notifications.isEmpty) {
      return null;
    }

    final first = notifications.first;
    if (first is! Map<String, dynamic>) {
      return null;
    }

    final title = first['title'] as String?;
    final body = first['body'] as String?;
    final phoneNumber = _chooseBestPhone(
      primary: first['address'] as String?,
      addresses: first['addresses'],
      fallback: title,
      conversationId: first['conversation_iden'] as String?,
    );
    final timestamp = _timestampFromSeconds(first['timestamp'] as num?) ?? DateTime.now();
    final notificationId = first['notification_id'] as String? ?? first['iden'] as String?;
    final deviceId = first['source_device_iden'] as String? ??
        first['target_device_iden'] as String? ??
        push['source_device_iden'] as String?;
    final conversationId = first['conversation_iden'] as String? ?? phoneNumber;

    return PushbulletSmsEvent(
      phoneNumber: phoneNumber,
      message: body,
      timestamp: timestamp,
      notificationId: notificationId,
      deviceId: deviceId,
      conversationId: conversationId,
      sourceUserId: sourceUserId,
      title: title,
    );
  }

  static DateTime? _timestampFromSeconds(num? seconds) {
    if (seconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).toInt());
  }

  static String? _chooseBestPhone({
    String? primary,
    dynamic addresses,
    String? fallback,
    String? conversationId,
  }) {
    String? sanitize(String? input) {
      if (input == null) return null;
      final trimmed = input.trim();
      if (trimmed.isEmpty) return null;
      return trimmed;
    }

    final candidates = <String>[
      if (primary != null) primary,
      if (addresses is List)
        ...addresses.whereType<String>(),
      if (conversationId != null) conversationId,
      if (fallback != null) fallback,
    ];

    for (final raw in candidates) {
      final candidate = sanitize(_extractPhoneNumber(raw) ?? raw);
      if (candidate == null) {
        continue;
      }
      if (RegExp(r'\d').hasMatch(candidate)) {
        return candidate;
      }
    }
    return sanitize(primary ?? fallback ?? conversationId);
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
      final pushType = push['type'] as String?;
      if (pushType == 'mirror') {
        final notification = push['notification'] as Map<String, dynamic>?;
        if (notification == null) return false;
        return notification['type'] == 'sms_changed';
      }
      if (pushType == 'sms_changed') {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Provide a short human-readable summary of a Pushbullet event
  static String describeEvent(Map<String, dynamic> event) {
    try {
      final type = event['type'];
      if (type != 'push') {
        return 'type=$type';
      }
      final push = event['push'] as Map<String, dynamic>?;
      final pushType = push?['type'];
      if (pushType == 'sms_changed') {
        final notifications = push?['notifications'];
        final count = notifications is List ? notifications.length : 0;
        return 'type=push pushType=sms_changed notifications=$count';
      }
      final notification = push?['notification'] as Map<String, dynamic>?;
      final notificationType = notification?['type'];
      final title = notification?['title'];
      return 'type=push pushType=$pushType notificationType=$notificationType title=$title';
    } catch (e) {
      return 'unable to summarize event: $e';
    }
  }
}

