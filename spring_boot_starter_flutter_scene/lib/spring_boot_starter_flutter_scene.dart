/// 3D scenes for Spring Boot Flutter apps, on `flutter_scene`.
///
/// - `SpringSceneView`: a scene among the app's widgets, with the frame
///   ceiling, the still frame and the pause off the screen of
///   `spring.flutter.scene.*`, and a plain widget where scenes do not
///   draw; `SceneBackdrop`: a scene behind a widget;
/// - `SceneModels` and `SpringSceneModel`: the models of
///   `spring.flutter.scene.models.*`, loaded with the splash or when first
///   shown;
/// - `SceneMaterials` and `SpringSceneMesh`: the materials of
///   `spring.flutter.scene.materials.*` (`.fmat` files the build hook
///   compiles), by name;
/// - `ApplicationScene`: one scene for the whole app, under every screen;
/// - the start in events (`SceneEvent`) and in words (`SceneStatus`);
/// - a tab of the debug panel with every scene, model and material by
///   name.
///
/// The engine itself is `package:flutter_scene/scene.dart`: its scene
/// widgets (`SceneNode`, `SceneMesh`, ...) go into a `SpringSceneView`.
library;

export 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

export 'src/app/application_scene.dart';
export 'src/app/application_scene_background.dart';
export 'src/app/scene_customizer.dart';
export 'src/conditions/scene_condition.dart';
export 'src/conditions/slow_frames_scene_condition.dart';
export 'src/conditions/touch_scene_condition.dart';
export 'src/debug/scene_debug.dart';
export 'src/debug/scene_fps_segment.dart';
export 'src/debug/scene_material_precisions.dart';
export 'src/debug/scene_model_shape.dart';
export 'src/debug/scene_section.dart';
export 'src/engine/scene_availability.dart';
export 'src/engine/scene_backend.dart';
export 'src/engine/scene_engine.dart';
export 'src/engine/scene_engine_log.dart';
export 'src/engine/scene_frames.dart';
export 'src/materials/scene_material_handle.dart';
export 'src/materials/scene_material_loader.dart';
export 'src/materials/scene_material_precision.dart';
export 'src/materials/scene_materials.dart';
export 'src/models/remote_model_resource.dart';
export 'src/models/scene_model_handle.dart';
export 'src/models/scene_model_importer.dart';
export 'src/models/scene_models.dart';
export 'src/properties/scene_properties.dart';
export 'src/scene_colors.dart';
export 'src/scene_events.dart';
export 'src/scene_start.dart';
export 'src/scene_status.dart';
export 'src/widgets/on_screen.dart';
export 'src/widgets/scene_backdrop.dart';
export 'src/widgets/scene_clock.dart';
export 'src/widgets/scene_surface.dart';
export 'src/widgets/scene_view_observer.dart';
export 'src/widgets/spring_scene_mesh.dart';
export 'src/widgets/spring_scene_model.dart';
export 'src/widgets/spring_scene_view.dart';
