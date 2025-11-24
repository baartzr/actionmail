import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Service for managing SMS sync via Pushbullet
/// Handles secure storage of access token and sync state
class SmsSyncService {
  static final SmsSyncService _instance = SmsSyncService._internal();
  factory SmsSyncService() => _instance;
  SmsSyncService._internal();

  static const String _prefsKeySyncEnabled = 'sms_sync_enabled';
  static const String _secureStorageKeyToken = 'pushbullet_access_token';
  static const String _prefsKeyAccountId = 'sms_sync_account_id';
  static const String _prefsKeyDeviceId = 'sms_sync_device_id';
  
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// Check if SMS sync is enabled
  Future<bool> isSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeySyncEnabled) ?? false;
  }

  /// Enable or disable SMS sync
  Future<void> setSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeySyncEnabled, enabled);
    debugPrint('[SmsSync] Sync ${enabled ? "enabled" : "disabled"}');
    
    // If disabling, optionally clear the token (user might want to keep it)
    // Uncomment the line below if you want to clear token when disabling
    // if (!enabled) await clearToken();
  }

  /// Get the stored Pushbullet access token
  Future<String?> getToken() async {
    try {
      return await _secureStorage.read(key: _secureStorageKeyToken);
    } catch (e) {
      debugPrint('[SmsSync] Error reading token: $e');
      return null;
    }
  }

  /// Store the Pushbullet access token securely
  Future<void> setToken(String token) async {
    try {
      await _secureStorage.write(key: _secureStorageKeyToken, value: token);
      debugPrint('[SmsSync] Token stored securely');
    } catch (e) {
      debugPrint('[SmsSync] Error storing token: $e');
      rethrow;
    }
  }

  /// Clear the stored token
  Future<void> clearToken() async {
    try {
      await _secureStorage.delete(key: _secureStorageKeyToken);
      debugPrint('[SmsSync] Token cleared');
      await clearDeviceId();
    } catch (e) {
      debugPrint('[SmsSync] Error clearing token: $e');
    }
  }

  /// Check if a token is stored
  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Get the Gmail account ID that owns the Pushbullet token
  Future<String?> getAccountId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKeyAccountId);
  }

  /// Persist the Gmail account ID for SMS sync
  Future<void> setAccountId(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyDeviceId);
    await prefs.setString(_prefsKeyAccountId, accountId);
    debugPrint('[SmsSync] Account id set to $accountId');
  }

  /// Clear the stored Gmail account ID
  Future<void> clearAccountId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyAccountId);
    await prefs.remove(_prefsKeyDeviceId);
    debugPrint('[SmsSync] Account id cleared');
  }

  /// Store the last-known Pushbullet device id (phone) for SMS sending
  Future<void> setDeviceId(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyDeviceId, deviceId);
    debugPrint('[SmsSync] Device id stored ($deviceId)');
  }

  /// Get the stored Pushbullet device id
  Future<String?> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKeyDeviceId);
  }

  /// Clear the stored Pushbullet device id
  Future<void> clearDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyDeviceId);
    debugPrint('[SmsSync] Device id cleared');
  }
}

