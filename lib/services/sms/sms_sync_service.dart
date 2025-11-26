import 'dart:convert';
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
  static const String _secureStorageKeyTokenPrefix = 'pushbullet_access_token_';
  static const String _prefsKeyDeviceIdPrefix = 'sms_sync_device_id_';
  
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

  /// Get the stored Pushbullet access token for a specific account
  Future<String?> getToken(String accountId) async {
    try {
      final key = '$_secureStorageKeyTokenPrefix$accountId';
      return await _secureStorage.read(key: key);
    } catch (e) {
      debugPrint('[SmsSync] Error reading token for account $accountId: $e');
      return null;
    }
  }

  /// Store the Pushbullet access token securely for a specific account
  Future<void> setToken(String accountId, String token) async {
    try {
      final key = '$_secureStorageKeyTokenPrefix$accountId';
      await _secureStorage.write(key: key, value: token);
      // Update the account IDs list
      final accounts = await getAccountsWithTokens();
      if (!accounts.contains(accountId)) {
        accounts.add(accountId);
        await _updateTokenAccountIdsList(accounts);
      }
      debugPrint('[SmsSync] Token stored securely for account $accountId');
    } catch (e) {
      debugPrint('[SmsSync] Error storing token for account $accountId: $e');
      rethrow;
    }
  }

  /// Clear the stored token for a specific account
  Future<void> clearToken(String accountId) async {
    try {
      final key = '$_secureStorageKeyTokenPrefix$accountId';
      await _secureStorage.delete(key: key);
      // Remove from account IDs list
      final accounts = await getAccountsWithTokens();
      accounts.remove(accountId);
      await _updateTokenAccountIdsList(accounts);
      debugPrint('[SmsSync] Token cleared for account $accountId');
      await clearDeviceId(accountId);
    } catch (e) {
      debugPrint('[SmsSync] Error clearing token for account $accountId: $e');
    }
  }

  /// Check if a token is stored for a specific account
  Future<bool> hasToken(String accountId) async {
    final token = await getToken(accountId);
    return token != null && token.isNotEmpty;
  }

  /// Get all account IDs that have tokens stored
  Future<List<String>> getAccountsWithTokens() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accountIds = <String>[];
      
      // Check secure storage keys (we need to use a different approach)
      // Since FlutterSecureStorage doesn't support listing keys, we'll track
      // account IDs in SharedPreferences instead
      final tokenAccountIdsKey = 'sms_sync_token_account_ids';
      final accountIdsJson = prefs.getString(tokenAccountIdsKey);
      if (accountIdsJson != null) {
        try {
          final List<dynamic> decoded = jsonDecode(accountIdsJson);
          accountIds.addAll(decoded.cast<String>());
        } catch (e) {
          debugPrint('[SmsSync] Error parsing account IDs: $e');
        }
      }
      
      // Filter to only accounts that actually have tokens
      final validAccountIds = <String>[];
      for (final accountId in accountIds) {
        if (await hasToken(accountId)) {
          validAccountIds.add(accountId);
        }
      }
      
      // Update the stored list if it changed
      if (validAccountIds.length != accountIds.length) {
        await _updateTokenAccountIdsList(validAccountIds);
      }
      
      return validAccountIds;
    } catch (e) {
      debugPrint('[SmsSync] Error getting accounts with tokens: $e');
      return [];
    }
  }

  /// Update the list of account IDs with tokens
  Future<void> _updateTokenAccountIdsList(List<String> accountIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tokenAccountIdsKey = 'sms_sync_token_account_ids';
      if (accountIds.isEmpty) {
        await prefs.remove(tokenAccountIdsKey);
      } else {
        await prefs.setString(tokenAccountIdsKey, jsonEncode(accountIds));
      }
    } catch (e) {
      debugPrint('[SmsSync] Error updating token account IDs list: $e');
    }
  }

  /// Store the last-known Pushbullet device id (phone) for SMS sending for a specific account
  Future<void> setDeviceId(String accountId, String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefsKeyDeviceIdPrefix$accountId';
    await prefs.setString(key, deviceId);
    debugPrint('[SmsSync] Device id stored ($deviceId) for account $accountId');
  }

  /// Get the stored Pushbullet device id for a specific account
  Future<String?> getDeviceId(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefsKeyDeviceIdPrefix$accountId';
    return prefs.getString(key);
  }

  /// Clear the stored Pushbullet device id for a specific account
  Future<void> clearDeviceId(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefsKeyDeviceIdPrefix$accountId';
    await prefs.remove(key);
    debugPrint('[SmsSync] Device id cleared for account $accountId');
  }

}

