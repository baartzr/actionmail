import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:domail/services/sms/sms_sync_service.dart';
import 'package:domail/services/sms/sms_sync_manager.dart';
import 'package:domail/services/auth/google_auth_service.dart';

/// Widget for SMS sync settings
/// Allows users to enable/disable SMS sync and configure Pushbullet access tokens per account
class SmsSyncSettingsWidget extends StatefulWidget {
  const SmsSyncSettingsWidget({super.key});

  @override
  State<SmsSyncSettingsWidget> createState() => _SmsSyncSettingsWidgetState();
}

class _SmsSyncSettingsWidgetState extends State<SmsSyncSettingsWidget> {
  final SmsSyncService _smsSyncService = SmsSyncService();
  final GoogleAuthService _authService = GoogleAuthService();
  final TextEditingController _tokenController = TextEditingController();
  bool _isLoading = false;
  bool _isTokenVisible = false;
  bool? _syncEnabled;
  List<GoogleAccount> _accounts = [];
  String? _selectedAccountId;
  bool _hasToken = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    setState(() => _isLoading = true);
    try {
      final loadAccountsFuture = _authService.loadAccounts();
      final enabled = await _smsSyncService.isSyncEnabled();
      final accounts = await loadAccountsFuture;
      
      // Select first account if available
      String? selectedId;
      bool hasToken = false;
      if (accounts.isNotEmpty) {
        selectedId = accounts.first.id;
        final token = await _smsSyncService.getToken(selectedId);
        _tokenController.text = token ?? '';
        hasToken = token != null && token.isNotEmpty;
      }
      
      setState(() {
        _accounts = accounts;
        _selectedAccountId = selectedId;
        _hasToken = hasToken;
        _syncEnabled = enabled;
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
    setState(() => _isLoading = true);
    try {
      await _smsSyncService.setSyncEnabled(value);
      
      // Start or stop SMS sync manager
      final smsManager = SmsSyncManager();
      if (value) {
        await smsManager.start();
      } else {
        await smsManager.stop();
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

  Future<void> _onAccountSelected(String? accountId) async {
    if (accountId == null) {
      setState(() {
        _selectedAccountId = null;
        _hasToken = false;
        _tokenController.clear();
      });
      return;
    }

    // Load token for the selected account
    final token = await _smsSyncService.getToken(accountId);
    final hasToken = token != null && token.isNotEmpty;
    
    setState(() {
      _selectedAccountId = accountId;
      _hasToken = hasToken;
      _tokenController.text = token ?? '';
    });
  }

  Future<void> _saveToken() async {
    if (_selectedAccountId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select an account first'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid access token'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _smsSyncService.setToken(_selectedAccountId!, token);
      
      // If sync is enabled, start sync for this account
      if (_syncEnabled == true) {
        final smsManager = SmsSyncManager();
        await smsManager.startForAccount(_selectedAccountId!);
      }
      
      setState(() {
        _isLoading = false;
        _hasToken = true;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Access token saved securely'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving token: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _clearToken() async {
    if (_selectedAccountId == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Access Token'),
        content: const Text('Are you sure you want to clear the stored access token for this account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await _smsSyncService.clearToken(_selectedAccountId!);
        
        // Stop sync for this account
        final smsManager = SmsSyncManager();
        await smsManager.stopForAccount(_selectedAccountId!);
        
        _tokenController.clear();
        setState(() {
          _isLoading = false;
          _hasToken = false;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Access token cleared'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error clearing token: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
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
                        'Sync SMS messages from your phone via Pushbullet',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isEnabled,
                  onChanged: _isLoading ? null : _onSyncToggleChanged,
                ),
              ],
            ),
            
            // Account token configuration (shown when enabled)
            if (isEnabled) ...[
              const SizedBox(height: 16),
              Divider(color: theme.colorScheme.outlineVariant),
              const SizedBox(height: 12),
              Text(
                'Pushbullet Access Token',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Get your access token from pushbullet.com/account → Access Tokens',
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
                    'Add an email account first to link Pushbullet SMS sync.',
                    style: theme.textTheme.bodySmall,
                  ),
                )
              else ...[
                Text(
                  'Select Account',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
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
                    await _onAccountSelected(accountId);
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
                if (_selectedAccountId != null) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tokenController,
                    obscureText: !_isTokenVisible,
                    enabled: !_isLoading,
                    decoration: InputDecoration(
                      hintText: 'Enter your Pushbullet access token',
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              _isTokenVisible ? Icons.visibility_off : Icons.visibility,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() => _isTokenVisible = !_isTokenVisible);
                            },
                            tooltip: _isTokenVisible ? 'Hide token' : 'Show token',
                          ),
                          if (_hasToken)
                            IconButton(
                              icon: const Icon(Icons.copy, size: 20),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _tokenController.text));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Token copied to clipboard'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                              tooltip: 'Copy token',
                            ),
                        ],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _isLoading ? null : _saveToken,
                        icon: const Icon(Icons.save, size: 18),
                        label: const Text('Save Token', style: TextStyle(fontSize: 14)),
                      ),
                      const SizedBox(width: 8),
                      if (_hasToken)
                        OutlinedButton.icon(
                          onPressed: _isLoading ? null : _clearToken,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Clear', style: TextStyle(fontSize: 14)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }
}
