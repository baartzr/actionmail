import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:domail/data/models/message_index.dart';
import 'package:intl/intl.dart';
import 'package:domail/app/theme/actionmail_theme.dart';

/// Table-style email list with action focus
/// 
/// Features:
/// - Full screen with no side panels
/// - Table layout with one row per email
/// - Action details prominently displayed
/// - Action buttons for quick management
/// - Filter bar at top with bulk actions
class GridEmailList extends StatefulWidget {
  final List<MessageIndex> emails;
  final String selectedFolder;
  final String? selectedAccountEmail;
  final List<String>? availableAccounts;
  final List<String>? localFolders;
  final bool isLocalFolder;
  final ValueChanged<String?>? onFolderChanged;
  final ValueChanged<MessageIndex>? onEmailTap;
  final ValueChanged<MessageIndex>? onEmailAction;
  final ValueChanged<Set<String>>? onFiltersChanged;
  final Set<String> activeFilters;
  final ValueChanged<MessageIndex>? onPersonalBusinessToggle;
  final ValueChanged<MessageIndex>? onStarToggle;
  final ValueChanged<MessageIndex>? onTrash;
  final ValueChanged<MessageIndex>? onArchive;
  final ValueChanged<MessageIndex>? onMoveToLocalFolder;
  final ValueChanged<String?>? onAccountChanged;
  final VoidCallback? onToggleLocalFolderView;
  final ValueChanged<int>? onSelectionChanged;
  final ValueChanged<Set<String>>? onSelectedIdsChanged;

  const GridEmailList({
    super.key,
    required this.emails,
    required this.selectedFolder,
    this.selectedAccountEmail,
    this.availableAccounts,
    this.localFolders,
    this.isLocalFolder = false,
    this.onFolderChanged,
    this.onEmailTap,
    this.onEmailAction,
    this.onFiltersChanged,
    this.activeFilters = const {},
    this.onPersonalBusinessToggle,
    this.onStarToggle,
    this.onTrash,
    this.onArchive,
    this.onMoveToLocalFolder,
    this.onAccountChanged,
    this.onToggleLocalFolderView,
    this.onSelectionChanged,
    this.onSelectedIdsChanged,
  });

  @override
  State<GridEmailList> createState() => _GridEmailListState();
}

class _GridEmailListState extends State<GridEmailList> {
  final Set<String> _selectedEmailIds = {};
  final List<Map<String, dynamic>> _undoStack = [];
  bool _isCtrlPressed = false;
  bool _showSearchField = false;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _horizontalScrollController = ScrollController();

  @override
  void dispose() {
    _searchController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Listener(
      onPointerDown: (_) {
        // Update Ctrl key state on any pointer event
        final isControlPressed = HardwareKeyboard.instance.isControlPressed;
        if (isControlPressed != _isCtrlPressed) {
          setState(() => _isCtrlPressed = isControlPressed);
        }
      },
      onPointerMove: (_) {
        // Update Ctrl key state on pointer move as well
        final isControlPressed = HardwareKeyboard.instance.isControlPressed;
        if (isControlPressed != _isCtrlPressed) {
          setState(() => _isCtrlPressed = isControlPressed);
        }
      },
      child: Focus(
        onKeyEvent: (node, event) {
          // Check if Control key is pressed using HardwareKeyboard
          final isControlPressed = HardwareKeyboard.instance.isControlPressed;
          if (isControlPressed != _isCtrlPressed) {
            setState(() => _isCtrlPressed = isControlPressed);
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: _buildEmailTable(context, theme),
      ),
      ),
    );
  }

  // ignore: unused_element
  PreferredSizeWidget _buildAppBar(BuildContext context, ThemeData theme) {
    return AppBar(
      automaticallyImplyLeading: false,
      elevation: 0,
      backgroundColor: ActionMailTheme.darkTeal,
      title: Row(
        children: [
          Text(
            'ActionMail',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFFB2DFDB), // Light teal for contrast on dark teal
            ),
          ),
          const SizedBox(width: 16),
          // Account dropdown
          if (widget.availableAccounts != null && widget.availableAccounts!.isNotEmpty)
            DropdownButton<String>(
              value: widget.selectedAccountEmail,
              items: widget.availableAccounts!.map((email) {
                return DropdownMenuItem(
                  value: email,
                  child: Text(email),
                );
              }).toList(),
              onChanged: widget.onAccountChanged,
              underline: const SizedBox(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFFB2DFDB), // Light teal for contrast on dark teal
              ),
              iconEnabledColor: const Color(0xFFB2DFDB),
            ),
        ],
      ),
      actions: [
        // Toggle local folder view button
        if (widget.onToggleLocalFolderView != null)
          IconButton(
            icon: Icon(
              widget.isLocalFolder ? Icons.folder : Icons.folder_outlined,
              color: const Color(0xFFB2DFDB), // Light teal for contrast on dark teal
            ),
            onPressed: widget.onToggleLocalFolderView,
            tooltip: widget.isLocalFolder 
                ? 'Switch to Gmail folders' 
                : 'Switch to local folders',
          ),
        // Folder dropdown
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: DropdownButton<String>(
            value: widget.selectedFolder,
            items: widget.isLocalFolder && widget.localFolders != null
                ? widget.localFolders!.map((folder) {
                    return DropdownMenuItem(
                      value: folder,
                      child: Text(folder),
                    );
                  }).toList()
                : const [
                    DropdownMenuItem(value: 'INBOX', child: Text('Inbox')),
                    DropdownMenuItem(value: 'SENT', child: Text('Sent')),
                    DropdownMenuItem(value: 'ARCHIVE', child: Text('Archive')),
                    DropdownMenuItem(value: 'TRASH', child: Text('Trash')),
                    DropdownMenuItem(value: 'SPAM', child: Text('Spam')),
                  ],
            onChanged: widget.onFolderChanged,
            underline: const SizedBox(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFB2DFDB), // Light teal for contrast on dark teal
            ),
            iconEnabledColor: const Color(0xFFB2DFDB),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildFilterBar(BuildContext context, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: ActionMailTheme.darkTeal,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // All button
                _buildFilterChipIconOnly(
                  context,
                  Icons.dashboard,
                  'All',
                  null,
                  widget.activeFilters.isEmpty,
                  Colors.grey,
                ),
                
                // Status group
                _buildSectionLabel(context, 'Status'),
                _buildFilterChipIconOnly(
                  context,
                  Icons.search,
                  'Search',
                  null,
                  _showSearchField,
                  Colors.grey,
                  onTap: () {
                    setState(() {
                      _showSearchField = !_showSearchField;
                      if (!_showSearchField) {
                        _searchController.clear();
                      }
                    });
                  },
                ),
                if (_showSearchField)
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _searchController,
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Search emails...',
                        hintStyle: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        // Trigger search - you'll need to add a callback for this
                        // For now, just update the state
                        setState(() {});
                      },
                    ),
                  ),
                _buildFilterChipIconOnly(
                  context,
                  Icons.mark_email_unread,
                  'Unread',
                  'unread',
                  widget.activeFilters.contains('unread'),
                  Colors.blue,
                ),
                _buildFilterChipIconOnly(
                  context,
                  Icons.star,
                  'Starred',
                  'starred',
                  widget.activeFilters.contains('starred'),
                  Colors.amber,
                ),
                _buildFilterChipIconOnly(
                  context,
                  Icons.person,
                  'Personal',
                  'personal',
                  widget.activeFilters.contains('personal'),
                  Colors.blue,
                ),
                _buildFilterChipIconOnly(
                  context,
                  Icons.business_center,
                  'Business',
                  'business',
                  widget.activeFilters.contains('business'),
                  Colors.purple,
                ),
                
                // Tags group
                _buildSectionLabel(context, 'Tags'),
                _buildFilterChipIconOnly(
                  context,
                  Icons.lightbulb,
                  'Action',
                  'action',
                  widget.activeFilters.contains('action'),
                  Colors.orange,
                ),
                _buildFilterChipIconOnly(
                  context,
                  Icons.attach_file,
                  'Attachments',
                  'attachments',
                  widget.activeFilters.contains('attachments'),
                  Colors.teal,
                ),
                _buildFilterChipIconOnly(
                  context,
                  Icons.subscriptions,
                  'Subscriptions',
                  'subscriptions',
                  widget.activeFilters.contains('subscriptions'),
                  Colors.pink,
                ),
                _buildFilterChipIconOnly(
                  context,
                  Icons.shopping_bag,
                  'Shopping',
                  'shopping',
                  widget.activeFilters.contains('shopping'),
                  Colors.green,
                ),
                
                // Actions group
                _buildSectionLabel(context, 'Actions'),
                _buildFilterChipIconOnly(
                  context,
                  Icons.today,
                  'Today',
                  'action_today',
                  widget.activeFilters.contains('action_today'),
                  Colors.cyan,
                ),
                _buildFilterChipIconOnly(
                  context,
                  Icons.schedule,
                  'Upcoming',
                  'action_upcoming',
                  widget.activeFilters.contains('action_upcoming'),
                  Colors.indigo,
                ),
                _buildFilterChipIconOnly(
                  context,
                  Icons.warning,
                  'Overdue',
                  'action_overdue',
                  widget.activeFilters.contains('action_overdue'),
                  Colors.red,
                ),
                _buildFilterChipIconOnly(
                  context,
                  Icons.help_outline,
                  'Possible',
                  'action_possible',
                  widget.activeFilters.contains('action_possible'),
                  Colors.deepPurple,
                ),
              ],
            ),
          ),
          
          // Bulk action buttons on the right
          if (_selectedEmailIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _buildBulkActionButtons(context, theme),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(BuildContext context, String label) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: const Color(0xFFB2DFDB), // Light teal to match AppBar
          fontWeight: FontWeight.w700,
          fontSize: 10,
          letterSpacing: 0.8,
        ),
      ),
    );
  }


  Widget _buildFilterChipIconOnly(
    BuildContext context,
    IconData icon,
    String tooltip,
    String? value,
    bool isActive,
    Color iconColor, {
    VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap ?? () {
          final newFilters = Set<String>.from(widget.activeFilters);
          
          if (value == null) {
            // "All" button: clear all filters
            newFilters.clear();
          } else if (isActive) {
            // If already active, deselect just this one
            newFilters.remove(value);
          } else {
            // If not active, add it to existing filters (always multi-select)
            newFilters.add(value);
          }
          
          widget.onFiltersChanged?.call(newFilters);
        },
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: isActive
                ? LinearGradient(
                    colors: [
                      iconColor.withValues(alpha: 0.2),
                      iconColor.withValues(alpha: 0.1),
                    ],
                  )
                : null,
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: iconColor.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 18,
            color: isActive
                ? iconColor
                : iconColor.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }


  Widget _buildBulkActionButtons(BuildContext context, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${_selectedEmailIds.length}',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _buildBulkActionButton(
          context,
          theme,
          Icons.person,
          'Personal',
          () => _applyBulkAction('personal'),
        ),
        _buildBulkActionButton(
          context,
          theme,
          Icons.business_center,
          'Business',
          () => _applyBulkAction('business'),
        ),
        _buildBulkActionButton(
          context,
          theme,
          Icons.star,
          'Star',
          () => _applyBulkAction('star'),
        ),
        _buildBulkActionButton(
          context,
          theme,
          Icons.folder_outlined,
          'Move',
          () => _applyBulkAction('move'),
        ),
        _buildBulkActionButton(
          context,
          theme,
          Icons.archive_outlined,
          'Archive',
          () => _applyBulkAction('archive'),
        ),
        _buildBulkActionButton(
          context,
          theme,
          Icons.delete_outline,
          'Trash',
          () => _applyBulkAction('trash'),
        ),
        if (_undoStack.isNotEmpty) ...[
          const SizedBox(width: 4),
          _buildBulkActionButton(
            context,
            theme,
            Icons.undo,
            'Undo',
            _undoLastBulkAction,
          ),
        ],
      ],
    );
  }

  Widget _buildBulkActionButton(
    BuildContext context,
    ThemeData theme,
    IconData icon,
    String tooltip,
    VoidCallback onPressed,
  ) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 16),
        onPressed: onPressed,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        color: theme.colorScheme.primary,
      ),
    );
  }

  void _applyBulkAction(String action) {
    // Save current state for undo
    final selectedEmails = widget.emails
        .where((e) => _selectedEmailIds.contains(e.id))
        .toList();
    
    _undoStack.add({
      'action': action,
      'emailIds': _selectedEmailIds.toList(),
      'emails': selectedEmails.map((e) => e.id).toList(),
    });

    // Apply action to selected emails
    for (final email in selectedEmails) {
      switch (action) {
        case 'personal':
          widget.onPersonalBusinessToggle?.call(email);
          break;
        case 'business':
          widget.onPersonalBusinessToggle?.call(email);
          break;
        case 'star':
          widget.onStarToggle?.call(email);
          break;
        case 'trash':
          widget.onTrash?.call(email);
          break;
        case 'archive':
          widget.onArchive?.call(email);
          break;
        case 'move':
          widget.onMoveToLocalFolder?.call(email);
          break;
      }
    }

    setState(() {
      _selectedEmailIds.clear();
      widget.onSelectionChanged?.call(0);
      widget.onSelectedIdsChanged?.call({});
    });
  }

  void _undoLastBulkAction() {
    if (_undoStack.isEmpty) return;
    
    _undoStack.removeLast();
    // In a real implementation, you would restore the previous state
    // For now, we'll just clear the selection
    setState(() {
      _selectedEmailIds.clear();
      widget.onSelectionChanged?.call(0);
      widget.onSelectedIdsChanged?.call({});
    });
  }

  Widget _buildEmailTable(BuildContext context, ThemeData theme) {
    if (widget.emails.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No emails',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate column widths - use fixed widths for better control
        final checkboxWidth = 50.0;
        final dateWidth = 100.0;
        final senderWidth = 200.0;
        final actionDetailsWidth = 250.0;
        final statusWidth = 170.0; // Width to accommodate all status buttons (Personal/Business switch + 4 icon buttons)
        // Subject & Snippet - minimum width, but can expand
        final subjectMinWidth = 300.0;
        final fixedColumnsWidth = checkboxWidth + dateWidth + senderWidth + actionDetailsWidth + statusWidth;
        final totalMinWidth = fixedColumnsWidth + subjectMinWidth;
        
        // Calculate available width - use constraints if valid, otherwise use minimum width
        final hasValidConstraints = constraints.maxWidth.isFinite && 
                                    constraints.maxWidth > 0;
        
        // Calculate subject column width based on available space
        // If available space is less than minimum, use minimum and enable scrolling
        // Otherwise, use available space (but at least minimum)
        final availableWidth = hasValidConstraints ? constraints.maxWidth : totalMinWidth;
        final availableForSubject = availableWidth - fixedColumnsWidth;
        final subjectWidth = availableForSubject >= subjectMinWidth 
            ? availableForSubject 
            : subjectMinWidth;
        
        // Final table width - use available width if it fits, otherwise use minimum for scrolling
        final finalTableWidth = availableWidth >= totalMinWidth 
            ? availableWidth 
            : totalMinWidth;
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0), // Add padding at bottom for scrollbar
          child: Scrollbar(
            controller: _horizontalScrollController,
            thumbVisibility: true, // Always show scrollbar when scrollable
            thickness: 12.0, // Make scrollbar thicker for easier clicking
            radius: const Radius.circular(6.0), // Rounded corners
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: finalTableWidth,
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: Table(
                    columnWidths: {
                      0: FixedColumnWidth(checkboxWidth),
                      1: FixedColumnWidth(dateWidth),
                      2: FixedColumnWidth(senderWidth),
                      3: FixedColumnWidth(subjectWidth), // Subject & Snippet - expands with available space
                      4: FixedColumnWidth(actionDetailsWidth),
                      5: FixedColumnWidth(statusWidth),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      // Header row
                      TableRow(
                        decoration: BoxDecoration(
                          color: ActionMailTheme.alertColor,
                        ),
                        children: [
                          TableCell(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              child: _buildSelectAllCheckbox(context, theme),
                            ),
                          ),
                          TableCell(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              child: Text(
                                'Date',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          TableCell(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              child: Text(
                                'Sender',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          TableCell(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              child: Text(
                                'Subject & Snippet',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          TableCell(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              child: Text(
                                'Action Details',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          TableCell(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              child: Text(
                                'Status',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Data rows
                      ...widget.emails.map((email) => _buildEmailTableRow(context, theme, email, constraints.maxWidth)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSelectAllCheckbox(BuildContext context, ThemeData theme) {
    final allSelected = widget.emails.isNotEmpty && 
        _selectedEmailIds.length == widget.emails.length;
    final someSelected = _selectedEmailIds.isNotEmpty && !allSelected;

    return GestureDetector(
      onTap: () {
        setState(() {
          if (allSelected) {
            // Deselect all
            _selectedEmailIds.clear();
          } else {
            // Select all
            _selectedEmailIds.clear();
            _selectedEmailIds.addAll(widget.emails.map((e) => e.id));
          }
          widget.onSelectionChanged?.call(_selectedEmailIds.length);
          widget.onSelectedIdsChanged?.call(Set<String>.from(_selectedEmailIds));
        });
      },
      child: Container(
        width: 18,
        height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: allSelected || someSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  width: allSelected || someSelected ? 0 : 2.0,
                ),
          color: allSelected || someSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.15)
              : Colors.transparent,
        ),
        child: allSelected
            ? Icon(
                Icons.check,
                size: 12,
                color: theme.colorScheme.primary,
              )
            : someSelected
                ? Icon(
                    Icons.remove,
                    size: 12,
                    color: theme.colorScheme.primary,
                  )
                : null,
      ),
    );
  }

  TableRow _buildEmailTableRow(BuildContext context, ThemeData theme, MessageIndex email, double availableWidth) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isOverdue = email.actionDate != null && email.actionDate!.isBefore(today);

    // Extract sender name and email
    final fromMatch = RegExp(r'^(.+?)\s*<(.+?)>$').firstMatch(email.from);
    final senderName = fromMatch?.group(1)?.trim() ?? '';
    final senderEmail = fromMatch?.group(2)?.trim() ?? email.from;

    // Determine row background color
    final rowColor = email.isRead
        ? theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.3)
        : theme.colorScheme.surface;

    final isSelected = _selectedEmailIds.contains(email.id);
    final bgColor = isSelected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
        : rowColor;

    return TableRow(
      decoration: BoxDecoration(color: bgColor),
      children: [
        // Checkbox
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: GestureDetector(
              onTap: () {
                final isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
                setState(() {
                  if (isCtrlPressed) {
                    if (isSelected) {
                      _selectedEmailIds.remove(email.id);
                    } else {
                      _selectedEmailIds.add(email.id);
                    }
                  } else {
                    _selectedEmailIds.clear();
                    if (!isSelected) {
                      _selectedEmailIds.add(email.id);
                    }
                  }
                  widget.onSelectionChanged?.call(_selectedEmailIds.length);
                  widget.onSelectedIdsChanged?.call(Set<String>.from(_selectedEmailIds));
                });
              },
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    width: isSelected ? 0 : 2.0, // Border width when unselected
                  ),
                  color: isSelected
                      ? theme.colorScheme.primary.withValues(alpha: 0.15)
                      : Colors.transparent,
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        size: 12,
                        color: theme.colorScheme.primary,
                      )
                    : null,
              ),
            ),
          ),
        ),
        // Date
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: GestureDetector(
            onTap: () => widget.onEmailTap?.call(email),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text(
                _formatDate(email.internalDate, now),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ),
        // Sender
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: GestureDetector(
            onTap: () => widget.onEmailTap?.call(email),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    senderName.isNotEmpty ? senderName : senderEmail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: email.isRead ? FontWeight.normal : FontWeight.w600,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (senderName.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      senderEmail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // Subject & Snippet
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: GestureDetector(
            onTap: () => widget.onEmailTap?.call(email),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    email.subject.isNotEmpty ? email.subject : '(No subject)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: email.isRead ? FontWeight.normal : FontWeight.w600,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (email.snippet != null && email.snippet!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      email.snippet!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // Action Details
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: GestureDetector(
            onTap: () => widget.onEmailAction?.call(email),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: _buildActionDetails(context, theme, email, isOverdue),
            ),
          ),
        ),
        // Status
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: _buildStatusButtons(context, theme, email),
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
  DataRow _buildEmailRow(BuildContext context, ThemeData theme, MessageIndex email) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isOverdue = email.actionDate != null && email.actionDate!.isBefore(today);

    // Extract sender name and email
    final fromMatch = RegExp(r'^(.+?)\s*<(.+?)>$').firstMatch(email.from);
    final senderName = fromMatch?.group(1)?.trim() ?? '';
    final senderEmail = fromMatch?.group(2)?.trim() ?? email.from;

    // Determine row background color
    final rowColor = email.isRead
        ? theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.3)
        : theme.colorScheme.surface;

    final isSelected = _selectedEmailIds.contains(email.id);

    return DataRow(
      selected: isSelected,
      color: WidgetStateProperty.resolveWith((states) {
        if (isSelected) {
          return theme.colorScheme.primaryContainer.withValues(alpha: 0.3);
        }
        if (states.contains(WidgetState.hovered)) {
          return theme.colorScheme.primaryContainer.withValues(alpha: 0.15);
        }
        return rowColor;
      }),
      cells: [
        // Custom subtle checkbox column
        DataCell(
          GestureDetector(
            onTap: () {
              final isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
              setState(() {
                if (isCtrlPressed) {
                  // Multi-select mode: toggle this email's selection
                  if (isSelected) {
                    _selectedEmailIds.remove(email.id);
                  } else {
                    _selectedEmailIds.add(email.id);
                  }
                } else {
                  // Single select mode: clear all and select only this one
                  _selectedEmailIds.clear();
                  if (!isSelected) {
                    _selectedEmailIds.add(email.id);
                  }
                }
              });
            },
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant.withValues(alpha: 0.9),
                  width: isSelected ? 0 : 1.5,
                ),
                color: isSelected
                    ? theme.colorScheme.primary.withValues(alpha: 0.15)
                    : Colors.transparent,
              ),
              child: isSelected
                  ? Icon(
                      Icons.check,
                      size: 12,
                      color: theme.colorScheme.primary,
                    )
                  : null,
            ),
          ),
        ),
        // Date column
        DataCell(
          GestureDetector(
            onTap: () => widget.onEmailTap?.call(email),
            child: Text(
              _formatDate(email.internalDate, now),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ),
        ),

        // Sender column
        DataCell(
          GestureDetector(
            onTap: () => widget.onEmailTap?.call(email),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  senderName.isNotEmpty ? senderName : senderEmail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: email.isRead ? FontWeight.normal : FontWeight.w600,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (senderName.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    senderEmail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),

        // Subject & Snippet column
        DataCell(
          GestureDetector(
            onTap: () => widget.onEmailTap?.call(email),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  email.subject.isNotEmpty ? email.subject : '(No subject)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: email.isRead ? FontWeight.normal : FontWeight.w600,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (email.snippet != null && email.snippet!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email.snippet!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),

        // Action Details column - PROMINENT
        DataCell(
          GestureDetector(
            onTap: () => widget.onEmailTap?.call(email),
            child: _buildActionDetails(context, theme, email, isOverdue),
          ),
        ),

        // Status column (formerly Actions)
        DataCell(
          _buildStatusButtons(context, theme, email),
        ),
      ],
    );
  }

  Widget _buildActionDetails(BuildContext context, ThemeData theme, MessageIndex email, bool isOverdue) {
    if (!email.hasAction) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lightbulb_outline,
              size: 12,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 4),
            Text(
              'No action',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                fontStyle: FontStyle.italic,
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
    }

    final actionText = email.actionInsightText ?? '';
    final isComplete = email.actionComplete;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isOverdue
            ? Colors.red.shade50
            : (isComplete ? Colors.green.shade50 : Colors.orange.shade50),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isOverdue
              ? Colors.red.shade300
              : (isComplete ? Colors.green.shade300 : Colors.orange.shade300),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lightbulb,
                size: 12,
                color: isOverdue
                    ? Colors.red.shade700
                    : (isComplete ? Colors.green.shade700 : Colors.orange.shade700),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: isOverdue
                      ? Colors.red.shade200
                      : (isComplete ? Colors.green.shade200 : Colors.orange.shade200),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  isOverdue
                      ? 'OVERDUE'
                      : (isComplete ? 'COMPLETE' : 'ACTION'),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: isOverdue
                        ? Colors.red.shade900
                        : (isComplete ? Colors.green.shade900 : Colors.orange.shade900),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          if (actionText.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              actionText,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: isOverdue
                    ? Colors.red.shade900
                    : (isComplete ? Colors.green.shade900 : Colors.orange.shade900),
                fontSize: 10,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (email.actionDate != null) ...[
            const SizedBox(height: 3),
            Text(
              _formatActionDate(email.actionDate!, DateTime.now()),
              style: theme.textTheme.labelSmall?.copyWith(
                color: isOverdue
                    ? Colors.red.shade700
                    : (isComplete ? Colors.green.shade700 : Colors.orange.shade700),
                fontWeight: FontWeight.w600,
                fontSize: 9,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusButtons(BuildContext context, ThemeData theme, MessageIndex email) {
    final isPersonal = email.localTagPersonal == 'Personal';
    final isBusiness = email.localTagPersonal == 'Business';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Personal/Business switch
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: 'Personal',
                child: InkWell(
                  onTap: () {
                    // Match TileView behavior: tap same value to toggle off
                    // If Personal is selected, deselect (set to null)
                    // Otherwise, set to Personal
                    final newValue = isPersonal ? null : 'Personal';
                    // Create a temporary email with the new value to pass to callback
                    // copyWith doesn't handle null correctly, so manually construct when null
                    final updatedEmail = newValue == null
                        ? MessageIndex(
                            id: email.id,
                            threadId: email.threadId,
                            accountId: email.accountId,
                            accountEmail: email.accountEmail,
                            historyId: email.historyId,
                            internalDate: email.internalDate,
                            from: email.from,
                            to: email.to,
                            subject: email.subject,
                            snippet: email.snippet,
                            hasAttachments: email.hasAttachments,
                            gmailCategories: email.gmailCategories,
                            gmailSmartLabels: email.gmailSmartLabels,
                            localTagPersonal: null, // Explicitly set to null
                            subsLocal: email.subsLocal,
                            shoppingLocal: email.shoppingLocal,
                            unsubscribedLocal: email.unsubscribedLocal,
                            actionDate: email.actionDate,
                            actionConfidence: email.actionConfidence,
                            actionInsightText: email.actionInsightText,
                            actionComplete: email.actionComplete,
                            hasAction: email.hasAction,
                            isRead: email.isRead,
                            isStarred: email.isStarred,
                            isImportant: email.isImportant,
                            folderLabel: email.folderLabel,
                            prevFolderLabel: email.prevFolderLabel,
                          )
                        : email.copyWith(localTagPersonal: newValue);
                    widget.onPersonalBusinessToggle?.call(updatedEmail);
                  },
                  borderRadius: BorderRadius.circular(15),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      gradient: isPersonal
                          ? LinearGradient(
                              colors: [
                                Colors.blue.shade600,
                                Colors.blue.shade400,
                              ],
                            )
                          : null,
                      color: isPersonal ? null : Colors.transparent,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      Icons.person,
                      size: 14,
                      color: isPersonal
                          ? Colors.white
                          : Colors.blue.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
              Tooltip(
                message: 'Business',
                child: InkWell(
                  onTap: () {
                    // Match TileView behavior: tap same value to toggle off
                    // If Business is selected, deselect (set to null)
                    // Otherwise, set to Business
                    final newValue = isBusiness ? null : 'Business';
                    // copyWith doesn't handle null correctly, so manually construct when null
                    final updatedEmail = newValue == null
                        ? MessageIndex(
                            id: email.id,
                            threadId: email.threadId,
                            accountId: email.accountId,
                            accountEmail: email.accountEmail,
                            historyId: email.historyId,
                            internalDate: email.internalDate,
                            from: email.from,
                            to: email.to,
                            subject: email.subject,
                            snippet: email.snippet,
                            hasAttachments: email.hasAttachments,
                            gmailCategories: email.gmailCategories,
                            gmailSmartLabels: email.gmailSmartLabels,
                            localTagPersonal: null, // Explicitly set to null
                            subsLocal: email.subsLocal,
                            shoppingLocal: email.shoppingLocal,
                            unsubscribedLocal: email.unsubscribedLocal,
                            actionDate: email.actionDate,
                            actionConfidence: email.actionConfidence,
                            actionInsightText: email.actionInsightText,
                            actionComplete: email.actionComplete,
                            hasAction: email.hasAction,
                            isRead: email.isRead,
                            isStarred: email.isStarred,
                            isImportant: email.isImportant,
                            folderLabel: email.folderLabel,
                            prevFolderLabel: email.prevFolderLabel,
                          )
                        : email.copyWith(localTagPersonal: newValue);
                    widget.onPersonalBusinessToggle?.call(updatedEmail);
                  },
                  borderRadius: BorderRadius.circular(15),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      gradient: isBusiness
                          ? LinearGradient(
                              colors: [
                                Colors.purple.shade600,
                                Colors.purple.shade400,
                              ],
                            )
                          : null,
                      color: isBusiness ? null : Colors.transparent,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      Icons.business_center,
                      size: 14,
                      color: isBusiness
                          ? Colors.white
                          : Colors.purple.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        
        // Star toggle
        Tooltip(
          message: email.isStarred ? 'Unstar' : 'Star',
          child: IconButton(
            icon: Icon(
              email.isStarred ? Icons.star : Icons.star_border,
              size: 16,
              color: email.isStarred
                  ? Colors.amber.shade700
                  : theme.colorScheme.onSurfaceVariant,
            ),
            onPressed: () => widget.onStarToggle?.call(email),
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ),
        const SizedBox(width: 2),
        
        // Move to local folder
        Tooltip(
          message: 'Move to local folder',
          child: IconButton(
            icon: Icon(
              Icons.folder_outlined,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            onPressed: () => widget.onMoveToLocalFolder?.call(email),
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ),
        const SizedBox(width: 2),
        
        // Archive
        Tooltip(
          message: 'Archive',
          child: IconButton(
            icon: Icon(
              Icons.archive_outlined,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            onPressed: () => widget.onArchive?.call(email),
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ),
        const SizedBox(width: 2),
        
        // Trash
        Tooltip(
          message: 'Trash',
          child: IconButton(
            icon: Icon(
              Icons.delete_outline,
              size: 16,
              color: theme.colorScheme.error,
            ),
            onPressed: () => widget.onTrash?.call(email),
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date, DateTime now) {
    final localDate = date.toLocal();
    final localNow = now.toLocal();
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final targetDay = DateTime(localDate.year, localDate.month, localDate.day);
    final daysDiff = today.difference(targetDay).inDays;

    if (daysDiff == 0) {
      return DateFormat('h:mm a').format(localDate).replaceAll('AM', 'am').replaceAll('PM', 'pm');
    } else if (daysDiff == 1) {
      return 'Yesterday';
    } else if (daysDiff < 7) {
      return DateFormat('EEE').format(localDate);
    } else {
      return DateFormat('MMM d').format(localDate);
    }
  }

  String _formatActionDate(DateTime date, DateTime now) {
    final localDate = date.toLocal();
    final localNow = now.toLocal();
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final targetDay = DateTime(localDate.year, localDate.month, localDate.day);
    final daysDiff = today.difference(targetDay).inDays;

    if (daysDiff == 0) {
      return 'Today';
    } else if (daysDiff == 1) {
      return 'Tomorrow';
    } else if (daysDiff == -1) {
      return 'Yesterday';
    } else if (daysDiff > 0 && daysDiff < 7) {
      return 'In $daysDiff days';
    } else if (daysDiff < 0 && daysDiff > -7) {
      return '${-daysDiff} days ago';
    } else {
      return DateFormat('MMM d, yyyy').format(localDate);
    }
  }
}
