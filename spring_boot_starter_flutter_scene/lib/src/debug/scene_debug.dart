import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:spring_boot_starter_flutter_scene/src/widgets/scene_view_observer.dart';

/// What the scenes' debug panel knows of the views on the screen: every
/// `SpringSceneView` (and `SceneBackdrop`) by its name, with the frames
/// it draws. It notifies its listeners when a view opens, closes or
/// changes how it draws, not for each frame: the panel reads the numbers
/// on its own clock.
///
/// Only in a build with the panel (`spring.flutter.scene.debug.enabled`).
final class SceneDebug extends ChangeNotifier implements SceneViewObserver {
  final List<SceneViewRecord> _views = [];
  bool _scheduled = false;

  /// The views on the screen, in the order they opened.
  List<SceneViewRecord> get views => UnmodifiableListView(_views);

  @override
  SceneViewMeasure opened(String name, SceneViewState state) {
    final record = SceneViewRecord._(this, name, state);
    _views.add(record);
    _notify();
    return record;
  }

  /// Views report while they are built: the listeners hear after it.
  void _notify() {
    if (_scheduled) {
      return;
    }
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      notifyListeners();
    });
  }
}

/// One view in the [SceneDebug]: what it shows and how fast.
final class SceneViewRecord implements SceneViewMeasure {
  SceneViewRecord._(this._debug, this.name, this._state);

  final SceneDebug _debug;

  /// The view's name.
  final String name;

  SceneViewState _state;
  final Queue<int> _frames = Queue<int>();
  final Stopwatch _clock = Stopwatch()..start();
  int _count = 0;
  Duration _last = Duration.zero;

  /// What the view shows now.
  SceneViewState get state => _state;

  /// Every frame it drew since it opened.
  int get frameCount => _count;

  /// The time between its last two frames.
  Duration get lastFrame => _last;

  /// The frames it drew in the last second.
  int get framesPerSecond {
    _trim();
    return _frames.length;
  }

  /// The engine's numbers of its scene's last frame: draw calls,
  /// vertices, the passes and their time on the page's thread. `null`
  /// before the first frame.
  RenderFrameStats? get stats => _state.scene?.renderStats.latest;

  @override
  void frame(Duration delta) {
    _count++;
    _last = delta;
    _frames.add(_clock.elapsedMilliseconds);
    _trim();
  }

  @override
  void changed(SceneViewState state) {
    final same =
        identical(state.scene, _state.scene) &&
        state.animated == _state.animated &&
        state.frameRate == _state.frameRate &&
        state.pixelRatio == _state.pixelRatio &&
        state.paused == _state.paused;
    _state = state;
    if (!same) {
      _debug._notify();
    }
  }

  @override
  void closed() {
    _debug
      .._views.remove(this)
      .._notify();
  }

  void _trim() {
    final from = _clock.elapsedMilliseconds - 1000;
    while (_frames.isNotEmpty && _frames.first < from) {
      _frames.removeFirst();
    }
  }
}
