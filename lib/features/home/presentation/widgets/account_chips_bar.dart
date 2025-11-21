import 'package:flutter/material.dart';
import 'package:domail/services/auth/google_auth_service.dart';

/// Account chips bar for TableView - shows accounts with unread counts
/// Max 5 accounts visible, scrollable if more
class AccountChipsBar extends StatelessWidget {
  final List<GoogleAccount> accounts;
  final String? selectedAccountId;
  final Map<String, int> accountUnreadCounts;
  final ValueChanged<String> onAccountSelected;
  final VoidCallback onAddAccount;

  const AccountChipsBar({
    super.key,
    required this.accounts,
    required this.selectedAccountId,
    required this.accountUnreadCounts,
    required this.onAccountSelected,
    required this.onAddAccount,
  });

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) {
      return const SizedBox.shrink();
    }

    final appBarFg = Theme.of(context).appBarTheme.foregroundColor;
    final theme = Theme.of(context);

    return Row(
      children: [
        // Account text links (scrollable if more than 5)
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ...accounts.map((account) {
                  final isSelected = account.id == selectedAccountId;
                  final unreadCount = accountUnreadCounts[account.id] ?? 0;

                  return Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: InkWell(
                      onTap: () => onAccountSelected(account.id),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  account.email,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: appBarFg,
                                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                                  ),
                                ),
                                if (unreadCount > 0) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    '($unreadCount)',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: appBarFg,
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (isSelected)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                height: 2,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        // Add Account button
        IconButton(
          onPressed: onAddAccount,
          icon: Icon(
            Icons.add,
            size: 20,
            color: appBarFg,
          ),
          tooltip: 'Add Account',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }
}

