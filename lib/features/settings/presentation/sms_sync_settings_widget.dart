import 'package:flutter/material.dart';
import 'package:domail/services/sms/sms_sync_service.dart';
import 'package:domail/services/sms/sms_sync_manager.dart';
import 'package:domail/services/sms/companion_sms_service.dart';
import 'package:domail/services/auth/google_auth_service.dart';
import 'dart:io';

/// Widget for SMS sync settings
/// Allows users to enable/disable SMS sync via the Companion app
class SmsSyncSettingsWidget extends StatefulWidget {
  const SmsSyncSettingsWidget({super.key});

  @override
  State<SmsSyncSettingsWidget> createState() => _SmsSyncSettingsWidgetState();
}

class _SmsSyncSettingsWidgetState extends State<SmsSyncSettingsWidget> {
  final SmsSyncService _smsSyncService = SmsSyncService();
  final CompanionSmsService _companionService = CompanionSmsService();
  final GoogleAuthService _authService = GoogleAuthService();
  bool _isLoading = false;
  bool? _syncEnabled;
  bool? _companionAppAvailable;
  List<GoogleAccount> _accounts = [];
  String? _selectedAccountId;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadState() async {
    setState(() => _isLoading = true);
    try {
      final enabled = await _smsSyncService.isSyncEnabled();
      final available = Platform.isAndroid 
          ? await _companionService.isCompanionAppAvailable()
          : false;
      final accounts = await _authService.loadAccounts();
      final selectedAccountId = await _smsSyncService.getSelectedAccountId();
      
      // If no account is selected but sync is enabled, select the first account
      String? accountId = selectedAccountId;
      if (accountId == null && accounts.isNotEmpty && enabled) {
        accountId = accounts.first.id;
        await _smsSyncService.setSelectedAccountId(accountId);
      }
      
      setState(() {
        _syncEnabled = enabled;
        _companionAppAvailable = available;
        _accounts = accounts;
        _selectedAccountId = accountId;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading SMS sync settings: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _onSyncToggleChanged(bool value) async {
    if (!Platform.isAndroid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SMS sync is only available on Android'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Check if companion app is available
    final available = await _companionService.isCompanionAppAvailable();
    if (value && !available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SMS Companion app is not installed or not accessible. Please install the SMS Companion app first.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _smsSyncService.setSyncEnabled(value);
      
      // Start or stop SMS sync manager
      final smsManager = SmsSyncManager();
      if (value) {
        // Use selected account or first available
        final accountId = _selectedAccountId ?? 
            (_accounts.isNotEmpty ? _accounts.first.id : null);
        if (accountId != null) {
          await _smsSyncService.setSelectedAccountId(accountId);
          smsManager.startCompanionSync(accountId);
        }
      } else {
        smsManager.stopCompanionSync();
      }
      
      setState(() {
        _syncEnabled = value;
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value ? 'SMS sync enabled' : 'SMS sync disabled'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating sync setting: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    if (_isLoading && _syncEnabled == null) {
      return Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      );
    }

    final isEnabled = _syncEnabled ?? false;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with switch
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SMS Sync',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        Platform.isAndroid
                            ? 'Sync SMS messages from your phone via SMS Companion app'
                            : 'SMS sync is only available on Android',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isEnabled,
                  onChanged: _isLoading || !Platform.isAndroid ? null : _onSyncToggleChanged,
                ),
              ],
            ),
            
            // Account selection (shown when enabled)
            if (isEnabled && Platform.isAndroid) ...[
              const SizedBox(height: 16),
              Divider(color: theme.colorScheme.outlineVariant),
              const SizedBox(height: 12),
              Text(
                'Gmail Account',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Select which Gmail account SMS messages should be associated with',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (_accounts.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: theme.colorScheme.surface,
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Text(
                    'Add a Gmail account first to enable SMS sync.',
                    style: theme.textTheme.bodySmall,
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _selectedAccountId,
                  hint: const Text('Select account'),
                  items: _accounts
                      .map(
                        (acc) => DropdownMenuItem(
                          value: acc.id,
                          child: Text(
                            '${acc.displayName} • ${acc.email}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  selectedItemBuilder: (ctx) => _accounts
                      .map(
                        (acc) => Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${acc.displayName} • ${acc.email}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  isExpanded: true,
                  onChanged: _isLoading ? null : (accountId) async {
                    if (accountId == null) return;
                    final messenger = ScaffoldMessenger.of(context);
                    final theme = Theme.of(context);
                    setState(() => _isLoading = true);
                    try {
                      await _smsSyncService.setSelectedAccountId(accountId);
                      final smsManager = SmsSyncManager();
                      smsManager.stopCompanionSync();
                      smsManager.startCompanionSync(accountId);
                      setState(() {
                        _selectedAccountId = accountId;
                        _isLoading = false;
                      });
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('SMS sync account updated'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    } catch (e) {
                      setState(() => _isLoading = false);
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Error updating account: $e'),
                          backgroundColor: theme.colorScheme.error,
                        ),
                      );
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Select account',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                  ),
                ),
            ],
            
            // Status information
            if (Platform.isAndroid) ...[
              const SizedBox(height: 12),
              if (_companionAppAvailable == false)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: theme.colorScheme.errorContainer,
                    border: Border.all(color: theme.colorScheme.error),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 20,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'SMS Companion app is not installed or not accessible. Please install the SMS Companion app first.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (_companionAppAvailable == true)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: theme.colorScheme.primaryContainer,
                    border: Border.all(color: theme.colorScheme.primary),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 20,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'SMS Companion app is installed and ready',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
