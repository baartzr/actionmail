import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ActionEditResult {
  final DateTime? actionDate;
  final String? actionText;
  final bool removed;

  const ActionEditResult({this.actionDate, this.actionText, this.removed = false});

  factory ActionEditResult.removed() => const ActionEditResult(removed: true);

  bool get hasAction => !removed && (actionDate != null || (actionText != null && actionText!.isNotEmpty));
}

class ActionEditDialog extends StatefulWidget {
  const ActionEditDialog({
    super.key,
    this.initialDate,
    this.initialText,
    this.title = 'Edit Action',
    this.allowRemove = false,
    this.confirmRemove = true,
  });

  final DateTime? initialDate;
  final String? initialText;
  final String title;
  final bool allowRemove;
  final bool confirmRemove;

  static Future<ActionEditResult?> show(
    BuildContext context, {
    DateTime? initialDate,
    String? initialText,
    String title = 'Edit Action',
    bool allowRemove = false,
    bool confirmRemove = true,
  }) {
    return showDialog<ActionEditResult?>(
      context: context,
      builder: (ctx) => ActionEditDialog(
        initialDate: initialDate,
        initialText: initialText,
        title: title,
        allowRemove: allowRemove,
        confirmRemove: confirmRemove,
      ),
    );
  }

  @override
  State<ActionEditDialog> createState() => _ActionEditDialogState();
}

class _ActionEditDialogState extends State<ActionEditDialog> {
  late DateTime? _selectedDate;
  late TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _textController = TextEditingController(text: widget.initialText ?? '');
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _handleRemove() async {
    if (!widget.allowRemove) {
      return;
    }

    bool confirmed = true;
    if (widget.confirmRemove) {
      confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Remove Action'),
              content: const Text('Are you sure you want to remove this action?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                    foregroundColor: Theme.of(ctx).colorScheme.onError,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Remove'),
                ),
              ],
            ),
          ) ??
          false;
    }

    if (!confirmed) {
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(ActionEditResult.removed());
  }

  void _handleSave() {
    final trimmed = _textController.text.trim();
    Navigator.of(context).pop(
      ActionEditResult(
        actionDate: _selectedDate,
        actionText: trimmed.isEmpty ? null : trimmed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel = _selectedDate != null ? DateFormat('dd-MMM, y').format(_selectedDate!) : 'Pick date';

    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _textController,
              decoration: const InputDecoration(
                labelText: 'Action',
              ),
              maxLines: 3,
              minLines: 1,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today),
              label: Text(dateLabel),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.allowRemove)
          TextButton.icon(
            onPressed: _handleRemove,
            icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
            label: Text(
              'Remove',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _handleSave,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
