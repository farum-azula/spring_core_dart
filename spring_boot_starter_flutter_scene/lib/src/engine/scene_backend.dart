import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter_scene/scene.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_frame_transfer.dart';

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
///
/// In a browser its canvas is made so that its frames reach Flutter as
/// Flutter takes them ([startWithFrameTransfer]): WebKit passes a frame
/// of WebGL with its colour divided by its alpha. With [onEngineCanvas]
/// its canvas is one the page shows (`spring.flutter.scene.canvas:
/// engine`), and no frame is passed.
final class FlutterSceneBackend implements SceneBackend {
  /// The engine.
  const FlutterSceneBackend({this.onEngineCanvas = false});

  /// Whether the scenes are drawn on the engine's canvas, shown as it is.
  final bool onEngineCanvas;

  @override
  String get name => 'flutter_scene';

  @override
  Future<void> start() {
    // The engine marks each pass of a frame on the timeline; in a browser
    // a release build does not drop them, and each is a mark kept by the
    // page for good (eight a frame of two scenes).
    if (kIsWeb && kReleaseMode) {
      RenderStats.timelineEvents = false;
    }
    return startWithFrameTransfer(
      Scene.initializeStaticResources,
      onScreen: onEngineCanvas,
    );
  }
}
