import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domail/services/auth/google_auth_service.dart';
import 'package:domail/shared/widgets/app_window_dialog.dart';
import 'package:domail/data/repositories/message_repository.dart';
import 'package:domail/features/home/domain/providers/email_list_provider.dart';
import 'package:domail/services/sync/firebase_sync_service.dart';
import 'package:domail/services/pdf_viewer_preference_service.dart';
import 'package:domail/data/repositories/action_feedback_repository.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';
import 'package:domail/constants/app_brand.dart';
import 'package:domail/features/home/domain/providers/view_mode_provider.dart';
import 'package:domail/app/theme/actionmail_theme.dart';
// import 'package:shared_preferences/shared_preferences.dart'; // unused

class AccountsSettingsDialog extends ConsumerStatefulWidget {
  const AccountsSettingsDialog({super.key});

  @override
  ConsumerState<AccountsSettingsDialog> createState() => _AccountsSettingsDialogState();
}

class _AccountsSettingsDialogState extends ConsumerState<AccountsSettingsDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    final maxWidth = isDesktop ? 600.0 : double.infinity;
/*
    return AppWindowDialog(
      title: 'Settings',
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SingleChildScrollView(
            child: Padding(
              padding: isDesktop
                  ? const EdgeInsets.symmetric(horizontal: 24, vertical: 16)
                  : const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 0,
                    color: Colors.transparent, // <- transparent background
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
                            AppBrand.productName,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          FutureBuilder<PackageInfo>(
                            future: PackageInfo.fromPlatform(),
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                final packageInfo = snapshot.data!;
                                return Column(
                                  children: [
                                    Text(
                                      'Version ${packageInfo.version}',
                                      style: theme.textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w500,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Build ${packageInfo.buildNumber}',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                );
                              } else {
                                return Text(
                                  'Loading version...',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Sync section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                    child: Text(
                      'Preferences',
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
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                    child: Text(
                      'Action Statistics (debug)',
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
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
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
          ),
        ),
      ),
    );
*/
    return AppWindowDialog(
      title: 'Settings',
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            thickness: 12.0,
            radius: const Radius.circular(6.0),
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Padding(
                padding: isDesktop
                    ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                    : const EdgeInsets.all(12),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App info card
                  Card(
                    elevation: 0,
                    color: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  theme.colorScheme.primary,
                                  theme.colorScheme.primary.withValues(alpha: 0.7),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.email_outlined,
                              size: 36,
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            AppBrand.productName,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          FutureBuilder<PackageInfo>(
                            future: PackageInfo.fromPlatform(),
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                final packageInfo = snapshot.data!;
                                return Column(
                                  children: [
                                    Text(
                                      'Version ${packageInfo.version}',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w500,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Build ${packageInfo.buildNumber}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                );
                              } else {
                                return Text(
                                  'Loading version...',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Preferences section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
                    child: Text(
                      'Preferences',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
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
                                const SizedBox(height: 2),
                                Text(
                                  'Sync email metadata across devices (personal/business tags, actions)',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
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
                                      if (value) {
                                        final accounts = await GoogleAuthService().loadAccounts();
                                        if (accounts.isNotEmpty) {
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
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PDF Viewer',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Use internal PDF viewer instead of system file opener',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Consumer(
                            builder: (context, ref, child) {
                              return FutureBuilder<bool>(
                                future: PdfViewerPreferenceService().useInternalViewer(),
                                builder: (context, snapshot) {
                                  final useInternal = snapshot.data ?? false;
                                  return Switch(
                                    value: useInternal,
                                    onChanged: (value) async {
                                      final messenger = ScaffoldMessenger.of(context);
                                      final prefService = PdfViewerPreferenceService();
                                      await prefService.setUseInternalViewer(value);
                                      if (!context.mounted) return;
                                      setState(() {});
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(value 
                                            ? 'PDFs will open in internal viewer' 
                                            : 'PDFs will open with system file opener'),
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
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Default View',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Choose your default email list view (desktop only)',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Consumer(
                            builder: (context, ref, child) {
                              return FutureBuilder<ViewMode>(
                                future: ref.read(viewModeProvider.notifier).getDefaultView(),
                                builder: (context, snapshot) {
                                  final defaultView = snapshot.data ?? ViewMode.tile;
                                  return SegmentedButton<ViewMode>(
                                    segments: const [
                                      ButtonSegment<ViewMode>(
                                        value: ViewMode.tile,
                                        label: Text('Tile'),
                                        icon: Icon(Icons.view_module, size: 16),
                                      ),
                                      ButtonSegment<ViewMode>(
                                        value: ViewMode.table,
                                        label: Text('Table'),
                                        icon: Icon(Icons.table_chart, size: 16),
                                      ),
                                    ],
                                    selected: {defaultView},
                                    onSelectionChanged: (Set<ViewMode> newSelection) async {
                                      if (newSelection.isEmpty) return;
                                      final newMode = newSelection.first;
                                      await ref.read(viewModeProvider.notifier).setDefaultView(newMode);
                                      // Also update current view if it matches the old default
                                      final currentView = ref.read(viewModeProvider);
                                      if (currentView == (newMode == ViewMode.table ? ViewMode.tile : ViewMode.table)) {
                                        ref.read(viewModeProvider.notifier).setViewMode(newMode);
                                      }
                                      if (!context.mounted) return;
                                      setState(() {});
                                      final messenger = ScaffoldMessenger.of(context);
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(newMode == ViewMode.table
                                            ? 'Default view set to Table View' 
                                            : 'Default view set to Tile View'),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    style: SegmentedButton.styleFrom(
                                      selectedBackgroundColor: ActionMailTheme.alertColor.withValues(alpha: 0.2),
                                      selectedForegroundColor: ActionMailTheme.alertColor,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Action Statistics (debug)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
                    child: Text(
                      'Action Statistics (debug)',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Feedback Collection Statistics',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Phase 1: Collecting feedback when you edit actions',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 8),
                          FutureBuilder<int>(
                            future: ActionFeedbackRepository().getFeedbackCount(),
                            builder: (context, snapshot) {
                              final count = snapshot.data ?? 0;
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Total feedback entries:',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  Text(
                                    '$count',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 8),
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
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Refresh Count', style: TextStyle(fontSize: 14)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Database section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
                    child: Text(
                      'Database',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Clear Database',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'This will permanently delete all emails from the local database. This action cannot be undone.',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            icon: const Icon(Icons.delete_forever, size: 18),
                            label: const Text('Delete Database', style: TextStyle(fontSize: 14)),
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
          ),
        ),
      ),
      ),
    );


  }
}

