import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:spring_boot_starter_flutter_scene/src/widgets/scene_surface.dart';
import 'package:spring_boot_starter_flutter_scene/src/widgets/spring_scene_view.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// What a [SceneBackdrop] draws behind its child, for the child's
/// rectangle.
typedef SceneBackdropBuilder = List<Widget> Function(
  BuildContext context,
  SceneSurface surface,
);

/// A 3D scene behind a widget: a frame of light around a panel, a glass
/// under a card. The scene is as large as [child] and [margin] pixels
/// around it (for light that reaches past its edge), and a pixel of the
/// child is a pixel of the scene: [scene] lays its meshes out by the
/// [SceneSurface] it is given.
///
/// ```dart
/// SceneBackdrop(
///   name: 'match-header',
///   margin: 48,
///   tilt: 0.7,
///   placeholder: const PlainPanel(),
///   scene: (context, surface) => [GlassPanel(surface), NeonEdge(surface)],
///   child: const MatchHeader(),
/// )
/// ```
///
/// It is a `SpringSceneView.declarative` under the child, so everything
/// of that holds: where scenes do not draw only [placeholder] and
/// [child] are built; the frame ceiling, the still frame and the pause
/// off the screen come from the properties. With [tilt] the scene turns a
/// little after the pointer.
class SceneBackdrop extends StatefulWidget {
  /// The scene [scene] behind [child].
  const SceneBackdrop({
    super.key,
    required this.child,
    required this.scene,
    this.name = 'backdrop',
    this.placeholder,
    this.margin = 0,
    this.padding = EdgeInsets.zero,
    this.maxFrameRate,
    this.tilt = 0,
    this.toneMapping = ToneMappingMode.linear,
  });

  /// The widget in front.
  final Widget child;

  /// The scene widgets behind it.
  final SceneBackdropBuilder scene;

  /// What the scene is called in the scenes' debug panel.
  final String name;

  /// What stands behind the child until the scene draws, and for good
  /// where it cannot.
  final Widget? placeholder;

  /// How far the scene reaches past the child's edge, in pixels.
  final double margin;

  /// Space between the child and the edge of the scene's rectangle.
  final EdgeInsetsGeometry padding;

  /// The most frames a second the scene draws, under the properties'.
  final double? maxFrameRate;

  /// How far the scene turns after the pointer, in degrees; 0 keeps it
  /// flat.
  final double tilt;

  /// How colours are brought to the screen's range; `linear` keeps a
  /// colour of the theme as it is.
  final ToneMappingMode toneMapping;

  @override
  State<SceneBackdrop> createState() => _SceneBackdropState();
}

class _SceneBackdropState extends State<SceneBackdrop> {
  static const _fieldOfView = 30 * math.pi / 180;

  Offset _pointer = Offset.zero;

  bool get _tilts =>
      widget.tilt != 0 && !SpringSceneView.reducedMotionOf(context);

  /// Where the pointer is over the child: -1..1 from its middle.
  void _follow(PointerEvent event, Size size) {
    if (!_tilts || size.isEmpty) {
      return;
    }
    setState(
      () => _pointer = Offset(
        (event.localPosition.dx / size.width * 2 - 1).clamp(-1, 1),
        (event.localPosition.dy / size.height * 2 - 1).clamp(-1, 1),
      ),
    );
  }

  void _rest() {
    if (_pointer != Offset.zero) {
      setState(() => _pointer = Offset.zero);
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    // Not by the text's direction: the scene is centred on the child.
    alignment: Alignment.topLeft,
    clipBehavior: Clip.none,
    children: [
      Positioned.fill(
        left: -widget.margin,
        top: -widget.margin,
        right: -widget.margin,
        bottom: -widget.margin,
        child: IgnorePointer(child: LayoutBuilder(builder: _view)),
      ),
      LayoutBuilder(
        builder: (context, constraints) => MouseRegion(
          opaque: false,
          onHover: (event) => _follow(event, context.size ?? Size.zero),
          onExit: (_) => _rest(),
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    ],
  );

  vm.Quaternion get _turn {
    final angle = widget.tilt * math.pi / 180;
    return vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), _pointer.dx * angle) *
        vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), _pointer.dy * angle);
  }

  Widget _view(BuildContext context, BoxConstraints view) {
    final surface = SceneSurface(
      Size(
        view.maxWidth - widget.margin * 2,
        view.maxHeight - widget.margin * 2,
      ),
    );
    // The camera stands where the view's height is exactly the scene's.
    final distance =
        view.maxHeight / surface.pixelsPerUnit / 2 / math.tan(_fieldOfView / 2);
    return SpringSceneView.declarative(
      name: widget.name,
      placeholder: widget.placeholder == null
          ? null
          : Padding(
              padding: EdgeInsets.all(widget.margin),
              child: widget.placeholder,
            ),
      toneMapping: widget.toneMapping,
      maxFrameRate: widget.maxFrameRate,
      camera: PerspectiveCamera(
        fovRadiansY: _fieldOfView,
        position: vm.Vector3(0, 0, -distance),
        target: vm.Vector3.zero(),
      ),
      children: [
        SceneNode(rotation: _turn, children: widget.scene(context, surface)),
      ],
    );
  }
}
