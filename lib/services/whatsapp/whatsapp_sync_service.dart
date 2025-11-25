import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Service for managing WhatsApp sync via WhatsApp Business API
/// Handles secure storage of access token, phone number ID, and sync state
class WhatsAppSyncService {
  static final WhatsAppSyncService _instance = WhatsAppSyncService._internal();
  factory WhatsAppSyncService() => _instance;
  WhatsAppSyncService._internal();

  static const String _prefsKeySyncEnabled = 'whatsapp_sync_enabled';
  static const String _secureStorageKeyToken = 'whatsapp_access_token';
  static const String _prefsKeyPhoneNumberId = 'whatsapp_phone_number_id';
  static const String _prefsKeyAccountId = 'whatsapp_sync_account_id';
  static const String _prefsKeyPhoneNumber = 'whatsapp_phone_number';
  static const String _prefsKeyWebhookVerifyToken = 'whatsapp_webhook_verify_token';
  
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// Check if WhatsApp sync is enabled
  Future<bool> isSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeySyncEnabled) ?? false;
  }

  /// Enable or disable WhatsApp sync
  Future<void> setSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeySyncEnabled, enabled);
    debugPrint('[WhatsAppSync] Sync ${enabled ? "enabled" : "disabled"}');
  }

  /// Get the stored WhatsApp Business API access token
  Future<String?> getToken() async {
    try {
      return await _secureStorage.read(key: _secureStorageKeyToken);
    } catch (e) {
      debugPrint('[WhatsAppSync] Error reading token: $e');
      return null;
    }
  }

  /// Store the WhatsApp Business API access token securely
  Future<void> setToken(String token) async {
    try {
      await _secureStorage.write(key: _secureStorageKeyToken, value: token);
      debugPrint('[WhatsAppSync] Token stored securely');
    } catch (e) {
      debugPrint('[WhatsAppSync] Error storing token: $e');
      rethrow;
    }
  }

  /// Clear the stored token
  Future<void> clearToken() async {
    try {
      await _secureStorage.delete(key: _secureStorageKeyToken);
      debugPrint('[WhatsAppSync] Token cleared');
    } catch (e) {
      debugPrint('[WhatsAppSync] Error clearing token: $e');
    }
  }

  /// Check if a token is stored
  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Get the WhatsApp Business API phone number ID
  Future<String?> getPhoneNumberId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKeyPhoneNumberId);
  }

  /// Store the WhatsApp Business API phone number ID
  Future<void> setPhoneNumberId(String phoneNumberId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyPhoneNumberId, phoneNumberId);
    debugPrint('[WhatsAppSync] Phone number ID stored ($phoneNumberId)');
  }

  /// Get the user's WhatsApp phone number
  Future<String?> getPhoneNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKeyPhoneNumber);
  }

  /// Store the user's WhatsApp phone number
  Future<void> setPhoneNumber(String phoneNumber) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyPhoneNumber, phoneNumber);
    debugPrint('[WhatsAppSync] Phone number stored ($phoneNumber)');
  }

  /// Get the Gmail account ID that owns the WhatsApp credentials
  Future<String?> getAccountId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKeyAccountId);
  }

  /// Persist the Gmail account ID for WhatsApp sync
  Future<void> setAccountId(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyAccountId, accountId);
    debugPrint('[WhatsAppSync] Account id set to $accountId');
  }

  /// Clear the stored Gmail account ID
  Future<void> clearAccountId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyAccountId);
    debugPrint('[WhatsAppSync] Account id cleared');
  }

  /// Get the webhook verify token
  Future<String?> getWebhookVerifyToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKeyWebhookVerifyToken);
  }

  /// Store the webhook verify token
  Future<void> setWebhookVerifyToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyWebhookVerifyToken, token);
    debugPrint('[WhatsAppSync] Webhook verify token stored');
  }
}

