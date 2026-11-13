import 'package:flutter_scene/scene.dart';

/// Changes the application's scene when it is made: adds nodes, sets its
/// light, fog, anti-aliasing.
///
/// Declare a bean that implements it. Every such bean receives the scene
/// once, in `@Order`, after the engine started and before the scene is
/// first drawn.
///
/// ```dart
/// @Component()
/// class Stage implements SceneCustomizer {
///   Stage(this.models);
///
///   // A provider: with scenes turned off this bean is still made.
///   final ObjectProvider<SceneModels> models;
///
///   @override
///   Future<void> customize(Scene scene) async {
///     scene.add((await models.getObject()['stage'].load()).clone());
///   }
/// }
/// ```
///
/// Spring Boot (Java) customizes what it makes the same way
/// (`WebServerFactoryCustomizer`).
abstract interface class SceneCustomizer {
  /// Changes [scene] in place.
  Future<void> customize(Scene scene);
}
