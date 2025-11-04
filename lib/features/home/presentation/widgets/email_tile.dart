import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:io';
import 'package:actionmail/data/models/message_index.dart';
import 'package:actionmail/constants/app_constants.dart';
import 'package:intl/intl.dart';
import 'package:actionmail/shared/widgets/app_switch_button.dart';
import 'package:actionmail/services/domain_icon_service.dart';

/// Email tile widget with action insight line
class EmailTile extends StatefulWidget {
  final MessageIndex message;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onStarToggle;
  final Function(String?)? onLocalStateChanged; // Personal/Business/None
  final VoidCallback? onTrash;
  final VoidCallback? onArchive;
  final VoidCallback? onRestore;
  final VoidCallback? onMoveToInbox;
  final void Function(DateTime? date, String? text, {bool? actionComplete})? onActionUpdated;
  final VoidCallback? onActionCompleted;
  final VoidCallback? onMarkRead;
  final void Function(String folderName)? onSaveToFolder;
  final bool isLocalFolder; // Whether this email is from a local folder (not Gmail)

  const EmailTile({
    super.key,
    required this.message,
    this.onTap,
    this.onStarToggle,
    this.onLocalStateChanged,
    this.onTrash,
    this.onArchive,
    this.onRestore,
    this.onMoveToInbox,
    this.onActionUpdated,
    this.onActionCompleted,
    this.onMarkRead,
    this.onSaveToFolder,
    this.isLocalFolder = false,
  });

  @override
  State<EmailTile> createState() => _EmailTileState();
}

class _EmailTileState extends State<EmailTile> {
  bool _expanded = false;
  String? _localState; // null | Personal | Business
  bool _starred = false;
  int _revealDir = 0; // -1 left swipe, 1 right swipe, 0 none
  DateTime? _actionDate;
  String? _actionText;
  bool _actionComplete = false;
  bool _showActionLine = true; // Visibility of action line

  @override
  void initState() {
    super.initState();
    _localState = widget.message.localTagPersonal;
    _starred = widget.message.isStarred;
    _actionDate = widget.message.actionDate;
    _actionText = widget.message.actionInsightText;
    _actionComplete = widget.message.actionComplete;
    // Default: show action if action date exists, hide if no action date
    _showActionLine = widget.message.actionDate != null;
  }

  bool _hasLeftActions(String folder) {
    // Shown on right swipe (left side)
    if (folder == 'TRASH') return true; // Restore
    if (folder == 'ARCHIVE') return true; // Restore on right swipe as well
    if (folder == 'SPAM') return true; // Move to Inbox
    return false;
  }

  bool _hasRightActions(String folder) {
    // Shown on left swipe (right side)
    if (folder == 'ARCHIVE') return true; // Trash
    if (folder == 'INBOX' || folder == 'SPAM') return true; // Trash/Archive
    if (folder == 'SENT') return true; // Trash only (cannot archive)
    return false;
  }

  Widget _buildLeftActions(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final folder = widget.message.folderLabel;
    if (folder == 'TRASH' || folder == 'ARCHIVE') {
      return Container(
        color: cs.secondary,
        child: InkWell(
          onTap: () {
            setState(() => _revealDir = 0);
            if (widget.onRestore != null) widget.onRestore!();
          },
          child: Center(
            child: Text(
              'Restore',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: cs.onSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }
    if (folder == 'SPAM') {
      // Right swipe shows Move to Inbox
      return Container(
        color: cs.primary,
        child: InkWell(
          onTap: () {
            setState(() => _revealDir = 0);
            if (widget.onMoveToInbox != null) widget.onMoveToInbox!();
          },
          child: Center(
            child: Text(
              'Inbox',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: cs.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildRightActions(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final folder = widget.message.folderLabel;
    if (folder == 'SPAM') {
      // SPAM folder: left swipe shows Trash and Archive
      return Row(
        children: [
          Expanded(
            child: Container(
              color: cs.error,
              child: InkWell(
                onTap: () {
                  setState(() => _revealDir = 0);
                  if (widget.onTrash != null) widget.onTrash!();
                },
                child: Center(
                  child: Text(
                    AppConstants.swipeActionTrash,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: cs.onError,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: cs.secondary,
              child: InkWell(
                onTap: () {
                  setState(() => _revealDir = 0);
                  if (widget.onArchive != null) widget.onArchive!();
                },
                child: Center(
                  child: Text(
                    AppConstants.swipeActionArchive,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: cs.onSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (folder == 'INBOX') {
      // INBOX: left swipe shows Trash and Archive
      return Row(
        children: [
          Expanded(
            child: Container(
              color: cs.error,
              child: InkWell(
                onTap: () {
                  setState(() => _revealDir = 0);
                  if (widget.onTrash != null) widget.onTrash!();
                },
                child: Center(
                  child: Text(
                    AppConstants.swipeActionTrash,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: cs.onError,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: cs.secondary,
              child: InkWell(
                onTap: () {
                  setState(() => _revealDir = 0);
                  if (widget.onArchive != null) widget.onArchive!();
                },
                child: Center(
                  child: Text(
                    AppConstants.swipeActionArchive,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: cs.onSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (folder == 'SENT') {
      // SENT: left swipe shows Trash only (cannot archive)
      return Container(
        color: cs.error,
        child: InkWell(
          onTap: () {
            setState(() => _revealDir = 0);
            if (widget.onTrash != null) widget.onTrash!();
          },
          child: Center(
            child: Text(
              AppConstants.swipeActionTrash,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: cs.onError,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }
    if (folder == 'ARCHIVE') {
      // Left swipe should show Trash only
      return Container(
        color: cs.error,
        child: InkWell(
          onTap: () {
            setState(() => _revealDir = 0);
            if (widget.onTrash != null) widget.onTrash!();
          },
          child: Center(
            child: Text(
              AppConstants.swipeActionTrash,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: cs.onError,
                fontWeight: FontWeight.w600,
              ),
            ),
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
        oldWidget.message.actionInsightText != widget.message.actionInsightText ||
        oldWidget.message.actionComplete != widget.message.actionComplete) {
      _actionDate = widget.message.actionDate;
      _actionText = widget.message.actionInsightText;
      _actionComplete = widget.message.actionComplete;
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
              // right swipe → show left actions if defined OR cancel left swipe
              if (_hasLeftActions(folder)) {
                setState(() => _revealDir = 1);
              } else if (_revealDir == -1) {
                // Cancel left swipe by swiping right
                setState(() => _revealDir = 0);
              }
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
                  color: widget.message.isRead 
                      ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
                      : theme.colorScheme.surfaceContainerLow,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: const Color(0xFF00897B).withValues(alpha: 0.4), // Darker teal border
                      width: 0.5,
                    ),
                  ),
                  child: _buildDraggableWrapper(
                    context,
                    child: GestureDetector(
                      onTap: () {
                        if (_revealDir != 0) {
                          setState(() {
                            _revealDir = 0;
                          });
                          return;
                        }
                        // Update state immediately for instant response
                        final wasExpanded = _expanded;
                        setState(() {
                          _expanded = !_expanded;
                        });
                        // Mark as read when expanded (not when collapsing)
                        if (!wasExpanded && _expanded && !widget.message.isRead && widget.onMarkRead != null) {
                          widget.onMarkRead!();
                        }
                      },
                      onDoubleTap: () {
                        // Double tap to open email viewer
                        if (widget.onTap != null) widget.onTap!();
                      },
                      child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        splashColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                        highlightColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
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
                  _decodeHtmlEntities(widget.message.subject),
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
                    _decodeHtmlEntities(widget.message.snippet!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: _expanded ? null : 1,
                    overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                  ),
                ],

                // Email Full View button and 4 info buttons (always visible)
                ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          // Open email viewer
                          if (widget.onTap != null) widget.onTap!();
                        },
                        icon: Icon(
                          Icons.open_in_new,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        label: Text(
                          'Full View',
                          style: TextStyle(color: theme.colorScheme.primary),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: theme.textTheme.labelSmall,
                        ),
                      ),
                      const Spacer(),
                      // Action line toggle button
                      IconButton(
                        iconSize: 20,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: Icon(
                          _showActionLine ? Icons.visibility : Icons.visibility_off,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () {
                          setState(() {
                            _showActionLine = !_showActionLine;
                          });
                        },
                        tooltip: _showActionLine ? 'Hide action' : 'Show action',
                      ),
                      const SizedBox(width: 4),
                      _buildCategoryIconSwitch(context),
                      const SizedBox(width: 4),
                      IconButton(
                        iconSize: 20,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
                        iconSize: 20,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: Icon(
                          Icons.delete_outline,
                          color: theme.colorScheme.error,
                        ),
                        onPressed: widget.onTrash,
                        tooltip: AppConstants.swipeActionTrash,
                      ),
                    ],
                  ),
                ],

                // Action row - show in all folders, but disable when not in INBOX
                if (_showActionLine) ...[
                  const SizedBox(height: 8),
                  Opacity(
                    opacity: widget.message.folderLabel == 'INBOX' ? 1.0 : 0.5,
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
                              final isInbox = widget.message.folderLabel == 'INBOX';
                              final baseStyle = theme.textTheme.bodySmall?.copyWith(
                                color: isOverdue
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              );
                              
                              // Show full action UI
                              if (!hasAction) {
                                return GestureDetector(
                                  onTap: isInbox ? _openEditActionDialog : null,
                                  behavior: HitTestBehavior.opaque,
                                  child: RichText(
                                    text: TextSpan(
                                      style: baseStyle,
                                      children: [
                                        const TextSpan(text: 'No action set. '),
                                        TextSpan(
                                          text: 'Add Action',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: isInbox 
                                                ? theme.colorScheme.secondary
                                                : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                            decoration: TextDecoration.none,
                                            fontStyle: FontStyle.normal,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }
                            // With action: show [date] action text and [Edit, Complete/Incomplete toggle]
                            final display = _actionText ?? '';
                            final dateLabel = _actionDate != null
                                ? _formatActionDate(_actionDate!, DateTime.now())
                                : null;
                            final isComplete = _actionComplete;
                              return GestureDetector(
                                onTap: isInbox ? _openEditActionDialog : null,
                                behavior: HitTestBehavior.opaque,
                                child: RichText(
                                  text: TextSpan(
                                    style: baseStyle,
                                    children: [
                                    if (dateLabel != null) ...[
                                      TextSpan(text: dateLabel),
                                      const TextSpan(text: '  •  '),
                                    ],
                                      if (display.isNotEmpty) TextSpan(text: display),
                                      const TextSpan(text: '  '),
                                      TextSpan(
                                        text: isComplete ? 'Status: Complete' : 'Status: Incomplete',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: isInbox 
                                              ? theme.colorScheme.tertiary
                                              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                          decoration: TextDecoration.none,
                                          fontStyle: FontStyle.normal,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        recognizer: isInbox 
                                            ? (TapGestureRecognizer()
                                              ..onTap = () {
                                                _handleMarkActionComplete();
                                              })
                                            : null,
                                      ),
                                    ],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                    ],
                  ),
                ),
                      ),
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

  /// Get allowed Gmail folders based on swipe actions for the current folder
  // Removed unused _getAllowedGmailFolders

  /// Wraps the child in a Draggable widget (desktop only)
  Widget _buildDraggableWrapper(BuildContext context, {required Widget child}) {
    final isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    
    // Only enable drag on desktop
    if (!isDesktop) {
      return child;
    }
    
    // Local folder emails: can only drag to other local folders (onSaveToFolder must be provided)
    // Gmail emails: can drag to local folders (onSaveToFolder) or allowed Gmail folders
    if (widget.isLocalFolder) {
      // Local folder emails can only drag to local folders
      if (widget.onSaveToFolder == null) {
        return child;
      }
    } else {
      // Gmail emails can drag to local folders or allowed Gmail folders
      // If no handlers are provided, disable drag
      if (widget.onSaveToFolder == null) {
        return child;
      }
    }
    
    return Draggable<MessageIndex>(
      data: widget.message,
      onDragStarted: () {
        // Notify parent that drag started
        // We'll use a notification or callback if needed
      },
      onDragEnd: (details) {
        // Notify parent that drag ended
      },
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: 0.8,
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.message.subject,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.message.from,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: child,
      ),
      child: child,
    );
  }

  // (removed) _isAllowedGmailFolder was unused

  // ignore: unused_element
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
    
    // Create a connected switch appearance
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: isPersonal ? cs.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                setState(() {
                  _localState = isPersonal ? null : 'Personal';
                });
                if (widget.onLocalStateChanged != null) {
                  widget.onLocalStateChanged!(_localState);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Icon(
                  isPersonal ? Icons.person : Icons.person_outline,
                  size: 20,
                  color: isPersonal ? cs.onPrimary : colorFor(false),
                ),
              ),
            ),
          ),
          Material(
            color: isBusiness ? cs.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                setState(() {
                  _localState = isBusiness ? null : 'Business';
                });
                if (widget.onLocalStateChanged != null) {
                  widget.onLocalStateChanged!(_localState);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Icon(
                  isBusiness ? Icons.business_center : Icons.business_center_outlined,
                  size: 20,
                  color: isBusiness ? cs.onPrimary : colorFor(false),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Dismiss background removed; custom swipe implemented above

  Future<void> _openEditActionDialog() async {
    DateTime? tempDate = _actionDate ?? DateTime.now();
    // Use action text as-is (no need to remove "(Complete)" since we use boolean field now)
    final currentText = _actionText ?? '';
    final textController = TextEditingController(text: currentText);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, sbSet) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(0), // Square corners
              ),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Title
                    Text(
                      'Edit Action',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Action text field
                    TextField(
                      controller: textController,
                      decoration: InputDecoration(
                        labelText: 'Action',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      maxLines: 3,
                      minLines: 1,
                    ),
                    const SizedBox(height: 16),
                    // Date picker button
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: tempDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                dialogTheme: DialogThemeData(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(0), // Square corners
                                  ),
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          sbSet(() {
                            tempDate = picked;
                          });
                        }
                      },
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(
                        tempDate != null
                            ? DateFormat('dd MMM yyyy').format(tempDate!)
                            : 'Pick date',
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Action buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () {
                            final newText = textController.text.trim();
                            setState(() {
                              _actionDate = tempDate;
                              _actionText = newText.isEmpty ? null : newText;
                              // Note: actionComplete state is preserved when editing (not reset)
                            });
                            if (widget.onActionUpdated != null) {
                              widget.onActionUpdated!(_actionDate, _actionText, actionComplete: _actionComplete);
                            }
                            Navigator.of(context).pop();
                          },
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _handleMarkActionComplete() {
    setState(() {
      _actionComplete = !_actionComplete;
    });
    // Update action with new completion state
    if (widget.onActionUpdated != null) {
      widget.onActionUpdated!(_actionDate, _actionText, actionComplete: _actionComplete);
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

  /// Decode HTML entities in text
  String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
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

  /// Format action date - always shows date, not time (even for today)
  String _formatActionDate(DateTime date, DateTime now) {
    final localDate = date.toLocal();
    final localNow = now.toLocal();
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final targetDay = DateTime(localDate.year, localDate.month, localDate.day);
    final daysDiff = today.difference(targetDay).inDays;

    if (daysDiff == 0) {
      // For today, just show the date (not time)
      return DateFormat('dd-MMM').format(localDate);
    } else if (daysDiff == 1) {
      return 'Yesterday';
    } else {
      return DateFormat('dd-MMM').format(localDate);
    }
  }
}

class _DomainIcon extends StatefulWidget {
  final String email;
  const _DomainIcon({required this.email});

  @override
  State<_DomainIcon> createState() => _DomainIconState();
}

class _DomainIconState extends State<_DomainIcon> {
  ImageProvider? _iconProvider;
  bool _loading = true;
  String? _lastEmail;
  final _service = DomainIconService();

  @override
  void initState() {
    super.initState();
    _lastEmail = widget.email;
    _loadIcon();
  }

  @override
  void didUpdateWidget(_DomainIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.email != widget.email) {
      _lastEmail = widget.email;
      _loadIcon();
    }
  }

  Future<void> _loadIcon() async {
    setState(() {
      _loading = true;
      _iconProvider = null;
    });
    final provider = await _service.getDomainIcon(widget.email);
    if (mounted && widget.email == _lastEmail) {
      setState(() {
        _iconProvider = provider;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final domain = _service.extractDomain(widget.email);
    final letter = domain.isNotEmpty ? domain[0].toUpperCase() : '?';
    
    if (_iconProvider != null && !_loading) {
      return CircleAvatar(
        radius: 12,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: ClipOval(
          child: Image(
            image: _iconProvider!,
            width: 24,
            height: 24,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              // Fallback to letter if image fails to load
              return CircleAvatar(
                radius: 12,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                child: Text(letter, style: Theme.of(context).textTheme.labelSmall),
              );
            },
          ),
        ),
      );
    }

    // Fallback to letter avatar
    return CircleAvatar(
      radius: 12,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
      child: Text(letter, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class Tuple2<A, B> {
  final A item1;
  final B item2;
  const Tuple2(this.item1, this.item2);
}
