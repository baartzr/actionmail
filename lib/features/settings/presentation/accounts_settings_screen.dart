import 'package:flutter/material.dart';
import 'package:actionmail/services/auth/google_auth_service.dart';
import 'package:actionmail/shared/widgets/app_button.dart';

class AccountsSettingsScreen extends StatefulWidget {
  const AccountsSettingsScreen({super.key});

  @override
  State<AccountsSettingsScreen> createState() => _AccountsSettingsScreenState();
}

class _AccountsSettingsScreenState extends State<AccountsSettingsScreen> {
  List<GoogleAccount> _accounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // No native window resizing here; we will present this as a modal dialog
  }

  Future<void> _load() async {
    final list = await GoogleAuthService().loadAccounts();
    if (!mounted) return;
    setState(() {
      _accounts = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_accounts.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text(
                          'No accounts yet. Add one to get started.',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: _accounts.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final acc = _accounts[index];
                          return ListTile(
                            leading: const Icon(Icons.account_circle),
                            title: Text(acc.email),
                            subtitle: Text(acc.displayName),
                            trailing: Wrap(
                              spacing: 8,
                              children: [
                                AppButton(
                                  label: 'Sign out',
                                  onPressed: () async {
                                    await GoogleAuthService().signOutAccount(acc.id);
                                    await _load();
                                  },
                                ),
                                AppButton(
                                  label: 'Remove',
                                  onPressed: () async {
                                    await GoogleAuthService().removeAccount(acc.id);
                                    await _load();
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context, rootNavigator: true)
                              .pushNamed('/', arguments: {'forceAdd': true});
                        },
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Add account'),
                      ),
                    ],
                  ),
                ],
              ),
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
