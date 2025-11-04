import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:actionmail/services/auth/google_auth_service.dart';
import 'package:actionmail/shared/widgets/app_window_dialog.dart';
import 'package:actionmail/data/repositories/message_repository.dart';
import 'package:actionmail/features/home/domain/providers/email_list_provider.dart';
import 'package:actionmail/services/sync/firebase_sync_service.dart';
import 'package:actionmail/data/repositories/action_feedback_repository.dart';
// import 'package:shared_preferences/shared_preferences.dart'; // unused

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
                          /* Container(
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
                          ), */
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Sync section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      'Sync',
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Firebase Sync',
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Sync email metadata across devices (personal/business tags, actions)',
                                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              Consumer(
                                builder: (context, ref, child) {
                                  return FutureBuilder<bool>(
                                    future: FirebaseSyncService().isSyncEnabled(),
                                    builder: (context, snapshot) {
                                      final isEnabled = snapshot.data ?? false;
                                      return Switch(
                                        value: isEnabled,
                                        onChanged: (value) async {
                                          final messenger = ScaffoldMessenger.of(context);
                                          final syncService = FirebaseSyncService();
                                          await syncService.setSyncEnabled(value);
                                          
                                          // Initialize user if enabling
                                          if (value) {
                                            final accounts = await GoogleAuthService().loadAccounts();
                                            if (accounts.isNotEmpty) {
                                              // Use account email as user ID
                                              await syncService.initializeUser(accounts.first.email);
                                            }
                                          }
                                          
                                          if (!context.mounted) return;
                                          setState(() {});
                                          messenger.showSnackBar(
                                              SnackBar(
                                                content: Text(value ? 'Firebase sync enabled' : 'Firebase sync disabled'),
                                                duration: const Duration(seconds: 2),
                                              ),
                                            );
                                        },
                                      );
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Action Extraction Debug section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      'Action Extraction (Debug)',
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
                            'Feedback Collection Statistics',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Phase 1: Collecting feedback when you edit actions',
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          FutureBuilder<int>(
                            future: ActionFeedbackRepository().getFeedbackCount(),
                            builder: (context, snapshot) {
                              final count = snapshot.data ?? 0;
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Total feedback entries:',
                                    style: theme.textTheme.bodyLarge,
                                  ),
                                  Text(
                                    '$count',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          TextButton.icon(
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final repo = ActionFeedbackRepository();
                              final count = await repo.getFeedbackCount();
                              if (!context.mounted) return;
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Feedback entries: $count'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh Count'),
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
                            icon: const Icon(Icons.delete_forever),
                            label: const Text('Delete Database'),
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.colorScheme.error,
                              foregroundColor: theme.colorScheme.onError,
                            ),
                            onPressed: () async {
                              final scaffoldMessenger = ScaffoldMessenger.of(context);
                              final emailListRef = ref;
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete Database'),
                                  content: const Text(
                                    'This will completely delete the database file for a fresh start. You will need to re-sync all emails. Continue?',
                                  ),
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
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true && mounted) {
                                await MessageRepository().deleteDatabase();
                                if (!mounted) return;
                                scaffoldMessenger.showSnackBar(
                                  const SnackBar(content: Text('Database file deleted. Restart the app for a fresh start.')),
                                );
                                // Refresh email list if there's an active account
                                final accounts = await GoogleAuthService().loadAccounts();
                                if (!mounted) return;
                                if (accounts.isNotEmpty) {
                                  emailListRef.read(emailListProvider.notifier).refresh(accounts.first.id);
                                }
                              }
                            },
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

