/// For an app's `hook/build.dart`: what of its scenes is made at build
/// time (the engine's shader bundle with only what the scenes draw with,
/// the app's materials and models), written into `lib/spring_gen/`. Runs
/// on the Dart VM only (it reads files and runs the SDK's shader
/// compiler), so it is not part of `spring_boot_starter_flutter_scene.dart`.
library;

export 'src/hooks/scene_shaders.dart'
    show buildSceneAssets, buildSceneShaders, unlitSceneShaders;
export 'src/hooks/scene_stage.dart' show SceneStage, sceneGeneratedDirectory;
