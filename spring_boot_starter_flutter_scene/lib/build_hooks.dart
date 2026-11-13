/// For an app's `hook/build.dart`: the engine's shader bundle with only
/// what the app's scenes draw with. Runs on the Dart VM only (it reads
/// files and runs the SDK's shader compiler), so it is not part of
/// `spring_boot_starter_flutter_scene.dart`.
library;

export 'src/hooks/scene_shaders.dart' show buildSceneShaders, unlitSceneShaders;
