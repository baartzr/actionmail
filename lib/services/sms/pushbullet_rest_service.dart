import 'dart:convert';
import 'package:domail/services/sms/pushbullet_message_parser.dart';
import 'package:domail/services/sms/sms_sync_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// REST helper for Pulling SMS history from Pushbullet.
class PushbulletRestService {
  PushbulletRestService();

  final SmsSyncService _smsSyncService = SmsSyncService();

  /// Fetch recent SMS threads and return them as PushbulletSmsEvent objects.
  /// The result is sorted by timestamp (oldest first) so callers can insert
  /// messages chronologically.
  Future<List<PushbulletSmsEvent>> fetchRecentSmsEvents(String accountId) async {
    final token = await _smsSyncService.getToken(accountId);
    if (token == null || token.isEmpty) {
      debugPrint('[PushbulletRest] Missing access token for account $accountId');
      return [];
    }

    final deviceId = await _smsSyncService.getDeviceId(accountId);
    if (deviceId == null || deviceId.isEmpty) {
      debugPrint('[PushbulletRest] Missing device id for account $accountId, cannot fetch recent SMS');
      return [];
    }

    final uri = Uri.parse('https://api.pushbullet.com/v2/permanents/${deviceId}_recent_sms');
    try {
      final resp = await http.get(
        uri,
        headers: {
          'Access-Token': token,
          'Content-Type': 'application/json',
        },
      );

      if (resp.statusCode != 200) {
        // 404 is expected when permanent object doesn't exist yet (normal for new devices or devices without SMS history)
        // Suppress 404 errors as they're expected and not actionable
        if (resp.statusCode == 404) {
          // Silent return - 404 is expected when permanent object doesn't exist yet
          // The object will be created by Pushbullet after the first SMS is received
          return [];
        }
        // Log other error status codes
        debugPrint('[PushbulletRest] Failed response: ${resp.statusCode} ${resp.body}');
        return [];
      }

      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      final threads = (map['threads'] as List<dynamic>?) ?? const [];
      final events = PushbulletMessageParser.parseRecentSmsThreads(threads);
      events.sort((a, b) {
        final aTime = a.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aTime.compareTo(bTime);
      });
      return events;
    } catch (e, stackTrace) {
      debugPrint('[PushbulletRest] Error fetching recent SMS: $e');
      debugPrint('[PushbulletRest] Stack trace: $stackTrace');
      return [];
    }
  }
}

