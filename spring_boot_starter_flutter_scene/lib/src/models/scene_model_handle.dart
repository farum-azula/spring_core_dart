import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_engine.dart';
import 'package:spring_boot_starter_flutter_scene/src/models/scene_model_importer.dart';
import 'package:spring_boot_starter_flutter_scene/src/scene_events.dart';

const _log = SpringLog('spring.flutter.scene');

/// Where a model's load is.
enum SceneModelState {
  /// Not asked for yet.
  idle,

  /// Its file is being read and imported.
  loading,

  /// Loaded: [SceneModelHandle.template] is there.
  ready,

  /// The load failed.
  failed,
}

/// A model of `spring.flutter.scene.models.<name>`: its load, once, and
/// the template every use of it clones (the geometry, textures and
/// materials stay shared on the GPU). It notifies its listeners when its
/// [state] or [hidden] changes.
///
/// Taken from `SceneModels` by its name; a `SpringSceneModel` widget shows
/// it in a scene.
final class SceneModelHandle extends ChangeNotifier {
  /// Model [name] read from [resource], which the app named as
  /// [location].
  SceneModelHandle({
    required this.name,
    required this.location,
    required this.resource,
    required this.eager,
    required this.engine,
    required this.importer,
    required this.events,
  });

  /// The model's name.
  final String name;

  /// Where its file is, as the properties say.
  final String location;

  /// Its file.
  final Resource resource;

  /// Whether it is loaded with the splash.
  final bool eager;

  /// The engine, started for the load when nothing has yet.
  final SceneEngine engine;

  /// What reads the file.
  final SceneModelImporter importer;

  /// Where the steps of the load are published.
  final ApplicationEventPublisher events;

  Future<Node>? _load;
  SceneModelState _state = SceneModelState.idle;
  Node? _template;
  Object? _failure;
  int? _bytes;
  Duration? _readTook;
  Duration? _importTook;
  bool _hidden = false;

  /// Where the load is.
  SceneModelState get state => _state;

  /// The loaded node tree, cloned by every use; `null` until [state] is
  /// [SceneModelState.ready].
  Node? get template => _template;

  /// What the load threw, when it failed.
  Object? get failure => _failure;

  /// The size of the file, once read.
  int? get bytes => _bytes;

  /// How long the file took to read (to download, for an address).
  Duration? get readTook => _readTook;

  /// How long the import took: decoding, uploading to the GPU.
  Duration? get importTook => _importTook;

  /// Whether every use of the model is hidden: the debug panel's switch,
  /// for seeing what a frame costs without it.
  bool get hidden => _hidden;

  set hidden(bool value) {
    if (_hidden != value) {
      _hidden = value;
      notifyListeners();
    }
  }

  /// Loads the model, once: every call answers the same load. Starts the
  /// engine when nothing has yet. [index] of [count] is its place among
  /// the models loaded together, for the event.
  ///
  /// Throws what the load threw; a load that failed is tried again by
  /// [reload].
  Future<Node> load({int index = 1, int count = 1}) =>
      _load ??= _run(index, count);

  /// Loads the model again after a failure.
  Future<Node> reload() {
    _load = null;
    return load();
  }

  Future<Node> _run(int index, int count) async {
    _failure = null;
    _move(SceneModelState.loading);
    events.publishEvent(
      SceneModelLoadingEvent(
        this,
        name: name,
        location: location,
        index: index,
        count: count,
      ),
    );
    final watch = Stopwatch()..start();
    try {
      if (!await engine.start()) {
        throw StateError(
          'The 3D engine did not start, so model "$name" cannot be loaded.',
        );
      }
      final Uint8List bytes = await resource.readAsBytes();
      _bytes = bytes.length;
      _readTook = watch.elapsed;
      final template = await importer.import(bytes, name: name);
      _importTook = watch.elapsed - _readTook!;
      _template = template;
    } on Object catch (error, stackTrace) {
      _failure = error;
      _log.warning(
        'The model "$name" ($location) did not load',
        error: error,
        stackTrace: stackTrace,
      );
      _move(SceneModelState.failed);
      events.publishEvent(
        SceneFailedEvent(
          this,
          step: SceneStep.model,
          name: name,
          error: error,
        ),
      );
      rethrow;
    }
    _move(SceneModelState.ready);
    events.publishEvent(
      SceneModelLoadedEvent(
        this,
        name: name,
        took: watch.elapsed,
        bytes: _bytes!,
      ),
    );
    return _template!;
  }

  void _move(SceneModelState state) {
    _state = state;
    notifyListeners();
  }
}
