import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Service for managing SMS sync via Companion app
/// Handles sync state
class SmsSyncService {
  static final SmsSyncService _instance = SmsSyncService._internal();
  factory SmsSyncService() => _instance;
  SmsSyncService._internal();

  static const String _prefsKeySyncEnabled = 'sms_sync_enabled';
  static const String _prefsKeySelectedAccountId = 'sms_sync_selected_account_id';

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
  }

  /// Get the selected account ID for SMS sync
  Future<String?> getSelectedAccountId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKeySelectedAccountId);
  }

  /// Set the selected account ID for SMS sync
  Future<void> setSelectedAccountId(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeySelectedAccountId, accountId);
    debugPrint('[SmsSync] Selected account ID set: $accountId');
  }

  /// Clear the selected account ID
  Future<void> clearSelectedAccountId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeySelectedAccountId);
    debugPrint('[SmsSync] Selected account ID cleared');
  }


}

