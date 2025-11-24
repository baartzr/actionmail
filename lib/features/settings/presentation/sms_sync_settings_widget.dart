import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:domail/services/sms/sms_sync_service.dart';
import 'package:domail/services/sms/sms_sync_manager.dart';

/// Widget for SMS sync settings
/// Allows users to enable/disable SMS sync and enter their Pushbullet access token
class SmsSyncSettingsWidget extends StatefulWidget {
  const SmsSyncSettingsWidget({super.key});

  @override
  State<SmsSyncSettingsWidget> createState() => _SmsSyncSettingsWidgetState();
}

class _SmsSyncSettingsWidgetState extends State<SmsSyncSettingsWidget> {
  final SmsSyncService _smsSyncService = SmsSyncService();
  final TextEditingController _tokenController = TextEditingController();
  bool _isLoading = false;
  bool _isTokenVisible = false;
  bool? _syncEnabled;
  bool? _hasToken;

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
      final enabled = await _smsSyncService.isSyncEnabled();
      final hasToken = await _smsSyncService.hasToken();
      final token = await _smsSyncService.getToken();
      
      setState(() {
        _syncEnabled = enabled;
        _hasToken = hasToken;
        if (token != null) {
          _tokenController.text = token;
        }
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

  Future<void> _saveToken() async {
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
      await _smsSyncService.setToken(token);
      
      // If sync is enabled, restart the sync manager with new token
      if (_syncEnabled == true) {
        final smsManager = SmsSyncManager();
        await smsManager.stop();
        await smsManager.start();
      }
      
      setState(() {
        _hasToken = true;
        _isLoading = false;
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Access Token'),
        content: const Text('Are you sure you want to clear the stored access token?'),
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
        await _smsSyncService.clearToken();
        _tokenController.clear();
        setState(() {
          _hasToken = false;
          _isLoading = false;
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
            
            // Token input section (shown when enabled)
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
              const SizedBox(height: 8),
              Text(
                'Get your access token from pushbullet.com/account → Access Tokens',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
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
                      if (_hasToken == true)
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
                  if (_hasToken == true)
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
        ),
      ),
    );
  }
}

