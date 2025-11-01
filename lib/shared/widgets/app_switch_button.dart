import 'package:flutter/material.dart';

/// A compact, two-state pill switch button.
/// Example: AppSwitchButton(values: ['Personal','Business'], selected: 'Personal', onChanged: ...)
class AppSwitchButton<T> extends StatelessWidget {
  final List<T> values;
  final T? selected; // allow no selection
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onChanged;

  const AppSwitchButton({
    super.key,
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
      ),
      padding: const EdgeInsets.all(1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: values.map((v) {
          final isSel = selected != null && v == selected;
          return _Segment(
            label: labelBuilder(v),
            selected: isSel,
            onTap: () => onChanged(v),
          );
        }).toList(),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primary : cs.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: selected ? cs.onPrimary : cs.onSurface,
                ),
          ),
        ),
      ),
    );
  }
}


