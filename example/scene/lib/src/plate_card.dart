import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:spring_boot_starter_flutter_scene/spring_boot_starter_flutter_scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A scene behind a widget: a plate of the widget's own size, laid out by
/// its pixels, that leans after the pointer. The text over it is an
/// ordinary widget.
class PlateCard extends StatelessWidget {
  /// The card over [child].
  const PlateCard({super.key, required this.child});

  /// The widget in front.
  final Widget child;

  static const _color = Color(0xFF1B2A44);

  @override
  Widget build(BuildContext context) => SceneBackdrop(
    name: 'plate-card',
    margin: 24,
    tilt: 4,
    padding: const EdgeInsets.all(20),
    placeholder: const ColoredBox(color: _color),
    scene: (context, surface) => [_Plate(surface, color: _color)],
    child: child,
  );
}

/// The plate: a thin box as wide and as high as the widget.
class _Plate extends StatefulWidget {
  const _Plate(this.surface, {required this.color});

  final SceneSurface surface;
  final Color color;

  @override
  State<_Plate> createState() => _PlateState();
}

class _PlateState extends State<_Plate> {
  late Geometry _geometry = _build();
  // The engine's materials take linear light, the app's colours are sRGB.
  late final UnlitMaterial _material = UnlitMaterial()
    ..baseColorFactor = widget.color.linearWithAlpha;

  Geometry _build() => CuboidGeometry(
    vm.Vector3(widget.surface.width, widget.surface.height, 0.06),
  );

  @override
  void didUpdateWidget(_Plate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.surface != widget.surface) {
      _geometry = _build();
    }
  }

  @override
  Widget build(BuildContext context) => SceneMesh(
    geometry: _geometry,
    material: _material,
    position: vm.Vector3(0, 0, 0.03),
  );
}
