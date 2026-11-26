import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// A pane of the debug console that scrolls and lets taps through: the
/// list [child] draws, scrolled by [controller] (a list that grows
/// upwards, `reverse: true`), takes no pointer itself; over it a layer
/// takes the wheel's turns and the vertical drags of touch, a stylus and
/// a trackpad, and lets every tap reach the app under the console.
///
/// With [interactive], the list takes pointers too (the log pane while it
/// selects); [gestures] are recognized by the layer over it as well.
class DebugConsoleScrollArea extends StatefulWidget {
  /// [child] scrolled by [controller].
  const DebugConsoleScrollArea({
    required this.controller,
    required this.child,
    this.interactive = false,
    this.gestures = const {},
    super.key,
  });

  /// Whether the list takes pointers itself.
  final bool interactive;

  /// More gestures of the layer over the list, which lets taps through
  /// to the app as long as none of them takes them.
  final Map<Type, GestureRecognizerFactory> gestures;

  /// The list's controller.
  final ScrollController controller;

  /// The list.
  final Widget child;

  @override
  State<DebugConsoleScrollArea> createState() => _DebugConsoleScrollAreaState();
}

class _DebugConsoleScrollAreaState extends State<DebugConsoleScrollArea> {
  Drag? _drag;

  @override
  void dispose() {
    _drag?.cancel();
    super.dispose();
  }

  ScrollController get _scroll => widget.controller;

  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) {
      return;
    }
    // The list grows upwards: a turn down goes towards the newest.
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (event) => _scroll.position.pointerScroll(
        -(event as PointerScrollEvent).scrollDelta.dy,
      ),
    );
  }

  void _dragStart(DragStartDetails details) {
    if (_scroll.hasClients) {
      _drag = _scroll.position.drag(details, () => _drag = null);
    }
  }

  void _dragUpdate(DragUpdateDetails details) => _drag?.update(details);

  void _dragEnd(DragEndDetails details) => _drag?.end(details);

  void _dragCancel() => _drag?.cancel();

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      IgnorePointer(ignoring: !widget.interactive, child: widget.child),
      Positioned.fill(
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: _wheel,
          child: RawGestureDetector(
            behavior: HitTestBehavior.translucent,
            gestures: {
              ...widget.gestures,
              VerticalDragGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    VerticalDragGestureRecognizer
                  >(
                    () => VerticalDragGestureRecognizer(
                      supportedDevices: const {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.stylus,
                        PointerDeviceKind.invertedStylus,
                        PointerDeviceKind.trackpad,
                        PointerDeviceKind.unknown,
                      },
                    ),
                    (drag) => drag
                      ..onStart = _dragStart
                      ..onUpdate = _dragUpdate
                      ..onEnd = _dragEnd
                      ..onCancel = _dragCancel,
                  ),
            },
          ),
        ),
      ),
    ],
  );
}
