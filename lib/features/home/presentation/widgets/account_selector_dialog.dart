import 'dart:io';
import 'package:flutter/material.dart';
import 'package:actionmail/services/auth/google_auth_service.dart';
import 'package:actionmail/shared/widgets/app_window_dialog.dart';
import 'package:actionmail/features/auth/presentation/splash_screen.dart';

/// Dialog for selecting an account
class AccountSelectorDialog extends StatefulWidget {
  final List<GoogleAccount> accounts;
  final String? selectedAccountId;

  const AccountSelectorDialog({
    super.key,
    required this.accounts,
    this.selectedAccountId,
  });

  @override
  State<AccountSelectorDialog> createState() => _AccountSelectorDialogState();
}

class _AccountSelectorDialogState extends State<AccountSelectorDialog> {
  late List<GoogleAccount> _accounts;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _accounts = List.from(widget.accounts);
  }

  Future<void> _handleSignOut(String accountId) async {
    setState(() => _loading = true);
    final svc = GoogleAuthService();
    final success = await svc.signOutAccount(accountId);
    if (!mounted) return;
    setState(() => _loading = false);
    if (success) {
      final updated = await svc.loadAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = updated;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signed out successfully')),
      );
      // If signed out account was selected, auto-select next account
      if (accountId == widget.selectedAccountId && _accounts.isNotEmpty) {
        if (!mounted) return;
        Navigator.of(context).pop(_accounts.first.id);
      }
    }
  }

  Future<void> _handleRemove(String accountId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Account'),
        content: const Text('Are you sure you want to remove this account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _loading = true);
    final svc = GoogleAuthService();
    final success = await svc.removeAccount(accountId);
    if (!mounted) return;
    setState(() => _loading = false);
    if (success) {
      final updated = await svc.loadAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = updated;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account removed')),
      );
      // If removed account was selected, auto-select next account
      if (accountId == widget.selectedAccountId) {
        if (!mounted) return;
        if (_accounts.isNotEmpty) {
          Navigator.of(context).pop(_accounts.first.id);
        } else {
          Navigator.of(context).pop(null);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    return LayoutBuilder(
      builder: (context, constraints) {
        return AppWindowDialog(
          title: 'Select Account',
          size: isMobile ? AppWindowSize.large : AppWindowSize.small,
          height: isMobile ? null : MediaQuery.of(context).size.height * 0.8,
          bodyPadding: EdgeInsets.zero,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(12.0),
                        children: _accounts.map((account) {
                          final isSelected = account.id == widget.selectedAccountId;
                          final theme = Theme.of(context);
                          final cs = theme.colorScheme;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2.0),
                            child: Card(
                              elevation: 1,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: isSelected
                                    ? BorderSide(color: cs.primary, width: 2)
                                    : BorderSide.none,
                              ),
                              child: Stack(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Row 1: Email (with tick) + Name below (clickable to switch account)
                                        InkWell(
                                          onTap: () {
                                            Navigator.of(context).pop(account.id);
                                          },
                                          borderRadius: BorderRadius.circular(4),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 2),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        account.email,
                                                        style: theme.textTheme.bodyMedium?.copyWith(
                                                          fontWeight: FontWeight.w500,
                                                          fontSize: 14,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                      if (account.displayName.isNotEmpty) ...[
                                                        const SizedBox(height: 1),
                                                        Text(
                                                          account.displayName,
                                                          style: theme.textTheme.bodySmall?.copyWith(
                                                            color: cs.onSurfaceVariant,
                                                            fontSize: 11,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                                if (isSelected) ...[
                                                  const SizedBox(width: 6),
                                                  Icon(
                                                    Icons.check,
                                                    size: 18,
                                                    color: cs.primary.withValues(alpha: 0.7),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                        // Row 2: SignOut icon + text + Remove icon + text
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            InkWell(
                                              onTap: () => _handleSignOut(account.id),
                                              borderRadius: BorderRadius.circular(4),
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.logout,
                                                      size: 16,
                                                      color: cs.onSurfaceVariant,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'SignOut',
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        color: cs.onSurfaceVariant,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            InkWell(
                                              onTap: () => _handleRemove(account.id),
                                              borderRadius: BorderRadius.circular(4),
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.delete_outline,
                                                      size: 16,
                                                      color: cs.error,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Remove',
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        color: cs.error,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Switch icon button in top right corner for inactive accounts
                                  if (!isSelected)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () {
                                            Navigator.of(context).pop(account.id);
                                          },
                                          borderRadius: BorderRadius.circular(20),
                                          child: Padding(
                                            padding: const EdgeInsets.all(4),
                                            child: Icon(
                                              Icons.switch_account,
                                              size: 20,
                                              color: cs.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: FilledButton.icon(
                        onPressed: () async {
                          // Navigate to splash screen with forceAdd flag using rootNavigator
                          // This will show the splash screen above the dialog
                          final result = await Navigator.of(context, rootNavigator: true).push<dynamic>(
                            MaterialPageRoute<String?>(
                              builder: (_) => const SplashScreen(),
                              settings: RouteSettings(
                                name: '/',
                                arguments: {'forceAdd': true},
                              ),
                            ),
                          );
                          if (!context.mounted) return;
                          // Close this dialog and return the new account ID to the parent
                          final newAccountId = result is String ? result : null;
                          final navigator = Navigator.of(context);
                          if (newAccountId != null) {
                            navigator.pop(newAccountId);
                          } else {
                            // User cancelled, just close the dialog without changing account
                            navigator.pop();
                          }
                        },
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Add Account'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
        );
      },
    );
  }
}

