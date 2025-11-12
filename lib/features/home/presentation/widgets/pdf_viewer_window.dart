import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_editor_core/pdf_editor_core.dart';

import 'package:domail/shared/widgets/app_window_dialog.dart';

class PdfViewerWindow extends StatelessWidget {
  const PdfViewerWindow({
    super.key,
    required this.filePath,
    this.windowId = 'pdfViewerWindow',
    this.initialSize,
    this.initialOffset,
  });

  final String filePath;
  final String windowId;
  final Size? initialSize;
  final Offset? initialOffset;

  static Future<void> open(
    BuildContext context, {
    required String filePath,
    String windowId = 'pdfViewerWindow',
  }) {
    final controller = AppWindowScope.maybeOf(context);
    return showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (_) => PdfViewerWindow(
        filePath: filePath,
        windowId: windowId,
        initialSize: controller?.size,
        initialOffset: controller?.offset,
      ),
    );
  }

  static String _deriveTitle(String path) {
    try {
      return 'PDF: ${p.basename(path)}';
    } catch (_) {
      return 'PDF Viewer';
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _deriveTitle(filePath);
    return AppWindowDialog(
      title: title,
      size: AppWindowSize.large,
      windowId: windowId,
      initialSize: initialSize,
      initialOffset: initialOffset,
      headerActions: [
        Builder(
          builder: (context) => _FullscreenToggleButton(
            color: Theme.of(context).appBarTheme.foregroundColor ??
                const Color(0xFFB2DFDB),
          ),
        ),
      ],
      child: _PdfViewerContent(filePath: filePath),
    );
  }
}

class _PdfViewerContent extends StatelessWidget {
  const _PdfViewerContent({required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          builder: (_) => const PdfViewerScreen(),
          settings: RouteSettings(arguments: filePath),
        );
      },
    );
  }
}

class _FullscreenToggleButton extends StatelessWidget {
  const _FullscreenToggleButton({this.color});

  final Color? color;
  @override
  Widget build(BuildContext context) {
    final controller = AppWindowScope.maybeOf(context);
    if (controller == null) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isFullscreen = controller.isFullscreen;
        return IconButton(
          icon: Icon(
            isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
          ),
          color: color,
          tooltip: isFullscreen ? 'Exit full screen' : 'Full screen',
          onPressed: controller.toggleFullscreen,
        );
      },
    );
  }
}

