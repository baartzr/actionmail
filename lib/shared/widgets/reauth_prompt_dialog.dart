import 'package:flutter/material.dart';
import 'package:domail/shared/widgets/app_window_dialog.dart';

/// Dialog to prompt user to re-authenticate an account
class ReauthPromptDialog extends StatelessWidget {
  final String accountId;
  final String accountEmail;

  const ReauthPromptDialog({
    super.key,
    required this.accountId,
    required this.accountEmail,
  });

  static Future<bool> show({
    required BuildContext context,
    required String accountId,
    required String accountEmail,
  }) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => ReauthPromptDialog(
        accountId: accountId,
        accountEmail: accountEmail,
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
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

