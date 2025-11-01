import 'package:flutter/material.dart';

enum AppButtonVariant { filled, tonal, outlined, text, ghost }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool isDestructive;
  final bool isExpanded;
  final double? width;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.filled,
    this.leadingIcon,
    this.trailingIcon,
    this.isDestructive = false,
    this.isExpanded = false,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    final padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
    final textStyle = theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600);

    final ButtonStyle baseStyle = ButtonStyle(
      padding: WidgetStatePropertyAll(padding),
      minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
      shape: WidgetStatePropertyAll(shape),
      visualDensity: VisualDensity.compact,
      textStyle: WidgetStatePropertyAll(textStyle),
    );

    final ColorScheme cs = theme.colorScheme;
    final Color? fgOverride = isDestructive
        ? (variant == AppButtonVariant.outlined || variant == AppButtonVariant.text
            ? cs.error
            : cs.onError)
        : null;
    final Color? bgOverride = isDestructive
        ? (variant == AppButtonVariant.filled
            ? cs.error
            : variant == AppButtonVariant.tonal
                ? cs.errorContainer
                : null)
        : null;

    final child = _buildChild(theme, fgOverride);
    final button = switch (variant) {
      AppButtonVariant.filled => FilledButton(
          style: baseStyle.merge(ButtonStyle(
            foregroundColor: fgOverride != null ? WidgetStatePropertyAll(fgOverride) : null,
            backgroundColor: bgOverride != null ? WidgetStatePropertyAll(bgOverride) : null,
          )),
          onPressed: onPressed,
          child: child,
        ),
      AppButtonVariant.tonal => FilledButton.tonal(
          style: baseStyle.merge(ButtonStyle(
            foregroundColor: fgOverride != null ? WidgetStatePropertyAll(fgOverride) : null,
            backgroundColor: bgOverride != null ? WidgetStatePropertyAll(bgOverride) : null,
          )),
          onPressed: onPressed,
          child: child,
        ),
      AppButtonVariant.outlined => OutlinedButton(
          style: baseStyle,
          onPressed: onPressed,
          child: child,
        ),
      AppButtonVariant.text => TextButton(
          style: baseStyle,
          onPressed: onPressed,
          child: child,
        ),
      AppButtonVariant.ghost => _GhostButton(
          style: baseStyle,
          onPressed: onPressed,
          child: child,
        ),
    };

    if (isExpanded) {
      return SizedBox(width: width, child: button);
    }
    return button;
  }

  Widget _buildChild(ThemeData theme, Color? fgOverride) {
    final color = fgOverride ?? theme.colorScheme.onPrimary;
    final leading = leadingIcon != null
        ? Icon(leadingIcon, size: 18, color: variant == AppButtonVariant.filled || variant == AppButtonVariant.tonal ? null : null)
        : null;
    final trailing = trailingIcon != null
        ? Icon(trailingIcon, size: 18, color: variant == AppButtonVariant.filled || variant == AppButtonVariant.tonal ? null : null)
        : null;

    final text = Text(label, overflow: TextOverflow.ellipsis);

    if (leading == null && trailing == null) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[leading, const SizedBox(width: 8)],
        Flexible(child: text),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    );
  }
}

class _GhostButton extends StatelessWidget {
  final ButtonStyle style;
  final VoidCallback? onPressed;
  final Widget child;
  const _GhostButton({required this.style, required this.onPressed, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final base = style.merge(ButtonStyle(
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      foregroundColor: WidgetStatePropertyAll(cs.onSurface),
      overlayColor: WidgetStatePropertyAll(cs.primary.withOpacity(0.08)),
      side: WidgetStatePropertyAll(BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
      elevation: const WidgetStatePropertyAll(0),
    ));
    return OutlinedButton(style: base, onPressed: onPressed, child: child);
  }
}


