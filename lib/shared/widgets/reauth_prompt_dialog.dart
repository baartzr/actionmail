import 'package:flutter/material.dart';
import 'package:domail/shared/widgets/app_window_dialog.dart';

/// Dialog to prompt user to re-authenticate an account or reconnect
class ReauthPromptDialog extends StatelessWidget {
  final String accountId;
  final String accountEmail;
  final bool isConnectionError;

  const ReauthPromptDialog({
    super.key,
    required this.accountId,
    required this.accountEmail,
    this.isConnectionError = false,
  });

  /// Show re-authentication dialog
  /// Note: isConnectionError parameter is deprecated - network errors are now handled
  /// by the networkErrorProvider system. This parameter is ignored.
  static Future<String?> show({
    required BuildContext context,
    required String accountId,
    required String accountEmail,
    bool isConnectionError = false, // Deprecated - always treated as false
  }) async {
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => ReauthPromptDialog(
        accountId: accountId,
        accountEmail: accountEmail,
        isConnectionError: isConnectionError,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Note: isConnectionError should never be true anymore - network errors are handled
    // by networkErrorProvider system. This parameter is kept for backward compatibility
    // but will always be false in practice.
    return AppWindowDialog(
      title: 'Re-authentication Required',
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Google account session has expired.',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Account: $accountEmail',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Please re-authenticate to continue syncing emails.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop('cancel'),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop('reauth'),
                  child: const Text('Re-authenticate'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

