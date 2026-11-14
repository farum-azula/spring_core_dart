import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_engine.dart';
import 'package:spring_boot_starter_flutter_scene/src/materials/scene_material_handle.dart';
import 'package:spring_boot_starter_flutter_scene/src/materials/scene_material_loader.dart';
import 'package:spring_boot_starter_flutter_scene/src/properties/scene_properties.dart';

/// The materials of `spring.flutter.scene.materials.*`, by name:
///
/// ```yaml
/// spring:
///   flutter:
///     scene:
///       materials:
///         glass:
///           source: assets/materials/glass.fmat
///           preload: eager
/// ```
///
/// ```dart
/// SpringSceneMesh(
///   material: 'glass',
///   geometry: panel,
///   parameters: (p) => p.setFloat('strength', 0.2),
/// )
/// ```
///
/// A scene draws with one through the `SpringSceneMesh` widget; code
/// outside a scene takes a material of its own with
/// `materials['glass'].create()`. An eager material is loaded while the
/// splash shows; a lazy one when a scene first shows it.
final class SceneMaterials {
  /// The materials of [properties], made by [loader].
  SceneMaterials({
    required SceneProperties properties,
    required SceneEngine engine,
    required SceneMaterialLoader loader,
    required ApplicationEventPublisher events,
  }) : _handles = {
         for (final MapEntry(key: name, value: material)
             in (properties.materials ?? const {}).entries)
           name: SceneMaterialHandle(
             name: name,
             location: _location(name, material),
             eager: (material.preload ?? properties.preload) == SceneLoad.eager,
             engine: engine,
             loader: loader,
             events: events,
           ),
       };

  final Map<String, SceneMaterialHandle> _handles;

  static String _location(String name, SceneMaterialProperties material) =>
      material.source ??
      (throw StateError(
        'The material "$name" has no source: set '
        'spring.flutter.scene.materials.$name.source '
        '(assets/materials/$name.fmat).',
      ));

  /// The names of the materials.
  Iterable<String> get names => _handles.keys;

  /// Every material.
  Iterable<SceneMaterialHandle> get all => _handles.values;

  /// The materials loaded with the splash.
  Iterable<SceneMaterialHandle> get eager =>
      all.where((material) => material.eager);

  /// Whether there is a material [name].
  bool contains(String name) => _handles.containsKey(name);

  /// The material [name]. Throws when the properties have none of that
  /// name.
  SceneMaterialHandle operator [](String name) =>
      _handles[name] ??
      (throw StateError(
        'No material "$name" in spring.flutter.scene.materials: '
        '${_handles.isEmpty ? 'none is declared' : names.join(', ')}.',
      ));

  /// Loads the eager materials one after another; [progress] takes the
  /// share done, from 0 to 1. A material that fails is logged, published
  /// as a `SceneFailedEvent` and skipped: its meshes are not drawn.
  Future<void> preload({void Function(double fraction)? progress}) async {
    final materials = eager.toList();
    for (final (index, material) in materials.indexed) {
      try {
        await material.preload(index: index + 1, count: materials.length);
      } on Object catch (_) {
        // Logged and published by the material.
      }
      progress?.call((index + 1) / materials.length);
    }
  }

  /// Frees the listeners of every material.
  void dispose() {
    for (final material in all) {
      material.dispose();
    }
  }
}
