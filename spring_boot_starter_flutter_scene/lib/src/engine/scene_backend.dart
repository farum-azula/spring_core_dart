import 'package:flutter_scene/scene.dart';

/// What draws the scenes, started once for the application by the
/// `SceneEngine`.
///
/// The starter's is [FlutterSceneBackend]; a test declares its own bean,
/// since `flutter_scene` needs a GPU a test does not have.
abstract interface class SceneBackend {
  /// Its name, in the events and the debug panel.
  String get name;

  /// Starts it: compiles its shaders, loads its tables. Throws where it
  /// cannot draw.
  Future<void> start();
}

/// `flutter_scene`: WebGL2 in a browser, Impeller (Flutter GPU) elsewhere.
final class FlutterSceneBackend implements SceneBackend {
  /// The engine.
  const FlutterSceneBackend();

  @override
  String get name => 'flutter_scene';

  @override
  Future<void> start() => Scene.initializeStaticResources();
}
