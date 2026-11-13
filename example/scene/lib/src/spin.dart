import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// Turns its node about the vertical axis, [turnsPerSecond] turns a
/// second. A component of the engine: it runs on the scene's own clock,
/// so no widget is rebuilt for a frame.
class Spin extends Component {
  /// A turn every `1 / turnsPerSecond` seconds.
  Spin({this.turnsPerSecond = 0.1, Vector3? axis})
    : axis = axis ?? Vector3(0, 1, 0);

  /// How fast.
  final double turnsPerSecond;

  /// What it turns about.
  final Vector3 axis;

  double _angle = 0;

  @override
  void update(double deltaSeconds) {
    _angle += deltaSeconds * turnsPerSecond * 6.283185307179586;
    node.localTransform = Matrix4.compose(
      node.localTransform.getTranslation(),
      Quaternion.axisAngle(axis, _angle),
      Vector3.all(node.localTransform.getMaxScaleOnAxis()),
    );
  }
}
