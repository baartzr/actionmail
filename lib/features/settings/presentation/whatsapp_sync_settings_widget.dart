import 'package:flutter/material.dart';
import 'package:domail/services/whatsapp/whatsapp_sync_service.dart';
import 'package:domail/services/whatsapp/whatsapp_sync_manager.dart';
import 'package:domail/services/auth/google_auth_service.dart';

/// Widget for WhatsApp sync settings
/// Allows users to enable/disable WhatsApp sync and enter their WhatsApp Business API credentials
class WhatsAppSyncSettingsWidget extends StatefulWidget {
  const WhatsAppSyncSettingsWidget({super.key});

  @override
  State<WhatsAppSyncSettingsWidget> createState() => _WhatsAppSyncSettingsWidgetState();
}

class _WhatsAppSyncSettingsWidgetState extends State<WhatsAppSyncSettingsWidget> {
  final WhatsAppSyncService _whatsAppSyncService = WhatsAppSyncService();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _phoneNumberIdController = TextEditingController();
  final TextEditingController _phoneNumberController = TextEditingController();
  bool _loading = true;
  bool _syncEnabled = false;
  bool _hasToken = false;
  String? _accountId;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _phoneNumberIdController.dispose();
    _phoneNumberController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      setState(() => _loading = true);
      
      final enabled = await _whatsAppSyncService.isSyncEnabled();
      final hasToken = await _whatsAppSyncService.hasToken();
      final token = await _whatsAppSyncService.getToken();
      final phoneNumberId = await _whatsAppSyncService.getPhoneNumberId();
      final phoneNumber = await _whatsAppSyncService.getPhoneNumber();
      final accountId = await _whatsAppSyncService.getAccountId();
      
      setState(() {
        _syncEnabled = enabled;
        _hasToken = hasToken;
        _tokenController.text = token ?? '';
        _phoneNumberIdController.text = phoneNumberId ?? '';
        _phoneNumberController.text = phoneNumber ?? '';
        _accountId = accountId;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading WhatsApp sync settings: $e')),
        );
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _toggleSync(bool value) async {
    try {
      await _whatsAppSyncService.setSyncEnabled(value);
      setState(() => _syncEnabled = value);
      
      // Start or stop WhatsApp sync manager
      final whatsappManager = WhatsAppSyncManager();
      if (value) {
        await whatsappManager.start();
      } else {
        await whatsappManager.stop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating sync setting: $e')),
        );
      }
    }
  }

  Future<void> _saveCredentials() async {
    try {
      final token = _tokenController.text.trim();
      final phoneNumberId = _phoneNumberIdController.text.trim();
      final phoneNumber = _phoneNumberController.text.trim();

      if (token.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Access token is required')),
          );
        }
        return;
      }

      if (phoneNumberId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Phone number ID is required')),
          );
        }
        return;
      }

      // Get the first Google account to associate with WhatsApp sync
      final accounts = await GoogleAuthService().loadAccounts();
      if (accounts.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please add a Google account first')),
          );
        }
        return;
      }

      final accountId = accounts.first.id;
      
      await _whatsAppSyncService.setToken(token);
      await _whatsAppSyncService.setPhoneNumberId(phoneNumberId);
      if (phoneNumber.isNotEmpty) {
        await _whatsAppSyncService.setPhoneNumber(phoneNumber);
      }
      await _whatsAppSyncService.setAccountId(accountId);
      
      setState(() {
        _hasToken = true;
        _accountId = accountId;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp credentials saved')),
        );
      }

      // Restart sync manager if enabled
      if (_syncEnabled) {
        final whatsappManager = WhatsAppSyncManager();
        await whatsappManager.stop();
        await whatsappManager.start();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving credentials: $e')),
        );
      }
    }
  }

  Future<void> _clearCredentials() async {
    try {
      await _whatsAppSyncService.clearToken();
      await _whatsAppSyncService.clearAccountId();
      _tokenController.clear();
      _phoneNumberIdController.clear();
      _phoneNumberController.clear();
      
      setState(() {
        _hasToken = false;
        _accountId = null;
        _syncEnabled = false;
      });

      // Stop sync manager
      final whatsappManager = WhatsAppSyncManager();
      await whatsappManager.stop();
      await _whatsAppSyncService.setSyncEnabled(false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp credentials cleared')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing credentials: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WhatsApp Sync',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Receive and send WhatsApp messages via WhatsApp Business API',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _syncEnabled,
                  onChanged: _hasToken ? _toggleSync : null,
                ),
              ],
            ),
            if (!_hasToken) ...[
              const SizedBox(height: 16),
              Text(
                'To enable WhatsApp sync, you need:',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                '• WhatsApp Business API access token\n'
                '• Phone number ID (from Meta Business)\n'
                '• Your WhatsApp phone number (optional)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: 'Access Token',
                hintText: 'Enter WhatsApp Business API access token',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              enabled: !_hasToken || _tokenController.text.isNotEmpty,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneNumberIdController,
              decoration: const InputDecoration(
                labelText: 'Phone Number ID',
                hintText: 'Enter your WhatsApp Business phone number ID',
                border: OutlineInputBorder(),
              ),
              enabled: !_hasToken || _phoneNumberIdController.text.isNotEmpty,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneNumberController,
              decoration: const InputDecoration(
                labelText: 'Your WhatsApp Number (Optional)',
                hintText: 'e.g., +1234567890',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_hasToken)
                  TextButton(
                    onPressed: _clearCredentials,
                    child: const Text('Clear'),
                  ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saveCredentials,
                  child: const Text('Save Credentials'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

