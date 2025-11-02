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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        return AppWindowDialog(
          title: 'Select Account',
          size: AppWindowSize.small,
          bodyPadding: EdgeInsets.zero,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16.0),
                        itemCount: _accounts.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final account = _accounts[index];
                          final isSelected = account.id == widget.selectedAccountId;
                          final theme = Theme.of(context);
                          final cs = theme.colorScheme;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                    padding: const EdgeInsets.symmetric(vertical: 4),
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
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (account.displayName.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  account.displayName,
                                                  style: theme.textTheme.bodySmall?.copyWith(
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        if (isSelected) ...[
                                          const SizedBox(width: 8),
                                          Icon(
                                            Icons.check,
                                            size: 20,
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
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.logout,
                                              size: 18,
                                              color: cs.onSurfaceVariant,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'SignOut',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    InkWell(
                                      onTap: () => _handleRemove(account.id),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.delete_outline,
                                              size: 18,
                                              color: cs.error,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Remove',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: cs.error,
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
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
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
                          if (!mounted) return;
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
                  ],
                ),
        );
      },
    );
  }
}

