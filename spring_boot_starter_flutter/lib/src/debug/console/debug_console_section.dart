import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart' show Ordered;
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';

/// The debug panel's Console tab (`debugConsoleSection`, under `Tools`):
/// a switch for each segment of the header and each pane the build has
/// (`spring.flutter.debug.console.segments`, `panes`); a segment dragged
/// among the others moves in the header ([DebugConsoleSegmentChips]).
/// Applied at once to the `debugConsole` bean, where the state lives while
/// the app runs; it starts as `header` and `shown-panes` say. Every pane
/// the build has is listed, `logs` too, each switch selected exactly while
/// its pane shows, whatever changed it (the start, another switch, a
/// command calling `DebugConsole.showPane`); with every pane hidden the
/// console is its header alone. A hidden segment measures nothing, a
/// hidden pane is not built. The tab scrolls when it is higher than the
/// panel.
///
/// In the build only with the panel and the console.
final class DebugConsoleSection implements GroupedDebugPanelSection, Ordered {
  /// The tab of [console].
  const DebugConsoleSection(this.console);

  /// The console it switches.
  final DebugConsole console;

  @override
  String get title => 'Console';

  @override
  String get group => 'Tools';

  @override
  int get order => 46;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: console,
    builder: (context, _) {
      final style = DebugStyle.of(context);
      final muted = style.text.copyWith(color: style.muted);
      final segments = console.segmentOrder;
      final panes = console.namedPanes;
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Header', style: style.title),
            const SizedBox(height: 8),
            if (segments.isEmpty)
              Text(
                'No segment in this build '
                '(spring.flutter.debug.console.segments).',
                style: muted,
              ),
            if (segments.isNotEmpty) DebugConsoleSegmentChips(console: console),
            const SizedBox(height: 12),
            Text('Panes', style: style.title),
            const SizedBox(height: 8),
            if (panes.isEmpty)
              Text(
                'No pane in this build (spring.flutter.debug.console.panes).',
                style: muted,
              )
            else
              Wrap(
                children: [
                  for (final MapEntry(key: name, value: pane) in panes.entries)
                    DebugChip(
                      pane.title,
                      key: ValueKey('debug-console-pane-switch-$name'),
                      selected: console.showsPane(name),
                      onTap: () => console.showPane(
                        name,
                        shown: !console.showsPane(name),
                      ),
                    ),
                ],
              ),
          ],
        ),
      );
    },
  );
}

/// The segments of the console's header as one wrapping row of chips, in
/// the header's order: a tap shows or hides one, a drag moves it, by mouse
/// at once and by touch after a long press. While dragged it follows the
/// pointer, dim in its place, and a bar in the debug theme's accent marks
/// where it lands.
class DebugConsoleSegmentChips extends StatefulWidget {
  /// The chips of [console]'s segments.
  const DebugConsoleSegmentChips({required this.console, super.key});

  /// The console whose header they order.
  final DebugConsole console;

  @override
  State<DebugConsoleSegmentChips> createState() =>
      _DebugConsoleSegmentChipsState();
}

// Where a dragged segment lands: before the segment at [index] of the
// order (its length: after the last), the bar at the side of [rect], the
// chip next to it, that the pointer is nearest.
typedef _Landing = ({int index, Rect rect, bool after});

class _DebugConsoleSegmentChipsState extends State<DebugConsoleSegmentChips> {
  // The room each chip keeps at its right and under it (DebugChip's
  // margin): the bar stands in its middle.
  static const double _gap = 6;

  static const _mouse = {PointerDeviceKind.mouse};
  static const _touch = {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };

  final GlobalKey _row = GlobalKey();
  final Map<String, GlobalKey> _chips = {};
  String? _dragged;
  Offset _pointer = Offset.zero;
  _Landing? _landing;

  void _start(String name, Offset at) {
    setState(() {
      _dragged = name;
      _pointer = at;
      _landing = _landingAt(at);
    });
  }

  void _move(Offset at) {
    if (_dragged == null) {
      return;
    }
    setState(() {
      _pointer = at;
      _landing = _landingAt(at);
    });
  }

  void _drop() {
    final name = _dragged;
    final landing = _landing;
    _cancel();
    if (name == null || landing == null) {
      return;
    }
    final from = widget.console.segmentOrder.indexOf(name);
    final to = landing.index > from ? landing.index - 1 : landing.index;
    widget.console.moveSegment(name, to - from);
  }

  void _cancel() {
    if (_dragged != null) {
      setState(() {
        _dragged = null;
        _landing = null;
      });
    }
  }

  // The landing nearest [global]: in the row of chips under it first,
  // then before or after the chip by which half it is over.
  _Landing? _landingAt(Offset global) {
    _Landing? nearest;
    var least = double.infinity;
    for (final (i, name) in widget.console.segmentOrder.indexed) {
      final box = _chips[name]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) {
        continue;
      }
      final rect = box.localToGlobal(Offset.zero) & box.size;
      double off(double at, double low, double high) =>
          at < low ? low - at : (at > high ? at - high : 0);
      final distance =
          off(global.dy, rect.top, rect.bottom) * 1000 +
          off(global.dx, rect.left, rect.right);
      if (distance < least) {
        least = distance;
        final after = global.dx > rect.center.dx;
        nearest = (index: after ? i + 1 : i, rect: rect, after: after);
      }
    }
    return nearest;
  }

  Widget _chip(String name) {
    final console = widget.console;
    return KeyedSubtree(
      key: _chips.putIfAbsent(name, GlobalKey.new),
      child: Opacity(
        opacity: _dragged == name ? 0.4 : 1,
        child: MouseRegion(
          cursor: _dragged == null
              ? SystemMouseCursors.grab
              : SystemMouseCursors.grabbing,
          child: GestureDetector(
            supportedDevices: _mouse,
            onPanStart: (details) => _start(name, details.globalPosition),
            onPanUpdate: (details) => _move(details.globalPosition),
            onPanEnd: (_) => _drop(),
            onPanCancel: _cancel,
            child: GestureDetector(
              supportedDevices: _touch,
              onLongPressStart: (details) =>
                  _start(name, details.globalPosition),
              onLongPressMoveUpdate: (details) => _move(details.globalPosition),
              onLongPressEnd: (_) => _drop(),
              onLongPressCancel: _cancel,
              child: DebugChip(
                name,
                key: ValueKey('debug-console-segment-$name'),
                selected: console.showsSegment(name),
                onTap: () => console.showSegment(
                  name,
                  shown: !console.showsSegment(name),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // The bar where the dragged segment lands, in the row's coordinates;
  // none where it would not move.
  Widget? _bar(DebugStyle style) {
    final dragged = _dragged;
    final landing = _landing;
    final row = _row.currentContext?.findRenderObject();
    if (dragged == null || landing == null || row is! RenderBox) {
      return null;
    }
    final from = widget.console.segmentOrder.indexOf(dragged);
    if (landing.index == from || landing.index == from + 1) {
      return null;
    }
    final rect = landing.rect;
    final x = landing.after ? rect.right - _gap / 2 : rect.left - _gap / 2;
    final at = row.globalToLocal(Offset(x, rect.top));
    return Positioned(
      key: const ValueKey('debug-console-segment-drop'),
      left: at.dx - 1,
      top: at.dy,
      width: 2,
      height: rect.height - _gap,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: style.accent,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }

  // The dragged chip under the pointer.
  Widget? _ghost() {
    final dragged = _dragged;
    final row = _row.currentContext?.findRenderObject();
    if (dragged == null || row is! RenderBox) {
      return null;
    }
    final at = row.globalToLocal(_pointer);
    return Positioned(
      left: at.dx + 8,
      top: at.dy - 14,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.85,
          child: DebugChip(
            dragged,
            selected: widget.console.showsSegment(dragged),
            onTap: () {},
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          key: _row,
          clipBehavior: Clip.none,
          children: [
            Wrap(
              children: [
                for (final name in widget.console.segmentOrder) _chip(name),
              ],
            ),
            ?_bar(style),
            ?_ghost(),
          ],
        ),
        Text(
          'Tap to show or hide; drag to reorder (long press on touch).',
          style: style.text.copyWith(color: style.muted),
        ),
      ],
    );
  }
}
