import 'package:flutter/material.dart';
import 'package:domail/app/theme/actionmail_theme.dart';
import 'package:domail/constants/app_constants.dart';

/// Widget that displays active filter labels in a banner
class HomeFilterBanner extends StatelessWidget {
  final String? selectedLocalState;
  final String? selectedActionFilter;
  final String? stateFilter;
  final Set<String> selectedCategories;
  final String searchQuery;
  final TextEditingController searchController;
  final VoidCallback onClearFilters;

  const HomeFilterBanner({
    super.key,
    required this.selectedLocalState,
    required this.selectedActionFilter,
    required this.stateFilter,
    required this.selectedCategories,
    required this.searchQuery,
    required this.searchController,
    required this.onClearFilters,
  });

  List<String> _activeFilterLabels() {
    final labels = <String>[];

    if (selectedLocalState != null) {
      labels.add('${selectedLocalState!} Emails');
    }

    if (selectedActionFilter != null) {
      final actionLabel = () {
        switch (selectedActionFilter) {
          case AppConstants.filterToday:
            return AppConstants.actionSummaryToday;
          case AppConstants.filterUpcoming:
            return 'Future';
          case AppConstants.filterOverdue:
            return AppConstants.actionSummaryOverdue;
          case AppConstants.filterPossible:
            return AppConstants.filterPossible;
          default:
            return AppConstants.actionSummaryAll;
        }
      }();
      labels.add('Action: $actionLabel');
    }

    if (stateFilter != null) {
      labels.add(stateFilter!);
    }

    if (selectedCategories.isNotEmpty) {
      final names = selectedCategories
          .map((c) => AppConstants.categoryDisplayNames[c] ?? c)
          .join(', ');
      labels.add('Categories: $names');
    }

    if (searchQuery.isNotEmpty) {
      final raw = searchController.text.trim();
      if (raw.isNotEmpty) {
        labels.add('Search: "$raw"');
      } else {
        labels.add('Search filters applied');
      }
    }

    return labels;
  }

  @override
  Widget build(BuildContext context) {
    final labels = _activeFilterLabels();
    if (labels.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final textColor = const Color(0xFF333333);
    final bannerColor = ActionMailTheme.alertColor.withValues(alpha: 0.5);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bannerColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.start,
              runAlignment: WrapAlignment.center,
              children: labels
                  .map(
                    (label) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: textColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: onClearFilters,
            style: TextButton.styleFrom(
              foregroundColor: textColor,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Clear filters'),
          ),
        ],
      ),
    );
  }
}

