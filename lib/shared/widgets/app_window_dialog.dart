import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Reusable modal window for desktop/mobile
/// - Large: Width 90% of viewport (max 800px), Height 80% of viewport
/// - Small: Width 50% of viewport (max 500px), Height auto-fit content (max 60% of viewport)
/// - AppBar-styled header with title and a close button on the right
enum AppWindowSize { large, small }

class AppWindowController extends ChangeNotifier {
  AppWindowController._(this._state);

  _AppWindowDialogState? _state;

  bool get isFullscreen => _state?._fullscreen ?? false;
  Size get size => _state?._currentSize ?? Size.zero;
  Offset get offset => _state?._offset ?? Offset.zero;

  void toggleFullscreen() => _state?._toggleFullscreen();
  void enterFullscreen() => _state?._setFullscreen(true);
  void exitFullscreen() => _state?._setFullscreen(false);

  void _attach(_AppWindowDialogState state) {
    _state = state;
  }

  void _detach() {
    _state = null;
  }

  void _notify() {
    notifyListeners();
  }
}

class AppWindowScope extends InheritedNotifier<AppWindowController> {
  const AppWindowScope({
    super.key,
    required AppWindowController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppWindowController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppWindowScope>()?.notifier;
}

class AppWindowDialog extends StatefulWidget {
  final String title;
  final Widget child;
  final EdgeInsetsGeometry bodyPadding;
  final List<Widget>? headerActions;
  final AppWindowSize size;
  final bool fullscreen;
  final double? height; // Optional height override
  final String? windowId;
  final bool resizable;
  final bool movable;
  final Size? initialSize;
  final Offset? initialOffset;

  const AppWindowDialog({
    super.key,
    required this.title,
    required this.child,
    this.bodyPadding = const EdgeInsets.all(24.0),
    this.headerActions,
    this.size = AppWindowSize.large,
    this.fullscreen = false,
    this.height,
    this.windowId,
    this.resizable = true,
    this.movable = true,
    this.initialSize,
    this.initialOffset,
  });

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget child,
    EdgeInsetsGeometry bodyPadding = const EdgeInsets.all(16.0),
    List<Widget>? headerActions,
    bool barrierDismissible = true,
    AppWindowSize size = AppWindowSize.large,
    double? height,
    bool fullscreen = false,
    String? windowId,
    bool resizable = true,
    bool movable = true,
    Size? initialSize,
    Offset? initialOffset,
    bool useRootNavigator = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      useRootNavigator: useRootNavigator,
      builder: (ctx) => AppWindowDialog(
        title: title,
        bodyPadding: bodyPadding,
        headerActions: headerActions,
        size: size,
        height: height,
        fullscreen: fullscreen,
        windowId: windowId,
        resizable: resizable,
        movable: movable,
        initialSize: initialSize,
        initialOffset: initialOffset,
        child: child,
      ),
    );
  }

  @override
  State<AppWindowDialog> createState() => _AppWindowDialogState();
}

class _WindowGeometry {
  const _WindowGeometry({
    required this.size,
    required this.offset,
  });

  final Size size;
  final Offset offset;
}

class _AppWindowDialogState extends State<AppWindowDialog> {
  static final Map<String, _WindowGeometry> _savedGeometry = {};

  late final AppWindowController _controller;
  bool _initialized = false;
  bool _fullscreen = false;
  double _width = 0;
  double _height = 0;
  Offset _offset = Offset.zero;
  Size _lastScreenSize = Size.zero;
  _WindowGeometry? _restoreGeometry;

  Offset? _dragStartPosition;
  Offset? _dragStartOffset;
  Offset? _resizeStartPosition;
  Size? _resizeStartSize;

  Size get _currentSize =>
      _fullscreen ? _lastScreenSize : Size(_width, _height);

  @override
  void initState() {
    super.initState();
    _controller = AppWindowController._(this).._attach(this);
    _fullscreen = widget.fullscreen;
  }

  @override
  void dispose() {
    _persistGeometry();
    _controller._detach();
    super.dispose();
  }

  void _initialize(Size screenSize) {
    if (_initialized) return;

    final saved = widget.windowId != null
        ? _savedGeometry[widget.windowId!]
        : null;

    if (saved != null) {
      _width = saved.size.width;
      _height = saved.size.height;
      _offset = saved.offset;
    } else if (widget.initialSize != null) {
      _width = widget.initialSize!.width;
      _height = widget.initialSize!.height;
      _offset = widget.initialOffset ?? Offset.zero;
    } else {
      final defaults = _defaultSize(screenSize);
      _width = defaults.width;
      _height = defaults.height;
      _offset = Offset(
        (screenSize.width - _width) / 2,
        (screenSize.height - _height) / 2,
      );
    }

    if (_fullscreen) {
      _restoreGeometry = _WindowGeometry(
        size: Size(_width, _height),
        offset: _offset,
      );
      _width = screenSize.width;
      _height = screenSize.height;
      _offset = Offset.zero;
    } else {
      _clampGeometry(screenSize);
    }

    _initialized = true;
  }

  Size _defaultSize(Size screenSize) {
    if (widget.height != null) {
      final width = widget.size == AppWindowSize.small
          ? math.min(screenSize.width * 0.5, 500.0)
          : math.min(screenSize.width * 0.9, 800.0);
      return Size(width, widget.height!);
    }

    if (widget.size == AppWindowSize.small) {
      return Size(
        math.min(screenSize.width * 0.5, 500.0),
        math.min(screenSize.height * 0.6, 600.0),
      );
    }

    return Size(
      math.min(screenSize.width * 0.9, 800.0),
      screenSize.height * 0.8,
    );
  }

  void _clampGeometry(Size screenSize) {
    final maxWidth = screenSize.width;
    final maxHeight = screenSize.height;
    final minWidth = _minWidth;
    final minHeight = _minHeight;

    _width = _width.clamp(minWidth, maxWidth);
    _height = _height.clamp(minHeight, maxHeight);

    final maxLeft = math.max(0.0, screenSize.width - _width);
    final maxTop = math.max(0.0, screenSize.height - _height);
    _offset = Offset(
      _offset.dx.clamp(0.0, maxLeft),
      _offset.dy.clamp(0.0, maxTop),
    );
  }

  double get _minWidth =>
      widget.size == AppWindowSize.small ? 280 : 520;

  double get _minHeight =>
      widget.size == AppWindowSize.small ? 220 : 360;

  void _persistGeometry() {
    if (widget.windowId != null && !_fullscreen) {
      _savedGeometry[widget.windowId!] = _WindowGeometry(
        size: Size(_width, _height),
        offset: _offset,
      );
    }
  }

  void _startDrag(DragStartDetails details) {
    if (!widget.movable || _fullscreen) return;
    _dragStartPosition = details.globalPosition;
    _dragStartOffset = _offset;
  }

  void _handleDrag(DragUpdateDetails details, Size screenSize) {
    if (!widget.movable || _fullscreen) return;
    if (_dragStartPosition == null || _dragStartOffset == null) return;
    final delta = details.globalPosition - _dragStartPosition!;
    setState(() {
      _offset = _dragStartOffset! + delta;
      _clampGeometry(screenSize);
      _persistGeometry();
      _controller._notify();
    });
  }

  void _startResize(DragStartDetails details) {
    if (!widget.resizable || _fullscreen) return;
    _resizeStartPosition = details.globalPosition;
    _resizeStartSize = Size(_width, _height);
  }

  void _handleResize(DragUpdateDetails details, Size screenSize) {
    if (!widget.resizable || _fullscreen) return;
    if (_resizeStartPosition == null || _resizeStartSize == null) return;
    final delta = details.globalPosition - _resizeStartPosition!;
    setState(() {
      _width = (_resizeStartSize!.width + delta.dx)
          .clamp(_minWidth, screenSize.width);
      _height = (_resizeStartSize!.height + delta.dy)
          .clamp(_minHeight, screenSize.height);
      _clampGeometry(screenSize);
      _persistGeometry();
      _controller._notify();
    });
  }

  void _toggleFullscreen() {
    _setFullscreen(!_fullscreen);
  }

  void _setFullscreen(bool value) {
    final screenSize = _lastScreenSize;
    setState(() {
      if (value == _fullscreen) return;
      if (value) {
        _restoreGeometry = _WindowGeometry(
          size: Size(_width, _height),
          offset: _offset,
        );
        _fullscreen = true;
        _width = screenSize.width;
        _height = screenSize.height;
        _offset = Offset.zero;
      } else {
        _fullscreen = false;
        if (_restoreGeometry != null) {
          _width = _restoreGeometry!.size.width;
          _height = _restoreGeometry!.size.height;
          _offset = _restoreGeometry!.offset;
        } else {
          final defaults = _defaultSize(screenSize);
          _width = defaults.width;
          _height = defaults.height;
          _offset = Offset(
            (screenSize.width - _width) / 2,
            (screenSize.height - _height) / 2,
          );
        }
        _clampGeometry(screenSize);
        _persistGeometry();
      }
      _controller._notify();
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final screenSize = media.size;
    _lastScreenSize = screenSize;
    _initialize(screenSize);

    final double width = _fullscreen ? screenSize.width : _width;
    final double height = _fullscreen ? screenSize.height : _height;
    final double left = _fullscreen ? 0.0 : _offset.dx;
    final double top = _fullscreen ? 0.0 : _offset.dy;

    final appBarBg =
        theme.appBarTheme.backgroundColor ?? const Color(0xFF00695C);
    final appBarFg =
        theme.appBarTheme.foregroundColor ?? const Color(0xFFB2DFDB);

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          child: AppWindowScope(
            controller: _controller,
            child: Material(
              color: Colors.transparent,
              elevation: 16,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: screenSize.width,
                  maxHeight: screenSize.height,
                ),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_fullscreen ? 0 : 12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.dialogTheme.backgroundColor ?? theme.colorScheme.surface,
                      ),
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildHeader(
                                context,
                                appBarBg,
                                appBarFg,
                                theme,
                                screenSize,
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child: widget.size == AppWindowSize.small
                                    ? widget.child
                                    : Padding(
                                        padding: widget.bodyPadding,
                                        child: widget.child,
                                      ),
                              ),
                            ],
                          ),
                          if (widget.resizable && !_fullscreen)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: GestureDetector(
                                onPanStart: _startResize,
                                onPanUpdate: (details) =>
                                    _handleResize(details, screenSize),
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.resizeUpLeftDownRight,
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    alignment: Alignment.bottomRight,
                                    padding: const EdgeInsets.all(2),
                                    child: Icon(
                                      Icons.open_in_full,
                                      size: 12,
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    Color background,
    Color foreground,
    ThemeData theme,
    Size screenSize,
  ) {
    final row = SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 24),
          Expanded(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (widget.headerActions != null)
            ...widget.headerActions!,
          IconButton(
            tooltip: 'Close',
            icon: Icon(Icons.close, color: foreground),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );

    final header = Material(
      color: background,
      child: SafeArea(
        bottom: false,
        child: widget.movable && !_fullscreen
            ? GestureDetector(
                onPanStart: _startDrag,
                onPanUpdate: (details) => _handleDrag(details, screenSize),
                child: MouseRegion(
                  cursor: SystemMouseCursors.move,
                  child: row,
                ),
              )
            : row,
      ),
    );

    return header;
  }
}
