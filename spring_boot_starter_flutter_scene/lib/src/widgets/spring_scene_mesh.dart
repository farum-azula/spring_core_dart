import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show SpringScope;
import 'package:spring_boot_starter_flutter_scene/src/materials/scene_material_handle.dart';
import 'package:spring_boot_starter_flutter_scene/src/materials/scene_materials.dart';
import 'package:spring_boot_starter_flutter_scene/src/widgets/spring_scene_view.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Sets the parameters of a [SpringSceneMesh]'s material.
typedef SceneMaterialParameters = void Function(MaterialParameters parameters);

/// Sets the parameters of a [SpringSceneMesh]'s material for a frame,
/// [elapsed] being the time its scene has run.
typedef SceneMaterialFrame = void Function(
  MaterialParameters parameters,
  Duration elapsed,
);

/// [geometry] drawn with the material of
/// `spring.flutter.scene.materials.<name>`: a material of its own, its
/// parameters set by [parameters] on every build and by [everyFrame] on
/// every frame of the scene (without a build).
///
/// ```dart
/// SpringSceneView.declarative(
///   children: [
///     SpringSceneMesh(
///       material: 'glass',
///       geometry: panel,
///       parameters: (p) => p..setFloat('strength', 0.2),
///       everyFrame: (p, elapsed) =>
///           p.setFloat('time', elapsed.inMicroseconds / 1e6),
///     ),
///   ],
/// )
/// ```
///
/// Nothing is drawn until the material is loaded; its scene waits for it
/// before its first frame, as for a model. A material that failed to load
/// is not drawn. It is a scene widget: it goes among the children of a
/// `SpringSceneView` (or of the engine's own scene widgets).
class SpringSceneMesh extends StatefulWidget {
  /// [geometry] with the material [material] of the properties.
  const SpringSceneMesh({
    super.key,
    required this.material,
    required this.geometry,
    this.parameters,
    this.everyFrame,
    this.position,
    this.rotation,
    this.scale,
    this.visible = true,
    this.components = const [],
    this.children = const [],
  });

  /// The material's name in `spring.flutter.scene.materials`.
  final String material;

  /// What is drawn.
  final Geometry geometry;

  /// Sets the material's parameters, on every build.
  final SceneMaterialParameters? parameters;

  /// Sets the material's parameters on every frame of the scene.
  final SceneMaterialFrame? everyFrame;

  /// Where it stands.
  final vm.Vector3? position;

  /// How it is turned.
  final vm.Quaternion? rotation;

  /// Its scale.
  final vm.Vector3? scale;

  /// Whether it is drawn.
  final bool visible;

  /// Behaviour on its node.
  final List<Component> components;

  /// Scene widgets under its node.
  final List<Widget> children;

  @override
  State<SpringSceneMesh> createState() => _SpringSceneMeshState();
}

class _SpringSceneMeshState extends State<SpringSceneMesh> {
  SceneMaterialHandle? _handle;
  String? _scene;
  PreprocessedMaterial? _material;
  ValueListenable<Duration>? _clock;
  bool _hidden = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _take();
    final clock = SceneScope.maybeOf(context)?.elapsed;
    if (!identical(clock, _clock)) {
      _clock?.removeListener(_frame);
      _clock = clock?..addListener(_frame);
    }
  }

  @override
  void didUpdateWidget(SpringSceneMesh oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.material != widget.material) {
      _leave();
      _material = null;
      _take();
    }
  }

  @override
  void dispose() {
    _clock?.removeListener(_frame);
    _leave();
    super.dispose();
  }

  void _take() {
    if (_handle != null) {
      return;
    }
    final handle = SpringScope.of(
      context,
    ).getBean<SceneMaterials>()[widget.material];
    final scene = SpringSceneView.nameOf(context) ?? 'scene';
    _hidden = handle.hidden;
    _handle = handle..addListener(_changed);
    _scene = scene;
    handle.use(scene);
    final made = handle.create();
    // The view waits for it before its first frame.
    SpringSceneView.loadsOf(context)?.add(made);
    made.then(
      (material) {
        if (mounted && identical(_handle, handle)) {
          setState(() => _material = material);
          SpringSceneView.repaintOf(context);
        }
      },
      onError: (Object _) {
        // Logged and published by the material; nothing is drawn.
      },
    );
  }

  void _leave() {
    final handle = _handle;
    if (handle != null) {
      handle
        ..removeListener(_changed)
        ..release(_scene!);
    }
    _handle = null;
  }

  // Built again for the debug panel's switch only, not for the uses of
  // the material elsewhere.
  void _changed() {
    final hidden = _handle?.hidden ?? false;
    if (mounted && hidden != _hidden) {
      setState(() => _hidden = hidden);
    }
  }

  void _frame() {
    final material = _material;
    final clock = _clock;
    if (material != null && clock != null) {
      widget.everyFrame?.call(material.parameters, clock.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final material = _material;
    if (material == null) {
      return const SceneNode();
    }
    widget.parameters?.call(material.parameters);
    _frame();
    return SceneMesh(
      geometry: widget.geometry,
      material: material,
      position: widget.position,
      rotation: widget.rotation,
      scale: widget.scale,
      visible: widget.visible && !_hidden,
      components: widget.components,
      children: widget.children,
    );
  }
}
