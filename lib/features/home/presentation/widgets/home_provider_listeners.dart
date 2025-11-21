import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domail/features/home/domain/providers/email_list_provider.dart';
import 'package:domail/features/home/domain/providers/view_mode_provider.dart';
import 'package:domail/data/models/message_index.dart';

/// Widget that handles all provider listeners for HomeScreen
/// Must be placed in the build method where ref.listen can be used
class HomeProviderListeners extends ConsumerWidget {
  final String? selectedAccountId;
  final Set<String> pendingLocalUnreadAccounts;
  final Function(bool, bool) onPanelCollapseChanged;
  final Function(String) onHandleReauthNeeded;
  final Function(String) onRefreshAccountUnreadCountLocal;
  final Widget child;

  const HomeProviderListeners({
    super.key,
    required this.selectedAccountId,
    required this.pendingLocalUnreadAccounts,
    required this.onPanelCollapseChanged,
    required this.onHandleReauthNeeded,
    required this.onRefreshAccountUnreadCountLocal,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listen for network errors - show simple message dialog (only for manual refresh)
    ref.listen<bool>(networkErrorProvider, (previous, next) {
      if (!context.mounted) return;
      if (!next) return;

      // Clear the provider immediately
      ref.read(networkErrorProvider.notifier).state = false;
      // Show simple dialog
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => AlertDialog(
            title: const Text('Network Issue'),
            content: const Text('There\'s a network issue. Please try again later.'),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      });
    });

    // Listen for auth failures during incremental sync
    ref.listen<String?>(authFailureProvider, (previous, next) {
      if (!context.mounted) return;
      if (next == null) return;

      // Only show dialog if this is for the currently selected account
      if (next != selectedAccountId) {
        return;
      }

      // Use post-frame callback to avoid showing dialog during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        onHandleReauthNeeded(next);
      });
    });

    // Listen for view mode changes and adjust panels accordingly
    ref.listen<ViewMode>(viewModeProvider, (previous, next) {
      if (!context.mounted) return;
      // When switching to table view, collapse both panels
      if (next == ViewMode.table && previous != ViewMode.table) {
        onPanelCollapseChanged(true, true);
      }
      // When switching to tile view, expand both panels
      else if (next == ViewMode.tile && previous != ViewMode.tile) {
        onPanelCollapseChanged(false, false);
      }
    });

    // Listen to email list changes and refresh active account's unread count
    ref.listen<AsyncValue<List<MessageIndex>>>(emailListProvider, (previous, next) {
      final activeAccountId = selectedAccountId;
      if (!context.mounted || !next.hasValue || activeAccountId == null) {
        return;
      }
      if (pendingLocalUnreadAccounts.contains(activeAccountId)) {
        return;
      }
      // Refresh active account's unread count from local DB when emails change
      // Use post-frame callback to avoid updating during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        if (selectedAccountId != activeAccountId) return;
        if (pendingLocalUnreadAccounts.contains(activeAccountId)) return;
        onRefreshAccountUnreadCountLocal(activeAccountId);
      });
    });

    // Return the child widget - listeners are set up above
    return child;
  }
}

