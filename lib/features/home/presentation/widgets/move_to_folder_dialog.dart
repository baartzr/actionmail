import 'package:flutter/material.dart';
import 'package:domail/features/home/presentation/widgets/local_folder_tree.dart';
import 'package:domail/app/theme/actionmail_theme.dart';

/// Dialog for selecting a folder to move emails to
class MoveToFolderDialog extends StatelessWidget {
  const MoveToFolderDialog({super.key});

  /// Show the dialog and return the selected folder path, or null if cancelled
  static Future<String?> show(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (context) => const MoveToFolderDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarBg = theme.appBarTheme.backgroundColor ?? theme.colorScheme.primary;
    final appBarFg = theme.appBarTheme.foregroundColor ?? theme.colorScheme.onPrimary;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), // Sharper corners
      child: Container(
        width: 400,
        height: 500,
        decoration: BoxDecoration(
          color: theme.dialogTheme.backgroundColor ?? theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header matching AppWindowDialog style
            Material(
              color: appBarBg,
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Move to Folder',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: appBarFg,
                          fontWeight: FontWeight.w600,
                        ), // Smaller text matching windows
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: appBarFg, size: 20),
                      iconSize: 20,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: LocalFolderTree(
                  selectedFolder: null,
                  selectedBackgroundColor: ActionMailTheme.alertColor.withValues(alpha: 0.2),
                  onFolderSelected: (folderPath) {
                    Navigator.of(context).pop(folderPath);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

