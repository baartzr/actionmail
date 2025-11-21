import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domail/features/home/domain/providers/email_list_provider.dart';
import 'package:domail/constants/app_constants.dart';
import 'package:domail/app/theme/actionmail_theme.dart';

/// Filter bar widget for home screen
/// Handles state filters (Unread, Starred, Important), category filter, and search
class HomeFilterBar extends ConsumerWidget {
  final String? stateFilter;
  final Set<String> selectedCategories;
  final bool showFilterBar;
  final bool showSearch;
  final String searchQuery;
  final TextEditingController searchController;
  final String? selectedActionFilter;
  final String? selectedLocalState;
  final bool isLocalFolder;
  final Function(String?) onStateFilterChanged;
  final Function(Set<String>) onCategoriesChanged;
  final Function(bool) onFilterBarToggled;
  final Function(bool) onSearchToggled;
  final Function(String) onSearchQueryChanged;
  final Function(String?) onActionFilterChanged;
  final Future<void> Function(List<String>) onMarkAllAsRead;

  const HomeFilterBar({
    super.key,
    required this.stateFilter,
    required this.selectedCategories,
    required this.showFilterBar,
    required this.showSearch,
    required this.searchQuery,
    required this.searchController,
    required this.selectedActionFilter,
    required this.selectedLocalState,
    required this.isLocalFolder,
    required this.onStateFilterChanged,
    required this.onCategoriesChanged,
    required this.onFilterBarToggled,
    required this.onSearchToggled,
    required this.onSearchQueryChanged,
    required this.onActionFilterChanged,
    required this.onMarkAllAsRead,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTopFilterRow(context, ref),
        if (showFilterBar) _buildFilterBar(context, ref),
        if (showFilterBar && showSearch) _buildSearchField(context),
      ],
    );
  }

  Widget _buildTopFilterRow(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.only(left: 8.0, right: 8.0, top: 6.0, bottom: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Action filter as text buttons
          Builder(
            builder: (context) {
              final emailsValue = ref.read(emailListProvider);
              int countToday = 0,
                  countUpcoming = 0,
                  countOverdue = 0,
                  countPossible = 0;
              emailsValue.whenData((emails) {
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                for (final m in emails) {
                  if (selectedLocalState != null &&
                      m.localTagPersonal != selectedLocalState) {
                    continue;
                  }
                  if (m.actionComplete) {
                    continue;
                  }
                  if (!m.hasAction) {
                    continue;
                  }
                  if (m.actionDate == null) {
                    countPossible++;
                    continue;
                  }
                  final local = m.actionDate!.toLocal();
                  final d = DateTime(local.year, local.month, local.day);
                  if (d == today) {
                    countToday++;
                  } else if (d.isAfter(today)) {
                    countUpcoming++;
                  } else {
                    countOverdue++;
                  }
                }
              });
              // Action filter as text buttons
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildActionFilterTextButton(
                      context, AppConstants.filterToday, countToday),
                  _buildActionFilterTextButton(
                      context, AppConstants.filterUpcoming, countUpcoming),
                  _buildActionFilterTextButton(
                      context, AppConstants.filterOverdue, countOverdue),
                  _buildActionFilterTextButton(
                      context, AppConstants.filterPossible, countPossible),
                ],
              );
            },
          ),
          const SizedBox(width: 16),
          // Filter toggle icon (subtle, sophisticated)
          IconButton(
            tooltip: 'Filters',
            icon: Icon(showFilterBar
                ? Icons.filter_list
                : Icons.filter_list_outlined),
            color: showFilterBar
                ? const Color(0xFF00695C) // Teal when active
                : Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.7),
            iconSize: 20,
            onPressed: () {
              onFilterBarToggled(!showFilterBar);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context, WidgetRef ref) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    return Container(
      padding: const EdgeInsets.only(left: 8.0, right: 8.0, top: 2.0, bottom: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // State filter buttons (Unread, Starred, Important) - sophisticated style
          _buildSophisticatedStateFilterButtons(context, ref),
          SizedBox(width: isDesktop ? 4 : 12),
          // Category filter button - sophisticated style
          _buildSophisticatedCategoryButton(context),
          SizedBox(width: isDesktop ? 4 : 12),
          // Search button - sophisticated style
          _buildSophisticatedSearchButton(context),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Center(
        child: SizedBox(
          width: 400,
          child: TextField(
            controller: searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search emails...',
              hintStyle: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  onSearchQueryChanged('');
                  searchController.clear();
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 13,
            ),
            onChanged: (value) {
              onSearchQueryChanged(value.toLowerCase().trim());
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSophisticatedStateFilterButtons(
      BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    // Get counts from the currently displayed email list (account + folder)
    // This reflects what's actually shown in the email list
    final emailListAsync = ref.watch(emailListProvider);

    // Calculate counts from the current email list
    final counts = emailListAsync.when(
      data: (emails) {
        // Count from emails in the current folder (already filtered by account and folder)
        return {
          'unread': emails.where((m) => !m.isRead).length,
          'starred': emails.where((m) => m.isStarred).length,
          'important': emails.where((m) => m.isImportant).length,
        };
      },
      loading: () => {'unread': 0, 'starred': 0, 'important': 0},
      error: (_, __) => {'unread': 0, 'starred': 0, 'important': 0},
    );

    final unreadCount = counts['unread']!;
    final starredCount = counts['starred']!;
    final importantCount = counts['important']!;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSophisticatedFilterButton(
            context,
            'Unread',
            Icons.mark_email_unread_outlined,
            Icons.mark_email_unread,
            stateFilter == 'Unread',
            unreadCount,
            () {
              onStateFilterChanged(stateFilter == 'Unread' ? null : 'Unread');
            },
          ),
          // Mark all as read button (only show when Unread filter is active)
          if (stateFilter == 'Unread') ...[
            SizedBox(width: isDesktop ? 2 : 12),
            _buildMarkAllAsReadButton(context, ref),
          ],
          SizedBox(width: isDesktop ? 2 : 12),
          _buildSophisticatedFilterButton(
            context,
            'Starred',
            Icons.star_border,
            Icons.star,
            stateFilter == 'Starred',
            starredCount,
            () {
              onStateFilterChanged(stateFilter == 'Starred' ? null : 'Starred');
            },
          ),
          SizedBox(width: isDesktop ? 2 : 12),
          _buildSophisticatedFilterButton(
            context,
            'Important',
            Icons.priority_high_outlined,
            Icons.priority_high,
            stateFilter == 'Important',
            importantCount,
            () {
              onStateFilterChanged(
                  stateFilter == 'Important' ? null : 'Important');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSophisticatedCategoryButton(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasCategories = selectedCategories.isNotEmpty;
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(2),
      child: Material(
        color: hasCategories
            ? ActionMailTheme.alertColor.withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _showCategoriesPopup(context),
          child: Container(
            padding: isDesktop
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
                : const EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    Icon(
                      hasCategories
                          ? Icons.filter_alt
                          : Icons.filter_alt_outlined,
                      size: 18,
                      color: hasCategories
                          ? ActionMailTheme.alertColor
                          : const Color(0xFF00897B), // Teal for categories
                    ),
                    if (hasCategories)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: ActionMailTheme.alertColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: ActionMailTheme.alertColor
                                    .withValues(alpha: 0.3),
                                width: 1),
                          ),
                        ),
                      ),
                  ],
                ),
                if (isDesktop) ...[
                  const SizedBox(width: 6),
                  Text(
                    'Categories',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: hasCategories
                          ? ActionMailTheme.alertColor
                          : cs.onSurfaceVariant,
                      fontWeight:
                          hasCategories ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMarkAllAsReadButton(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Get unread emails from the current list (reactive)
    final emailListAsync = ref.watch(emailListProvider);

    final unreadInfo = emailListAsync.when(
      data: (emails) {
        final unreadEmails = emails.where((m) => !m.isRead).toList();
        return {
          'count': unreadEmails.length,
          'ids': unreadEmails.map((m) => m.id).toList(),
        };
      },
      loading: () => {'count': 0, 'ids': <String>[]},
      error: (_, __) => {'count': 0, 'ids': <String>[]},
    );

    final unreadCount = unreadInfo['count'] as int;
    final unreadMessageIds = unreadInfo['ids'] as List<String>;
    final isEnabled = unreadCount > 0 && !isLocalFolder;

    return Tooltip(
      message: 'Mark all as Read',
      child: Material(
        color: isEnabled ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: isEnabled ? () => onMarkAllAsRead(unreadMessageIds) : null,
          child: Container(
            padding: const EdgeInsets.all(6),
            child: Icon(
              Icons.done_all,
              size: 18,
              color: isEnabled
                  ? cs.onPrimaryContainer
                  : cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSophisticatedSearchButton(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isSearchActive = showSearch;
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(2),
      child: Material(
        color: isSearchActive
            ? ActionMailTheme.alertColor.withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            onSearchToggled(!showSearch);
            if (!showSearch) {
              onSearchQueryChanged('');
              searchController.clear();
            }
          },
          child: Container(
            padding: isDesktop
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
                : const EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSearchActive ? Icons.search_off : Icons.search,
                  size: 18,
                  color: isSearchActive
                      ? ActionMailTheme.alertColor
                      : const Color(0xFF42A5F5), // Blue for search
                ),
                if (isDesktop) ...[
                  const SizedBox(width: 6),
                  Text(
                    'Search',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isSearchActive
                          ? ActionMailTheme.alertColor
                          : cs.onSurfaceVariant,
                      fontWeight:
                          isSearchActive ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSophisticatedFilterButton(
    BuildContext context,
    String label,
    IconData outlinedIcon,
    IconData filledIcon,
    bool selected,
    int count,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    // Assign colors based on filter type
    Color iconColor;
    if (selected) {
      iconColor = ActionMailTheme.alertColor;
    } else {
      switch (label) {
        case 'Unread':
          iconColor = const Color(0xFF2196F3); // Blue
          break;
        case 'Starred':
          iconColor = const Color(0xFFFFB300); // Amber/Yellow
          break;
        case 'Important':
          iconColor = const Color(0xFFE91E63); // Pink/Red
          break;
        default:
          iconColor = cs.onSurfaceVariant;
      }
    }

    // Tooltip text
    String tooltipText;
    switch (label) {
      case 'Starred':
        tooltipText = 'Emails you have Starred';
        break;
      case 'Important':
        tooltipText = 'Emails Google has flagged as Important';
        break;
      default:
        tooltipText = label;
    }
    if (count > 0) {
      tooltipText = '$tooltipText ($count)';
    }

    return Tooltip(
      message: tooltipText,
      child: Material(
        color: selected
            ? ActionMailTheme.alertColor.withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: isDesktop
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
                : const EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? filledIcon : outlinedIcon,
                  size: 18,
                  color: iconColor,
                ),
                if (isDesktop) ...[
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected
                          ? ActionMailTheme.alertColor
                          : cs.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: selected ? ActionMailTheme.alertColor : iconColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ] else if (count > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected ? ActionMailTheme.alertColor : iconColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionFilterTextButton(
      BuildContext context, String filter, int count) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = selectedActionFilter == filter;
    String label;
    String tooltipText;
    switch (filter) {
      case AppConstants.filterToday:
        label = AppConstants.actionSummaryToday;
        tooltipText = 'Actions due today';
        break;
      case AppConstants.filterUpcoming:
        label = 'Future';
        tooltipText = 'Upcoming actions';
        break;
      case AppConstants.filterOverdue:
        label = AppConstants.actionSummaryOverdue;
        tooltipText = 'Overdue actions';
        break;
      case AppConstants.filterPossible:
        label = AppConstants.filterPossible;
        tooltipText = 'Actions without a date';
        break;
      default:
        label = AppConstants.actionSummaryAll;
        tooltipText = label;
    }
    final displayText = '$label ($count)';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.0),
      child: Tooltip(
        message: tooltipText,
        child: InkWell(
          onTap: () {
            // Toggle: if already selected, deselect (null); otherwise select
            onActionFilterChanged(selectedActionFilter == filter ? null : filter);
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: selected
                ? BoxDecoration(
                    color: ActionMailTheme.alertColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  )
                : null,
            child: Text(
              displayText,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected ? ActionMailTheme.alertColor : cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showCategoriesPopup(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final currentSelections = Set<String>.from(selectedCategories);

    // Map categories to icons and colors
    final categoryConfig = <String, Map<String, dynamic>>{
      'categoryPersonal': {
        'icon': Icons.person_outline,
        'color': const Color(0xFF2196F3)
      },
      'categorySocial': {
        'icon': Icons.people_outline,
        'color': const Color(0xFF673AB7)
      },
      'categoryPromotions': {
        'icon': Icons.local_offer_outlined,
        'color': const Color(0xFFE91E63)
      },
      'categoryUpdates': {
        'icon': Icons.info_outline,
        'color': const Color(0xFF00BCD4)
      },
      'categoryForums': {
        'icon': Icons.forum_outlined,
        'color': const Color(0xFFFF9800)
      },
      'categoryBills': {
        'icon': Icons.receipt_long_outlined,
        'color': const Color(0xFF4CAF50)
      },
      'categoryPurchases': {
        'icon': Icons.shopping_bag_outlined,
        'color': const Color(0xFFFF5722)
      },
      'categoryFinance': {
        'icon': Icons.account_balance_outlined,
        'color': const Color(0xFF009688)
      },
      'categoryTravel': {
        'icon': Icons.flight_outlined,
        'color': const Color(0xFF03A9F4)
      },
      'categoryReceipts': {
        'icon': Icons.receipt_outlined,
        'color': const Color(0xFF795548)
      },
    };

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            return Container(
              width: 250,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Text(
                          'Categories',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          iconSize: 20,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Category list
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children:
                            AppConstants.allGmailCategories.map((category) {
                          final displayName =
                              AppConstants.categoryDisplayNames[category] ??
                                  category;
                          final isSelected =
                              currentSelections.contains(category);
                          final config = categoryConfig[category] ??
                              {
                                'icon': Icons.label_outline,
                                'color': cs.onSurfaceVariant
                              };
                          final icon = config['icon'] as IconData;
                          final color = config['color'] as Color;

                          return InkWell(
                            onTap: () {
                              setDialogState(() {
                                if (isSelected) {
                                  currentSelections.remove(category);
                                } else {
                                  currentSelections.add(category);
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? cs.primaryContainer.withValues(alpha: 0.3)
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    icon,
                                    size: 20,
                                    color: isSelected ? cs.primary : color,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      displayName,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: isSelected
                                            ? cs.onPrimaryContainer
                                            : null,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      Icons.check,
                                      size: 18,
                                      color: cs.primary,
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ).then((_) {
      // Apply selections when dialog closes
      onCategoriesChanged(currentSelections);
    });
  }
}

