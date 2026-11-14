import 'package:flutter_scene/scene.dart';

/// Makes a material from its compiled `.fmat`: what the starter's
/// materials are loaded with. A bean of the app's own replaces it.
abstract interface class SceneMaterialLoader {
  /// A new material of the `.fmat` file at [source] (its path from the
  /// app's root), with its own parameters; the compiled programs are
  /// shared.
  Future<PreprocessedMaterial> load(String source);
}

/// The engine's loader: the material the app's build hook compiled
/// (`buildSceneAssets`), found by the path of its `.fmat` file.
final class FmatMaterialLoader implements SceneMaterialLoader {
  /// The loader.
  const FmatMaterialLoader();

  @override
  Future<PreprocessedMaterial> load(String source) => loadFmatMaterial(source);
}
