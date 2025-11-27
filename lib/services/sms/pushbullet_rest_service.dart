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
  /// 
  /// [modifiedAfter] - Optional timestamp to only fetch messages modified after this time.
  /// If provided, only messages modified after this timestamp will be returned.
  Future<List<PushbulletSmsEvent>> fetchRecentSmsEvents(
    String accountId, {
    DateTime? modifiedAfter,
  }) async {
    debugPrint('[PushbulletRest] fetchRecentSmsEvents called for account $accountId');
    final token = await _smsSyncService.getToken(accountId);
    if (token == null || token.isEmpty) {
      debugPrint('[PushbulletRest] Missing access token for account $accountId');
      return [];
    }
    debugPrint('[PushbulletRest] Access token found for account $accountId');

    var deviceId = await _smsSyncService.getDeviceId(accountId);
    if (deviceId == null || deviceId.isEmpty) {
      debugPrint('[PushbulletRest] Device ID not stored locally, attempting to fetch from Pushbullet API...');
      // Try to fetch device ID from Pushbullet devices API
      try {
        final devicesUri = Uri.parse('https://api.pushbullet.com/v2/devices');
        final devicesResp = await http.get(
          devicesUri,
          headers: {
            'Access-Token': token,
            'Content-Type': 'application/json',
          },
        );
        if (devicesResp.statusCode == 200) {
          final devicesMap = jsonDecode(devicesResp.body) as Map<String, dynamic>;
          final devices = (devicesMap['devices'] as List<dynamic>?) ?? [];
          // Find the first phone device (type == 'phone')
          for (final device in devices) {
            if (device is Map<String, dynamic>) {
              final type = device['type'] as String?;
              final iden = device['iden'] as String?;
              if (type == 'phone' && iden != null && iden.isNotEmpty) {
                deviceId = iden;
                await _smsSyncService.setDeviceId(accountId, deviceId);
                debugPrint('[PushbulletRest] Fetched and stored device ID from API: $deviceId');
                break;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[PushbulletRest] Error fetching device ID from API: $e');
      }
    }
    
    if (deviceId == null || deviceId.isEmpty) {
      debugPrint('[PushbulletRest] Missing device id for account $accountId, cannot fetch recent SMS');
      return [];
    }
    debugPrint('[PushbulletRest] Device ID found for account $accountId: $deviceId');

    // Build URI with optional modified_after parameter
    final uriBuilder = Uri.parse('https://api.pushbullet.com/v2/permanents/${deviceId}_recent_sms');
    final queryParams = <String, String>{};
    if (modifiedAfter != null) {
      // Pushbullet uses Unix timestamp (seconds since epoch)
      final modifiedAfterSeconds = modifiedAfter.millisecondsSinceEpoch ~/ 1000;
      queryParams['modified_after'] = modifiedAfterSeconds.toString();
      debugPrint('[PushbulletRest] Using modified_after: $modifiedAfterSeconds (${modifiedAfter.toIso8601String()})');
    }
    final uri = queryParams.isEmpty 
        ? uriBuilder 
        : uriBuilder.replace(queryParameters: queryParams);
    debugPrint('[PushbulletRest] Fetching from URI: $uri');
    try {
      final resp = await http.get(
        uri,
        headers: {
          'Access-Token': token,
          'Content-Type': 'application/json',
        },
      );

      debugPrint('[PushbulletRest] Response status: ${resp.statusCode}');
      if (resp.statusCode != 200) {
        // 404 is expected when permanent object doesn't exist yet (normal for new devices or devices without SMS history)
        // Suppress 404 errors as they're expected and not actionable
        if (resp.statusCode == 404) {
          debugPrint('[PushbulletRest] 404 response (permanent object not yet created) - this is normal for new devices');
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
      debugPrint('[PushbulletRest] Parsed ${threads.length} threads from response');
      final events = PushbulletMessageParser.parseRecentSmsThreads(threads);
      debugPrint('[PushbulletRest] Parsed ${events.length} SMS events from threads');
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

