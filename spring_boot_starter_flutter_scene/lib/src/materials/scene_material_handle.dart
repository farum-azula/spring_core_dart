import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_engine.dart';
import 'package:spring_boot_starter_flutter_scene/src/materials/scene_material_loader.dart';
import 'package:spring_boot_starter_flutter_scene/src/scene_events.dart';

const _log = SpringLog('spring.flutter.scene');

/// Where a material's first load is.
enum SceneMaterialState {
  /// Not asked for yet.
  idle,

  /// Its compiled programs are being loaded.
  loading,

  /// Loaded: every use gets a material of its own at once.
  ready,

  /// The load failed.
  failed,
}

/// A material of `spring.flutter.scene.materials.<name>`: its first load,
/// timed, and a new material for every use (the compiled programs stay
/// shared, the parameters are the use's own). It notifies its listeners
/// when its [state], its uses or [hidden] change.
///
/// Taken from `SceneMaterials` by its name; a `SpringSceneMesh` widget
/// draws with it.
final class SceneMaterialHandle extends ChangeNotifier {
  /// Material [name] of the `.fmat` file at [location].
  SceneMaterialHandle({
    required this.name,
    required this.location,
    required this.eager,
    required this.engine,
    required this.loader,
    required this.events,
  });

  /// The material's name.
  final String name;

  /// Its `.fmat` file, as the properties say.
  final String location;

  /// Whether it is loaded with the splash.
  final bool eager;

  /// The engine, started for the load when nothing has yet.
  final SceneEngine engine;

  /// What makes the material.
  final SceneMaterialLoader loader;

  /// Where the steps of the load are published.
  final ApplicationEventPublisher events;

  Future<PreprocessedMaterial>? _first;
  PreprocessedMaterial? _spare;
  SceneMaterialState _state = SceneMaterialState.idle;
  Object? _failure;
  Duration? _took;
  bool? _withSplash;
  String? _shading;
  bool? _opaque;
  List<String> _parameters = const [];
  final Map<String, int> _uses = {};
  bool _hidden = false;
  bool _scheduled = false;

  /// Where the first load is.
  SceneMaterialState get state => _state;

  /// What the first load threw, when it failed.
  Object? get failure => _failure;

  /// How long the first load took.
  Duration? get took => _took;

  /// Whether the first load was made with the splash (`true`) or while
  /// the app ran (`false`); `null` before it.
  bool? get loadedWithSplash => _withSplash;

  /// How the material is lit (`unlit`, `lit`, `physical`, ...), once
  /// loaded.
  String? get shading => _shading;

  /// Whether it is drawn without blending, once loaded.
  bool? get opaque => _opaque;

  /// The names of its parameters, once loaded.
  List<String> get parameters => _parameters;

  /// The uses on the screen now, by the name of their scene.
  Map<String, int> get uses => UnmodifiableMapView(_uses);

  /// How many uses are on the screen now.
  int get useCount => _uses.values.fold(0, (sum, count) => sum + count);

  /// Whether every use is hidden: the debug panel's switch, for seeing
  /// what a frame costs without it.
  bool get hidden => _hidden;

  set hidden(bool value) {
    if (_hidden != value) {
      _hidden = value;
      notifyListeners();
    }
  }

  /// Loads the material once, with the splash: its first use then gets it
  /// at once. [index] of [count] is its place among the materials loaded
  /// together, for the event. Throws what the load threw.
  Future<void> preload({int index = 1, int count = 1}) =>
      _first ??= _run(index, count, withSplash: true);

  /// A material of its own for one use. The first load starts the engine
  /// when nothing has yet; a load that failed is tried again by
  /// [reload].
  Future<PreprocessedMaterial> create() async {
    final first = await (_first ??= _run(1, 1, withSplash: false));
    if (identical(_spare, first)) {
      _spare = null;
      return first;
    }
    return loader.load(location);
  }

  /// Loads the material again after a failure.
  Future<PreprocessedMaterial> reload() {
    _first = null;
    _spare = null;
    return create();
  }

  /// A use in the scene [scene] began.
  void use(String scene) {
    _uses[scene] = (_uses[scene] ?? 0) + 1;
    _notifyLater();
  }

  /// A use in the scene [scene] ended.
  void release(String scene) {
    final count = (_uses[scene] ?? 0) - 1;
    if (count > 0) {
      _uses[scene] = count;
    } else {
      _uses.remove(scene);
    }
    _notifyLater();
  }

  Future<PreprocessedMaterial> _run(
    int index,
    int count, {
    required bool withSplash,
  }) async {
    _failure = null;
    _move(SceneMaterialState.loading);
    events.publishEvent(
      SceneMaterialLoadingEvent(
        this,
        name: name,
        location: location,
        index: index,
        count: count,
      ),
    );
    final watch = Stopwatch()..start();
    final PreprocessedMaterial material;
    try {
      if (!await engine.start()) {
        throw StateError(
          'The 3D engine did not start, so material "$name" cannot be '
          'loaded.',
        );
      }
      material = await loader.load(location);
    } on Object catch (error, stackTrace) {
      _failure = error;
      _log.warning(
        'The material "$name" ($location) did not load',
        error: error,
        stackTrace: stackTrace,
      );
      _move(SceneMaterialState.failed);
      events.publishEvent(
        SceneFailedEvent(
          this,
          step: SceneStep.material,
          name: name,
          error: error,
        ),
      );
      rethrow;
    }
    _took = watch.elapsed;
    _withSplash = withSplash;
    _shading = material.shadingModel.name;
    _opaque = material.isOpaque();
    _parameters = List.unmodifiable(material.parameters.parameterNames);
    _spare = material;
    _move(SceneMaterialState.ready);
    events.publishEvent(
      SceneMaterialLoadedEvent(this, name: name, took: _took!),
    );
    return material;
  }

  void _move(SceneMaterialState state) {
    _state = state;
    notifyListeners();
  }

  // Uses begin and end while the scene's widgets are built: the
  // listeners (the debug panel) hear after it.
  void _notifyLater() {
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
