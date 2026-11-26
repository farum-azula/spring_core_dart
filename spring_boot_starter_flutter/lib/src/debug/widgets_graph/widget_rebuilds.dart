import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// The rebuilds of one element: when, how many within the window, how long
/// its own `build` took.
final class WidgetRebuildStats {
  final Queue<Duration> _at = Queue();

  /// When it was built last.
  Duration? last;

  /// How long its last build took by itself (the time until the next
  /// element of the frame started building), when measured.
  Duration? lastTook;

  Duration _took = Duration.zero;
  int _timed = 0;

  /// The mean of the builds measured.
  Duration? get averageTook => _timed == 0 ? null : _took ~/ _timed;

  /// How many times it was built within [window] of [now].
  int countWithin(Duration now, Duration window) {
    while (_at.isNotEmpty && now - _at.first > window) {
      _at.removeFirst();
    }
    return _at.length;
  }

  void _hit(Duration now) {
    last = now;
    _at.addLast(now);
    if (_at.length > 512) {
      _at.removeFirst();
    }
  }

  void _timedAs(Duration took) {
    lastTook = took;
    _took += took;
    _timed++;
  }
}

/// The rebuilds of the app's elements, heard while the widgets layer shows.
///
/// In a debug build every rebuild is heard (Flutter's
/// `debugOnRebuildDirtyWidget`, chained after any other listener such as
/// DevTools'), with the time each element's own `build` took: until the
/// next element of the frame starts building. Elsewhere the layer counts
/// what changed between two walks of the tree ([seen]).
final class WidgetRebuilds {
  /// The rebuilds, timed by [clock] (a monotonic one by default).
  WidgetRebuilds({Duration Function()? clock}) : _clock = clock ?? _monotonic;

  static final Stopwatch _since = Stopwatch()..start();
  static Duration _monotonic() => _since.elapsed;

  final Duration Function() _clock;

  /// The time of its clock.
  Duration get now => _clock();

  final Map<Element, WidgetRebuildStats> _stats = HashMap.identity();
  RebuildDirtyWidgetCallback? _previous;
  late final RebuildDirtyWidgetCallback _hook = _heard;
  bool _listening = false;
  WidgetRebuildStats? _open;
  Duration _openedAt = Duration.zero;
  bool _closing = false;

  /// Called after each rebuild heard, with the element.
  void Function(Element element)? onRebuild;

  /// Whether every rebuild is heard (a debug build).
  bool get hearsEach => _listening;

  /// Starts hearing rebuilds (a debug build), until [stop].
  void start() {
    if (_listening || !kDebugMode) {
      return;
    }
    _listening = true;
    _previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = _hook;
  }

  /// Stops hearing them; what was counted is forgotten.
  void stop() {
    if (_listening) {
      _listening = false;
      if (identical(debugOnRebuildDirtyWidget, _hook)) {
        debugOnRebuildDirtyWidget = _previous;
      }
      _previous = null;
    }
    _stats.clear();
    _open = null;
  }

  void _heard(Element element, bool builtOnce) {
    _previous?.call(element, builtOnce);
    record(element);
  }

  /// Counts a rebuild of [element] now; the build of the element heard
  /// before it in the frame ends here.
  void record(Element element) {
    final now = _clock();
    final open = _open;
    if (open != null) {
      open._timedAs(now - _openedAt);
    }
    final stats = _stats[element] ??= WidgetRebuildStats();
    stats._hit(now);
    _open = stats;
    _openedAt = now;
    if (!_closing) {
      _closing = true;
      // The last build of a frame is not timed: nothing marks its end.
      try {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _closing = false;
          _open = null;
        });
      } on Object {
        _closing = false;
      }
    }
    onRebuild?.call(element);
  }

  final Map<Element, (Widget, Widget?)> _widgets = HashMap.identity();

  /// Where every rebuild is not heard: notes [element] as rebuilt when its
  /// widget or its child's widget changed since the last walk.
  void seen(Element element, Widget? child) {
    if (_listening) {
      return;
    }
    final before = _widgets[element];
    _widgets[element] = (element.widget, child);
    if (before != null &&
        (!identical(before.$1, element.widget) ||
            !identical(before.$2, child))) {
      record(element);
    }
  }

  /// Forgets the elements no longer mounted.
  void prune() {
    _stats.removeWhere((element, _) => !element.mounted);
    _widgets.removeWhere((element, _) => !element.mounted);
  }

  /// The rebuilds of [element], or `null` when none was heard.
  WidgetRebuildStats? of(Element element) => _stats[element];

  /// Every element heard of, with its rebuilds.
  Map<Element, WidgetRebuildStats> get all => _stats;

  /// Frees what it keeps.
  void dispose() {
    stop();
    _widgets.clear();
  }
}
