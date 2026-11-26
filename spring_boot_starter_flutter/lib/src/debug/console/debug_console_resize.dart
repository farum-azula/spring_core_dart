import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';

/// A handle of the debug console that a vertical drag moves, by mouse,
/// touch, a stylus or a trackpad: the one on its lower edge stretches or
/// shrinks the lowest pane, the divider between two neighbouring panes
/// moves the room between them. Only its own strip takes the pointer; a
/// drag calls [onDrag] with how far it went down since the last call (up
/// is negative).
class DebugConsoleResizeHandle extends StatelessWidget {
  /// A handle calling [onDrag].
  const DebugConsoleResizeHandle({
    required this.onDrag,
    this.divider = false,
    super.key,
  });

  /// How high the strip that takes the drag is.
  static const double height = 10;

  /// Called with each move down, in logical pixels.
  final ValueChanged<double> onDrag;

  /// Whether it is the divider between two panes (a line across) rather
  /// than the lower edge's grip.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          VerticalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                VerticalDragGestureRecognizer
              >(
                VerticalDragGestureRecognizer.new,
                (drag) => drag
                  ..dragStartBehavior = DragStartBehavior.down
                  ..onUpdate = (details) => onDrag(details.delta.dy),
              ),
        },
        child: SizedBox(
          height: height,
          child: Center(
            child: divider
                ? Container(height: 1, color: style.line)
                : Container(
                    width: 36,
                    height: 3,
                    decoration: BoxDecoration(
                      color: style.muted.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
