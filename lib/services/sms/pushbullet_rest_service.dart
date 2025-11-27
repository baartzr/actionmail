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
    debugPrint('[PushbulletRest] Build mode: ${kDebugMode ? "DEBUG" : "RELEASE"}');
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
          debugPrint('[PushbulletRest] Found ${devices.length} total device(s) in Pushbullet account');
          
          // Find the first phone device (type == 'phone' or 'android')
          // Note: Android phones show up as type='android', not 'phone'
          bool foundPhoneDevice = false;
          for (final device in devices) {
            if (device is Map<String, dynamic>) {
              final type = device['type'] as String?;
              final iden = device['iden'] as String?;
              final nickname = device['nickname'] as String?;
              debugPrint('[PushbulletRest]   Device: type=$type, iden=$iden, nickname=$nickname');
              
              // Accept both 'phone' and 'android' as valid phone device types
              if ((type == 'phone' || type == 'android') && iden != null && iden.isNotEmpty) {
                deviceId = iden;
                await _smsSyncService.setDeviceId(accountId, deviceId);
                debugPrint('[PushbulletRest] ✓ Fetched and stored phone device ID from API: $deviceId (type=$type)');
                foundPhoneDevice = true;
                break;
              }
            }
          }
          
          if (!foundPhoneDevice) {
            debugPrint('[PushbulletRest] No phone devices found in Pushbullet account');
            debugPrint('[PushbulletRest] Will wait for SMS via WebSocket to get device ID');
          }
        } else {
          debugPrint('[PushbulletRest] Failed to fetch devices from API: status ${devicesResp.statusCode}');
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
        // Log response body for debugging
        if (resp.body.isNotEmpty) {
          debugPrint('[PushbulletRest] Response body: ${resp.body.substring(0, resp.body.length > 200 ? 200 : resp.body.length)}');
        }
        
        // 404 is expected when permanent object doesn't exist yet (normal for new devices or devices without SMS history)
        if (resp.statusCode == 404) {
          // Always try fetching without modified_after to check if object exists at all
          debugPrint('[PushbulletRest] 404 received, checking if permanent object exists without modified_after...');
          try {
            final fallbackUri = Uri.parse('https://api.pushbullet.com/v2/permanents/${deviceId}_recent_sms');
            final fallbackResp = await http.get(
              fallbackUri,
              headers: {
                'Access-Token': token,
                'Content-Type': 'application/json',
              },
            );
            debugPrint('[PushbulletRest] Fallback fetch (no modified_after) status: ${fallbackResp.statusCode}');
            if (fallbackResp.statusCode == 200) {
              debugPrint('[PushbulletRest] Permanent object EXISTS but no messages modified after ${modifiedAfter?.toIso8601String() ?? "N/A"}');
              // Parse and return the messages
              final map = jsonDecode(fallbackResp.body) as Map<String, dynamic>;
              final threads = (map['threads'] as List<dynamic>?) ?? const [];
              debugPrint('[PushbulletRest] Found ${threads.length} threads in permanent object');
              final events = PushbulletMessageParser.parseRecentSmsThreads(threads);
              debugPrint('[PushbulletRest] Parsed ${events.length} SMS events from threads');
              events.sort((a, b) {
                final aTime = a.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
                final bTime = b.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
                return aTime.compareTo(bTime);
              });
              return events;
            } else if (fallbackResp.statusCode == 404) {
              debugPrint('[PushbulletRest] Permanent object does NOT exist - Pushbullet has not created it yet');
              debugPrint('[PushbulletRest] Device ID: $deviceId');
              debugPrint('[PushbulletRest] Note: Permanent object is created by Pushbullet backend, may take time after SMS activity');
              // Try to verify device ID is correct
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
                  // Android phones show up as type='android', not 'phone'
                  final phoneDevices = devices.where((d) => 
                    d is Map<String, dynamic> && 
                    ((d['type'] as String?) == 'phone' || (d['type'] as String?) == 'android')
                  ).toList();
                  debugPrint('[PushbulletRest] Found ${phoneDevices.length} phone device(s) in account');
                  
                  bool deviceIdFound = false;
                  for (final device in phoneDevices) {
                    final d = device as Map<String, dynamic>;
                    final iden = d['iden'] as String?;
                    final nickname = d['nickname'] as String?;
                    debugPrint('[PushbulletRest]   Device: iden=$iden, nickname=$nickname');
                    if (iden == deviceId) {
                      debugPrint('[PushbulletRest]   ✓ Stored device ID matches this device');
                      deviceIdFound = true;
                    }
                  }
                  
                  // If we have a stored device ID but it doesn't match any phone device, clear it
                  if (phoneDevices.isEmpty || !deviceIdFound) {
                    if (deviceId.isNotEmpty) {
                      debugPrint('[PushbulletRest] ⚠️ Stored device ID ($deviceId) is invalid - no matching phone device found');
                      debugPrint('[PushbulletRest] This could happen if:');
                      debugPrint('[PushbulletRest]   1. Device was removed/re-registered in Pushbullet');
                      debugPrint('[PushbulletRest]   2. Device ID was stored by a different build (debug vs release)');
                      debugPrint('[PushbulletRest]   3. Device ID is from a different Pushbullet account');
                      debugPrint('[PushbulletRest] Clearing invalid device ID. Will wait for new SMS via WebSocket to get correct device ID.');
                      await _smsSyncService.setDeviceId(accountId, '');
                      debugPrint('[PushbulletRest] Invalid device ID cleared');
                    } else if (phoneDevices.isEmpty) {
                      debugPrint('[PushbulletRest] No phone devices found in Pushbullet account');
                      debugPrint('[PushbulletRest] SMS sync will not work until a phone device is registered');
                    }
                  }
                }
              } catch (e) {
                debugPrint('[PushbulletRest] Error verifying device ID: $e');
              }
            } else {
              debugPrint('[PushbulletRest] Fallback fetch returned unexpected status: ${fallbackResp.statusCode}');
            }
          } catch (e) {
            debugPrint('[PushbulletRest] Error in fallback fetch: $e');
          }
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

  /// Query a specific push by ID to check its status
  Future<void> checkPushStatus(String accountId, String pushId) async {
    debugPrint('[PushbulletRest] Checking status of push $pushId...');
    final token = await _smsSyncService.getToken(accountId);
    if (token == null || token.isEmpty) {
      debugPrint('[PushbulletRest] Missing access token for account $accountId');
      return;
    }

    try {
      final uri = Uri.parse('https://api.pushbullet.com/v2/pushes/$pushId');
      final resp = await http.get(
        uri,
        headers: {
          'Access-Token': token,
          'Content-Type': 'application/json',
        },
      );

      debugPrint('[PushbulletRest] Push status endpoint status: ${resp.statusCode}');
      if (resp.statusCode == 200) {
        final push = jsonDecode(resp.body) as Map<String, dynamic>;
        final active = push['active'] as bool?;
        final type = push['type'] as String?;
        final data = push['data'] as Map<String, dynamic>?;
        final error = push['error'] as Map<String, dynamic>?;
        debugPrint('[PushbulletRest] Push $pushId: active=$active, type=$type');
        if (error != null) {
          debugPrint('[PushbulletRest] ⚠️ Push has error: $error');
        }
        if (data != null) {
          debugPrint('[PushbulletRest] Push data: addresses=${data['addresses']}, message length=${(data['message'] as String?)?.length ?? 0}');
        }
      } else {
        debugPrint('[PushbulletRest] Push status error: ${resp.statusCode} ${resp.body}');
      }
    } catch (e, stackTrace) {
      debugPrint('[PushbulletRest] Error checking push status: $e');
      debugPrint('[PushbulletRest] Stack trace: $stackTrace');
    }
  }

  /// Query the /v2/pushes endpoint to check if sent SMS messages are recorded
  /// Pushbullet stores texts as pushes with data.addresses field
  /// This helps diagnose if SMS sends are being created but not sent
  Future<void> checkSentTexts(String accountId) async {
    debugPrint('[PushbulletRest] Checking sent texts (via pushes) for account $accountId...');
    final token = await _smsSyncService.getToken(accountId);
    if (token == null || token.isEmpty) {
      debugPrint('[PushbulletRest] Missing access token for account $accountId');
      return;
    }

    try {
      // Query recent pushes (last 20, include inactive to see if they're being deleted)
      final uri = Uri.parse('https://api.pushbullet.com/v2/pushes').replace(
        queryParameters: {
          'limit': '20',
        },
      );
      final resp = await http.get(
        uri,
        headers: {
          'Access-Token': token,
          'Content-Type': 'application/json',
        },
      );

      debugPrint('[PushbulletRest] Pushes endpoint status: ${resp.statusCode}');
      if (resp.statusCode == 200) {
        final map = jsonDecode(resp.body) as Map<String, dynamic>;
        final pushes = (map['pushes'] as List<dynamic>?) ?? [];
        debugPrint('[PushbulletRest] Found ${pushes.length} total push(es) (including inactive)');
        
        // Filter for text pushes (pushes with data.addresses field)
        final textPushes = <Map<String, dynamic>>[];
        final activeTextPushes = <Map<String, dynamic>>[];
        final inactiveTextPushes = <Map<String, dynamic>>[];
        
        for (final push in pushes) {
          if (push is Map<String, dynamic>) {
            final data = push['data'] as Map<String, dynamic>?;
            if (data != null && data.containsKey('addresses')) {
              textPushes.add(push);
              final active = push['active'] as bool?;
              if (active == true) {
                activeTextPushes.add(push);
              } else {
                inactiveTextPushes.add(push);
              }
            }
          }
        }
        
        debugPrint('[PushbulletRest] Found ${textPushes.length} text push(es) total');
        debugPrint('[PushbulletRest]   ${activeTextPushes.length} active, ${inactiveTextPushes.length} inactive');
        
        if (textPushes.isEmpty) {
          debugPrint('[PushbulletRest] ⚠️ No text pushes found at all');
          debugPrint('[PushbulletRest] This suggests:');
          debugPrint('[PushbulletRest]   1. Text pushes are not being stored in /v2/pushes');
          debugPrint('[PushbulletRest]   2. Text pushes are immediately deleted after creation');
          debugPrint('[PushbulletRest]   3. Text pushes might be stored elsewhere');
          debugPrint('[PushbulletRest] Note: Push was created (got 200 response), but not found in pushes list');
        } else {
          debugPrint('[PushbulletRest] Recent text pushes:');
          for (var i = 0; i < textPushes.length && i < 5; i++) {
            final push = textPushes[i];
            final iden = push['iden'] as String?;
            final active = push['active'] as bool?;
            final created = push['created'] as num?;
            final modified = push['modified'] as num?;
            final data = push['data'] as Map<String, dynamic>?;
            final addresses = data?['addresses'] as List<dynamic>?;
            final message = data?['message'] as String?;
            final targetDevice = push['target_device_iden'] as String?;
            debugPrint('[PushbulletRest]   Text $i: iden=$iden, active=$active');
            debugPrint('[PushbulletRest]     created=$created, modified=$modified');
            debugPrint('[PushbulletRest]     target_device=$targetDevice');
            debugPrint('[PushbulletRest]     addresses=$addresses');
            final messagePreview = message != null && message.length > 30 
                ? '${message.substring(0, 30)}...' 
                : message ?? '';
            debugPrint('[PushbulletRest]     message=$messagePreview');
          }
          
          if (inactiveTextPushes.isNotEmpty) {
            debugPrint('[PushbulletRest] ⚠️ Found ${inactiveTextPushes.length} inactive text push(es)');
            debugPrint('[PushbulletRest] This suggests texts are being created but immediately marked inactive');
          }
        }
      } else {
        debugPrint('[PushbulletRest] Pushes endpoint error: ${resp.statusCode} ${resp.body}');
      }
    } catch (e, stackTrace) {
      debugPrint('[PushbulletRest] Error checking sent texts: $e');
      debugPrint('[PushbulletRest] Stack trace: $stackTrace');
    }
  }
}

