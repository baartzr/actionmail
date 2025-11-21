import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domail/data/models/message_index.dart';
import 'package:domail/services/auth/google_auth_service.dart';
import 'package:domail/features/home/presentation/widgets/gmail_folder_tree.dart';
import 'package:domail/app/theme/actionmail_theme.dart';

/// Left panel widget for home screen
/// Displays accounts list and Gmail folder tree
class HomeLeftPanel extends ConsumerStatefulWidget {
  final bool isCollapsed;
  final List<GoogleAccount> accounts;
  final String? selectedAccountId;
  final String selectedFolder;
  final bool isLocalFolder;
  final Map<String, int> accountUnreadCounts;
  final Set<String> pendingLocalUnreadAccounts;
  final Function(bool) onToggleCollapse;
  final Future<void> Function(String) onAccountSelected;
  final Future<void> Function(String) onFolderSelected;
  final Future<void> Function(String, MessageIndex) onEmailDropped;

  const HomeLeftPanel({
    super.key,
    required this.isCollapsed,
    required this.accounts,
    required this.selectedAccountId,
    required this.selectedFolder,
    required this.isLocalFolder,
    required this.accountUnreadCounts,
    required this.pendingLocalUnreadAccounts,
    required this.onToggleCollapse,
    required this.onAccountSelected,
    required this.onFolderSelected,
    required this.onEmailDropped,
  });

  @override
  ConsumerState<HomeLeftPanel> createState() => _HomeLeftPanelState();
}

class _HomeLeftPanelState extends ConsumerState<HomeLeftPanel> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final highlightColor = ActionMailTheme.alertColor.withValues(alpha: 0.2);
    final highlightBorderColor =
        ActionMailTheme.alertColor.withValues(alpha: 1);
    const accountSelectedBorderColor = Color(0xFF00695C);

    if (widget.isCollapsed) {
      return Container(
        color: cs.surface,
        child: Align(
          alignment: Alignment.topCenter,
          child: IconButton(
            icon: Icon(
              Icons.chevron_right,
              color: cs.onSurfaceVariant,
            ),
            onPressed: () => widget.onToggleCollapse(false),
            tooltip: 'Expand left panel',
          ),
        ),
      );
    }

    final column = Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Collapse button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: Icon(
                  Icons.chevron_left,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                onPressed: () => widget.onToggleCollapse(true),
                tooltip: 'Collapse left panel',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        // Accounts section
        if (widget.accounts.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border(
                bottom: BorderSide(
                  color: cs.outline.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.account_circle, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Accounts',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 200,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: widget.accounts.map((account) {
                        final isSelected =
                            account.id == widget.selectedAccountId;
                        final isAccountActive =
                            isSelected && !widget.isLocalFolder;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () async {
                              await widget.onAccountSelected(account.id);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isAccountActive
                                    ? highlightColor
                                    : Colors.transparent,
                                border: isAccountActive
                                    ? Border(
                                        left: BorderSide(
                                          color: highlightBorderColor,
                                          width: 3,
                                        ),
                                      )
                                    : isSelected
                                        ? const Border(
                                            left: BorderSide(
                                              color: accountSelectedBorderColor,
                                              width: 3,
                                            ),
                                          )
                                        : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected
                                        ? Icons.account_circle
                                        : Icons.account_circle_outlined,
                                    size: 18,
                                    color: isAccountActive
                                        ? cs.onSurface
                                        : (isSelected
                                            ? accountSelectedBorderColor
                                            : cs.onSurfaceVariant),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      account.email,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: isAccountActive || !isSelected
                                            ? cs.onSurface
                                            : accountSelectedBorderColor,
                                        fontWeight: isAccountActive
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                  if (widget.accountUnreadCounts[account.id] !=
                                          null &&
                                      widget.accountUnreadCounts[account.id]! >
                                          0)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: Text(
                                        '(${widget.accountUnreadCounts[account.id]})',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: isAccountActive
                                              ? cs.onSurface
                                              : (isSelected
                                                  ? accountSelectedBorderColor
                                                  : cs.onSurfaceVariant),
                                          fontWeight: FontWeight.normal,
                                          fontSize: 12,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Gmail folder tree
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Only render folder tree when panel is wide enough
              if (constraints.maxWidth < 100) {
                return const SizedBox.shrink();
              }
              return GmailFolderTree(
                selectedFolder: widget.selectedFolder,
                isViewingLocalFolder: widget.isLocalFolder,
                accountId: widget.selectedAccountId,
                selectedBackgroundColor: highlightColor,
                onFolderSelected: widget.onFolderSelected,
                onEmailDropped: widget.onEmailDropped,
              );
            },
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Ensure we respect the width constraint strictly
        final panelWidth = constraints.maxWidth.isFinite &&
                constraints.maxWidth > 0
            ? constraints.maxWidth
            : double.infinity;
        if (kDebugMode) {
          debugPrint(
              '[LeftPanel] LayoutBuilder constraints: maxWidth=${constraints.maxWidth}, setting panelWidth: $panelWidth');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final renderObject = context.findRenderObject();
            if (renderObject != null && renderObject is RenderBox) {
              final box = renderObject;
              debugPrint(
                  '[LeftPanel] Actual size: ${box.size}, Constrained: ${box.hasSize}');
            }
          });
        }
        return Container(
          color: theme.colorScheme.surface,
          constraints: BoxConstraints.tightFor(width: panelWidth),
          child: ClipRect(
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: panelWidth,
              child: column,
            ),
          ),
        );
      },
    );
  }
}

