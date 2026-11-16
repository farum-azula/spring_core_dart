import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:spring_boot_starter_flutter_scene/src/conditions/scene_condition.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_frames.dart';

/// `slow`: while scenes move, the frames of the app take longer than
/// [frameTime] on this device (the middle one of each batch Flutter
/// reports, its build and its drawing), for [after] on end. A phone that
/// heats up slows down, and a page that keeps it busy heats it more: past
/// this, scenes take the mode of `spring.flutter.scene.when.slow` for the
/// rest of the run, and do not come back to be slow again.
final class SlowFramesSceneCondition extends ChangeNotifier
    implements SceneCondition {
  /// The condition over [frames], by [frameTime] and [after].
  SlowFramesSceneCondition({
    required this.frames,
    this.frameTime = const Duration(milliseconds: 16),
    this.after = const Duration(seconds: 3),
  });

  /// The moving scenes: frames are measured only while one moves.
  final SceneFrames frames;

  /// The time of a frame past which it is slow.
  final Duration frameTime;

  /// How long frames are slow before the condition holds.
  final Duration after;

  bool _holds = false;
  bool _listening = false;
  Duration? _middle;
  Duration _slowFor = Duration.zero;

  @override
  String get name => 'slow';

  @override
  bool get holds => _holds;

  /// The middle frame of the last batch, `null` before one.
  Duration? get middle => _middle;

  @override
  String get state {
    final middle = _middle;
    final measured = middle == null
        ? 'not measured yet'
        : '${_ms(middle)} a frame of ${_ms(frameTime)}';
    return _holds ? 'slow: $measured' : measured;
  }

  /// Starts hearing Flutter's frame times.
  void start() {
    if (_listening || _holds) {
      return;
    }
    _listening = true;
    SchedulerBinding.instance.addTimingsCallback(_timings);
  }

  /// Flutter's frame times, as it reports them: a batch at a time.
  @visibleForTesting
  void timings(List<FrameTiming> batch) => _timings(batch);

  void _timings(List<FrameTiming> batch) {
    if (_holds || batch.isEmpty) {
      return;
    }
    if (frames.moving == 0) {
      _slowFor = Duration.zero;
      return;
    }
    final times = [
      for (final timing in batch) timing.buildDuration + timing.rasterDuration,
    ]..sort();
    final middle = _middle = times[times.length ~/ 2];
    if (middle <= frameTime) {
      _slowFor = Duration.zero;
      return;
    }
    final span =
        batch.last.timestampInMicroseconds(FramePhase.rasterFinish) -
        batch.first.timestampInMicroseconds(FramePhase.vsyncStart);
    _slowFor += Duration(microseconds: span > 0 ? span : 0);
    if (_slowFor >= after) {
      _holds = true;
      _stop();
      notifyListeners();
    }
  }

  void _stop() {
    if (_listening) {
      _listening = false;
      SchedulerBinding.instance.removeTimingsCallback(_timings);
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  static String _ms(Duration time) =>
      '${(time.inMicroseconds / 1000).toStringAsFixed(1)} ms';
}
