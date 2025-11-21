import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domail/features/home/domain/providers/email_list_provider.dart';
import 'package:domail/data/models/message_index.dart';

/// Configuration for status button display
class _StatusButtonConfig {
  final bool showPersonalBusiness;
  final bool showStar;
  final bool showMove;
  final bool showArchive;
  final bool showTrash;
  final String moveLabel;
  final String moveTooltip;

  _StatusButtonConfig({
    required this.showPersonalBusiness,
    required this.showStar,
    required this.showMove,
    required this.showArchive,
    required this.showTrash,
    required this.moveLabel,
    required this.moveTooltip,
  });
}

/// Bulk action buttons widget for AppBar
class HomeBulkActionsAppBar extends ConsumerWidget {
  final Set<String> selectedEmailIds;
  final int selectedCount;
  final String selectedFolder;
  final bool isLocalFolder;
  final Function(List<MessageIndex>) onApplyPersonal;
  final Function(List<MessageIndex>) onApplyBusiness;
  final Function(List<MessageIndex>) onApplyStar;
  final Function(List<MessageIndex>) onApplyMove;
  final Function(List<MessageIndex>) onApplyArchive;
  final Function(List<MessageIndex>) onApplyTrash;

  const HomeBulkActionsAppBar({
    super.key,
    required this.selectedEmailIds,
    required this.selectedCount,
    required this.selectedFolder,
    required this.isLocalFolder,
    required this.onApplyPersonal,
    required this.onApplyBusiness,
    required this.onApplyStar,
    required this.onApplyMove,
    required this.onApplyArchive,
    required this.onApplyTrash,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final emailListAsync = ref.watch(emailListProvider);
    final config = _getStatusButtonConfig(selectedFolder);
    
    // Get selected emails
    final selectedEmails = emailListAsync.when(
      data: (emails) => emails.where((e) => selectedEmailIds.contains(e.id)).toList(),
      loading: () => <MessageIndex>[],
      error: (_, __) => <MessageIndex>[],
    );

    if (selectedEmails.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$selectedCount',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              color: cs.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Personal/Business Switch - show as two buttons
        _buildBulkActionButton(
          context,
          Icons.person_outline,
          'Personal',
          config.showPersonalBusiness ? () => onApplyPersonal(selectedEmails) : null,
          enabled: config.showPersonalBusiness,
        ),
        const SizedBox(width: 4),
        _buildBulkActionButton(
          context,
          Icons.business_center,
          'Business',
          config.showPersonalBusiness ? () => onApplyBusiness(selectedEmails) : null,
          enabled: config.showPersonalBusiness,
        ),
        const SizedBox(width: 4),
        _buildBulkActionButton(
          context,
          Icons.star_outline,
          'Star',
          config.showStar ? () => onApplyStar(selectedEmails) : null,
          enabled: config.showStar,
        ),
        const SizedBox(width: 4),
        _buildBulkActionButton(
          context,
          Icons.folder_outlined,
          config.moveTooltip,
          config.showMove ? () => onApplyMove(selectedEmails) : null,
          enabled: config.showMove,
        ),
        const SizedBox(width: 4),
        _buildBulkActionButton(
          context,
          Icons.archive_outlined,
          'Archive',
          config.showArchive ? () => onApplyArchive(selectedEmails) : null,
          enabled: config.showArchive,
        ),
        const SizedBox(width: 4),
        _buildBulkActionButton(
          context,
          Icons.delete_outline,
          'Trash',
          config.showTrash ? () => onApplyTrash(selectedEmails) : null,
          enabled: config.showTrash,
        ),
      ],
    );
  }

  Widget _buildBulkActionButton(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    bool enabled = true,
  }) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 18),
        onPressed: onPressed,
        color: enabled
            ? theme.appBarTheme.foregroundColor
            : theme.appBarTheme.foregroundColor?.withValues(alpha: 0.3),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        tooltip: tooltip,
      ),
    );
  }

  _StatusButtonConfig _getStatusButtonConfig(String folder) {
    final upperFolder = folder.toUpperCase();
    switch (upperFolder) {
      case 'INBOX':
        return _StatusButtonConfig(
          showPersonalBusiness: true,
          showStar: true,
          showMove: true,
          showArchive: true,
          showTrash: true,
          moveLabel: 'Move',
          moveTooltip: 'Move',
        );
      case 'SENT':
        return _StatusButtonConfig(
          showPersonalBusiness: false,
          showStar: false,
          showMove: false,
          showArchive: false,
          showTrash: true,
          moveLabel: 'Move',
          moveTooltip: 'Move',
        );
      case 'SPAM':
        return _StatusButtonConfig(
          showPersonalBusiness: false,
          showStar: false,
          showMove: true,
          showArchive: false,
          showTrash: true,
          moveLabel: 'Move to Inbox',
          moveTooltip: 'Move to Inbox',
        );
      case 'TRASH':
        return _StatusButtonConfig(
          showPersonalBusiness: false,
          showStar: false,
          showMove: true,
          showArchive: false,
          showTrash: false,
          moveLabel: 'Restore',
          moveTooltip: 'Restore',
        );
      case 'ARCHIVE':
        return _StatusButtonConfig(
          showPersonalBusiness: false,
          showStar: false,
          showMove: true,
          showArchive: false,
          showTrash: true,
          moveLabel: 'Restore',
          moveTooltip: 'Restore',
        );
      default:
        // Default to all enabled (for unknown folders)
        return _StatusButtonConfig(
          showPersonalBusiness: true,
          showStar: true,
          showMove: true,
          showArchive: true,
          showTrash: true,
          moveLabel: 'Move',
          moveTooltip: 'Move',
        );
    }
  }
}

