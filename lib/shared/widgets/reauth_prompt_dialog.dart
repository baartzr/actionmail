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

  static Future<String?> show({
    required BuildContext context,
    required String accountId,
    required String accountEmail,
    bool isConnectionError = false,
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
    return AppWindowDialog(
      title: isConnectionError ? 'Connection Problem' : 'Re-authentication Required',
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isConnectionError
                  ? "There's a problem connecting to Gmail."
                  : 'Your Google account session has expired.',
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
            isConnectionError
                ? RichText(
                    text: TextSpan(
                      style: theme.textTheme.bodyMedium,
                      children: [
                        const TextSpan(
                          text: 'This could be a problem with your internet connection or Gmail service. Please try again and if the problem persists, please ',
                        ),
                        WidgetSpan(
                          child: InkWell(
                            onTap: () => Navigator.of(context).pop(true),
                            child: Text(
                              'reconnect',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  )
                : Text(
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
                if (isConnectionError) ...[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop('retry'),
                    child: const Text('Retry'),
                  ),
                  const SizedBox(width: 8),
                ],
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(isConnectionError ? 'reconnect' : 'reauth'),
                  child: Text(isConnectionError ? 'Reconnect' : 'Re-authenticate'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

