import 'package:flutter_scene/scene.dart';

/// What a model is made of, counted by a walk of its nodes: the debug
/// panel's numbers for a model by name.
final class SceneModelShape {
  /// The shape of the node tree under [root].
  factory SceneModelShape.of(Node root) {
    var nodes = 0;
    var meshes = 0;
    var primitives = 0;
    final materials = Set<Material>.identity();
    void walk(Node node) {
      nodes++;
      if (node.mesh case final mesh?) {
        meshes++;
        primitives += mesh.primitives.length;
        for (final primitive in mesh.primitives) {
          materials.add(primitive.material);
        }
      }
      node.children.forEach(walk);
    }

    walk(root);
    return SceneModelShape._(
      nodes: nodes,
      meshes: meshes,
      primitives: primitives,
      materials: materials.length,
    );
  }

  const SceneModelShape._({
    required this.nodes,
    required this.meshes,
    required this.primitives,
    required this.materials,
  });

  /// Its nodes.
  final int nodes;

  /// The nodes that carry a mesh.
  final int meshes;

  /// The parts of its meshes: each is a draw call of every frame that
  /// shows the model once.
  final int primitives;

  /// Its different materials.
  final int materials;
}
