import 'dart:convert';
import 'package:domail/constants/app_constants.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:domail/data/models/message_index.dart';
import 'package:intl/intl.dart';
import 'package:domail/app/theme/actionmail_theme.dart';
import 'package:domail/features/home/presentation/widgets/domain_icon.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final ValueChanged<MessageIndex>? onActionCompleteToggle;
  final ValueChanged<MessageIndex>? onStarToggle;
  final ValueChanged<MessageIndex>? onTrash;
  final ValueChanged<MessageIndex>? onArchive;
  final ValueChanged<MessageIndex>? onMoveToLocalFolder;
  final ValueChanged<MessageIndex>? onRestore;
  final ValueChanged<MessageIndex>? onMoveToInbox;
  final ValueChanged<String?>? onAccountChanged;
  final VoidCallback? onToggleLocalFolderView;
  final ValueChanged<int>? onSelectionChanged;
  final ValueChanged<Set<String>>? onSelectedIdsChanged;
  final Set<String>? selectedEmailIds; // External control of selection - if provided, overrides internal state
  final Future<void> Function(String folderPath)? onLocalFolderSelected; // Callback for local folder selection

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
    this.onActionCompleteToggle,
    this.onStarToggle,
    this.onTrash,
    this.onArchive,
    this.onMoveToLocalFolder,
    this.onRestore,
    this.onMoveToInbox,
    this.onAccountChanged,
    this.onToggleLocalFolderView,
    this.onSelectionChanged,
    this.onSelectedIdsChanged,
    this.selectedEmailIds,
    this.onLocalFolderSelected,
  });

  @override
  State<GridEmailList> createState() => _GridEmailListState();
}

/// Configuration for status buttons based on folder
class _StatusButtonConfig {
  final bool showPersonalBusiness;
  final bool showStar;
  final bool showMove;
  final bool showArchive;
  final bool showTrash;
  final String moveLabel;
  final String moveTooltip;

  const _StatusButtonConfig({
    required this.showPersonalBusiness,
    required this.showStar,
    required this.showMove,
    required this.showArchive,
    required this.showTrash,
    required this.moveLabel,
    required this.moveTooltip,
  });
}

class _GridEmailListState extends State<GridEmailList> {
  final Set<String> _selectedEmailIds = {};
  bool _isCtrlPressed = false;
  bool _showSearchField = false;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _horizontalScrollController = ScrollController();
  
  // Column width state - column index -> width
  // Columns: 0=checkbox, 1=date, 2=sender, 3=subject (flexible), 4=action, 5=status
  Map<int, double> _columnWidths = {};
  bool _columnWidthsLoaded = false;
  static const String _prefsKeyColumnWidths = 'table_view_column_widths';
  static const double _minColumnWidth = 75.0;
  
  // Drag state for column resizing
  double? _resizeStartX;
  double? _resizeStartWidth;
  int? _resizingColumnIndex;
  
  // Default column widths
  static const double _defaultCheckboxWidth = 30.0;
  static const double _defaultDateWidth = 70.0;
  static const double _defaultSenderWidth = 200.0;
  static const double _defaultSubjectWidth = 300.0; // Subject column default width
  static const double _defaultActionDetailsWidth = 250.0;
  static const double _defaultStatusWidth = 172.0; // Will be overridden by IntrinsicColumnWidth, but used for calculations

  // Get current selection - use external if provided, otherwise use internal
  Set<String> get _currentSelectedIds {
    if (widget.selectedEmailIds != null) {
      return widget.selectedEmailIds!;
    }
    return _selectedEmailIds;
  }

  @override
  void initState() {
    super.initState();
    _loadColumnWidths();
  }

  Future<void> _loadColumnWidths() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKeyColumnWidths);
    if (saved != null) {
      try {
        final Map<String, dynamic> decoded = Map<String, dynamic>.from(
          (jsonDecode(saved) as Map).map((k, v) => MapEntry(k.toString(), v)),
        );
        setState(() {
          _columnWidths = decoded.map((k, v) => MapEntry(int.parse(k), (v as num).toDouble()));
          _columnWidthsLoaded = true;
        });
      } catch (e) {
        // If parsing fails, use defaults
        _initializeDefaultColumnWidths();
      }
    } else {
      _initializeDefaultColumnWidths();
    }
  }

  void _initializeDefaultColumnWidths() {
    setState(() {
      _columnWidths = {
        0: _defaultCheckboxWidth,
        1: _defaultDateWidth,
        2: _defaultSenderWidth,
        4: _defaultActionDetailsWidth,
        5: _defaultStatusWidth,
      };
      _columnWidthsLoaded = true;
    });
  }

  Future<void> _saveColumnWidths() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_columnWidths.map((k, v) => MapEntry(k.toString(), v)));
    await prefs.setString(_prefsKeyColumnWidths, encoded);
  }

  double _getColumnWidth(int columnIndex, double defaultWidth) {
    return _columnWidths[columnIndex] ?? defaultWidth;
  }

  void _updateColumnWidth(int columnIndex, double newWidth) {
    setState(() {
      _columnWidths[columnIndex] = newWidth.clamp(_minColumnWidth, double.infinity);
    });
    _saveColumnWidths();
  }

  @override
  void didUpdateWidget(GridEmailList oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Force rebuild if emails list changed (to catch actionComplete updates)
    if (widget.emails.length != oldWidget.emails.length ||
        widget.emails.any((email) {
          final oldEmail = oldWidget.emails.firstWhere(
            (e) => e.id == email.id,
            orElse: () => email,
          );
          return email.actionComplete != oldEmail.actionComplete ||
                 email.actionInsightText != oldEmail.actionInsightText ||
                 email.actionDate != oldEmail.actionDate;
        })) {
      // Emails changed - force rebuild
      setState(() {});
    }
    
    // Sync internal selection with external when external selection changes
    if (widget.selectedEmailIds != null) {
      final oldSet = oldWidget.selectedEmailIds;
      final newSet = widget.selectedEmailIds!;
      
      // Check if sets are different by comparing contents
      final setsAreDifferent = oldSet == null || 
          oldSet.length != newSet.length ||
          !oldSet.every((id) => newSet.contains(id));
      
      if (setsAreDifferent) {
        // Check if external selection was cleared (was non-empty, now empty)
        final wasNonEmpty = oldSet != null && oldSet.isNotEmpty;
        final isNowEmpty = newSet.isEmpty;
        
        if (wasNonEmpty && isNowEmpty) {
          // External selection was cleared after bulk action - clear internal selection
          setState(() {
            _selectedEmailIds.clear();
          });
        } else if (newSet.isNotEmpty) {
          // External selection was set or changed - sync with it
          if (_selectedEmailIds.length != newSet.length || 
              !_selectedEmailIds.every((id) => newSet.contains(id))) {
            setState(() {
              _selectedEmailIds.clear();
              _selectedEmailIds.addAll(newSet);
            });
          }
        } else if (isNowEmpty && _selectedEmailIds.isNotEmpty) {
          // External selection is empty and we have internal selection - clear it
          setState(() {
            _selectedEmailIds.clear();
          });
        }
      }
    }
  }

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
                  AppConstants.filterToday,
                  'action_today',
                  widget.activeFilters.contains('action_today'),
                  Colors.cyan,
                ),
                _buildFilterChipIconOnly(
                  context,
                  Icons.schedule,
                  AppConstants.filterUpcoming,
                  'action_upcoming',
                  widget.activeFilters.contains('action_upcoming'),
                  Colors.indigo,
                ),
                _buildFilterChipIconOnly(
                  context,
                  Icons.warning,
                  AppConstants.filterOverdue,
                  'action_overdue',
                  widget.activeFilters.contains('action_overdue'),
                  Colors.red,
                ),
                _buildFilterChipIconOnly(
                  context,
                  Icons.help_outline,
                  AppConstants.filterPossible,
                  'action_possible',
                  widget.activeFilters.contains('action_possible'),
                  Colors.deepPurple,
                ),
              ],
            ),
          ),
          
          // Bulk action buttons on the right
          if (_currentSelectedIds.isNotEmpty)
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
    final config = _getStatusButtonConfig(widget.selectedFolder);
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
            '${_currentSelectedIds.length}',
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
          config.showPersonalBusiness ? () => _applyBulkAction('personal') : null,
          enabled: config.showPersonalBusiness,
        ),
        _buildBulkActionButton(
          context,
          theme,
          Icons.business_center,
          'Business',
          config.showPersonalBusiness ? () => _applyBulkAction('business') : null,
          enabled: config.showPersonalBusiness,
        ),
        _buildBulkActionButton(
          context,
          theme,
          Icons.star,
          'Star',
          config.showStar ? () => _applyBulkAction('star') : null,
          enabled: config.showStar,
        ),
        _buildBulkActionButton(
          context,
          theme,
          Icons.folder_outlined,
          config.moveTooltip,
          config.showMove ? () => _applyBulkAction('move') : null,
          enabled: config.showMove,
        ),
        _buildBulkActionButton(
          context,
          theme,
          Icons.archive_outlined,
          'Archive',
          config.showArchive ? () => _applyBulkAction('archive') : null,
          enabled: config.showArchive,
        ),
        _buildBulkActionButton(
          context,
          theme,
          Icons.delete_outline,
          'Trash',
          config.showTrash ? () => _applyBulkAction('trash') : null,
          enabled: config.showTrash,
        ),
      ],
    );
  }

  Widget _buildBulkActionButton(
    BuildContext context,
    ThemeData theme,
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    bool enabled = true,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 16),
        onPressed: onPressed,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        color: enabled
            ? theme.colorScheme.primary
            : theme.colorScheme.primary.withValues(alpha: 0.3),
      ),
    );
  }

  Future<void> _applyBulkAction(String action) async {
    final selectedEmails = widget.emails
        .where((e) => _currentSelectedIds.contains(e.id))
        .toList();

    // Show confirmation dialog for archive and trash
    if (action == 'archive' || action == 'trash') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(action == 'archive' ? 'Archive Emails' : 'Trash Emails'),
          content: Text(
            action == 'archive'
                ? 'Are you sure you want to archive ${selectedEmails.length} email${selectedEmails.length == 1 ? '' : 's'}?'
                : 'Are you sure you want to move ${selectedEmails.length} email${selectedEmails.length == 1 ? '' : 's'} to trash?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: action == 'trash'
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(ctx).colorScheme.error,
                      foregroundColor: Theme.of(ctx).colorScheme.onError,
                    )
                  : null,
              child: Text(action == 'archive' ? 'Archive' : 'Trash'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

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
          // Determine which callback to use based on folder
          final upperFolder = widget.selectedFolder.toUpperCase();
          if (upperFolder == 'SPAM') {
            // Spam: Move to Inbox
            widget.onMoveToInbox?.call(email);
          } else if (upperFolder == 'TRASH' || upperFolder == 'ARCHIVE') {
            // Trash/Archive: Restore
            widget.onRestore?.call(email);
          } else {
            // Default: Move to local folder
            widget.onMoveToLocalFolder?.call(email);
          }
          break;
      }
    }

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

    // Wait for column widths to load before building table
    if (!_columnWidthsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Detect small screen for compact layout
        final isSmallScreen = MediaQuery.of(context).size.width < 1200;
        
        // Get column widths from saved preferences or use defaults
        final checkboxWidth = _getColumnWidth(0, _defaultCheckboxWidth);
        final dateWidth = _getColumnWidth(1, _defaultDateWidth);
        final senderWidth = _getColumnWidth(2, _defaultSenderWidth);
        final subjectWidth = _getColumnWidth(3, _defaultSubjectWidth); // Subject is now resizable
        final actionDetailsWidth = _getColumnWidth(4, _defaultActionDetailsWidth);
        // Status width to accommodate all status buttons (Personal/Business switch + 4 icon buttons)
        // Using IntrinsicColumnWidth to automatically size based on content
        // This adapts to ~172px on large screens and ~280px on mobile (where IconButtons need 48px tap targets)
        // 
        // TO REVERT: Replace IntrinsicColumnWidth() with FixedColumnWidth(statusWidth) below
        // and uncomment the statusWidth calculation:
        // final statusWidth = isSmallScreen ? 280.0 : 172.0;
        // final fixedColumnsWidth = checkboxWidth + dateWidth + senderWidth + subjectWidth + actionDetailsWidth + statusWidth;
        
        // Estimate status width for calculations (actual will be determined by IntrinsicColumnWidth at layout time)
        // Status width varies: ~172px on large screens, ~280px on mobile (IconButton tap targets)
        final estimatedStatusWidth = isSmallScreen ? 280.0 : 172.0;
        
        // Calculate fixed columns width (subject is now fixed/resizable, status is flexible)
        final fixedColumnsWidth = checkboxWidth + dateWidth + senderWidth + subjectWidth + actionDetailsWidth;
        final totalMinWidth = fixedColumnsWidth + estimatedStatusWidth;
        
        // Calculate available width - account for horizontal padding (16 * 2 = 32)
        final hasValidConstraints = constraints.maxWidth.isFinite && 
                                    constraints.maxWidth > 0;
        
        // Calculate available width from constraints, accounting for padding
        final availableWidth = hasValidConstraints 
            ? constraints.maxWidth - 32.0  // Account for horizontal padding
            : totalMinWidth;
        
        // Calculate actual table width from all column widths
        // Note: With IntrinsicColumnWidth for status, the actual status width will be determined at layout time
        final actualTableWidth = checkboxWidth + 
            dateWidth + 
            senderWidth + 
            subjectWidth + 
            actionDetailsWidth + 
            estimatedStatusWidth; // Estimated - actual will be determined by IntrinsicColumnWidth
        
        // Determine if table exceeds available width and needs scrolling
        // Compare with small tolerance for floating point precision
        final needsScrolling = (actualTableWidth - availableWidth) > 0.5;
        
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), // Add horizontal and bottom padding
          child: ClipRect(
            child: SizedBox(
              width: availableWidth,
              child: Scrollbar(
                controller: _horizontalScrollController,
                thumbVisibility: needsScrolling, // Show scrollbar only when content overflows
                thickness: 12.0, // Make scrollbar thicker for easier clicking
                radius: const Radius.circular(6.0), // Rounded corners
                child: SingleChildScrollView(
                  controller: _horizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: needsScrolling
                      ? const ClampingScrollPhysics() // Allow scrolling when content overflows
                      : const NeverScrollableScrollPhysics(), // Disable scrolling when table fits
                  clipBehavior: Clip.hardEdge, // Clip content to prevent overflow indicator
                  child: SizedBox(
                    width: actualTableWidth, // Use actual table width - will exceed available width when screen is small
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: Table(
                        // Key ensures table rebuilds when emails change (especially actionComplete)
                        key: ValueKey('email_table_${widget.emails.length}_${widget.emails.fold<int>(0, (sum, e) => sum ^ (e.id.hashCode ^ (e.actionComplete ? 1 : 0)))}'),
                        columnWidths: {
                          0: FixedColumnWidth(checkboxWidth),
                          1: FixedColumnWidth(dateWidth),
                          2: FixedColumnWidth(senderWidth),
                          3: FixedColumnWidth(subjectWidth), // Subject & Snippet - now resizable
                          4: FixedColumnWidth(actionDetailsWidth), // Action Details - not resizable
                          5: IntrinsicColumnWidth(), // Status column - flexible width based on content (not resizable)
                          // TO REVERT: Change above line to: 5: FixedColumnWidth(statusWidth),
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
                                child: _buildResizableHeaderCell(
                                  context: context,
                                  theme: theme,
                                  label: 'Date',
                                  columnIndex: 1,
                                  currentWidth: dateWidth,
                                ),
                              ),
                              TableCell(
                                child: _buildResizableHeaderCell(
                                  context: context,
                                  theme: theme,
                                  label: widget.selectedFolder == AppConstants.folderSent ? 'To' : 'Sender',
                                  columnIndex: 2,
                                  currentWidth: senderWidth,
                                ),
                              ),
                              TableCell(
                                child: _buildResizableHeaderCell(
                                  context: context,
                                  theme: theme,
                                  label: 'Subject & Snippet',
                                  columnIndex: 3,
                                  currentWidth: subjectWidth,
                                ),
                              ),
                              TableCell(
                                child: _buildResizableHeaderCell(
                                  context: context,
                                  theme: theme,
                                  label: 'Action Details',
                                  columnIndex: 4,
                                  currentWidth: actionDetailsWidth,
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
            ),
          ),
        );
      },
    );
  }

  Widget _buildResizableHeaderCell({
    required BuildContext context,
    required ThemeData theme,
    required String label,
    required int columnIndex,
    required double currentWidth,
  }) {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // Drag handle on the right edge
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              onPanStart: (details) {
                setState(() {
                  _resizeStartX = details.globalPosition.dx;
                  _resizeStartWidth = currentWidth;
                  _resizingColumnIndex = columnIndex;
                });
              },
              onPanUpdate: (details) {
                if (_resizeStartX != null && _resizeStartWidth != null && _resizingColumnIndex == columnIndex) {
                  final delta = details.globalPosition.dx - _resizeStartX!;
                  final newWidth = (_resizeStartWidth! + delta).clamp(_minColumnWidth, double.infinity);
                  _updateColumnWidth(columnIndex, newWidth);
                }
              },
              onPanEnd: (_) {
                setState(() {
                  _resizeStartX = null;
                  _resizeStartWidth = null;
                  _resizingColumnIndex = null;
                });
              },
              child: Container(
                width: 4,
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectAllCheckbox(BuildContext context, ThemeData theme) {
    final allSelected = widget.emails.isNotEmpty && 
        _currentSelectedIds.length == widget.emails.length;
    final someSelected = _currentSelectedIds.isNotEmpty && !allSelected;

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

    // Check if we're in SENT folder
    final isSentFolder = widget.selectedFolder == AppConstants.folderSent;
    
    // Extract sender/recipient name and email
    String senderName = '';
    String senderEmail = '';
    List<String> allRecipients = [];
    
    if (isSentFolder) {
      // Parse all recipients from the "to" field
      final recipients = _parseAddressList(email.to);
      allRecipients = recipients.map((r) => r.name.isNotEmpty ? r.name : r.email).toList();
      if (recipients.isNotEmpty) {
        senderName = recipients.first.name.isNotEmpty ? recipients.first.name : '';
        senderEmail = recipients.first.email.isNotEmpty ? recipients.first.email : email.to;
      } else {
        senderEmail = email.to;
      }
    } else {
      // Extract sender from "from" field
      final fromMatch = RegExp(r'^(.+?)\s*<(.+?)>$').firstMatch(email.from);
      senderName = fromMatch?.group(1)?.trim() ?? '';
      senderEmail = fromMatch?.group(2)?.trim() ?? email.from;
    }

    final iconEmail = senderEmail.isNotEmpty
        ? senderEmail
        : (isSentFolder ? email.to : email.from);

    // Determine row background color
    final rowColor = email.isRead
        ? theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.3)
        : theme.colorScheme.surface;

    final isSelected = _currentSelectedIds.contains(email.id);
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
                        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DomainIcon(email: iconEmail),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isSentFolder && allRecipients.isNotEmpty
                              ? allRecipients.join(', ')
                              : (senderName.isNotEmpty ? senderName : senderEmail),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: email.isRead ? FontWeight.normal : FontWeight.w600,
                            fontSize: 12,
                          ),
                          maxLines: isSentFolder && allRecipients.length > 1 ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (!isSentFolder && senderName.isNotEmpty) ...[
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
              child: KeyedSubtree(
                key: ValueKey('action_${email.id}_${email.actionComplete}'),
                child: _buildActionDetails(context, theme, email, isOverdue),
              ),
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

    // Check if we're in SENT folder
    final isSentFolder = widget.selectedFolder == AppConstants.folderSent;
    
    // Extract sender/recipient name and email
    String senderName = '';
    String senderEmail = '';
    List<String> allRecipients = [];
    
    if (isSentFolder) {
      // Parse all recipients from the "to" field
      final recipients = _parseAddressList(email.to);
      allRecipients = recipients.map((r) => r.name.isNotEmpty ? r.name : r.email).toList();
      if (recipients.isNotEmpty) {
        senderName = recipients.first.name.isNotEmpty ? recipients.first.name : '';
        senderEmail = recipients.first.email.isNotEmpty ? recipients.first.email : email.to;
      } else {
        senderEmail = email.to;
      }
    } else {
      // Extract sender from "from" field
      final fromMatch = RegExp(r'^(.+?)\s*<(.+?)>$').firstMatch(email.from);
      senderName = fromMatch?.group(1)?.trim() ?? '';
      senderEmail = fromMatch?.group(2)?.trim() ?? email.from;
    }

    final iconEmail = senderEmail.isNotEmpty
        ? senderEmail
        : (isSentFolder ? email.to : email.from);

    // Determine row background color
    final rowColor = email.isRead
        ? theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.3)
        : theme.colorScheme.surface;

    final isSelected = _currentSelectedIds.contains(email.id);

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
            child: Center(
              child: Container(
                // Minimum 48x48 tap target on small screens for accessibility
                width: MediaQuery.of(context).size.width < 1200 ? 48.0 : 18.0,
                height: MediaQuery.of(context).size.width < 1200 ? 48.0 : 18.0,
                alignment: Alignment.center,
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

        // Sender/To column
        DataCell(
          GestureDetector(
            onTap: () => widget.onEmailTap?.call(email),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DomainIcon(email: iconEmail),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        isSentFolder && allRecipients.isNotEmpty
                            ? allRecipients.join(', ')
                            : (senderName.isNotEmpty ? senderName : senderEmail),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: email.isRead ? FontWeight.normal : FontWeight.w600,
                          fontSize: 12,
                        ),
                        maxLines: isSentFolder && allRecipients.length > 1 ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (!isSentFolder && senderName.isNotEmpty) ...[
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
    if (kDebugMode) {
      debugPrint('[GRID_ACTION_BUILD] messageId=${email.id}, hasAction=${email.hasAction}, actionComplete=${email.actionComplete}, actionText=${email.actionInsightText}');
    }
    
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
    
    if (kDebugMode && email.hasAction) {
      debugPrint('[GRID_ACTION] messageId=${email.id}, actionComplete=$isComplete, actionText=$actionText');
    }

    // Priority: Complete > Overdue > Action
    // If complete, show COMPLETE even if overdue
    final displayStatus = isComplete ? 'COMPLETE' : (isOverdue ? 'OVERDUE' : 'ACTION');
    final statusColor = isComplete 
        ? Colors.green 
        : (isOverdue ? Colors.red : Colors.orange);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: statusColor.shade300,
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
                color: statusColor.shade700,
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: statusColor.shade200,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  displayStatus,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: statusColor.shade900,
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
                color: statusColor.shade900,
                fontSize: 10,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (email.actionDate != null) ...[
            const SizedBox(height: 3),
            RichText(
              text: TextSpan(
                style: theme.textTheme.labelSmall?.copyWith(
                  color: statusColor.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 9,
                ),
                children: [
                  // Date text
                  TextSpan(
                    text: _formatActionDate(email.actionDate!, DateTime.now()),
                  ),

                  // Dot separator
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text('•'),
                    ),
                  ),

                  // Clickable "Mark as ..." link
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          widget.onActionCompleteToggle?.call(email);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Text(
                            'Mark as ${isComplete ? 'Incomplete' : 'Complete'}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: statusColor.shade700,
                              fontWeight: FontWeight.w600,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          ],
        ],
      ),
    );
  }

  /// Configuration for status buttons based on folder
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
          moveLabel: 'Move to local folder',
          moveTooltip: 'Move to local folder',
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
          moveLabel: 'Move to local folder',
          moveTooltip: 'Move to local folder',
        );
    }
  }

  Widget _buildStatusButtons(BuildContext context, ThemeData theme, MessageIndex email) {
    final isPersonal = email.localTagPersonal == 'Personal';
    final isBusiness = email.localTagPersonal == 'Business';
    final config = _getStatusButtonConfig(widget.selectedFolder);
    final isSmallScreen = MediaQuery.of(context).size.width < 1200;
    final buttonPadding = isSmallScreen ? 1.0 : 2.0;
    final buttonConstraints = isSmallScreen 
        ? const BoxConstraints(minWidth: 20, minHeight: 20)
        : const BoxConstraints(minWidth: 24, minHeight: 24);
    final iconSize = isSmallScreen ? 14.0 : 16.0;
    final spacing = isSmallScreen ? 2.0 : 2.0; // Consistent spacing

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Personal/Business switch
        if (config.showPersonalBusiness)
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
        )
        else
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
                    onTap: null,
                    borderRadius: BorderRadius.circular(15),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.person,
                        size: 14,
                        color: Colors.blue.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Business',
                  child: InkWell(
                    onTap: null,
                    borderRadius: BorderRadius.circular(15),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.business_center,
                        size: 14,
                        color: Colors.purple.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        SizedBox(width: spacing),
        
        // Star toggle
        Tooltip(
          message: email.isStarred ? 'Unstar' : 'Star',
          child: IconButton(
            icon: Icon(
              email.isStarred ? Icons.star : Icons.star_border,
              size: iconSize,
              color: email.isStarred
                  ? Colors.amber.shade700
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: config.showStar ? 1.0 : 0.3),
            ),
            onPressed: config.showStar ? () => widget.onStarToggle?.call(email) : null,
            padding: EdgeInsets.all(buttonPadding),
            constraints: buttonConstraints,
          ),
        ),
        SizedBox(width: spacing),
        
        // Move/Restore button
        Tooltip(
          message: config.moveTooltip,
          child: IconButton(
            icon: Icon(
              Icons.folder_outlined,
              size: iconSize,
              color: theme.colorScheme.primary.withValues(alpha: config.showMove ? 1.0 : 0.3),
            ),
            onPressed: config.showMove
                ? () {
                    // Determine which callback to use based on folder
                    final upperFolder = widget.selectedFolder.toUpperCase();
                    if (upperFolder == 'SPAM') {
                      // Spam: Move to Inbox
                      widget.onMoveToInbox?.call(email);
                    } else if (upperFolder == 'TRASH' || upperFolder == 'ARCHIVE') {
                      // Trash/Archive: Restore
                      widget.onRestore?.call(email);
                    } else {
                      // Default: Move to local folder
                      widget.onMoveToLocalFolder?.call(email);
                    }
                  }
                : null,
            padding: EdgeInsets.all(buttonPadding),
            constraints: buttonConstraints,
          ),
        ),
        SizedBox(width: spacing),
        
        // Archive
        Tooltip(
          message: 'Archive',
          child: IconButton(
            icon: Icon(
              Icons.archive_outlined,
              size: iconSize,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: config.showArchive ? 1.0 : 0.3),
            ),
            onPressed: config.showArchive ? () => widget.onArchive?.call(email) : null,
            padding: EdgeInsets.all(buttonPadding),
            constraints: buttonConstraints,
          ),
        ),
        SizedBox(width: spacing),
        
        // Trash
        Tooltip(
          message: 'Trash',
          child: IconButton(
            icon: Icon(
              Icons.delete_outline,
              size: iconSize,
              color: theme.colorScheme.error.withValues(alpha: config.showTrash ? 1.0 : 0.3),
            ),
            onPressed: config.showTrash ? () => widget.onTrash?.call(email) : null,
            padding: EdgeInsets.all(buttonPadding),
            constraints: buttonConstraints,
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
    } else if (daysDiff == -1) {
      return 'Tomorrow';
    } else if (daysDiff == 1) {
      return 'Yesterday';
    } else if (daysDiff < -1 && daysDiff > -7) {
      // Future dates within a week - show actual date
      return DateFormat('MMM d').format(localDate);
    } else if (daysDiff > 1 && daysDiff < 7) {
      // Past dates within a week - show "X days ago"
      return '$daysDiff days ago';
    } else {
      // Dates beyond a week - show formatted date
      return DateFormat('MMM d, yyyy').format(localDate);
    }
  }

  // Parse address list from comma-separated string (handles names with emails)
  List<({String name, String email})> _parseAddressList(String addresses) {
    final results = <({String name, String email})>[];
    final parts = addresses.split(RegExp(r',(?![^<]*>)')); // Split on commas not inside < >
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final parsed = _parseSingleAddress(trimmed);
      if (parsed.name.isEmpty && parsed.email.isEmpty) continue;
      results.add(parsed);
    }
    if (results.isEmpty) {
      final parsed = _parseSingleAddress(addresses);
      if (parsed.name.isNotEmpty || parsed.email.isNotEmpty) {
        results.add(parsed);
      }
    }
    return results;
  }

  // Parse single address (handles both "Name <email>" and "email" formats)
  ({String name, String email}) _parseSingleAddress(String input) {
    final emailRegex = RegExp(r'<([^>]+)>');
    final match = emailRegex.firstMatch(input);
    if (match != null) {
      final email = match.group(1)!.trim();
      final name = input.replaceAll(match.group(0)!, '').trim();
      return (name: name.replaceAll('"', ''), email: email);
    }
    final trimmed = input.trim();
    if (trimmed.contains('@')) {
      return (name: '', email: trimmed);
    }
    return (name: trimmed, email: trimmed);
  }
}

