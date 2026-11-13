import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show HttpTransport;
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_engine.dart';
import 'package:spring_boot_starter_flutter_scene/src/models/scene_model_handle.dart';
import 'package:spring_boot_starter_flutter_scene/src/models/remote_model_resource.dart';
import 'package:spring_boot_starter_flutter_scene/src/models/scene_model_importer.dart';
import 'package:spring_boot_starter_flutter_scene/src/properties/scene_properties.dart';

/// The models of `spring.flutter.scene.models.*`, by name:
///
/// ```yaml
/// spring:
///   flutter:
///     scene:
///       models:
///         hero:
///           source: asset:assets/models/hero.glb
///           preload: eager
/// ```
///
/// ```dart
/// @Component()
/// class Showroom {
///   Showroom(this.models);
///
///   final ObjectProvider<SceneModels> models;
///
///   // No bean when the app runs with scenes turned off.
///   Future<void> open() async => models.getIfAvailable()?['hero'].load();
/// }
/// ```
///
/// A scene shows one with the `SpringSceneModel` widget. An eager model is
/// loaded while the splash shows; a lazy one when a scene first shows it.
final class SceneModels {
  /// The models of [properties], their files found by [resources]; one
  /// at an address is read through [transport] (the platform's client
  /// when `null`), `http` only with [allowInsecure].
  SceneModels({
    required SceneProperties properties,
    required ResourceLoader resources,
    required SceneEngine engine,
    required SceneModelImporter importer,
    required ApplicationEventPublisher events,
    HttpTransport? transport,
    bool allowInsecure = false,
  }) : _handles = {
         for (final MapEntry(key: name, value: model)
             in (properties.models ?? const {}).entries)
           name: SceneModelHandle(
             name: name,
             location: _location(name, model),
             resource: _resource(
               _location(name, model),
               resources,
               transport: transport,
               allowInsecure: allowInsecure,
             ),
             eager: (model.preload ?? properties.preload) == SceneLoad.eager,
             engine: engine,
             importer: importer,
             events: events,
           ),
       };

  final Map<String, SceneModelHandle> _handles;

  static String _location(String name, SceneModelProperties model) =>
      model.source ??
      (throw StateError(
        'The model "$name" has no source: set '
        'spring.flutter.scene.models.$name.source '
        '(asset:assets/models/$name.glb, or an https address).',
      ));

  /// The file at [location]: an address is read by the starter's own
  /// GET (the framework's `UrlResource` does not read in a browser),
  /// anything else by [resources].
  static Resource _resource(
    String location,
    ResourceLoader resources, {
    required HttpTransport? transport,
    required bool allowInsecure,
  }) => location.startsWith('https:') || location.startsWith('http:')
      ? RemoteModelResource(
          Uri.parse(location),
          transport: transport,
          allowInsecure: allowInsecure,
        )
      : resources.getResource(location);

  /// The names of the models.
  Iterable<String> get names => _handles.keys;

  /// Every model.
  Iterable<SceneModelHandle> get all => _handles.values;

  /// The models loaded with the splash.
  Iterable<SceneModelHandle> get eager => all.where((model) => model.eager);

  /// Whether there is a model [name].
  bool contains(String name) => _handles.containsKey(name);

  /// The model [name]. Throws when the properties have none of that name.
  SceneModelHandle operator [](String name) =>
      _handles[name] ??
      (throw StateError(
        'No model "$name" in spring.flutter.scene.models: '
        '${_handles.isEmpty ? 'none is declared' : names.join(', ')}.',
      ));

  /// Loads the eager models one after another; [progress] takes the share
  /// done, from 0 to 1. A model that fails is logged, published as a
  /// `SceneFailedEvent` and skipped: its scenes show their placeholders.
  Future<void> preload({void Function(double fraction)? progress}) async {
    final models = eager.toList();
    for (final (index, model) in models.indexed) {
      try {
        await model.load(index: index + 1, count: models.length);
      } on Object catch (_) {
        // Logged and published by the model.
      }
      progress?.call((index + 1) / models.length);
    }
  }

  /// Frees the listeners of every model.
  void dispose() {
    for (final model in all) {
      model.dispose();
    }
  }
}
