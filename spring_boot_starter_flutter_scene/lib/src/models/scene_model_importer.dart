import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';

/// Turns a model's file into the node tree every use of the model clones.
///
/// The starter's is [GlbModelImporter]; an app with another format, or a
/// test without a GPU, declares its own bean.
abstract interface class SceneModelImporter {
  /// The template of model [name] from the [bytes] of its file.
  Future<Node> import(Uint8List bytes, {required String name});
}

/// Imports a binary glTF file (`.glb`) with the engine's own importer.
final class GlbModelImporter implements SceneModelImporter {
  /// The importer.
  const GlbModelImporter();

  @override
  Future<Node> import(Uint8List bytes, {required String name}) =>
      Node.fromGlbBytes(bytes);
}
