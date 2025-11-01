import 'package:flutter/material.dart';

enum AppSegmentedStyle { classic, glass }

class AppSegmentedBar<T> extends StatelessWidget {
  final List<T> values;
  final String Function(T) labelBuilder;
  final T? selected;
  final ValueChanged<T?> onChanged; // pass null when deselecting current
  final AppSegmentedStyle style;

  const AppSegmentedBar({
    super.key,
    required this.values,
    required this.labelBuilder,
    required this.selected,
    required this.onChanged,
    this.style = AppSegmentedStyle.classic,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final containerColor = style == AppSegmentedStyle.classic
        ? cs.surfaceContainerHighest
        : cs.surface.withValues(alpha: 0.5);
    final borderColor = style == AppSegmentedStyle.classic
        ? cs.outlineVariant.withValues(alpha: 0.4)
        : cs.outlineVariant.withValues(alpha: 0.6);

    return Container(
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: values.map((v) {
          final bool isSel = (selected == null && v == null) || (selected != null && v == selected);
          return _Seg(
            label: labelBuilder(v),
            selected: isSel,
            onTap: () => onChanged(isSel ? null : v),
            style: style,
          );
        }).toList(),
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppSegmentedStyle style;
  const _Seg({required this.label, required this.selected, required this.onTap, required this.style});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? (style == AppSegmentedStyle.classic ? cs.primary : cs.primary.withValues(alpha: 0.85))
          : (style == AppSegmentedStyle.classic ? cs.surface : Colors.transparent),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: selected
                      ? cs.onPrimary
                      : (style == AppSegmentedStyle.classic ? cs.onSurface : cs.onSurface),
                ),
          ),
        ),
      ),
    );
  }
}
