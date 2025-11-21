import 'package:flutter/material.dart';
import 'package:domail/app/theme/actionmail_theme.dart';

/// Widget that displays an indicator when viewing a local saved folder
class HomeSavedListIndicator extends StatelessWidget {
  final String selectedFolder;
  final VoidCallback onBackToGmail;

  const HomeSavedListIndicator({
    super.key,
    required this.selectedFolder,
    required this.onBackToGmail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = const Color(0xFF333333);
    final highlightColor = ActionMailTheme.alertColor.withValues(alpha: 0.5);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: highlightColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.sd_storage_outlined,
            size: 20,
            color: textColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Viewing local storage',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Saved list: $selectedFolder',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          TextButton(
            onPressed: onBackToGmail,
            style: TextButton.styleFrom(
              foregroundColor: textColor,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Back to Gmail'),
          ),
        ],
      ),
    );
  }
}

