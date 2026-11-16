import 'dart:collection';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Frames the app draws without Flutter, by what draws them: a 3D scene
/// drawn on a canvas of its own under the page has a frame of its own
/// that is no frame of Flutter, and the frame meter would say `idle`
/// while it moves at 60 a second.
///
/// What draws them reports each one with what it cost the page's thread
/// ([frame]); the frame meter shows each source beside Flutter's frames
/// (`3D 60 fps · 2.1 ms`).
final class OutsideFrames {
  OutsideFrames._(this.name);

  /// The source named [name] (`3D`), made the first time it is asked for.
  static OutsideFrames of(String name) =>
      _sources.putIfAbsent(name, () => OutsideFrames._(name));

  static final Map<String, OutsideFrames> _sources = {};
  static final Stopwatch _stopwatch = Stopwatch()..start();
  static int Function() _now = () => _stopwatch.elapsedMicroseconds;

  /// The clock, in microseconds, for a test's own.
  @visibleForTesting
  static set clock(int Function() now) => _now = now;

  /// Forgets every source and puts the clock back, after a test.
  @visibleForTesting
  static void reset() {
    _sources.clear();
    _now = () => _stopwatch.elapsedMicroseconds;
  }

  /// Every source that reported.
  static Iterable<OutsideFrames> get all => _sources.values;

  /// What it is, shown by the meter.
  final String name;

  final ListQueue<({int at, int cost})> _frames = ListQueue();
  int _count = 0;

  /// How many frames it reported so far.
  int get count => _count;

  /// A frame drawn now, which took [cost] of the page's thread.
  void frame(Duration cost) {
    _count++;
    _frames.addLast((
      at: _now(),
      cost: cost.inMicroseconds,
    ));
    while (_frames.length > 240) {
      _frames.removeFirst();
    }
  }

  /// Its frames of the last second: how many a second, and what one cost
  /// on average, in milliseconds; `null` when it drew none.
  ({int rate, double cost})? get recent {
    final now = _now();
    var count = 0;
    var cost = 0;
    int? first;
    var last = 0;
    for (final frame in _frames) {
      if (now - frame.at <= 1000000) {
        count++;
        cost += frame.cost;
        first ??= frame.at;
        last = frame.at;
      }
    }
    if (count < 2 || first == null || last <= first) {
      return null;
    }
    // The time between the first and the last frame of the second.
    return (
      rate: ((count - 1) * 1e6 / (last - first)).round(),
      cost: cost / count / 1000,
    );
  }
}
