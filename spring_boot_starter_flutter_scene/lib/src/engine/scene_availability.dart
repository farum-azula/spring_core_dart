import 'package:flutter/foundation.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_engine.dart';
import 'package:spring_boot_starter_flutter_scene/src/properties/scene_properties.dart';
import 'package:spring_boot_starter_flutter_scene/src/scene_events.dart';

/// Whether scenes draw here, in one place: what the properties ask
/// (`spring.flutter.scene.render`, `max-frame-rate`, `pixel-ratio`) and
/// whether the engine started. Every scene widget of the starter reads it
/// and shows its placeholder when [draws] is `false`; it notifies its
/// listeners when the engine's start moves.
///
/// With `spring.flutter.scene.enabled: false` this bean does not exist,
/// and the widgets are placeholders for that reason. Code of the app that
/// needs it takes an `ObjectProvider<SceneAvailability>` and checks.
final class SceneAvailability extends ChangeNotifier {
  /// The availability by [properties] and [engine].
  SceneAvailability({required this.properties, required this.engine}) {
    engine.addListener(notifyListeners);
  }

  /// What the app asks for.
  final SceneProperties properties;

  /// The engine.
  final SceneEngine engine;

  /// Why scenes do not draw, `null` when they do (or may: the engine has
  /// not been asked to start yet).
  SceneUnavailable? get reason {
    if (properties.render == SceneRenderMode.off) {
      return SceneUnavailable.off;
    }
    if (engine.hasFailed) {
      return SceneUnavailable.engine;
    }
    return null;
  }

  /// Whether scenes draw, now or once the engine has started.
  bool get draws => reason == null;

  /// Whether a scene can be drawn this moment.
  bool get isReady => draws && engine.isReady;

  /// Whether scenes move; `false` for one frame that stands.
  bool get animates => properties.render == SceneRenderMode.animated;

  /// The frames a second of a scene that asks for [asked] (as many as the
  /// properties let it when it asks for none).
  double frameRate([double? asked]) =>
      asked == null || asked > properties.maxFrameRate
      ? properties.maxFrameRate
      : asked;

  @override
  void dispose() {
    engine.removeListener(notifyListeners);
    super.dispose();
  }
}
