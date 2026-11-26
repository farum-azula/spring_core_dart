import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_names.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_pane.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_segment.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_view.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_layout.dart';
import 'package:spring_boot_starter_flutter/src/debug/overlay/debug_overlay.dart';
import 'package:spring_boot_starter_flutter/src/properties/flutter_properties.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_handler.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_invocation.dart';

/// The debug console over the running app (the `debugConsole` bean), top
/// to bottom: a header row of compact segments ([segments]: `fps 60 · 3D
/// 120 · lost 0 · logs all`), then the shown panes ([panes],
/// `DebugConsolePane` beans: `logs`, the records of the log buffer, on
/// top; `commands`; a starter's; the application's) by their order.
/// [width] of the screen wide (all of a phone's). With no pane shown it is
/// a strip, the header alone.
///
/// Which segments the header shows, in which order, and which panes show,
/// are the console's while the app runs ([showSegment], [moveSegment],
/// [showPane]; the debug panel's Console tab switches them), starting as
/// `spring.flutter.debug.console.header` and `shown-panes` say. Of the
/// segments and panes the build has ([namedSegments], [namedPanes]) a
/// hidden one costs nothing: a segment measures nothing, a pane is not
/// built at all, and the next one moves up.
///
/// A handle on its lower edge stretches or shrinks the lowest pane, and
/// the divider between two neighbours moves the room between them, by
/// mouse or touch ([paneHeight], [resize]); the heights stay while the app
/// runs, a hidden pane's too.
///
/// The action `debug.console` shows or hides it: by default ⌘⇧O
/// (Ctrl+Shift+O) or eight quick taps and a ninth held two seconds;
/// `spring.flutter.shortcuts.debug.console` names other keys or taps. The
/// debug panel's Overlays tab switches it too. It slides in from its edge
/// and back out in [slideDuration]
/// (`spring.flutter.debug.console.slide-duration`; 0 shows and hides it at
/// once); pressed again while sliding out, it comes back.
///
/// Its panes pass the pointer through or interact ([interaction]): passing
/// it through, every tap, scroll, hover and drag over them reaches the
/// app, and only the header (where a drag takes it, with the `drag`
/// feature) and its handles take one; interacting, each pane works as it
/// does (the records scroll and select, the commands' input line types).
/// The toggle at the right of the header switches it, ⌥ (Alt) held on a
/// desktop interacts while held, and starting the records' selection or
/// focusing the input line switches it to interacting. While hidden it
/// listens to nothing and its segments measure nothing; shown, the header
/// is drawn again at most once a frame.
class DebugConsole extends ChangeNotifier
    implements KeyedShortcutHandler, DebugOverlay {
  /// The console with the segments [segments] (by name, in their order), of
  /// which [header] shows (by name, in its order; `*` for the others;
  /// `null`: all), and the panes [panes] (by name, top to bottom), of which
  /// [shownPanes] show; hidden, in the corner [position], with a background
  /// of [opacity] (0 to 1), its panes taking the pointer as [interaction]
  /// says, theirs of [passThroughOpacity] while they pass it through, and
  /// [width] (0.2 to 1) of a wide screen wide.
  DebugConsole({
    Map<String, DebugConsoleSegment> segments = const {},
    List<String>? header,
    Map<String, DebugConsolePane> panes = const {},
    Iterable<String> shownPanes = const [],
    this._position = DebugCorner.topLeft,
    double opacity = 0.9,
    this._interaction = DebugConsoleInteraction.interact,
    double passThroughOpacity = 0.7,
    double width = 1,
    this.slideDuration = const Duration(milliseconds: 220),
  }) : namedSegments = Map.unmodifiable(segments),
       namedPanes = Map.unmodifiable(panes),
       opacity = opacity.clamp(0.0, 1.0),
       passThroughOpacity = passThroughOpacity.clamp(0.0, 1.0),
       width = width.clamp(0.2, 1.0) {
    final shown = pickDebugConsoleNamed(segments, header ?? const ['*']);
    _segmentOrder = [
      ...shown.keys,
      for (final name in segments.keys)
        if (!shown.containsKey(name)) name,
    ];
    _shownSegments = shown.keys.toSet();
    _shownPanes = {
      for (final name in pickDebugConsoleNamed(panes, shownPanes.toList()).keys)
        name,
    };
    _refresh();
  }

  /// Every segment the build has, by name, in their order.
  final Map<String, DebugConsoleSegment> namedSegments;

  /// Every pane the build has, by name, top to bottom.
  final Map<String, DebugConsolePane> namedPanes;

  late List<String> _segmentOrder;
  late Set<String> _shownSegments;
  late Set<String> _shownPanes;
  List<DebugConsoleSegment> _segments = const [];
  List<String> _header = const [];
  List<String> _panes = const [];

  /// The segments of the header, in its order.
  List<DebugConsoleSegment> get segments => _segments;

  /// The names of the segments the header shows, in its order.
  List<String> get header => _header;

  /// Every segment's name in the header's order, the hidden ones too.
  List<String> get segmentOrder => List.unmodifiable(_segmentOrder);

  /// The names of the panes shown, top to bottom.
  List<String> get panes => _panes;

  /// Whether the header shows the segment [name].
  bool showsSegment(String name) => _shownSegments.contains(name);

  /// Whether the pane [name] shows.
  bool showsPane(String name) => _shownPanes.contains(name);

  /// Shows the segment [name] in the header, or hides it; one the build
  /// does not have is ignored.
  void showSegment(String name, {bool shown = true}) {
    if (!namedSegments.containsKey(name) ||
        _shownSegments.contains(name) == shown) {
      return;
    }
    shown ? _shownSegments.add(name) : _shownSegments.remove(name);
    _refresh();
    notifyListeners();
  }

  /// Moves the segment [name] [by] places in the header (negative: to the
  /// left), within its ends.
  void moveSegment(String name, int by) {
    final from = _segmentOrder.indexOf(name);
    if (from < 0) {
      return;
    }
    final to = (from + by).clamp(0, _segmentOrder.length - 1);
    if (to == from) {
      return;
    }
    _segmentOrder
      ..removeAt(from)
      ..insert(to, name);
    _refresh();
    notifyListeners();
  }

  /// Shows the pane [name], or hides it; one the build does not have is
  /// ignored. Hidden, it is not built at all, and keeps its height.
  void showPane(String name, {bool shown = true}) {
    if (!namedPanes.containsKey(name) || _shownPanes.contains(name) == shown) {
      return;
    }
    shown ? _shownPanes.add(name) : _shownPanes.remove(name);
    _refresh();
    notifyListeners();
  }

  void _refresh() {
    _header = List.unmodifiable(_segmentOrder.where(_shownSegments.contains));
    _segments = List.unmodifiable([
      for (final name in _header) namedSegments[name]!,
    ]);
    _panes = List.unmodifiable(namedPanes.keys.where(_shownPanes.contains));
  }

  /// How opaque its background is, from 0 (the text alone over the app)
  /// to 1; the text stays opaque. The panes' while they interact (unless a
  /// pane gives its own), the header's always.
  final double opacity;

  /// How opaque the panes' background is while they pass the pointer
  /// through, from 0 (none: the app shows as it is) to 1, whatever a pane
  /// gives.
  final double passThroughOpacity;

  DebugConsoleInteraction _interaction;

  /// How its panes take the pointer now: passing it through to the app,
  /// or interacting. Starts as `spring.flutter.debug.console.interaction`
  /// says; the toggle at the right of the header switches it, and so do
  /// the records' selection and the input line when they start (both to
  /// [DebugConsoleInteraction.interact]). ⌥ (Alt) held on a desktop makes
  /// the panes interact while held, without changing it.
  DebugConsoleInteraction get interaction => _interaction;

  set interaction(DebugConsoleInteraction value) {
    if (value != _interaction) {
      _interaction = value;
      notifyListeners();
    }
  }

  final Map<String, double> _paneHeights = {};

  /// How high the pane [name] is, shown or not: its
  /// `DebugConsolePane.initialHeight` until dragged, never under its
  /// `minHeight`; 0 for one the build does not have.
  double paneHeight(String name) {
    final pane = namedPanes[name];
    if (pane == null) {
      return 0;
    }
    return math.max(pane.minHeight, _paneHeights[name] ?? pane.initialHeight);
  }

  /// Makes each pane of [panes] its height, at least its `minHeight`;
  /// what is not given stays.
  void resize({Map<String, double> panes = const {}}) {
    var changed = false;
    for (final MapEntry(key: name, value: height) in panes.entries) {
      final pane = namedPanes[name];
      if (pane == null) {
        continue;
      }
      final next = math.max(pane.minHeight, height);
      if (next != paneHeight(name)) {
        _paneHeights[name] = next;
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  /// How much of a wide screen's width it takes, from 0.2 to 1; on a
  /// phone (narrower than [DebugLayout.phoneWidth]) all of it.
  final double width;

  DebugCorner _position;
  bool _shown = false;

  @override
  String get action => 'debug.console';

  @override
  List<String> get keys => const ['primary+shift+o', 'taps:8+hold:2s'];

  @override
  bool handle(ShortcutInvocation invocation) {
    // Pressed again while it slides out: it comes back.
    shown = leaving || !shown;
    return true;
  }

  /// How long the slide in and out takes; 0: it shows and hides at once.
  final Duration slideDuration;

  bool get _slides => slideDuration > Duration.zero;

  bool _leaving = false;
  bool _arriving = false;
  int _views = 0;

  /// Whether it is sliding out: still shown until the view tells it is
  /// gone ([left]).
  bool get leaving => _leaving;

  /// A view of it is built: hidden from now on, it slides out first. True
  /// when the view slides in: the first one built since it was shown, not
  /// one built again while it stays (the debug panel closed, moved).
  bool attach() {
    _views++;
    final arriving = _arriving;
    _arriving = false;
    return arriving;
  }

  /// A view of it is gone; the last one gone while it slides out leaves it
  /// hidden, after this frame.
  void detach() {
    _views--;
    if (_views == 0 && _leaving) {
      SchedulerBinding.instance.addPostFrameCallback((_) => left());
    }
  }

  /// The view's slide out ended: hidden now.
  void left() {
    if (_leaving) {
      _leaving = false;
      _shown = false;
      notifyListeners();
    }
  }

  @override
  String get id => 'console';

  @override
  String get title => 'Console';

  @override
  DebugCorner get corner => _position;

  /// Moves the console to [value].
  set corner(DebugCorner value) {
    if (value != _position) {
      _position = value;
      notifyListeners();
    }
  }

  @override
  int get order => 30;

  @override
  bool get shown => _shown;

  @override
  set shown(bool value) {
    if (!value && _shown && _slides && _views > 0) {
      // Hidden: it slides out first, and is hidden when the view says so.
      if (!_leaving) {
        _leaving = true;
        notifyListeners();
      }
      return;
    }
    if (value != _shown || (value && _leaving)) {
      _arriving = value && !_shown && _slides;
      _shown = value;
      _leaving = false;
      notifyListeners();
    }
  }

  @override
  Size get size => DebugConsoleView.sizeOf([
    for (final name in _panes) paneHeight(name),
  ]);

  @override
  Widget build(BuildContext context) => DebugConsoleView(console: this);
}
