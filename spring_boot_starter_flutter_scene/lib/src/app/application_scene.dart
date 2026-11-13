import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter_scene/src/app/scene_customizer.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_engine.dart';
import 'package:spring_boot_starter_flutter_scene/src/properties/scene_properties.dart';
import 'package:spring_boot_starter_flutter_scene/src/scene_events.dart';
import 'package:vector_math/vector_math.dart' as vm;

const _log = SpringLog('spring.flutter.scene');

/// The scene of the whole application
/// (`spring.flutter.scene.app.enabled: true`): one `Scene` the app owns,
/// made with the splash once the engine started, changed by the
/// [SceneCustomizer] beans. It shows under every screen
/// (`placement: background`) and in every `SpringSceneView()`; a screen
/// adds to it with the engine's `SceneSubtree` and takes its part away
/// when it leaves.
///
/// It notifies its listeners when [scene] is there.
final class ApplicationScene extends ChangeNotifier {
  /// The scene by [properties], made after [engine] starts and changed by
  /// [customizers]; [factory] makes the engine's object (a test gives its
  /// own, since a `Scene` needs a GPU).
  ApplicationScene({
    required this.properties,
    required this.engine,
    required this.events,
    this.customizers = const [],
    Scene Function()? factory,
  }) : _factory = factory ?? Scene.new;

  /// What the app asks for.
  final ApplicationSceneProperties properties;

  /// The engine.
  final SceneEngine engine;

  /// Where a failure is published.
  final ApplicationEventPublisher events;

  /// What changes the scene when it is made.
  final List<SceneCustomizer> customizers;

  final Scene Function() _factory;
  Future<Scene?>? _create;
  Scene? _scene;

  /// The scene, `null` until it is made (and for good where the engine
  /// did not start).
  Scene? get scene => _scene;

  /// The camera of `spring.flutter.scene.app.camera`, for a view that
  /// gives none.
  Camera get camera => PerspectiveCamera(
    fovRadiansY: properties.camera.fov * math.pi / 180,
    position: _vector(properties.camera.position, 'position'),
    target: _vector(properties.camera.target, 'target'),
  );

  /// Makes the scene, once: every call answers the same one. `null` when
  /// the engine did not start or a customizer failed.
  Future<Scene?> create() => _create ??= _run();

  Future<Scene?> _run() async {
    if (!await engine.start()) {
      return null;
    }
    try {
      final scene = _factory();
      for (final customizer in customizers) {
        await customizer.customize(scene);
      }
      _scene = scene;
    } on Object catch (error, stackTrace) {
      _log.warning(
        "The application's scene was not made",
        error: error,
        stackTrace: stackTrace,
      );
      events.publishEvent(
        SceneFailedEvent(this, step: SceneStep.application, error: error),
      );
      return null;
    }
    notifyListeners();
    return _scene;
  }

  static vm.Vector3 _vector(List<double> values, String key) {
    if (values.length != 3) {
      throw StateError(
        'spring.flutter.scene.app.camera.$key takes three numbers '
        '(x, y, z), not ${values.length}.',
      );
    }
    return vm.Vector3(values[0], values[1], values[2]);
  }

  @override
  void dispose() {
    _scene?.dispose();
    super.dispose();
  }
}
