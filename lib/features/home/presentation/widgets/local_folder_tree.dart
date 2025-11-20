import 'package:flutter/material.dart';
import 'package:domail/services/local_folders/local_folder_service.dart';
import 'package:domail/features/home/presentation/widgets/create_folder_dialog.dart';
import 'package:domail/data/models/message_index.dart';

/// Local folder navigation tree with nested subfolder support
class LocalFolderTree extends StatefulWidget {
  final String? selectedFolder;
  final ValueChanged<String> onFolderSelected;
  final void Function(String folderPath, MessageIndex message)? onEmailDropped;
  final Color? selectedBackgroundColor;

  const LocalFolderTree({
    super.key,
    required this.selectedFolder,
    required this.onFolderSelected,
    this.onEmailDropped,
    this.selectedBackgroundColor,
  });

  @override
  State<LocalFolderTree> createState() => _LocalFolderTreeState();
}

class _LocalFolderTreeState extends State<LocalFolderTree> {
  final LocalFolderService _folderService = LocalFolderService();
  Map<String, dynamic> _folderTree = {};
  final Set<String> _expandedFolders = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() => _isLoading = true);
    final tree = await _folderService.listFoldersTree();
    if (mounted) {
      setState(() {
        _folderTree = tree;
        _isLoading = false;
      });
    }
  }

  Future<void> _createNewFolder([String? parentPath]) async {
    final messenger = ScaffoldMessenger.of(context);
    final newFolderName = await showDialog<String>(
      context: context,
      builder: (ctx) => CreateFolderDialog(parentPath: parentPath),
    );

    if (newFolderName != null && newFolderName.isNotEmpty) {
      final created = await _folderService.createFolder(newFolderName, parentPath: parentPath);
      if (created) {
        if (!context.mounted) return;
        await _loadFolders();
        final fullPath = parentPath != null ? '$parentPath/$newFolderName' : newFolderName;
        messenger.showSnackBar(
          SnackBar(content: Text('Folder "$fullPath" created')),
        );
      } else if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to create folder')),
        );
      }
    }
  }

  Future<void> _renameFolder(String folderPath, String currentName) async {
    final controller = TextEditingController(text: currentName);
    try {
      final messenger = ScaffoldMessenger.of(context);
      final newName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rename Folder'),
          content: TextField(
            autofocus: true,
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Folder name',
              hintText: 'Enter new folder name',
            ),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                Navigator.of(ctx).pop(value.trim());
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) {
                  Navigator.of(ctx).pop(value);
                }
              },
              child: const Text('Rename'),
            ),
          ],
        ),
      );

      if (newName != null && newName.isNotEmpty && newName != currentName) {
        final renamed = await _folderService.renameFolder(folderPath, newName);
        if (renamed) {
          if (!context.mounted) return;
          await _loadFolders();
          // Select the renamed folder if it was selected
          if (widget.selectedFolder == folderPath) {
            // Calculate new path
            final oldParent = folderPath.contains('/') 
                ? folderPath.substring(0, folderPath.lastIndexOf('/'))
                : '';
            final newPath = oldParent.isEmpty ? newName : '$oldParent/$newName';
            widget.onFolderSelected(newPath);
          }
          messenger.showSnackBar(
            SnackBar(content: Text('Folder renamed to "$newName"')),
          );
        } else if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Failed to rename folder')),
          );
        }
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _deleteFolder(String folderPath) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text('Are you sure you want to delete "$folderPath"?\n\nAll emails and subfolders in this folder will be permanently deleted.'),
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
      final deleted = await _folderService.deleteFolder(folderPath);
      if (deleted) {
        if (!context.mounted) return;
        await _loadFolders();
        // If this was the selected folder, clear selection
        if (widget.selectedFolder == folderPath) {
          widget.onFolderSelected('');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Folder "$folderPath" deleted')),
          );
        }
      }
    }
  }

  void _toggleExpanded(String folderPath) {
    // Only allow expansion if folder actually has children
    bool hasChildren = _checkHasChildren(_folderTree, folderPath);
    if (!hasChildren && !_expandedFolders.contains(folderPath)) {
      return; // Don't allow expansion if no children
    }
    
    setState(() {
      if (_expandedFolders.contains(folderPath)) {
        _expandedFolders.remove(folderPath);
      } else {
        _expandedFolders.add(folderPath);
      }
    });
  }
  
  /// Check if a folder path has children in the tree
  bool _checkHasChildren(Map<String, dynamic> tree, String folderPath) {
    if (folderPath.isEmpty) return false;
    
    final parts = folderPath.split('/');
    Map<String, dynamic>? current = tree;
    
    for (final part in parts) {
      if (current is! Map<String, dynamic>) {
        return false;
      }
      final value = current[part];
      if (value == null) return false;
      
      if (value is Map<String, dynamic>) {
        current = value;
      } else {
        return false;
      }
    }
    
    // Check if current level has children
    return current is Map<String, dynamic> && current.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      // Removed fixed width: 240 - let parent constrain the width
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(
          left: BorderSide(
            color: cs.outline.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                const Icon(Icons.folder, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Local Folders',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  tooltip: 'Create Folder',
                  onPressed: () => _createNewFolder(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 18,
                ),
              ],
            ),
          ),
          // Folder list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _folderTree.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'No local folders\nCreate one to save emails',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        children: _buildFolderList(_folderTree),
                      ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFolderList(Map<String, dynamic> tree, [String prefix = '', int indent = 0]) {
    final widgets = <Widget>[];
    final sortedKeys = tree.keys.toList()..sort();
    
    for (final folderKey in sortedKeys) {
      // The key is now just the folder name (not a path), so use it directly
      final folderName = folderKey;
      
      // Build the full path from the prefix
      final fullPath = prefix.isEmpty ? folderName : '$prefix/$folderName';
      // Check if this folder has children - must be a non-null Map with entries
      final value = tree[folderKey];
      final hasChildren = value is Map<String, dynamic> && value.isNotEmpty;
      final isExpanded = hasChildren && _expandedFolders.contains(fullPath);
      final isSelected = widget.selectedFolder == fullPath;
      
      widgets.add(_buildFolderItem(
        folderName: folderName, // Display only the folder name, not the path
        fullPath: fullPath,
        hasChildren: hasChildren,
        isExpanded: isExpanded,
        isSelected: isSelected,
        indent: indent,
      ));
      
      // Add children if expanded and has children
      if (hasChildren && isExpanded) {
        final children = tree[folderKey] as Map<String, dynamic>;
        widgets.addAll(_buildFolderList(children, fullPath, indent + 1));
      }
    }
    
    return widgets;
  }

  Widget _buildFolderItem({
    required String folderName,
    required String fullPath,
    required bool hasChildren,
    required bool isExpanded,
    required bool isSelected,
    required int indent,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selectedBackground = widget.selectedBackgroundColor ??
        cs.secondaryContainer.withValues(alpha: 0.45);
    final selectedBorder = widget.selectedBackgroundColor != null
        ? widget.selectedBackgroundColor!.withValues(alpha: 1)
        : cs.secondary;

    Widget folderContent = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          // Only toggle expansion if folder has children
          if (hasChildren) {
            _toggleExpanded(fullPath);
          } else {
            widget.onFolderSelected(fullPath);
          }
        },
        child: Container(
          padding: EdgeInsets.only(
            left: 12 + (indent * 20),
            right: 12,
            //top: 0,
            //bottom: 0,
          ),
          constraints: const BoxConstraints(minHeight: 20),
          decoration: BoxDecoration(
            color: isSelected ? selectedBackground : Colors.transparent,
            border: isSelected
                ? Border(
                    left: BorderSide(
                      color: selectedBorder,
                      width: 3,
                    ),
                  )
                : null,
          ),
          child: Row(
            children: [
              if (hasChildren)
                GestureDetector(
                  onTap: () {
                    // Only allow expansion if folder has children
                    if (hasChildren) {
                      _toggleExpanded(fullPath);
                    }
                  },
                  child: Icon(
                    isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                )
              else
                const SizedBox(width: 16),
              Icon(
                hasChildren ? Icons.folder : Icons.folder_outlined,
                size: 20,
                color: isSelected ? cs.onSurface : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => widget.onFolderSelected(fullPath),
                  child: Text(
                    folderName, // This is already extracted as just the folder name, not the path
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: const Row(
                      children: [
                        Icon(Icons.edit, size: 18),
                        SizedBox(width: 8),
                        Text('Rename'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'create',
                    child: const Row(
                      children: [
                        Icon(Icons.add, size: 18),
                        SizedBox(width: 8),
                        Text('Create Subfolder'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18, color: cs.error),
                        const SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: cs.error)),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) {
                  if (value == 'rename') {
                    _renameFolder(fullPath, folderName);
                  } else if (value == 'create') {
                    _createNewFolder(fullPath);
                  } else if (value == 'delete') {
                    _deleteFolder(fullPath);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );

    // Wrap in DragTarget if onEmailDropped is provided
    if (widget.onEmailDropped == null) {
      return folderContent;
    }

    return DragTarget<MessageIndex>(
      onAcceptWithDetails: (details) {
        widget.onEmailDropped!(fullPath, details.data);
      },
      onWillAcceptWithDetails: (details) => true,
      builder: (context, candidateData, rejectedData) {
        final isHighlighted = candidateData.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: isHighlighted
                ? cs.primaryContainer.withValues(alpha: 0.3)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: folderContent,
        );
      },
    );
  }
}

