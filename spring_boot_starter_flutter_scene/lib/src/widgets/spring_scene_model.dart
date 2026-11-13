import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show SpringScope;
import 'package:spring_boot_starter_flutter_scene/src/models/scene_model_handle.dart';
import 'package:spring_boot_starter_flutter_scene/src/models/scene_models.dart';
import 'package:spring_boot_starter_flutter_scene/src/widgets/spring_scene_view.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A model of `spring.flutter.scene.models.<name>` in a scene: a clone of
/// its template under a node of this widget's (the geometry, textures and
/// materials stay shared with every other use). An eager model is there
/// at once; a lazy one is loaded when this widget first shows, with
/// [placeholder] in its place meanwhile.
///
/// ```dart
/// SpringSceneView.declarative(
///   children: [
///     SpringSceneModel('hero', position: Vector3(0, 1, 0)),
///   ],
/// )
/// ```
///
/// It is a scene widget: it goes among the children of a
/// `SpringSceneView` (or of the engine's own scene widgets), never among
/// ordinary widgets.
class SpringSceneModel extends StatelessWidget {
  /// The model [name] of the properties.
  const SpringSceneModel(
    this.name, {
    super.key,
    this.variant,
    this.animations = const [],
    this.placeholder,
    this.error,
    this.onLoaded,
    this.position,
    this.rotation,
    this.scale,
    this.visible = true,
    this.components = const [],
    this.children = const [],
  });

  /// The model's name in `spring.flutter.scene.models`.
  final String name;

  /// A material variant of the model (`KHR_materials_variants`).
  final String? variant;

  /// Which of its animations play, and how.
  final List<SceneAnimationSpec> animations;

  /// Scene widgets in its place while it loads.
  final WidgetBuilder? placeholder;

  /// Scene widgets in its place when it failed to load.
  final Widget Function(BuildContext context, Object error)? error;

  /// Called with the clone once it is in the scene.
  final void Function(Node node)? onLoaded;

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
  Widget build(BuildContext context) {
    final model = SpringScope.of(context).getBean<SceneModels>()[name];
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => SceneModel.from(
        _NamedModel(model),
        variant: variant,
        animations: animations,
        placeholder: placeholder,
        error: error,
        onLoaded: (node) {
          // A still frame drawn before the model came does not have it.
          SpringSceneView.repaintOf(context);
          onLoaded?.call(node);
        },
        name: name,
        position: position,
        rotation: rotation,
        scale: scale,
        visible: visible && !model.hidden,
        components: components,
        children: children,
      ),
    );
  }
}

/// The engine's source of a model kept by the starter: the template is
/// the handle's, so a model that left the screen and came back is not
/// imported again.
class _NamedModel extends SceneModelSource {
  const _NamedModel(this.model);

  final SceneModelHandle model;

  @override
  String get cacheKey => 'spring.flutter.scene.models.${model.name}';

  @override
  Future<Uint8List> load() => model.resource.readAsBytes();

  @override
  Future<Node> createNode() => model.load();
}
