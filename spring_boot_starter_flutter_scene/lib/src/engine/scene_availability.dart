import 'package:flutter/foundation.dart';
import 'package:spring_boot_starter_flutter_scene/src/conditions/scene_condition.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_engine.dart';
import 'package:spring_boot_starter_flutter_scene/src/properties/scene_properties.dart';
import 'package:spring_boot_starter_flutter_scene/src/scene_events.dart';

/// Whether scenes draw here, in one place: what the properties ask
/// (`spring.flutter.scene.render`, `max-frame-rate`, `pixel-ratio`), the
/// conditions that hold (`spring.flutter.scene.when`) and whether the
/// engine started. Every scene widget of the starter reads it
/// and shows its placeholder when [draws] is `false`; it notifies its
/// listeners when the engine's start moves.
///
/// With `spring.flutter.scene.enabled: false` this bean does not exist,
/// and the widgets are placeholders for that reason. Code of the app that
/// needs it takes an `ObjectProvider<SceneAvailability>` and checks.
final class SceneAvailability extends ChangeNotifier {
  /// The availability by [properties] and [engine].
  SceneAvailability({
    required this.properties,
    required this.engine,
    this.conditions = const [],
  }) {
    engine.addListener(notifyListeners);
    for (final condition in conditions) {
      condition.addListener(notifyListeners);
    }
  }

  /// The conditions the scenes follow.
  final List<SceneCondition> conditions;

  /// The conditions that hold now and change the mode, with the mode
  /// each asks for.
  List<(SceneCondition, SceneRenderMode)> get held => [
    for (final condition in conditions)
      if (condition.holds)
        if (properties.when?[condition.name] case final mode?)
          (condition, mode),
  ];

  /// How scenes draw now: [SceneProperties.render], or less while a
  /// condition holds.
  SceneRenderMode get render {
    var mode = properties.render;
    for (final (_, asked) in held) {
      if (asked.index > mode.index) {
        mode = asked;
      }
    }
    return mode;
  }

  /// What the app asks for.
  final SceneProperties properties;

  /// The engine.
  final SceneEngine engine;

  /// Why scenes do not draw, `null` when they do (or may: the engine has
  /// not been asked to start yet).
  SceneUnavailable? get reason {
    if (render == SceneRenderMode.off) {
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
  bool get animates => render == SceneRenderMode.animated;

  /// The frames a second of a scene that asks for [asked] (as many as the
  /// properties let it when it asks for none or `0`). With
  /// `max-frame-rate: 0` the screen's ([screenFrameRate]).
  double frameRate([double? asked]) {
    final most = properties.maxFrameRate > 0
        ? properties.maxFrameRate
        : screenFrameRate;
    return asked == null || asked <= 0 || asked > most ? most : asked;
  }

  /// The frames a second the screen shows: in a browser, where the scenes
  /// beat on its frames and it does not say how many there are, as many
  /// as it shows ([double.infinity]); elsewhere the display's refresh
  /// rate, 60 when it gives none.
  static double get screenFrameRate {
    if (kIsWeb) {
      return double.infinity;
    }
    final displays = PlatformDispatcher.instance.displays;
    final rate = displays.isEmpty ? 0.0 : displays.first.refreshRate;
    return rate > 0 ? rate : 60;
  }

  @override
  void dispose() {
    engine.removeListener(notifyListeners);
    for (final condition in conditions) {
      condition.removeListener(notifyListeners);
    }
    super.dispose();
  }
}
