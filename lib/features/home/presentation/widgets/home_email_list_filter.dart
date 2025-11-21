import 'package:domail/data/models/message_index.dart';
import 'package:domail/constants/app_constants.dart';

/// Helper class for filtering emails based on various criteria
class HomeEmailListFilter {
  /// Filter emails based on all active filters
  static List<MessageIndex> filterEmails({
    required List<MessageIndex> emails,
    String? selectedLocalState,
    String? stateFilter,
    Set<String> selectedCategories = const {},
    String? selectedActionFilter,
    String searchQuery = '',
  }) {
    return emails.where((m) {
      // Local state filter (null means no filter, Personal/Business means filter)
      if (selectedLocalState != null) {
        if (m.localTagPersonal != selectedLocalState) return false;
      }

      // Gmail category filter (AND across selected categories)
      if (selectedCategories.isNotEmpty) {
        final hasAny = m.gmailCategories.any((c) => selectedCategories.contains(c));
        if (!hasAny) return false;
      }

      // Email state single-select filter
      if (stateFilter != null) {
        switch (stateFilter) {
          case 'Unread':
            if (m.isRead) return false;
            break;
          case 'Starred':
            if (!m.isStarred) return false;
            break;
          case 'Important':
            if (!m.isImportant) return false;
            break;
        }
      }

      // Action summary filter
      if (selectedActionFilter != null) {
        // Only include messages that have an action
        if (!m.hasAction) return false;
        // Exclude completed actions
        if (m.actionComplete) return false;
        switch (selectedActionFilter) {
          case AppConstants.filterToday:
            if (m.actionDate == null) return false;
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final local = m.actionDate!.toLocal();
            final d = DateTime(local.year, local.month, local.day);
            if (d != today) return false;
            break;
          case AppConstants.filterUpcoming:
            if (m.actionDate == null) return false;
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final local = m.actionDate!.toLocal();
            final d = DateTime(local.year, local.month, local.day);
            if (!d.isAfter(today)) return false;
            break;
          case AppConstants.filterOverdue:
            if (m.actionDate == null) return false;
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final local = m.actionDate!.toLocal();
            final d = DateTime(local.year, local.month, local.day);
            if (!d.isBefore(today)) return false;
            break;
          case AppConstants.filterPossible:
            if (m.actionDate != null) return false;
            break;
        }
      }

      // Search filter
      if (searchQuery.isNotEmpty) {
        final query = searchQuery.toLowerCase();
        final matchesSubject = m.subject.toLowerCase().contains(query);
        final matchesFrom = m.from.toLowerCase().contains(query);
        final matchesTo = m.to.toLowerCase().contains(query);
        final matchesSnippet = (m.snippet ?? '').toLowerCase().contains(query);
        if (!matchesSubject && !matchesFrom && !matchesTo && !matchesSnippet) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  /// Build active filters set for GridEmailList
  static Set<String> buildActiveFilters({
    String? stateFilter,
    String? selectedLocalState,
    String? selectedActionFilter,
  }) {
    final activeFilters = <String>{};
    if (stateFilter == 'Unread') activeFilters.add('unread');
    if (stateFilter == 'Starred') activeFilters.add('starred');
    if (selectedLocalState == 'Personal') activeFilters.add('personal');
    if (selectedLocalState == 'Business') activeFilters.add('business');
    if (selectedActionFilter == AppConstants.filterToday) activeFilters.add('action_today');
    if (selectedActionFilter == AppConstants.filterUpcoming) activeFilters.add('action_upcoming');
    if (selectedActionFilter == AppConstants.filterOverdue) activeFilters.add('action_overdue');
    if (selectedActionFilter == AppConstants.filterPossible) activeFilters.add('action_possible');
    return activeFilters;
  }
}

