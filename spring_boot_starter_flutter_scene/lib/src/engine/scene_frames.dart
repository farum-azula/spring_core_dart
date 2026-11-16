import 'dart:async';

import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show OutsideFrames;
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_ticks.dart';

/// The frames of every moving scene of the app, from one beat.
///
/// The engine's view ticks with the display: every refresh (60 or 120 a
/// second) is a frame of Flutter, even when the scene draws 24 of them,
/// and on the web every frame of Flutter draws the whole page again. The
/// starter's views do not tick: each moving view joins here with the
/// frames a second it may draw, and on each beat it is asked whether it is
/// due. The views draw on the same beat, so the page is drawn once for
/// all of them: 30 times a second for a scene of 30 and one of 24, not 60
/// or 120. The beat is a timer at the highest of their rates, and in a
/// browser its frames (`requestAnimationFrame`), in step with the page's.
final class SceneFrames {
  final Map<Object, ({double rate, bool Function() beat})> _views = {};
  void Function()? _stop;
  final OutsideFrames _frames = OutsideFrames.of('3D');
  double _rate = 0;

  /// The frames a second the views move at now, 0 when nothing moves.
  double get rate => _rate;

  /// The views that move now.
  int get moving => _views.length;

  /// [view] moves at up to [rate] frames a second: [beat] is called on
  /// each beat, draws when the view is due, and says whether it drew a
  /// frame Flutter does not draw (on a canvas of the scene's own or the
  /// engine's). Those are the frame meter's `3D` ([OutsideFrames]): how
  /// many a second, and what a beat that drew cost the page's thread.
  void join(Object view, double rate, bool Function() beat) {
    final joined = _views[view];
    if (joined != null && joined.rate == rate) {
      _views[view] = (rate: rate, beat: beat);
      return;
    }
    _views[view] = (rate: rate, beat: beat);
    _retime();
  }

  /// [view] stands still or is gone.
  void leave(Object view) {
    if (_views.remove(view) != null) {
      _retime();
    }
  }

  /// Stops the beat.
  void dispose() {
    _views.clear();
    _retime();
  }

  void _retime() {
    var rate = 0.0;
    for (final view in _views.values) {
      if (view.rate > rate) {
        rate = view.rate;
      }
    }
    if (rate == _rate) {
      return;
    }
    _rate = rate;
    _stop?.call();
    _stop = rate <= 0
        ? null
        : startSceneTicks(
            // As many as the screen shows (a browser's frames): no period.
            rate.isInfinite
                ? Duration.zero
                : Duration(
                    microseconds: (Duration.microsecondsPerSecond / rate)
                        .round(),
                  ),
            _beat,
          );
  }

  void _beat() {
    final watch = Stopwatch()..start();
    var drew = false;
    for (final view in [..._views.values]) {
      if (view.beat()) {
        drew = true;
      }
    }
    if (drew) {
      // After the canvas the views drew on is drawn anew (a task of its
      // own, queued as they drew).
      scheduleMicrotask(() => _frames.frame(watch.elapsed));
    }
  }
}
