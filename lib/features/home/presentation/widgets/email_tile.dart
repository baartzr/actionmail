import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:actionmail/data/models/message_index.dart';
import 'package:actionmail/constants/app_constants.dart';
import 'package:intl/intl.dart';
import 'package:actionmail/shared/widgets/app_switch_button.dart';
import 'package:actionmail/shared/widgets/app_button.dart';

/// Email tile widget with action insight line
class EmailTile extends StatefulWidget {
  final MessageIndex message;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onStarToggle;
  final Function(String?)? onLocalStateChanged; // Personal/Business/None
  final VoidCallback? onTrash;
  final VoidCallback? onArchive;
  final VoidCallback? onRestore;
  final void Function(DateTime? date, String? text)? onActionUpdated;
  final VoidCallback? onActionCompleted;

  const EmailTile({
    super.key,
    required this.message,
    this.onTap,
    this.onStarToggle,
    this.onLocalStateChanged,
    this.onTrash,
    this.onArchive,
    this.onRestore,
    this.onActionUpdated,
    this.onActionCompleted,
  });

  @override
  State<EmailTile> createState() => _EmailTileState();
}

class _EmailTileState extends State<EmailTile> {
  bool _expanded = false;
  String? _localState; // null | Personal | Business
  bool _starred = false;
  bool _showInlineActions = false; // legacy, use _revealDir
  int _revealDir = 0; // -1 left swipe, 1 right swipe, 0 none
  DateTime? _actionDate;
  String? _actionText;

  @override
  void initState() {
    super.initState();
    _localState = widget.message.localTagPersonal;
    _starred = widget.message.isStarred;
    _actionDate = widget.message.actionDate;
    _actionText = widget.message.actionInsightText;
  }

  bool _hasLeftActions(String folder) {
    // Shown on right swipe (left side)
    if (folder == 'TRASH') return true; // Restore
    if (folder == 'ARCHIVE') return true; // Restore on right swipe as well
    return false;
  }

  bool _hasRightActions(String folder) {
    // Shown on left swipe (right side)
    if (folder == 'ARCHIVE') return true; // Trash
    if (folder == 'INBOX' || folder == 'SENT' || folder == 'SPAM') return true; // Trash/Archive
    return false;
  }

  Widget _buildLeftActions(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final folder = widget.message.folderLabel;
    if (folder == 'TRASH' || folder == 'ARCHIVE') {
      return Container(
        color: cs.secondaryContainer,
        child: Center(
          child: AppButton(
            label: 'Restore',
            variant: AppButtonVariant.tonal,
            leadingIcon: Icons.restore,
            onPressed: () {
              setState(() => _revealDir = 0);
              if (widget.onRestore != null) widget.onRestore!();
            },
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildRightActions(BuildContext context) {
    final theme = Theme.of(context);
    final folder = widget.message.folderLabel;
    if (folder == 'INBOX' || folder == 'SENT' || folder == 'SPAM') {
      return Row(
        children: [
          Expanded(
            child: Container(
              color: theme.colorScheme.errorContainer,
              child: Center(
                child: AppButton(
                  label: AppConstants.swipeActionTrash,
                  variant: AppButtonVariant.filled,
                  isDestructive: true,
                  leadingIcon: Icons.delete_outline,
                  onPressed: () {
                    setState(() => _revealDir = 0);
                    if (widget.onTrash != null) widget.onTrash!();
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: theme.colorScheme.secondaryContainer,
              child: Center(
                child: AppButton(
                  label: AppConstants.swipeActionArchive,
                  variant: AppButtonVariant.tonal,
                  leadingIcon: Icons.archive_outlined,
                  onPressed: () {
                    setState(() => _revealDir = 0);
                    if (widget.onArchive != null) widget.onArchive!();
                  },
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (folder == 'ARCHIVE') {
      // Left swipe should show Trash only
      return Container(
        color: theme.colorScheme.errorContainer,
        child: Center(
          child: AppButton(
            label: AppConstants.swipeActionTrash,
            variant: AppButtonVariant.filled,
            isDestructive: true,
            leadingIcon: Icons.delete_outline,
            onPressed: () {
              setState(() => _revealDir = 0);
              if (widget.onTrash != null) widget.onTrash!();
            },
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
  @override
  void didUpdateWidget(covariant EmailTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep local starred state in sync when the message changes or is updated upstream
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.isStarred != widget.message.isStarred) {
      _starred = widget.message.isStarred;
    }
    if (oldWidget.message.localTagPersonal != widget.message.localTagPersonal) {
      _localState = widget.message.localTagPersonal;
    }
    if (oldWidget.message.actionDate != widget.message.actionDate ||
        oldWidget.message.actionInsightText != widget.message.actionInsightText) {
      _actionDate = widget.message.actionDate;
      _actionText = widget.message.actionInsightText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final isOverdue = widget.message.actionDate != null &&
        widget.message.actionDate!.isBefore(today);

    final parsed = _parseFrom(widget.message.from);
    final senderName = parsed.item1;
    final senderEmail = parsed.item2;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final revealTarget = totalWidth * 0.40; // 40% reveal
        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            if (details.primaryDelta == null) return;
            final folder = widget.message.folderLabel;
            if (details.primaryDelta! < -6) {
              // left swipe → show right actions if defined
              if (_hasRightActions(folder)) setState(() => _revealDir = -1);
            } else if (details.primaryDelta! > 6) {
              // right swipe → show left actions if defined
              if (_hasLeftActions(folder)) setState(() => _revealDir = 1);
            }
          },
          onHorizontalDragEnd: (details) {},
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Stack(
            children: [
              if (_revealDir == 1)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: revealTarget,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildLeftActions(context),
                      ),
                    ),
                  ),
                ),
              if (_revealDir == -1)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: revealTarget,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildRightActions(context),
                      ),
                    ),
                  ),
                ),

              // Foreground card that slides by 40% based on direction
              AnimatedSlide(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                offset: _revealDir == -1
                    ? const Offset(-0.4, 0)
                    : _revealDir == 1
                        ? const Offset(0.4, 0)
                        : Offset.zero,
                child: Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    onTap: () {
                      if (_revealDir != 0) {
                        setState(() {
                          _revealDir = 0;
                        });
                        return;
                      }
                      setState(() {
                        _expanded = !_expanded;
                      });
                      if (widget.onTap != null) widget.onTap!();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                // Row 1: Leading domain icon, sender name/email (left), category switch, date (right pinned)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _DomainIcon(email: senderEmail),
                          const SizedBox(width: 12),
                          Flexible(
                            fit: FlexFit.loose,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  senderName.isNotEmpty ? senderName : senderEmail,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: widget.message.isRead
                                        ? FontWeight.normal
                                        : FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  senderEmail,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                    Text(
                      _formatDate(widget.message.internalDate, now),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // Row 2: Subject
                Text(
                  widget.message.subject,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight:
                        widget.message.isRead ? FontWeight.normal : FontWeight.w600,
                  ),
                  maxLines: _expanded ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                ),

                // Row 3: Snippet (one row collapsed, full when expanded)
                if (widget.message.snippet != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.message.snippet!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: _expanded ? null : 1,
                    overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                  ),
                ],

                // Local category chips (only show in expanded view)
                if (_expanded && widget.message.localTags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: widget.message.localTags.map((tag) {
                      return Chip(
                        label: Text(
                          tag,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 11,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: tag == 'Subscription'
                            ? theme.colorScheme.secondaryContainer
                            : tag == 'Shopping'
                                ? theme.colorScheme.tertiaryContainer
                                : theme.colorScheme.surfaceContainerHighest,
                        labelStyle: TextStyle(
                          color: tag == 'Subscription'
                              ? theme.colorScheme.onSecondaryContainer
                              : tag == 'Shopping'
                                  ? theme.colorScheme.onTertiaryContainer
                                  : theme.colorScheme.onSurfaceVariant,
                        ),
                      );
                    }).toList(),
                  ),
                ],

                if (widget.message.folderLabel == 'INBOX') ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.lightbulb_outline,
                              size: 16,
                              color: isOverdue
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.secondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  final hasAction = _actionDate != null || (_actionText != null && _actionText!.trim().isNotEmpty);
                                  final baseStyle = theme.textTheme.bodySmall?.copyWith(
                                    color: isOverdue
                                        ? theme.colorScheme.error
                                        : theme.colorScheme.onSurfaceVariant,
                                    fontStyle: FontStyle.italic,
                                  );
                                  if (!hasAction) {
                                    return RichText(
                                      text: TextSpan(
                                        style: baseStyle,
                                        children: [
                                          const TextSpan(text: 'No action set. '),
                                          TextSpan(
                                            text: 'Add Action',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: theme.colorScheme.secondary,
                                              decoration: TextDecoration.none,
                                              fontStyle: FontStyle.normal,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            recognizer: TapGestureRecognizer()
                                              ..onTap = _openEditActionDialog,
                                          ),
                                        ],
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    );
                                  }
                                // With action: show [date] action text and [Edit, Mark as Complete]
                                final display = _actionText ?? '';
                                final dateLabel = _actionDate != null
                                    ? _formatDate(_actionDate!, DateTime.now())
                                    : null;
                                  return RichText(
                                    text: TextSpan(
                                      style: baseStyle,
                                      children: [
                                      if (dateLabel != null) ...[
                                        TextSpan(text: dateLabel),
                                        const TextSpan(text: '  •  '),
                                      ],
                                        if (display.isNotEmpty) TextSpan(text: display + '  '),
                                        TextSpan(
                                          text: 'Edit',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.secondary,
                                            decoration: TextDecoration.none,
                                            fontStyle: FontStyle.normal,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          recognizer: TapGestureRecognizer()
                                            ..onTap = _openEditActionDialog,
                                        ),
                                        const TextSpan(text: '  '),
                                        TextSpan(
                                          text: 'Mark as complete',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.tertiary,
                                            decoration: TextDecoration.none,
                                            fontStyle: FontStyle.normal,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          recognizer: TapGestureRecognizer()
                                            ..onTap = _handleMarkActionComplete,
                                        ),
                                      ],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildCategoryIconSwitch(context),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(
                          _starred ? Icons.star : Icons.star_border,
                          color: _starred
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        onPressed: _handleStarToggle,
                        tooltip: AppConstants.emailStateStarred,
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: widget.onTrash,
                        tooltip: AppConstants.swipeActionTrash,
                      ),
                    ],
                  ),
                ],

                    ],
                  ),
                ),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  },
    );
  }

  Widget _buildCategorySwitch(BuildContext context) {
    final current = _localState;
    return AppSwitchButton<String>(
      values: const ['Personal', 'Business'],
      selected: current,
      labelBuilder: (v) => v,
      onChanged: (v) {
        setState(() {
          // Tap same value to toggle off
          if (_localState == v) {
            _localState = null;
          } else {
            _localState = v;
          }
        });
        if (widget.onLocalStateChanged != null) {
          widget.onLocalStateChanged!(_localState);
        }
      },
    );
  }

  Widget _buildCategoryIconSwitch(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isPersonal = _localState == 'Personal';
    final isBusiness = _localState == 'Business';
    Color colorFor(bool selected) => selected ? cs.primary : cs.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: isPersonal
              ? BoxDecoration(
                  color: cs.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: IconButton(
            tooltip: 'Personal',
            icon: Icon(isPersonal ? Icons.person : Icons.person_outline, color: colorFor(isPersonal)),
            onPressed: () {
              setState(() {
                _localState = isPersonal ? null : 'Personal';
              });
              if (widget.onLocalStateChanged != null) {
                widget.onLocalStateChanged!(_localState);
              }
            },
          ),
        ),
        Container(
          decoration: isBusiness
              ? BoxDecoration(
                  color: cs.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: IconButton(
            tooltip: 'Business',
            icon: Icon(isBusiness ? Icons.business_center : Icons.business_center_outlined, color: colorFor(isBusiness)),
            onPressed: () {
              setState(() {
                _localState = isBusiness ? null : 'Business';
              });
              if (widget.onLocalStateChanged != null) {
                widget.onLocalStateChanged!(_localState);
              }
            },
          ),
        ),
      ],
    );
  }

  // Dismiss background removed; custom swipe implemented above

  Future<void> _openEditActionDialog() async {
    DateTime? tempDate = _actionDate ?? DateTime.now();
    final textController = TextEditingController(text: _actionText ?? '');

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, sbSet) {
            return AlertDialog(
              title: const Text('Edit Action'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: textController,
                    decoration: const InputDecoration(
                      labelText: 'Action',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: tempDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        sbSet(() {
                          tempDate = picked;
                        });
                      }
                    },
                    icon: const Icon(Icons.calendar_today),
                    label: Text(tempDate != null
                        ? DateFormat('dd-MMM, y').format(tempDate!)
                        : 'Pick date'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _actionDate = tempDate;
                      _actionText = textController.text.trim();
                    });
                    if (widget.onActionUpdated != null) {
                      widget.onActionUpdated!(_actionDate, _actionText);
                    }
                    Navigator.of(context).pop();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleMarkActionComplete() {
    final existingText = (_actionText ?? '').trim();
    final alreadyComplete = existingText.toLowerCase().contains('complete');
    final newText = alreadyComplete ? existingText : (existingText.isEmpty ? 'Complete' : '$existingText (Complete)');
    setState(() {
      _actionText = newText;
      // Keep the existing date intact
    });
    // Persist as an update to the action (keep date, update text)
    if (widget.onActionUpdated != null) {
      widget.onActionUpdated!(_actionDate, _actionText);
    }
  }

  Future<void> _handleStarToggle() async {
    final newValue = !_starred;
    setState(() {
      _starred = newValue;
    });

    final success = await _updateStarOnGmail(newValue);
    if (!success) {
      // Revert on failure
      setState(() {
        _starred = !newValue;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update star on Gmail.')),
        );
      }
      return;
    }

    // Notify parent after successful update
    if (widget.onStarToggle != null) {
      widget.onStarToggle!(newValue);
    }
  }

  Future<bool> _updateStarOnGmail(bool starred) async {
    // Placeholder: replace this with the real Gmail update call
    try {
      debugPrint('[Gmail] Updating star state: id=${widget.message.id}, starred=$starred');
      await Future.delayed(const Duration(milliseconds: 300));
      return true;
    } catch (_) {
      return false;
    }
  }

  // Removed modal-based confirmation in favor of inline action buttons

  Tuple2<String, String> _parseFrom(String from) {
    final emailRegex = RegExp(r'<([^>]+)>');
    final match = emailRegex.firstMatch(from);
    if (match != null) {
      final email = match.group(1)!.trim();
      final name = from.replaceAll(match.group(0)!, '').trim();
      return Tuple2(name.replaceAll('"', ''), email);
    }
    // Fallbacks
    if (from.contains('@')) {
      return Tuple2('', from.trim());
    }
    return Tuple2(from.trim(), from.trim());
  }

  String _formatDate(DateTime date, DateTime now) {
    final localDate = date.toLocal();
    final localNow = now.toLocal();
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final targetDay = DateTime(localDate.year, localDate.month, localDate.day);
    final daysDiff = today.difference(targetDay).inDays;

    if (daysDiff == 0) {
      final s = DateFormat('h:mm a').format(localDate);
      return s.replaceAll('AM', 'am').replaceAll('PM', 'pm');
    } else if (daysDiff == 1) {
      return 'Yesterday';
    } else {
      return DateFormat('dd-MMM').format(localDate);
    }
  }
}

class _DomainIcon extends StatelessWidget {
  final String email;
  const _DomainIcon({required this.email});

  @override
  Widget build(BuildContext context) {
    final domain = _extractDomain(email);
    final letter = domain.isNotEmpty ? domain[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 12,
      backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
      foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
      child: Text(letter, style: Theme.of(context).textTheme.labelSmall),
    );
  }

  String _extractDomain(String email) {
    final at = email.indexOf('@');
    if (at == -1) return '';
    final host = email.substring(at + 1);
    return host.split('.').first;
  }
}

class Tuple2<A, B> {
  final A item1;
  final B item2;
  const Tuple2(this.item1, this.item2);
}
