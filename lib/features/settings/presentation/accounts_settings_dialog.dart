import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:actionmail/services/auth/google_auth_service.dart';
import 'package:actionmail/shared/widgets/app_button.dart';
import 'package:actionmail/shared/widgets/app_window_dialog.dart';
import 'package:actionmail/data/repositories/message_repository.dart';
import 'package:actionmail/features/home/domain/providers/email_list_provider.dart';

class AccountsSettingsDialog extends ConsumerStatefulWidget {
  const AccountsSettingsDialog({super.key});

  @override
  ConsumerState<AccountsSettingsDialog> createState() => _AccountsSettingsDialogState();
}

class _AccountsSettingsDialogState extends ConsumerState<AccountsSettingsDialog> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppWindowDialog(
      title: 'Settings',
      child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // About section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      'About',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ActionMail', style: theme.textTheme.titleLarge),
                          const SizedBox(height: 4),
                          Text('Version 0.1.0', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 12),
                          Text(
                            'A focused email client for fast actions and a clean workflow.\n\n'
                            '• Material 3 UI\n'
                            '• Inline swipe actions (Archive/Trash/Restore)\n'
                            '• Smart action labels and reminders\n'
                            '• 2‑minute background sync with Gmail',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Database section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      'Database',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Clear Database',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'This will permanently delete all emails from the local database. This action cannot be undone.',
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Clear Database'),
                                  content: const Text(
                                    'Are you sure you want to clear all emails from the database? This action cannot be undone.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(ctx).pop(false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.of(ctx).pop(true),
                                      child: const Text('Clear'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true && mounted) {
                                await MessageRepository().clearAll();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Database cleared')),
                                  );
                                  // Refresh email list if there's an active account
                                  final accounts = await GoogleAuthService().loadAccounts();
                                  if (accounts.isNotEmpty) {
                                    ref.read(emailListProvider.notifier).refresh(accounts.first.id);
                                  }
                                }
                              }
                            },
                            icon: const Icon(Icons.delete_sweep),
                            label: const Text('Clear Database'),
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.colorScheme.error,
                              foregroundColor: theme.colorScheme.onError,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _AddAccountInlineDialog extends StatefulWidget {
  const _AddAccountInlineDialog();

  @override
  State<_AddAccountInlineDialog> createState() => _AddAccountInlineDialogState();
}

class _AddAccountInlineDialogState extends State<_AddAccountInlineDialog> {
  bool _signingIn = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Add account')),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _signingIn
                    ? null
                    : () async {
                        setState(() => _signingIn = true);
                        final svc = GoogleAuthService();
                        final acc = await svc.signIn();
                        if (acc != null) {
                          final existing = await svc.loadAccounts();
                          await svc.saveAccounts([...existing, acc]);
                          if (!mounted) return;
                          Navigator.of(context).pop(acc.id);
                        } else {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Google sign-in not supported on this platform.')),
                          );
                          setState(() => _signingIn = false);
                        }
                      },
                icon: const Icon(Icons.login),
                label: Text(_signingIn ? 'Signing in…' : 'Sign in with Google'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


