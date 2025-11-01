import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Reusable modal window for desktop/mobile
/// - Width: 90% of viewport, capped at 800px
/// - Height: 80% of viewport
/// - AppBar-styled header with title and a close button on the right
class AppWindowDialog extends StatelessWidget {
  final String title;
  final Widget child;
  final EdgeInsetsGeometry bodyPadding;
  final List<Widget>? headerActions;

  const AppWindowDialog({
    super.key,
    required this.title,
    required this.child,
    this.bodyPadding = const EdgeInsets.all(24.0),
    this.headerActions,
  });

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget child,
    EdgeInsetsGeometry bodyPadding = const EdgeInsets.all(16.0),
    List<Widget>? headerActions,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => AppWindowDialog(
        title: title,
        child: child,
        bodyPadding: bodyPadding,
        headerActions: headerActions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxWidth = 800.0;
    final targetWidth = math.min(media.size.width * 0.9, maxWidth);
    final targetHeight = media.size.height * 0.8;
    final theme = Theme.of(context);
    // Use consistent dark teal for window title bars (same as appbar)
    final appBarBg = theme.appBarTheme.backgroundColor ?? const Color(0xFF00695C);
    final appBarFg = theme.appBarTheme.foregroundColor ?? const Color(0xFFB2DFDB);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: targetWidth,
        height: targetHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header bar styled to match AppBar
            Material(
              color: appBarBg,
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      const SizedBox(width: 24),
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(color: appBarFg, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (headerActions != null) ...headerActions!,
                      IconButton(
                        tooltip: 'Close',
                        icon: Icon(Icons.close, color: appBarFg),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            // Body
            Expanded(
              child: Padding(
                padding: bodyPadding,
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


