import 'package:flutter/material.dart';
import 'package:actionmail/services/auth/google_auth_service.dart';
import 'package:actionmail/shared/widgets/app_window_dialog.dart';
import 'package:actionmail/features/auth/presentation/add_account_dialog.dart';

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
      setState(() {
        _accounts = updated;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signed out successfully')),
      );
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
      // If removed account was selected, close the dialog
      if (accountId == widget.selectedAccountId) {
        if (!mounted) return;
        Navigator.of(context).pop(null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      return ListTile(
                        leading: const Icon(Icons.account_circle),
                        title: Text(account.email),
                        subtitle: Text(account.displayName),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSelected) const Icon(Icons.check, color: Colors.blue),
                            const SizedBox(width: 8),
                            PopupMenuButton(
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'signout',
                                  child: ListTile(
                                    leading: const Icon(Icons.logout, size: 20),
                                    title: const Text('Sign Out'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'remove',
                                  child: ListTile(
                                    leading: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                    title: const Text('Remove'),
                                    textColor: Colors.red,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
                              onSelected: (value) {
                                if (value == 'signout') {
                                  _handleSignOut(account.id);
                                } else if (value == 'remove') {
                                  _handleRemove(account.id);
                                }
                              },
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(context).pop(account.id);
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: FilledButton.icon(
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      navigator.pop();
                      await Future.delayed(const Duration(milliseconds: 100));
                      if (!mounted || !context.mounted) return;
                      final newAccountId = await showDialog<String>(
                        context: context,
                        builder: (_) => const AddAccountDialog(),
                      );
                      if (!mounted) return;
                      if (newAccountId != null) {
                        navigator.pop(newAccountId);
                      }
                    },
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Add Account'),
                  ),
                ),
              ],
            ),
    );
  }
}

