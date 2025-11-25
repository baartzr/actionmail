import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domail/constants/app_constants.dart';
import 'package:domail/features/home/presentation/widgets/compose_email_dialog.dart';
import 'package:domail/features/settings/presentation/accounts_settings_dialog.dart';
import 'package:domail/features/home/presentation/windows/actions_summary_window.dart';
import 'package:domail/features/home/presentation/windows/attachments_window.dart';
import 'package:domail/features/home/presentation/windows/subscriptions_window.dart';
import 'package:domail/features/home/presentation/windows/shopping_window.dart';
import 'package:domail/services/auth/google_auth_service.dart';
import 'package:domail/features/home/domain/providers/email_list_provider.dart';

/// Menu button widget for the home screen AppBar
class HomeMenuButton extends ConsumerWidget {
  final String? selectedAccountId;
  final String selectedFolder;
  final List<GoogleAccount> accounts;
  final Future<bool> Function(String accountId, {String? accountEmail}) ensureAccountAuthenticated;
  final Future<void> Function(String accountId, String folderLabel) onRefresh;

  const HomeMenuButton({
    super.key,
    required this.selectedAccountId,
    required this.selectedFolder,
    required this.accounts,
    required this.ensureAccountAuthenticated,
    required this.onRefresh,
  });

  Future<void> _handleMenuSelection(
    BuildContext context,
    String value,
    WidgetRef ref,
  ) async {
    switch (value) {
      case 'Compose':
        if (selectedAccountId != null) {
          showDialog(
            context: context,
            builder: (ctx) => ComposeEmailDialog(
              accountId: selectedAccountId!,
              mode: ComposeEmailMode.newEmail,
            ),
          );
        }
        break;

      case 'Refresh':
        if (selectedAccountId != null) {
          final accountInfo = accounts.firstWhere(
            (acc) => acc.id == selectedAccountId,
            orElse: () => GoogleAccount(
              id: selectedAccountId!,
              email: 'Unknown',
              displayName: '',
              photoUrl: null,
              accessToken: '',
              refreshToken: null,
              tokenExpiryMs: null,
              idToken: '',
            ),
          );
          // Clear any previous error state before refresh
          final auth = GoogleAuthService();
          auth.clearLastError(selectedAccountId!);
          // Clear network error provider state
          ref.read(networkErrorProvider.notifier).state = false;
          
          final authenticated = await ensureAccountAuthenticated(
            selectedAccountId!,
            accountEmail: accountInfo.email,
          );
          if (!authenticated) {
            // Error handling is done by provider listeners:
            // - Network errors -> networkErrorProvider -> handled in HomeProviderListeners
            // - Auth errors -> authFailureProvider -> handled in HomeProviderListeners
            // Just trigger the refresh, which will set the appropriate provider on error
            await onRefresh(selectedAccountId!, selectedFolder);
            break;
          }
          await onRefresh(selectedAccountId!, selectedFolder);
        }
        break;

      case 'Settings':
        showDialog(
          context: context,
          builder: (ctx) => const AccountsSettingsDialog(),
        );
        break;

      case 'Actions':
        showDialog(
          context: context,
          builder: (_) => ActionsSummaryWindow(),
        );
        break;

      case 'Attachments':
        showDialog(
          context: context,
          builder: (_) => const AttachmentsWindow(),
        );
        break;

      case 'Subscriptions':
        if (selectedAccountId != null) {
          showDialog(
            context: context,
            builder: (_) => SubscriptionsWindow(accountId: selectedAccountId!),
          );
        }
        break;

      case 'Shopping':
        showDialog(
          context: context,
          builder: (_) => const ShoppingWindow(),
        );
        break;
    }
  }

  List<PopupMenuEntry<String>> _buildPopupMenuItems(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    List<PopupMenuEntry<String>> items = [
      PopupMenuItem(
        value: 'Compose',
        child: Row(
          children: [
            Icon(Icons.edit_outlined, size: 18, color: cs.onSurface),
            const SizedBox(width: 12),
            Text(
              'Compose',
              style: TextStyle(color: cs.onSurface, fontSize: 13),
            ),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'Refresh',
        child: Row(
          children: [
            Icon(Icons.refresh, size: 18, color: cs.onSurface),
            const SizedBox(width: 12),
            Text(
              'Refresh',
              style: TextStyle(color: cs.onSurface, fontSize: 13),
            ),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'Settings',
        child: Row(
          children: [
            Icon(Icons.settings_outlined, size: 18, color: cs.onSurface),
            const SizedBox(width: 12),
            Text(
              'Settings',
              style: TextStyle(color: cs.onSurface, fontSize: 13),
            ),
          ],
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'Actions',
        child: Row(
          children: [
            Icon(Icons.dashboard_outlined, size: 18, color: cs.onSurface),
            const SizedBox(width: 12),
            Text(
              'Actions',
              style: TextStyle(color: cs.onSurface, fontSize: 13),
            ),
          ],
        ),
      ),
    ];

    // Dynamically add windows except ones handled above
    items.addAll(
      AppConstants.allFunctionWindows
          .where((window) =>
              window != AppConstants.windowActions &&
              window != AppConstants.windowActionsSummary)
          .map((window) {
        IconData icon;

        switch (window) {
          case AppConstants.windowAttachments:
            icon = Icons.attach_file;
            break;
          case AppConstants.windowSubscriptions:
            icon = Icons.subscriptions;
            break;
          case AppConstants.windowShopping:
            icon = Icons.shopping_bag;
            break;
          default:
            icon = Icons.info_outline;
        }

        return PopupMenuItem(
          value: window,
          child: Row(
            children: [
              Icon(icon, size: 18, color: cs.onSurface),
              const SizedBox(width: 12),
              Text(window, style: TextStyle(color: cs.onSurface, fontSize: 13)),
            ],
          ),
        );
      }),
    );

    return items;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.menu,
        size: 18,
        color: Theme.of(context).appBarTheme.foregroundColor,
      ),
      onSelected: (value) => _handleMenuSelection(context, value, ref),
      itemBuilder: (context) => _buildPopupMenuItems(context),
    );
  }
}

