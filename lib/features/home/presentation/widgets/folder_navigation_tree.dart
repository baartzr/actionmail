import 'package:flutter/material.dart';
import 'package:domail/constants/app_constants.dart';
import 'package:domail/services/local_folders/local_folder_service.dart';

/// Folder navigation tree for desktop
/// Shows Gmail folders and local backup folders
class FolderNavigationTree extends StatefulWidget {
  final String? selectedFolder;
  final bool isLocalFolder;
  final ValueChanged<String> onFolderSelected;
  final ValueChanged<bool> onLocalFolderToggled;

  const FolderNavigationTree({
    super.key,
    required this.selectedFolder,
    required this.isLocalFolder,
    required this.onFolderSelected,
    required this.onLocalFolderToggled,
  });

  @override
  State<FolderNavigationTree> createState() => _FolderNavigationTreeState();
}

class _FolderNavigationTreeState extends State<FolderNavigationTree> {
  final LocalFolderService _folderService = LocalFolderService();
  List<String> _localFolders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLocalFolders();
  }

  Future<void> _loadLocalFolders() async {
    setState(() => _isLoading = true);
    final folders = await _folderService.listFolders();
    if (mounted) {
      setState(() {
        _localFolders = folders;
        _isLoading = false;
      });
    }
  }

  Future<void> _createNewFolder() async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Folder Name',
            hintText: 'Enter folder name',
          ),
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final created = await _folderService.createFolder(result);
      if (created) {
        if (!context.mounted) return;
        await _loadLocalFolders();
        // Select the newly created folder
        widget.onLocalFolderToggled(true);
        widget.onFolderSelected(result);
        messenger.showSnackBar(
          SnackBar(content: Text('Folder "$result" created')),
        );
      } else if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to create folder')),
        );
      }
    }
  }

  Future<void> _deleteFolder(String folderName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text('Are you sure you want to delete "$folderName"?\n\nAll emails in this folder will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final deleted = await _folderService.deleteFolder(folderName);
      if (deleted) {
        if (!mounted) return;
        await _loadLocalFolders();
        if (!mounted) return;
        // If this was the selected folder, go back to INBOX
        if (widget.isLocalFolder && widget.selectedFolder == folderName) {
          widget.onLocalFolderToggled(false);
          widget.onFolderSelected(AppConstants.folderInbox);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Folder "$folderName" deleted')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border(
          right: BorderSide(
            color: cs.outline.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: cs.outline.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Folders',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  tooltip: 'Create Folder',
                  onPressed: _createNewFolder,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          // Folder list
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // Gmail Folders section
                _buildSectionHeader('Gmail', theme),
                _buildFolderItem(
                  context: context,
                  icon: Icons.inbox,
                  label: AppConstants.folderDisplayNames[AppConstants.folderInbox] ?? AppConstants.folderInbox,
                  folderId: AppConstants.folderInbox,
                  isSelected: !widget.isLocalFolder && widget.selectedFolder == AppConstants.folderInbox,
                  isGmail: true,
                ),
                _buildFolderItem(
                  context: context,
                  icon: Icons.send,
                  label: AppConstants.folderDisplayNames[AppConstants.folderSent] ?? AppConstants.folderSent,
                  folderId: AppConstants.folderSent,
                  isSelected: !widget.isLocalFolder && widget.selectedFolder == AppConstants.folderSent,
                  isGmail: true,
                ),
                _buildFolderItem(
                  context: context,
                  icon: Icons.archive,
                  label: AppConstants.folderDisplayNames[AppConstants.folderArchive] ?? AppConstants.folderArchive,
                  folderId: AppConstants.folderArchive,
                  isSelected: !widget.isLocalFolder && widget.selectedFolder == AppConstants.folderArchive,
                  isGmail: true,
                ),
                _buildFolderItem(
                  context: context,
                  icon: Icons.delete,
                  label: AppConstants.folderDisplayNames[AppConstants.folderTrash] ?? AppConstants.folderTrash,
                  folderId: AppConstants.folderTrash,
                  isSelected: !widget.isLocalFolder && widget.selectedFolder == AppConstants.folderTrash,
                  isGmail: true,
                ),
                _buildFolderItem(
                  context: context,
                  icon: Icons.block,
                  label: AppConstants.folderDisplayNames[AppConstants.folderSpam] ?? AppConstants.folderSpam,
                  folderId: AppConstants.folderSpam,
                  isSelected: !widget.isLocalFolder && widget.selectedFolder == AppConstants.folderSpam,
                  isGmail: true,
                ),
                const SizedBox(height: 16),
                // Local Folders section
                _buildSectionHeader('Local Backups', theme),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (_localFolders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'No local folders\nCreate one to save emails',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ..._localFolders.map((folderName) => _buildFolderItem(
                        context: context,
                        icon: Icons.folder_outlined,
                        label: folderName,
                        folderId: folderName,
                        isSelected: widget.isLocalFolder && widget.selectedFolder == folderName,
                        isGmail: false,
                        onDelete: () => _deleteFolder(folderName),
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildFolderItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String folderId,
    required bool isSelected,
    required bool isGmail,
    VoidCallback? onDelete,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          widget.onLocalFolderToggled(!isGmail);
          widget.onFolderSelected(folderId);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? cs.primaryContainer.withValues(alpha: 0.5)
                : Colors.transparent,
            border: isSelected
                ? Border(
                    left: BorderSide(
                      color: cs.primary,
                      width: 3,
                    ),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isSelected ? cs.primary : cs.onSurface,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isGmail && onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: cs.error,
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Delete folder',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

