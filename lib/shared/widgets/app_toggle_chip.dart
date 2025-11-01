import 'package:flutter/material.dart';

enum AppChipStyle { classic, glass }

class AppToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppChipStyle style;
  final Color? selectedColor; // optional custom selected bg color
  final bool linkStyle; // render as text-style button (no border)

  const AppToggleChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.style = AppChipStyle.classic,
    this.selectedColor,
    this.linkStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (linkStyle) {
      final color = selected ? cs.onSurface : cs.onSurfaceVariant;
      return InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              decoration: selected ? TextDecoration.underline : TextDecoration.none,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    final borderRadius = BorderRadius.circular(10);
    final bgColor = switch (style) {
      AppChipStyle.classic => selected ? (selectedColor ?? cs.primary) : theme.colorScheme.surfaceContainerHighest,
      AppChipStyle.glass => selected
          ? cs.primary.withValues(alpha: 0.85)
          : theme.colorScheme.surface.withValues(alpha: 0.5),
    };
    final side = switch (style) {
      AppChipStyle.classic => BorderSide(color: selected ? Colors.transparent : cs.outlineVariant.withValues(alpha: 0.4)),
      AppChipStyle.glass => BorderSide(color: selected ? Colors.transparent : cs.outlineVariant.withValues(alpha: 0.6)),
    };

    return Material(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: side,
      ),
      elevation: style == AppChipStyle.glass ? 1 : 0,
      shadowColor: style == AppChipStyle.glass ? cs.shadow.withValues(alpha: 0.2) : null,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: selected
                  ? cs.onPrimary
                  : (style == AppChipStyle.glass ? cs.onSurface : cs.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}


