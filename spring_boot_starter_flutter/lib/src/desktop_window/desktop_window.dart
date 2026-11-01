import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show
        PointerDeviceKind,
        PointerDownEvent,
        PointerEvent,
        PointerMoveEvent,
        kDoubleTapSlop,
        kDoubleTapTimeout,
        kPanSlop,
        kPrimaryButton;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/desktop_window/desktop_window_settings.dart';

/// The space the native window buttons take inside the window, in logical
/// pixels, so that content drawn under a transparent title bar leaves room
/// for them.
///
/// macOS: the traffic lights' area at the left of the title bar; Windows:
/// the caption buttons' area at the right; zero where there are none
/// (`title-bar=default`, `hidden`, Linux, mobile, web).
@immutable
final class DesktopWindowInsets {
  /// Insets of the given sides.
  const DesktopWindowInsets({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  /// No window buttons over the content.
  static const zero = DesktopWindowInsets();

  /// The insets of the map the native side answers with
  /// (`left`, `top`, `right`, `bottom`); a missing side is zero.
  factory DesktopWindowInsets.fromMap(Map<Object?, Object?>? map) {
    double side(String key) => ((map?[key]) as num?)?.toDouble() ?? 0;
    return DesktopWindowInsets(
      left: side('left'),
      top: side('top'),
      right: side('right'),
      bottom: side('bottom'),
    );
  }

  /// Width the buttons take at the left edge.
  final double left;

  /// Height the buttons take at the top edge.
  final double top;

  /// Width the buttons take at the right edge.
  final double right;

  /// Height the buttons take at the bottom edge.
  final double bottom;

  /// The insets as [EdgeInsets], for a `Padding`.
  EdgeInsets get edgeInsets => EdgeInsets.fromLTRB(left, top, right, bottom);

  @override
  bool operator ==(Object other) =>
      other is DesktopWindowInsets &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() =>
      'DesktopWindowInsets(left: $left, top: $top, right: $right, '
      'bottom: $bottom)';
}

/// What the app knows of its native window: the title bar style that was
/// applied and the [insets] of the window buttons.
@immutable
final class DesktopWindowData {
  /// Window data.
  const DesktopWindowData({
    this.titleBar = TitleBarStyle.defaultStyle,
    this.insets = DesktopWindowInsets.zero,
  });

  /// A window nobody changed: the OS's title bar, no insets (also what
  /// every non-desktop platform has).
  static const none = DesktopWindowData();

  /// The title bar style the window has.
  final TitleBarStyle titleBar;

  /// The space the window buttons take.
  final DesktopWindowInsets insets;

  @override
  bool operator ==(Object other) =>
      other is DesktopWindowData &&
      other.titleBar == titleBar &&
      other.insets == insets;

  @override
  int get hashCode => Object.hash(titleBar, insets);
}

/// Gives [DesktopWindowData] to the widgets below; `SpringApplicationWidget`
/// puts one above the app.
///
/// ```dart
/// final insets = DesktopWindow.insetsOf(context);
/// Padding(
///   padding: EdgeInsets.only(left: insets.left, right: insets.right),
///   child: const Toolbar(),
/// );
/// ```
class DesktopWindow extends InheritedWidget {
  /// Provides [data] to [child].
  const DesktopWindow({required this.data, required super.child, super.key});

  /// The window the widgets below see.
  final DesktopWindowData data;

  /// The window data above [context]; [DesktopWindowData.none] without a
  /// [DesktopWindow] above (a widget test, a phone).
  static DesktopWindowData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopWindow>()?.data ??
      DesktopWindowData.none;

  /// The space the window buttons take, as [of] says.
  static DesktopWindowInsets insetsOf(BuildContext context) =>
      of(context).insets;

  @override
  bool updateShouldNotify(DesktopWindow oldWidget) => data != oldWidget.data;
}

/// The native side of the window (the plugin's method channel), for the
/// starter's own use and for tests of an app.
abstract final class DesktopWindowChannel {
  /// The method channel's name.
  static const name = 'dev.farumazula/spring_boot_starter_flutter/window';

  static const _channel = MethodChannel(name);
  static const _log = SpringLog('spring_boot_starter_flutter.DesktopWindow');

  /// Whether this platform has a window the plugin can change: macOS,
  /// Windows and Linux, not the web, not a phone.
  static bool get isSupported =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux => true,
        _ => false,
      };

  /// Sets the window as [settings] say and answers the insets of the
  /// window buttons. Throws when the plugin is not registered (a widget
  /// test) or the native side fails.
  static Future<DesktopWindowInsets> apply(
    DesktopWindowSettings settings,
  ) async {
    final initial = settings.initialSize;
    final min = settings.minSize;
    final max = settings.maxSize;
    final answer = await _channel.invokeMapMethod<Object?, Object?>('apply', {
      'title': ?settings.title,
      'titleBar': settings.titleBar.propertyValue,
      'initialWidth': ?initial?.width,
      'initialHeight': ?initial?.height,
      'minWidth': ?min?.width,
      'minHeight': ?min?.height,
      'maxWidth': ?max?.width,
      'maxHeight': ?max?.height,
    });
    if (answer == null) {
      throw MissingPluginException('No answer to apply on $name');
    }
    return DesktopWindowInsets.fromMap(
      answer['insets'] as Map<Object?, Object?>?,
    );
  }

  /// What the native window is now: `contentWidth`, `contentHeight`,
  /// `minWidth`, `minHeight` (logical pixels, 0 for no minimum),
  /// `maxWidth`, `maxHeight` (0 for no maximum), `title`, `titleBar`, `x`, `y`. For tests that read the window back.
  static Future<Map<String, Object?>> describe() async =>
      (await _channel.invokeMapMethod<String, Object?>('describe')) ?? const {};

  /// Starts moving the window with the pointer that is down.
  static Future<void> startDrag() => _call('startDrag');

  /// Maximizes the window, or restores it when it is maximized (macOS:
  /// as the system's double click on a title bar is set to).
  static Future<void> toggleMaximize() => _call('toggleMaximize');

  static Future<void> _call(String method) async {
    if (!isSupported) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // No plugin (a widget test): nothing to move.
    } on PlatformException catch (error) {
      _log.warning(() => 'The window call $method failed: $error');
    }
  }
}

/// An area that moves the window when it is dragged and maximizes or
/// restores it on a double click, as a title bar does: for the title bar
/// the app draws itself (`title-bar=transparent` or `hidden`).
///
/// ```dart
/// WindowDragArea(
///   child: SizedBox(height: 40, child: Center(child: Text('NEON Books'))),
/// )
/// ```
///
/// A drag starts once the pointer has moved a few pixels with the primary
/// button down, so a click (and a button inside the area) is not a drag.
/// Does nothing on mobile and the web.
class WindowDragArea extends StatefulWidget {
  /// Makes [child] move the window.
  const WindowDragArea({
    super.key,
    this.child,
    this.doubleClickMaximizes = true,
  });

  /// The title bar's content.
  final Widget? child;

  /// Whether a double click maximizes or restores the window.
  final bool doubleClickMaximizes;

  @override
  State<WindowDragArea> createState() => _WindowDragAreaState();
}

class _WindowDragAreaState extends State<WindowDragArea> {
  Offset? _down;
  bool _dragging = false;
  Duration? _lastClickTime;
  Offset? _lastClickPosition;

  bool _isMouseButton(PointerEvent event) =>
      event.kind == PointerDeviceKind.mouse &&
      (event.buttons & kPrimaryButton) != 0;

  void _onDown(PointerDownEvent event) {
    if (!_isMouseButton(event)) {
      return;
    }
    _down = event.position;
    _dragging = false;
    final lastTime = _lastClickTime;
    final lastPosition = _lastClickPosition;
    if (widget.doubleClickMaximizes &&
        lastTime != null &&
        lastPosition != null &&
        event.timeStamp - lastTime <= kDoubleTapTimeout &&
        (event.position - lastPosition).distance <= kDoubleTapSlop) {
      // The second click: no drag follows it.
      _lastClickTime = null;
      _down = null;
      unawaited(DesktopWindowChannel.toggleMaximize());
      return;
    }
    _lastClickTime = event.timeStamp;
    _lastClickPosition = event.position;
  }

  void _onMove(PointerMoveEvent event) {
    final down = _down;
    if (down == null ||
        _dragging ||
        (event.position - down).distance <= kPanSlop) {
      return;
    }
    _dragging = true;
    _lastClickTime = null;
    unawaited(DesktopWindowChannel.startDrag());
  }

  void _onEnd(PointerEvent event) {
    _down = null;
    _dragging = false;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _onDown,
    onPointerMove: _onMove,
    onPointerUp: _onEnd,
    onPointerCancel: _onEnd,
    child: widget.child,
  );
}
