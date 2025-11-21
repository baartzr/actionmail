import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ActionEditResult {
  final DateTime? actionDate;
  final String? actionText;
  final bool removed;
  final bool? actionComplete;

  const ActionEditResult({this.actionDate, this.actionText, this.removed = false, this.actionComplete});

  factory ActionEditResult.removed() => const ActionEditResult(removed: true);

  bool get hasAction => !removed && (actionDate != null || (actionText != null && actionText!.isNotEmpty));
}

class ActionEditDialog extends StatefulWidget {
  const ActionEditDialog({
    super.key,
    this.initialDate,
    this.initialText,
    this.initialComplete = false,
    this.title = 'Edit Action',
    this.allowRemove = false,
    this.confirmRemove = true,
  });

  final DateTime? initialDate;
  final String? initialText;
  final bool initialComplete;
  final String title;
  final bool allowRemove;
  final bool confirmRemove;

  static Future<ActionEditResult?> show(
    BuildContext context, {
    DateTime? initialDate,
    String? initialText,
    bool initialComplete = false,
    String title = 'Edit Action',
    bool allowRemove = false,
    bool confirmRemove = true,
  }) {
    return showDialog<ActionEditResult?>(
      context: context,
      builder: (ctx) => ActionEditDialog(
        initialDate: initialDate,
        initialText: initialText,
        initialComplete: initialComplete,
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
  late bool _isComplete;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _textController = TextEditingController(text: widget.initialText ?? '');
    _isComplete = widget.initialComplete;
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
      final theme = Theme.of(context);
      final buttonStyle = FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
      );
      final textButtonStyle = TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
      );
      
      confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              title: Text(
                'Remove Action',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              content: Text(
                'Are you sure you want to remove this action?',
                style: theme.textTheme.bodyMedium,
              ),
              actions: [
                TextButton(
                  style: textButtonStyle,
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(
                    'Cancel',
                    style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                FilledButton(
                  style: buttonStyle.copyWith(
                    backgroundColor: WidgetStatePropertyAll(Theme.of(ctx).colorScheme.error),
                    foregroundColor: WidgetStatePropertyAll(Theme.of(ctx).colorScheme.onError),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(
                    'Remove',
                    style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
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
        actionComplete: null, // null means don't change complete status
      ),
    );
  }

  void _handleToggleComplete() {
    // Toggle complete status and close immediately
    final trimmed = _textController.text.trim();
    final newComplete = !_isComplete;
    Navigator.of(context).pop(
      ActionEditResult(
        actionDate: _selectedDate,
        actionText: trimmed.isEmpty ? null : trimmed,
        actionComplete: newComplete, // Toggle the status
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel = _selectedDate != null ? DateFormat('dd-MMM, y').format(_selectedDate!) : 'Pick date';

    // Modern button style matching windows - compact with smaller text
    final buttonStyle = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      minimumSize: const Size(0, 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      textStyle: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
    );
    final outlinedButtonStyle = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      minimumSize: const Size(0, 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      textStyle: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
    );
    final textButtonStyle = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      minimumSize: const Size(0, 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      textStyle: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
    );

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), // Sharper corners
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 8, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      title: Row(
        children: [
          Expanded(
            child: Text(
              widget.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ), // Smaller text matching windows
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            iconSize: 20,
            tooltip: 'Close',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
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
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              style: theme.textTheme.bodyMedium, // Smaller text
              maxLines: 3,
              minLines: 1,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: outlinedButtonStyle,
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(
                dateLabel,
                style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.allowRemove)
          TextButton.icon(
            style: textButtonStyle.copyWith(
              foregroundColor: WidgetStatePropertyAll(theme.colorScheme.error),
            ),
            onPressed: _handleRemove,
            icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
            label: Text(
              'Remove',
              style: TextStyle(
                color: theme.colorScheme.error,
                fontSize: theme.textTheme.labelSmall?.fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        // Text link button for Complete/Incomplete toggle
        TextButton(
          style: textButtonStyle,
          onPressed: _handleToggleComplete,
          child: Text(
            _isComplete ? 'Mark as Incomplete' : 'Mark as Complete',
            style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        FilledButton(
          style: buttonStyle.copyWith(
            foregroundColor: WidgetStatePropertyAll(Colors.white),
          ),
          onPressed: _handleSave,
          child: Text(
            'Save',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
