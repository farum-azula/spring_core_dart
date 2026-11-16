import 'package:flutter/foundation.dart';
import 'package:spring_boot_starter_flutter_scene/src/conditions/scene_condition.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_frames.dart';

/// `slow`: the scenes cost this device too much, decided by their own
/// frames before they show, and never by switching them off in front of
/// the user.
///
/// - **While the first scenes load** their placeholders show, and they draw
///   frames nobody sees. The first [warmUp] are left out (the engine builds
///   its programs on them), and the next [probe] are measured: what a beat
///   of every moving scene cost the page's thread, the scenes' own work,
///   not the page's (a page that decodes its images meanwhile is no reason
///   to lose its 3D). When the middle one takes more than half of
///   [frameTime], the condition holds, and the scenes show in the mode of
///   `spring.flutter.scene.when.slow` from their first frame.
/// - **After they show**, beats that cost more than half of [frameTime]
///   for [after] on end only mark it: it holds once no scene moves (the
///   user left the scenes), never while one is on the screen.
///
/// Once it holds it holds for the rest of the run. It follows nothing
/// unless `spring.flutter.scene.when` names it.
final class SlowFramesSceneCondition extends ChangeNotifier
    implements SceneCondition {
  /// The condition over [frames], by [frameTime] and [after]; [probe]
  /// frames measured after [warmUp] left out. [clock] is the time, for a
  /// test's own.
  SlowFramesSceneCondition({
    required this.frames,
    this.frameTime = const Duration(milliseconds: 16),
    this.after = const Duration(seconds: 3),
    this.probe = 24,
    this.warmUp = 6,
    @visibleForTesting Duration Function()? clock,
  }) : _clock = clock ?? _stopwatch;

  /// The moving scenes, whose beats are measured.
  final SceneFrames frames;

  /// The time of a frame: a beat of the scenes taking more than half of it
  /// is slow.
  final Duration frameTime;

  /// How long beats are slow, on end, after the scenes show, before the
  /// condition holds at the next moment no scene moves.
  final Duration after;

  /// How many frames are measured before the scenes show.
  final int probe;

  /// How many first frames are left out of the measure.
  final int warmUp;

  final Duration Function() _clock;

  static final Stopwatch _watch = Stopwatch()..start();
  static Duration _stopwatch() => _watch.elapsed;

  // A probe that is slow to come (a scene drawn twice a second) ends after
  // this with what it has.
  static const Duration _longest = Duration(seconds: 3);
  // After the scenes show, the beats are judged in windows of this many.
  static const int _window = 60;

  _Phase _phase = _Phase.idle;
  int _seen = 0;
  final List<int> _costs = [];
  Duration? _firstMeasured;
  Duration? _windowStart;
  Duration _slowFor = Duration.zero;
  Duration? _middle;

  @override
  String get name => 'slow';

  @override
  bool get holds => _phase == _Phase.held;

  @override
  bool get settled => _phase != _Phase.probing;

  /// The middle beat of the last measure, `null` before one.
  Duration? get middle => _middle;

  @override
  String get state {
    final middle = _middle;
    final measured = middle == null
        ? 'not measured'
        : '${_ms(middle)} a beat of the scenes, of ${_ms(frameTime ~/ 2)}';
    return switch (_phase) {
      _Phase.idle => 'not followed',
      _Phase.probing =>
        'measuring the first scenes ($_measuredCount of $probe frames)',
      _Phase.watching => measured,
      _Phase.marked => 'slow: $measured; holds when no scene moves',
      _Phase.held => 'slow: $measured',
    };
  }

  int get _measuredCount => _seen <= warmUp ? 0 : _seen - warmUp;

  /// Starts measuring: the scenes that move wait for it to know before
  /// they show.
  void start() {
    if (_phase != _Phase.idle) {
      return;
    }
    _phase = _Phase.probing;
    frames
      ..addDrawnListener(_drawn)
      ..addRestListener(_rested);
    notifyListeners();
  }

  /// A beat that drew, which cost [cost] (as [SceneFrames] tells it).
  @visibleForTesting
  void drawn(Duration cost) => _drawn(cost);

  void _drawn(Duration cost) {
    final now = _clock();
    switch (_phase) {
      case _Phase.probing:
        _seen++;
        if (_seen <= warmUp) {
          return;
        }
        final first = _firstMeasured ??= now;
        _costs.add(cost.inMicroseconds);
        if (_costs.length >= probe || now - first >= _longest) {
          _decide();
        }
      case _Phase.watching:
        final start = _windowStart ??= now;
        _costs.add(cost.inMicroseconds);
        if (_costs.length < _window) {
          return;
        }
        final slow = _slow();
        _windowStart = null;
        if (!slow) {
          _slowFor = Duration.zero;
          return;
        }
        _slowFor += now - start;
        if (_slowFor >= after) {
          _phase = _Phase.marked;
          notifyListeners();
        }
      case _Phase.idle || _Phase.marked || _Phase.held:
        return;
    }
  }

  void _decide() {
    final slow = _slow();
    _phase = slow ? _Phase.held : _Phase.watching;
    if (slow) {
      _stop();
    }
    notifyListeners();
  }

  // Whether the middle beat of those kept takes more than half a frame;
  // the beats kept are dropped.
  bool _slow() {
    final costs = [..._costs]..sort();
    _costs.clear();
    if (costs.isEmpty) {
      return false;
    }
    final middle = _middle = Duration(microseconds: costs[costs.length ~/ 2]);
    return middle > frameTime ~/ 2;
  }

  void _rested() {
    if (_phase == _Phase.marked) {
      _phase = _Phase.held;
      _stop();
      notifyListeners();
    }
  }

  void _stop() {
    frames
      ..removeDrawnListener(_drawn)
      ..removeRestListener(_rested);
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  static String _ms(Duration time) =>
      '${(time.inMicroseconds / 1000).toStringAsFixed(1)} ms';
}

enum _Phase { idle, probing, watching, marked, held }
