import 'package:flutter/material.dart';
import 'package:domail/shared/widgets/app_segmented_bar.dart';

/// Reusable Personal/Business filter widget for window dialogs
/// Uses the same style as Attachments window
class PersonalBusinessFilter extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onChanged;

  const PersonalBusinessFilter({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppSegmentedBar<String?>(
      values: const [null, 'Personal', 'Business'],
      labelBuilder: (v) => v ?? 'All',
      selected: selected,
      onChanged: onChanged,
    );
  }
}

