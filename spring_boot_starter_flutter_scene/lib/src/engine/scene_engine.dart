import 'package:flutter/foundation.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_backend.dart';
import 'package:spring_boot_starter_flutter_scene/src/scene_events.dart';

const _log = SpringLog('spring.flutter.scene');

/// Where the engine's start is.
enum SceneEngineState {
  /// Not asked for yet.
  idle,

  /// Starting.
  starting,

  /// Started: scenes draw.
  ready,

  /// It did not start: scenes show their placeholders.
  failed,
}

/// The one start of the 3D engine for the application: with the splash
/// (`spring.flutter.scene.preload: eager`) or when the first scene shows.
/// Its steps are application events ([SceneEngineStartingEvent],
/// [SceneEngineReadyEvent], [SceneFailedEvent]); it notifies its listeners
/// when its [state] changes.
///
/// A failed start is not a failed app: [start] answers `false`, the
/// failure is kept in [failure] and logged once.
final class SceneEngine extends ChangeNotifier {
  /// The engine of [backend], its steps published to [events].
  SceneEngine({required this.backend, required this.events});

  /// What draws.
  final SceneBackend backend;

  /// Where the steps are published.
  final ApplicationEventPublisher events;

  Future<bool>? _start;
  SceneEngineState _state = SceneEngineState.idle;
  Object? _failure;
  Duration? _took;

  /// Where the start is.
  SceneEngineState get state => _state;

  /// Whether scenes can draw now.
  bool get isReady => _state == SceneEngineState.ready;

  /// Whether the start failed.
  bool get hasFailed => _state == SceneEngineState.failed;

  /// What the start threw, when it failed.
  Object? get failure => _failure;

  /// How long the start took, once it ended.
  Duration? get took => _took;

  /// Starts the engine, once: every call answers the same start. `true`
  /// when scenes can draw, `false` when the start failed.
  Future<bool> start() => _start ??= _run();

  Future<bool> _run() async {
    final watch = Stopwatch()..start();
    _move(SceneEngineState.starting);
    events.publishEvent(SceneEngineStartingEvent(this, backend: backend.name));
    try {
      await backend.start();
    } on Object catch (error, stackTrace) {
      _took = watch.elapsed;
      _failure = error;
      _log.warning(
        'The 3D engine (${backend.name}) did not start: scenes show '
        'their placeholders',
        error: error,
        stackTrace: stackTrace,
      );
      _move(SceneEngineState.failed);
      events
        ..publishEvent(
          SceneFailedEvent(this, step: SceneStep.engine, error: error),
        )
        ..publishEvent(
          SceneUnavailableEvent(this, reason: SceneUnavailable.engine),
        );
      return false;
    }
    _took = watch.elapsed;
    _move(SceneEngineState.ready);
    events.publishEvent(
      SceneEngineReadyEvent(this, backend: backend.name, took: watch.elapsed),
    );
    return true;
  }

  void _move(SceneEngineState state) {
    _state = state;
    notifyListeners();
  }
}
