import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter_scene/src/widgets/scene_canvas_target.dart';

/// Whether a scene can be a layer of its own here: on the web alone.
const bool sceneLayers = false;

/// A canvas of a scene's own; nothing where [sceneLayers] is `false`.
final class SceneLayer implements SceneCanvasTarget {
  @override
  Widget build() => const SizedBox.shrink();

  @override
  bool present(void Function() draw) => false;

  @override
  void dispose() {}
}
