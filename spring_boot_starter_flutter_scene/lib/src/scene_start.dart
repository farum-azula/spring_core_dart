import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show SplashTask, SplashTaskContext;
import 'package:spring_boot_starter_flutter_scene/src/app/application_scene.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_engine.dart';
import 'package:spring_boot_starter_flutter_scene/src/models/scene_models.dart';
import 'package:spring_boot_starter_flutter_scene/src/properties/scene_properties.dart';
import 'package:spring_boot_starter_flutter_scene/src/scene_events.dart';

/// The scenes' part of the app's start, a `SplashTask`: the splash stays
/// until what was asked for with it is ready, and its loader moves with
/// the steps.
///
/// - the engine, with `spring.flutter.scene.preload: eager`, an eager
///   model or the application's scene;
/// - the eager models, one after another;
/// - the application's scene (`spring.flutter.scene.app.enabled`).
///
/// With nothing eager it does nothing: the engine starts when the first
/// scene shows. A step that fails does not stop the start.
final class SceneStart implements SplashTask {
  /// The start of [engine], [models] and the application's [scene].
  const SceneStart({
    required this.properties,
    required this.engine,
    required this.models,
    required this.events,
    this.scene,
  });

  /// What the app asks for.
  final SceneProperties properties;

  /// The engine.
  final SceneEngine engine;

  /// The models.
  final SceneModels models;

  /// Where [SceneReadyEvent] is published.
  final ApplicationEventPublisher events;

  /// The application's scene, when the app has one.
  final ApplicationScene? scene;

  @override
  String get name => 'scene';

  @override
  Future<void> run(SplashTaskContext task) async {
    final eager = models.eager.isNotEmpty;
    final wanted =
        properties.preload == SceneLoad.eager || eager || scene != null;
    if (!wanted || properties.render == SceneRenderMode.off) {
      return;
    }
    final watch = Stopwatch()..start();
    // The engine's share of the task: its start cannot report its own.
    const engineShare = 0.4;
    if (!await engine.start()) {
      return;
    }
    task.progress(eager ? engineShare : 1);
    await models.preload(
      progress: (fraction) =>
          task.progress(engineShare + (1 - engineShare) * fraction),
    );
    await scene?.create();
    events.publishEvent(SceneReadyEvent(this, took: watch.elapsed));
  }
}
