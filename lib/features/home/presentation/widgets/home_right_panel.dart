import 'package:flutter/material.dart';
import 'package:domail/features/home/presentation/widgets/local_folder_tree.dart';
import 'package:domail/app/theme/actionmail_theme.dart';
import 'package:domail/data/models/message_index.dart';

/// Right panel for desktop - displays local folder tree
class HomeRightPanel extends StatelessWidget {
  final bool isCollapsed;
  final bool isLocalFolder;
  final String selectedFolder;
  final VoidCallback onToggleCollapse;
  final Future<void> Function(String folderPath) onFolderSelected;
  final Future<void> Function(String folderPath, MessageIndex message) onEmailDropped;

  const HomeRightPanel({
    super.key,
    required this.isCollapsed,
    required this.isLocalFolder,
    required this.selectedFolder,
    required this.onToggleCollapse,
    required this.onFolderSelected,
    required this.onEmailDropped,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final highlightColor = ActionMailTheme.alertColor.withValues(alpha: 0.2);

    if (isCollapsed) {
      return Container(
        color: cs.surface,
        child: Align(
          alignment: Alignment.topCenter,
          child: IconButton(
            icon: Icon(
              Icons.chevron_left,
              color: cs.onSurfaceVariant,
            ),
            onPressed: onToggleCollapse,
            tooltip: 'Expand right panel',
          ),
        ),
      );
    }

    return Container(
      color: cs.surface,
      child: Column(
        children: [
          // Collapse button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  onPressed: onToggleCollapse,
                  tooltip: 'Collapse right panel',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Only render folder tree when panel is wide enough
                if (constraints.maxWidth < 100) {
                  return const SizedBox.shrink();
                }
                return LocalFolderTree(
                  selectedFolder: isLocalFolder ? selectedFolder : null,
                  selectedBackgroundColor: highlightColor,
                  onFolderSelected: (folderPath) async {
                    await onFolderSelected(folderPath);
                  },
                  onEmailDropped: (folderPath, message) async {
                    await onEmailDropped(folderPath, message);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

