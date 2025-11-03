import 'package:flutter/material.dart';
import 'package:actionmail/shared/widgets/app_window_dialog.dart';

class CreateFolderDialog extends StatefulWidget {
  final String? parentPath;
  
  const CreateFolderDialog({
    super.key,
    this.parentPath,
  });

  @override
  State<CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<CreateFolderDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppWindowDialog(
      title: widget.parentPath != null 
          ? 'Create Subfolder in ${widget.parentPath}'
          : 'Create New Folder',
      size: AppWindowSize.small,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.parentPath != null
                  ? 'Enter a name for your new subfolder.'
                  : 'Enter a name for your new local backup folder.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Folder Name',
                hintText: 'e.g., Important Receipts',
                border: const OutlineInputBorder(),
                errorText: _errorText,
              ),
              onChanged: (value) {
                if (_errorText != null && value.isNotEmpty) {
                  setState(() {
                    _errorText = null;
                  });
                }
              },
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final folderName = _controller.text.trim();
                    if (folderName.isEmpty) {
                      setState(() {
                        _errorText = 'Folder name cannot be empty';
                      });
                      return;
                    }
                    // Basic validation for filesystem safety
                    if (folderName.contains(RegExp(r'[<>:"/\\|?*]'))) {
                      setState(() {
                        _errorText = 'Folder name contains invalid characters';
                      });
                      return;
                    }
                    Navigator.of(context).pop(folderName);
                  },
                  child: const Text('Create'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

