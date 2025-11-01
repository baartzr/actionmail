import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:actionmail/services/auth/google_auth_service.dart';
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
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // App icon/logo
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  theme.colorScheme.primary,
                                  theme.colorScheme.primary.withValues(alpha: 0.7),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(
                              Icons.email_outlined,
                              size: 48,
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'ActionMail',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Version 0.1.0',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'A focused email client for fast actions and a clean workflow.',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _FeatureItem(icon: Icons.label_important_outline, text: 'Material 3 UI'),
                                _FeatureItem(icon: Icons.swipe, text: 'Inline swipe actions (Archive/Trash/Restore)'),
                                _FeatureItem(icon: Icons.schedule, text: 'Smart action labels and reminders'),
                                _FeatureItem(icon: Icons.sync, text: '2‑minute background sync with Gmail'),
                              ],
                            ),
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
                              final scaffoldMessenger = ScaffoldMessenger.of(context);
                              final emailListRef = ref;
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
                                if (!mounted) return;
                                scaffoldMessenger.showSnackBar(
                                  const SnackBar(content: Text('Database cleared')),
                                );
                                // Refresh email list if there's an active account
                                final accounts = await GoogleAuthService().loadAccounts();
                                if (!mounted) return;
                                if (accounts.isNotEmpty) {
                                  emailListRef.read(emailListProvider.notifier).refresh(accounts.first.id);
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

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FeatureItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
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
                        final navigator = Navigator.of(context);
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        final svc = GoogleAuthService();
                        final acc = await svc.signIn();
                        if (acc != null) {
                          final existing = await svc.loadAccounts();
                          await svc.saveAccounts([...existing, acc]);
                          if (!mounted) return;
                          navigator.pop(acc.id);
                        } else {
                          if (!mounted) return;
                          scaffoldMessenger.showSnackBar(
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


