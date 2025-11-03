import 'package:flutter/material.dart';
import 'package:actionmail/services/local_folders/local_folder_service.dart';
import 'package:actionmail/features/home/presentation/widgets/create_folder_dialog.dart';

/// Dialog for selecting a local folder to save an email
class SaveToFolderDialog extends StatefulWidget {
  const SaveToFolderDialog({super.key});

  @override
  State<SaveToFolderDialog> createState() => _SaveToFolderDialogState();
}

class _SaveToFolderDialogState extends State<SaveToFolderDialog> {
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
    final tree = await _folderService.listFoldersTree();
    if (mounted) {
      setState(() {
        _folderTree = tree;
        _isLoading = false;
      });
    }
  }

  Future<void> _createNewFolder([String? parentPath]) async {
    final newFolderName = await showDialog<String>(
      context: context,
      builder: (ctx) => CreateFolderDialog(parentPath: parentPath),
    );

    if (newFolderName != null && newFolderName.isNotEmpty) {
      final created = await _folderService.createFolder(newFolderName, parentPath: parentPath);
      if (created && mounted) {
        await _loadFolders();
      }
    }
  }

  void _toggleExpanded(String folderPath) {
    setState(() {
      if (_expandedFolders.contains(folderPath)) {
        _expandedFolders.remove(folderPath);
      } else {
        _expandedFolders.add(folderPath);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AlertDialog(
      title: const Text('Save to Folder'),
      content: SizedBox(
        width: 350,
        height: 400,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _folderTree.isEmpty
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'No local folders available.\nCreate one to save emails.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _createNewFolder,
                        icon: const Icon(Icons.add),
                        label: const Text('Create Folder'),
                      ),
                    ],
                  )
                : ListView(
                    children: _buildFolderList(_folderTree),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (!_isLoading)
          TextButton.icon(
            onPressed: _createNewFolder,
            icon: const Icon(Icons.add),
            label: const Text('New Folder'),
          ),
      ],
    );
  }

  List<Widget> _buildFolderList(Map<String, dynamic> tree, [String prefix = '', int indent = 0]) {
    final widgets = <Widget>[];
    final sortedKeys = tree.keys.toList()..sort();
    
    for (final folderName in sortedKeys) {
      final fullPath = prefix.isEmpty ? folderName : '$prefix/$folderName';
      final hasChildren = tree[folderName] is Map<String, dynamic> && 
                         (tree[folderName] as Map<String, dynamic>).isNotEmpty;
      final isExpanded = _expandedFolders.contains(fullPath);
      
      widgets.add(_buildFolderItem(
        folderName: folderName,
        fullPath: fullPath,
        hasChildren: hasChildren,
        isExpanded: isExpanded,
        indent: indent,
      ));
      
      // Add children if expanded
      if (hasChildren && isExpanded) {
        final children = tree[folderName] as Map<String, dynamic>;
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
    required int indent,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          // Toggle expansion if has children, otherwise select
          if (hasChildren) {
            _toggleExpanded(fullPath);
          } else {
            Navigator.of(context).pop(fullPath);
          }
        },
        child: Container(
          padding: EdgeInsets.only(
            left: 16 + (indent * 24),
            right: 16,
            top: 12,
            bottom: 12,
          ),
          child: Row(
            children: [
              if (hasChildren)
                GestureDetector(
                  onTap: () => _toggleExpanded(fullPath),
                  child: Icon(
                    isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                )
              else
                const SizedBox(width: 20),
              Icon(
                hasChildren ? Icons.folder : Icons.folder_outlined,
                size: 20,
                color: cs.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(fullPath),
                  child: Text(
                    folderName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

