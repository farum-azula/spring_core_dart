import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_interaction.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_pane.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_resize.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_segment.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_layout.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/properties/flutter_properties.dart';

/// The debug console's widget, top to bottom: the header of segments, with
/// what the shown panes add at its right ([DebugConsolePane.buildHeader])
/// and, with a pane shown, the toggle of their interaction
/// ([DebugConsoleInteractionToggle]); each shown pane ([DebugConsole.panes]), from the second on under a
/// divider that moves the room between it and the one above; the handle
/// on the lower edge that stretches or shrinks the lowest. With no pane
/// shown it is a strip, the header alone, without a handle. Each part
/// paints the console's background right behind it, the header and each
/// shown pane with its divider (the lowest with its handle), of the
/// console's opacity or the pane's own
/// ([DebugConsolePane.backgroundOpacity]); while the panes pass the pointer
/// through ([DebugConsole.interaction]) theirs is of
/// [DebugConsole.passThroughOpacity], and they take no pointer at all:
/// only the header and the handles do. On a desktop ⌥ (Alt) held makes
/// them interact while held. A hidden pane
/// is not built; a shown one is started ([DebugConsolePane.start]) while
/// it is built. When the panes do not fit the screen, the upper ones give
/// way first, none under its least.
class DebugConsoleView extends StatefulWidget {
  /// The view of [console].
  const DebugConsoleView({required this.console, super.key});

  /// The console.
  final DebugConsole console;

  /// The narrowest it is on a wide screen, and what the dock counts.
  static const double minWidth = 360;

  /// How high a line of the panes is.
  static const double lineHeight = 14;

  static const double _header = 16;
  static const _padding = EdgeInsets.fromLTRB(10, 6, 10, 0);

  // Under the header of a console without a pane shown.
  static const double _stripBottom = 6;

  // The dock's padding around the overlays, each side.
  static const double _margin = 8;

  /// The room it takes with shown panes of [heights], top to bottom, a
  /// divider between each two; the header alone without any.
  static Size sizeOf(List<double> heights) => Size(
    minWidth,
    _fixed(heights.length) + heights.fold(0.0, (sum, height) => sum + height),
  );

  // What the console takes besides [panes] panes: its padding, the header
  // (as high as the interaction's toggle with a pane), the dividers
  // between them and the lower edge's handle (without a pane, a margin
  // under the header instead).
  static double _fixed(int panes) =>
      _padding.vertical +
      (panes == 0
          ? _header + _stripBottom
          : math.max(_header, DebugConsoleInteractionToggle.size) +
                panes * DebugConsoleResizeHandle.height);

  // Where ⌥ (Alt) held makes the panes interact; a phone has the toggle
  // alone.
  static const _holdPlatforms = {
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  };

  /// [heights] made to fit [room] together, each kept at least its
  /// [least]: the upper ones give way first.
  static List<double> fitHeights(
    List<double> heights,
    List<double> least,
    double room,
  ) {
    final fitted = [...heights];
    var over = fitted.fold(0.0, (sum, height) => sum + height) - room;
    for (var i = 0; i < fitted.length && over > 0; i++) {
      final give = math.min(over, math.max(0.0, fitted[i] - least[i]));
      fitted[i] -= give;
      over -= give;
    }
    return fitted;
  }

  /// How wide it is on a screen of [screen] (its safe area, the dock's
  /// margins taken off): all of it on a phone, else [fraction] of it, not
  /// under [minWidth].
  static double widthFor(double screen, double fraction) {
    final room = math.max(0.0, screen - 2 * _margin);
    if (room < DebugLayout.phoneWidth) {
      return room;
    }
    return math.max(math.min(minWidth, room), room * fraction);
  }

  @override
  State<DebugConsoleView> createState() => _DebugConsoleViewState();
}

class _DebugConsoleViewState extends State<DebugConsoleView>
    with SingleTickerProviderStateMixin {
  int? _frame;

  // The slide in and out (`spring.flutter.debug.console.slide-duration`),
  // as a game's console drops down from its edge.
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: widget.console.slideDuration,
    value: 1,
  );
  late final Animation<double> _eased = CurvedAnimation(
    parent: _slide,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final Animation<Offset> _fromTop = Tween(
    begin: const Offset(0, -1),
    end: Offset.zero,
  ).animate(_eased);
  late final Animation<Offset> _fromBottom = Tween(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(_eased);

  // Whether ⌥ (Alt) is held now, on a desktop.
  bool _held = false;

  late final bool _holds = DebugConsoleView._holdPlatforms.contains(
    defaultTargetPlatform,
  );

  @override
  void initState() {
    super.initState();
    _attach(widget.console);
    if (_holds) {
      HardwareKeyboard.instance.addHandler(_key);
      _held = HardwareKeyboard.instance.isAltPressed;
    }
  }

  // Any key: whether ⌥ is held now; the key stays the app's.
  bool _key(KeyEvent event) {
    final held = HardwareKeyboard.instance.isAltPressed;
    if (held != _held && mounted) {
      setState(() => _held = held);
    }
    return false;
  }

  @override
  void didUpdateWidget(DebugConsoleView old) {
    super.didUpdateWidget(old);
    if (old.console != widget.console) {
      _detach(old.console);
      _attach(widget.console);
    }
  }

  // Listens to [console]; slides in when it was just shown, and goes on
  // sliding out when it was hidden while built elsewhere.
  void _attach(DebugConsole console) {
    console
      ..addListener(_schedule)
      ..addListener(_slideAsTold);
    if (console.attach()) {
      _slide.value = 0;
    }
    _slideAsTold();
  }

  void _detach(DebugConsole console) {
    console
      ..removeListener(_schedule)
      ..removeListener(_slideAsTold)
      ..detach();
  }

  @override
  void dispose() {
    _detach(widget.console);
    _slide.dispose();
    if (_holds) {
      HardwareKeyboard.instance.removeHandler(_key);
    }
    if (_frame case final frame?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(frame);
      _frame = null;
    }
    super.dispose();
  }

  // Hidden: slides out, then tells the console it is gone; shown again
  // meanwhile: slides back in from where it is.
  void _slideAsTold() {
    final console = widget.console;
    if (console.leaving) {
      if (_slide.status != AnimationStatus.reverse) {
        _slide.reverse().whenCompleteOrCancel(() {
          if (mounted && widget.console.leaving && _slide.value == 0) {
            widget.console.left();
          }
        });
      }
    } else if (_slide.status != AnimationStatus.forward && _slide.value < 1) {
      _slide.forward();
    }
  }

  // [child] sliding in from the console's edge: the top in a top corner,
  // the bottom in a bottom one.
  // Without the slide, [child] alone.
  Widget _slid(Widget child) {
    if (widget.console.slideDuration <= Duration.zero) {
      return child;
    }
    return ClipRect(
      child: SlideTransition(
        position: switch (widget.console.corner) {
          DebugCorner.topLeft || DebugCorner.topRight => _fromTop,
          DebugCorner.bottomLeft || DebugCorner.bottomRight => _fromBottom,
        },
        child: child,
      ),
    );
  }

  // However many changes come, one rebuild in the next frame.
  void _schedule() {
    _frame ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frame = null;
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _toggle() {
    final console = widget.console;
    console.interaction =
        console.interaction == DebugConsoleInteraction.interact
        ? DebugConsoleInteraction.passThrough
        : DebugConsoleInteraction.interact;
  }

  // The room the panes have on this screen: what the console's other
  // parts leave.
  double _room(MediaQueryData media, int panes) => math.max(
    DebugConsoleView.lineHeight,
    media.size.height -
        media.padding.vertical -
        DebugConsoleView._fixed(panes) -
        2 * DebugConsoleView._margin,
  );

  // The shown panes' names, with their heights fitted to the room and
  // their least.
  ({List<String> names, List<double> heights, List<double> least}) _layout(
    MediaQueryData media,
  ) {
    final console = widget.console;
    final names = console.panes;
    final least = [
      for (final name in names) console.namedPanes[name]!.minHeight,
    ];
    final heights = DebugConsoleView.fitHeights(
      [for (final name in names) console.paneHeight(name)],
      least,
      _room(media, names.length),
    );
    return (names: names, heights: heights, least: least);
  }

  void _resize(List<String> names, List<double> heights) =>
      widget.console.resize(
        panes: {for (final (i, name) in names.indexed) name: heights[i]},
      );

  // The lower edge: the lowest pane grows, as far as the screen lets it.
  void _dragEdge(double dy, MediaQueryData media) {
    final layout = _layout(media);
    final heights = [...layout.heights];
    final last = heights.length - 1;
    final others = heights.fold(0.0, (sum, h) => sum + h) - heights[last];
    final next = math.min(
      heights[last] + dy,
      _room(media, heights.length) - others,
    );
    heights[last] = math.max(layout.least[last], next);
    _resize(layout.names, heights);
  }

  // The divider above the pane at [below]: the room moves between it and
  // the one above, neither under its least.
  void _dragDivider(double dy, int below, MediaQueryData media) {
    final layout = _layout(media);
    final above = below - 1;
    final heights = [...layout.heights];
    final move = dy.clamp(
      layout.least[above] - heights[above],
      math.max(0.0, heights[below] - layout.least[below]),
    );
    heights[above] += move;
    heights[below] -= move;
    _resize(layout.names, heights);
  }

  @override
  Widget build(BuildContext context) {
    final console = widget.console;
    final style = DebugStyle.of(context);
    final text = style.code.copyWith(
      height: 1.25,
      decoration: TextDecoration.none,
    );
    final media = MediaQuery.of(context);
    final width = DebugConsoleView.widthFor(
      media.size.width - media.padding.horizontal,
      console.width,
    );
    final layout = _layout(media);
    final strip = layout.names.isEmpty;
    final last = layout.names.length - 1;
    const padding = DebugConsoleView._padding;
    const corner = Radius.circular(8);
    final interacts =
        _held || console.interaction == DebugConsoleInteraction.interact;
    Color tint(double? opacity) => style.background.withValues(
      alpha: (opacity ?? console.opacity).clamp(0.0, 1.0),
    );
    double? paneOpacity(String name) => interacts
        ? console.namedPanes[name]!.backgroundOpacity
        : console.passThroughOpacity;
    // Each part paints its own background right behind it, the header's
    // and each shown pane's (with the divider above it, and the lowest's
    // handle): nothing of the console is over the app without one, and a
    // pane may ask for a more opaque one while the panes interact. The
    // backgrounds let taps through to the app; the panes take them only
    // while they interact, the header and the handles always.
    return _slid(
      SizedBox(
        key: const ValueKey('debug-console'),
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DebugConsoleBackdrop(
              backgroundKey: const ValueKey('debug-console-background-header'),
              color: tint(null),
              borderRadius: strip
                  ? const BorderRadius.all(corner)
                  : const BorderRadius.vertical(top: corner),
              padding: padding.copyWith(
                bottom: strip ? DebugConsoleView._stripBottom : 0,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: DebugConsoleView._header,
                ),
                child: Row(
                  crossAxisAlignment: strip
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: DebugConsoleHeader(
                        segments: console.segments,
                        style: text,
                      ),
                    ),
                    for (final name in layout.names)
                      if (console.namedPanes[name]!.buildHeader(
                            context,
                            console,
                          )
                          case final extra?) ...[
                        const SizedBox(width: 8),
                        KeyedSubtree(
                          key: ValueKey('debug-console-header-$name'),
                          child: extra,
                        ),
                      ],
                    if (!strip) ...[
                      const SizedBox(width: 8),
                      DebugConsoleInteractionToggle(
                        interacts: interacts,
                        held:
                            _held &&
                            console.interaction !=
                                DebugConsoleInteraction.interact,
                        onToggle: _toggle,
                        style: text,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            for (final (i, name) in layout.names.indexed)
              DebugConsoleBackdrop(
                key: ValueKey('debug-console-part-$name'),
                backgroundKey: ValueKey('debug-console-background-$name'),
                color: tint(paneOpacity(name)),
                borderRadius: i == last
                    ? const BorderRadius.vertical(bottom: corner)
                    : BorderRadius.zero,
                padding: EdgeInsets.only(
                  left: padding.left,
                  right: padding.right,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (i > 0)
                      DebugConsoleResizeHandle(
                        key: ValueKey('debug-console-divider-$name'),
                        divider: true,
                        onDrag: (dy) => _dragDivider(dy, i, media),
                      ),
                    SizedBox(
                      key: ValueKey('debug-console-pane-$name'),
                      height: layout.heights[i],
                      child: IgnorePointer(
                        ignoring: !interacts,
                        child: DebugConsolePaneHost(
                          key: ValueKey(name),
                          pane: console.namedPanes[name]!,
                          console: console,
                        ),
                      ),
                    ),
                    if (i == last)
                      DebugConsoleResizeHandle(
                        key: const ValueKey('debug-console-handle'),
                        onDrag: (dy) => _dragEdge(dy, media),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A part of the debug console, the header or a shown pane, over its own
/// background: [color] in a box of [borderRadius] as big as the part,
/// keyed [backgroundKey], that takes no pointer, so taps on it go through
/// to the app; [child] inside [padding].
class DebugConsoleBackdrop extends StatelessWidget {
  /// [child] over a background of [color].
  const DebugConsoleBackdrop({
    required this.backgroundKey,
    required this.color,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  /// The key of the background's box.
  final Key backgroundKey;

  /// The background's colour, its opacity in it.
  final Color color;

  /// The background's corners.
  final BorderRadius borderRadius;

  /// Between the background's edges and [child].
  final EdgeInsets padding;

  /// The part.
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            key: backgroundKey,
            decoration: BoxDecoration(color: color, borderRadius: borderRadius),
          ),
        ),
      ),
      Padding(padding: padding, child: child),
    ],
  );
}

/// A shown pane of the debug console: [pane] built in [console], started
/// ([DebugConsolePane.start]) while it is built and stopped when it is no
/// more (the pane hidden, or the console).
class DebugConsolePaneHost extends StatefulWidget {
  /// The host of [pane] in [console].
  const DebugConsolePaneHost({
    required this.pane,
    required this.console,
    super.key,
  });

  /// The pane.
  final DebugConsolePane pane;

  /// The console.
  final DebugConsole console;

  @override
  State<DebugConsolePaneHost> createState() => _DebugConsolePaneHostState();
}

class _DebugConsolePaneHostState extends State<DebugConsolePaneHost> {
  late void Function() _stop;

  @override
  void initState() {
    super.initState();
    _stop = widget.pane.start();
  }

  @override
  void didUpdateWidget(DebugConsolePaneHost old) {
    super.didUpdateWidget(old);
    if (!identical(old.pane, widget.pane)) {
      _stop();
      _stop = widget.pane.start();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.pane.build(context, widget.console);
}

const _glue = '\u00A0';

/// The debug console's header: its [segments] in a line, wrapped onto the
/// next between segments when they do not fit, each a dim
/// label and its value, a number in the debug theme's number colour, a
/// state in its good, warning or bad colour. It starts the segments while
/// it shows and draws them again at most once a frame.
class DebugConsoleHeader extends StatefulWidget {
  /// The header of [segments] in [style].
  const DebugConsoleHeader({
    required this.segments,
    required this.style,
    super.key,
  });

  /// The segments, in order.
  final List<DebugConsoleSegment> segments;

  /// The text's style.
  final TextStyle style;

  @override
  State<DebugConsoleHeader> createState() => _DebugConsoleHeaderState();
}

class _DebugConsoleHeaderState extends State<DebugConsoleHeader> {
  // What stops each segment started, by the segment.
  final Map<DebugConsoleSegment, void Function()> _stops = {};
  int? _frame;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(DebugConsoleHeader old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    for (final stop in _stops.values) {
      stop();
    }
    _stops.clear();
    if (_frame case final frame?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(frame);
      _frame = null;
    }
    super.dispose();
  }

  // Starts the segments shown now and not before, stops those hidden; the
  // others keep measuring.
  void _sync() {
    final shown = widget.segments.toSet();
    _stops.removeWhere((segment, stop) {
      if (shown.contains(segment)) {
        return false;
      }
      stop();
      return true;
    });
    for (final segment in widget.segments) {
      _stops.putIfAbsent(segment, () => segment.start(_schedule));
    }
  }

  void _schedule() {
    _frame ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frame = null;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final muted = TextStyle(color: style.muted);
    final spans = <InlineSpan>[];
    void gap() {
      if (spans.isNotEmpty) {
        spans.add(TextSpan(text: '  ', style: muted));
      }
    }

    for (final segment in widget.segments) {
      final value = segment.read();
      if (value == null) {
        continue;
      }
      gap();
      // A segment is never broken: only the gaps between them wrap.
      if (value.label case final label?) {
        spans.add(TextSpan(text: '$label$_glue', style: muted));
      }
      final parts = value.parts.isEmpty ? [value] : value.parts;
      for (final (i, part) in parts.indexed) {
        if (i > 0) {
          spans.add(TextSpan(text: '$_glue·$_glue', style: muted));
        }
        if (value.parts.isNotEmpty && part.label != null) {
          spans.add(TextSpan(text: '${part.label}$_glue', style: muted));
        }
        spans.add(
          TextSpan(
            text: part.value.replaceAll(' ', _glue),
            style: TextStyle(
              color: switch (part.tone) {
                DebugConsoleTone.number => style.number,
                DebugConsoleTone.text => style.foreground,
                DebugConsoleTone.good => style.good,
                DebugConsoleTone.warning => style.warning,
                DebugConsoleTone.bad => style.bad,
                DebugConsoleTone.muted => style.muted,
              },
              fontWeight: part.tone == DebugConsoleTone.number
                  ? FontWeight.bold
                  : null,
            ),
          ),
        );
        if (part.unit case final unit?) {
          spans.add(TextSpan(text: '$_glue$unit', style: muted));
        }
      }
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: 'Console', style: muted));
    }
    return Text.rich(
      TextSpan(children: spans),
      key: const ValueKey('debug-console-header'),
      style: widget.style,
    );
  }
}
