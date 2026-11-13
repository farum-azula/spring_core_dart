import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart' show PerspectiveCamera;
import 'package:scene_showcase/src/spin.dart';
import 'package:spring_boot_starter_flutter_scene/spring_boot_starter_flutter_scene.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

/// A scene of its own with a model of the properties: the crate turning.
/// Where scenes do not draw, the box with the words stands in.
class Showroom extends StatelessWidget {
  /// The showroom.
  const Showroom({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 280,
    height: 280,
    child: SpringSceneView.declarative(
      name: 'showroom',
      camera: PerspectiveCamera(
        position: Vector3(0, 1.1, -2.6),
        target: Vector3.zero(),
      ),
      placeholder: const DecoratedBox(
        decoration: BoxDecoration(color: Color(0xFF12161C)),
        child: Center(
          child: Text(
            'The crate\n(no 3D here)',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF8A93A6)),
          ),
        ),
      ),
      children: [
        SpringSceneModel('crate', components: [Spin(turnsPerSecond: 0.15)]),
      ],
    ),
  );
}
