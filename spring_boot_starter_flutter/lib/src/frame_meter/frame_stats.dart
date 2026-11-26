import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:spring_boot_starter_flutter/src/frame_meter/outside_frames.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stage.dart';

/// The frames the app draws, measured only while something listens: the
/// frame meter's gauge and the debug console's `fps` and `frames-lost`
/// segments read it.
///
/// It takes Flutter's own times (`FrameTiming`) and notes, as each frame
/// ends, whether the app had asked for the next: a frame the app was
/// waiting for is measured by the time since the one before, one asked
/// for now and then by its own build and raster (few frames by choice are
/// not late). It tells its listeners at most four times a second, and
/// only when something changed; the frame their repaint costs is not
/// counted, so an idle app reads `idle`, not the meter.
///
/// Frames drawn without Flutter (a 3D scene, [OutsideFrames]) are read by
/// [outside].
class FrameStats extends ChangeNotifier {
  /// The frames against the budget of [targetRate]; nothing is counted
  /// until the app shows ([stages], `null`: at once).
  FrameStats({this.targetRate = 60, this.stages});

  /// The frames a second the screen is meant to show.
  final int targetRate;

  /// The stages of the start: until the app shows nothing is counted.
  final ValueListenable<SplashStage>? stages;

  /// The most frames kept: the bars of the meter's strip.
  static const int kept = 48;

  static const _window = 1000000;
  static const _pause = 250000;

  final _frames = ListQueue<_Frame>();
  // For each frame that ended, in order: whether it was drawn for the
  // listeners alone, and whether the next one was asked for already.
  final _ends = ListQueue<({bool own, bool next})>();
  bool _awaited = false;
  int? _lastStart;
  bool _mine = false;
  bool _fresh = false;
  int _outside = 0;
  bool _outsideShown = false;
  Timer? _timer;
  bool _watching = false;
  FrameReading? _reading;

  /// The time a frame may take, in microseconds.
  int get budget => 1000000 ~/ targetRate;

  /// Whether it measures now (something listens).
  bool get measuring => _timer != null;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_timer == null) {
      _start();
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _stop();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  bool get _started => stages == null || stages!.value == SplashStage.app;

  void _start() {
    SchedulerBinding.instance.addTimingsCallback(_timings);
    if (!_watching) {
      _watching = true;
      _watch();
    }
    stages?.addListener(_stageChanged);
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  void _stop() {
    if (_timer == null) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    stages?.removeListener(_stageChanged);
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    _frames.clear();
    _ends.clear();
    _lastStart = null;
    _awaited = false;
    _reading = null;
  }

  void _tick() {
    final outside = OutsideFrames.all.fold(0, (sum, s) => sum + s.count);
    final moved = outside != _outside;
    _outside = outside;
    if (_fresh || moved || _outsideShown) {
      _fresh = false;
      _outsideShown = moved;
      _reading = null;
      // A frame that is coming anyway carries the repaint with it, and
      // stays the app's.
      _mine = !SchedulerBinding.instance.hasScheduledFrame;
      notifyListeners();
    }
  }

  void _stageChanged() {
    if (_started) {
      _reading = null;
      notifyListeners();
    }
  }

  // Notes, as each frame ends, whether the app has asked for the next: a
  // callback after the frame that puts itself back while measuring, and
  // asks for no frame itself.
  void _watch() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_timer == null) {
        _watching = false;
        return;
      }
      _ends.addLast((
        own: _mine,
        next: SchedulerBinding.instance.hasScheduledFrame,
      ));
      _mine = false;
      while (_ends.length > 600) {
        _ends.removeFirst();
      }
      _watch();
    });
  }

  void _timings(List<FrameTiming> timings) {
    if (!_started) {
      return;
    }
    for (final timing in timings) {
      final start = timing.timestampInMicroseconds(FramePhase.vsyncStart);
      final end = _ends.isEmpty ? null : _ends.removeFirst();
      final awaited = _awaited;
      _awaited = end?.next ?? false;
      // The listeners' own repaint: not the app's, and not a frame
      // between two of the app's either.
      if (end?.own ?? false) {
        continue;
      }
      final last = _lastStart;
      _lastStart = start;
      _frames.addLast((
        start: start,
        interval: last == null || (!awaited && start - last > _pause)
            ? 0
            : start - last,
        build: timing.buildDuration.inMicroseconds,
        raster: timing.rasterDuration.inMicroseconds,
        awaited: awaited,
      ));
      _fresh = true;
    }
    while (_frames.length > kept) {
      _frames.removeFirst();
    }
  }

  /// What the frames say now; `null` until the app shows.
  FrameReading? get reading {
    if (!_started) {
      return null;
    }
    return _reading ??= FrameReading._of(_frames.toList(), budget);
  }
}

typedef _Frame = ({
  int start,
  int interval,
  int build,
  int raster,
  bool awaited,
});

extension on _Frame {
  // How long the frame took to come once it was wanted.
  int get took => awaited && interval > 0 ? interval : build + raster;
}

/// How a frame did against the budget: within it (a fifth over allowed),
/// up to twice it, or over.
enum FrameStatus {
  /// Within the budget.
  good,

  /// Up to twice the budget.
  warning,

  /// Over twice the budget.
  bad,
}

/// What [FrameStats] read of the last frames.
final class FrameReading {
  FrameReading._({
    required this.took,
    required this.budget,
    required this.rate,
    required this.moving,
    required this.build,
    required this.raster,
    required this.worst,
    required this.lost,
  });

  factory FrameReading._of(List<_Frame> frames, int budget) {
    final last = frames.isEmpty ? null : frames.last.start;
    final recent = [
      for (final frame in frames)
        if (last != null && last - frame.start < FrameStats._window) frame,
    ];
    final moving = <int>[
      for (final frame in recent)
        if (frame.awaited && frame.interval > 0) frame.interval,
    ];
    final paced = <int>[
      if (moving.isEmpty)
        for (final (i, frame) in recent.indexed)
          if (i > 0 && frame.interval > 0) frame.interval,
    ];
    final between = moving.isEmpty ? paced : moving;
    double average(int Function(_Frame) of) => recent.isEmpty
        ? 0
        : recent.map(of).reduce((a, b) => a + b) / recent.length / 1000;
    final took = [for (final frame in frames) frame.took];
    final recentTook = [for (final frame in recent) frame.took];
    return FrameReading._(
      took: took,
      budget: budget,
      rate: between.isEmpty
          ? 0
          : (between.length * 1e6 / between.reduce((a, b) => a + b)).round(),
      moving: moving.isNotEmpty,
      build: average((f) => f.build),
      raster: average((f) => f.raster),
      worst: recentTook.isEmpty ? 0 : recentTook.reduce(math.max),
      lost: [
        for (final t in recentTook)
          if (statusOf(t, budget) != FrameStatus.good) t,
      ].length,
    );
  }

  /// The time each kept frame took to come once it was wanted, oldest
  /// first, in microseconds.
  final List<int> took;

  /// The time a frame may take, in microseconds.
  final int budget;

  /// The frames a second over the last second; 0: idle.
  final int rate;

  /// Whether something moved at every frame (the app was waiting for
  /// them); else the frames were asked for now and then, few by choice.
  final bool moving;

  /// The average build time of the last second, in milliseconds.
  final double build;

  /// The average raster time of the last second, in milliseconds.
  final double raster;

  /// The longest frame of the last second, in microseconds.
  final int worst;

  /// How many frames of the last second were over the budget.
  final int lost;

  /// Whether nothing was drawn in the last second.
  bool get idle => rate == 0;

  /// How the frames of the last second did: good without a lost frame,
  /// bad with one over twice the budget, else a warning.
  FrameStatus get status => lost == 0
      ? FrameStatus.good
      : statusOf(worst, budget) == FrameStatus.bad
      ? FrameStatus.bad
      : FrameStatus.warning;

  /// How a frame that took [took] did against [budget].
  static FrameStatus statusOf(int took, int budget) => took <= budget * 1.2
      ? FrameStatus.good
      : took <= budget * 2
      ? FrameStatus.warning
      : FrameStatus.bad;
}
