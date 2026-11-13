// The engine has a class Component of its own: only what is used here.
import 'package:flutter_scene/scene.dart' show Scene;
import 'package:scene_showcase/src/spin.dart';
import 'package:spring_boot_starter_flutter_scene/spring_boot_starter_flutter_scene.dart';
import 'package:vector_math/vector_math.dart';

/// What the application's scene shows under every screen: three crates
/// (clones of the model `crate`, loaded once) turning slowly in the dark.
///
/// A `SceneCustomizer` bean receives the scene once, when it is made with
/// the splash.
///
/// The models come through an `ObjectProvider`: with
/// `spring.flutter.scene.enabled: false` no scene bean exists, and this
/// bean must still be made. Nothing calls [customize] then.
@Component()
class Backdrop implements SceneCustomizer {
  /// The backdrop of [models].
  Backdrop(this.models);

  /// The models of the properties, when the app has scenes.
  final ObjectProvider<SceneModels> models;

  @override
  Future<void> customize(Scene scene) async {
    final crate = await models.getObject()['crate'].load();
    for (final (x, y, scale, speed) in const [
      (-3.2, 1.2, 0.9, 0.03),
      (3.0, -0.9, 1.3, -0.02),
      (0.4, -1.9, 0.6, 0.05),
    ]) {
      scene.add(
        crate.clone()
          ..localTransform = Matrix4.compose(
            Vector3(x, y, 2),
            Quaternion.axisAngle(Vector3(1, 0, 0), 0.5),
            Vector3.all(scale),
          )
          ..addComponent(
            Spin(
              turnsPerSecond: speed,
              axis: Vector3(0.3, 1, 0.2)..normalize(),
            ),
          ),
      );
    }
  }
}
