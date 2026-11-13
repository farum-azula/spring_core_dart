// The starter's beans by the properties: all of them with scenes on, none
// with scenes off, the application's scene and the debug tab only when
// asked for; the splash task loads what is eager and tells it in events.
import 'package:flutter_scene/scene.dart' show PerspectiveCamera;
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_scene/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_scene/spring_boot_starter_flutter_scene.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show ApplicationContextRunner, doesNotHaveBean, hasSingleBean;

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final runner = const ApplicationContextRunner()
      .withAutoConfiguration(springBootAutoConfiguration)
      .withAutoConfiguration(springBootStarterFlutterAutoConfiguration)
      .withAutoConfiguration(springBootStarterFlutterSceneAutoConfiguration)
      .withAutoConfiguration(
        springBootStarterFlutterSceneDebugAutoConfiguration,
      )
      .withBean<SceneBackend>(FakeBackend.new)
      .withBean<SceneModelImporter>(FakeImporter.new);

  test('with scenes: the engine, the availability, the models, the start', () {
    runner.run((context) {
      expect(context.startupFailure, isNull);
      expect(context, hasSingleBean<SceneEngine>());
      expect(context, hasSingleBean<SceneAvailability>());
      expect(context, hasSingleBean<SceneModels>());
      expect(context, hasSingleBean<SceneStatus>());
      expect(context, hasSingleBean<SceneStart>());
      expect(context.getBean<SplashTask>(qualifier: 'sceneStart'), isNotNull);
      expect(context.getBean<SceneEngine>().backend, isA<FakeBackend>());
      // Not asked for.
      expect(context, doesNotHaveBean<ApplicationScene>());
      expect(context, doesNotHaveBean<ApplicationSceneBackground>());
      // Nothing started by the context alone.
      expect(context.getBean<SceneEngine>().state, SceneEngineState.idle);
    });
  });

  test('scenes off: no scene bean, and a provider that says so', () {
    runner.withPropertyValues(['spring.flutter.scene.enabled=false']).run((
      context,
    ) {
      expect(context.startupFailure, isNull);
      expect(context, doesNotHaveBean<SceneEngine>());
      expect(context, doesNotHaveBean<SceneAvailability>());
      expect(context, doesNotHaveBean<SceneModels>());
      expect(context, doesNotHaveBean<SceneStart>());
      expect(context, doesNotHaveBean<SceneDebug>());
      expect(
        context.context.getBeanProvider<SceneModels>().getIfAvailable(),
        isNull,
      );
    });
  });

  test('the properties', () {
    runner
        .withPropertyValues([
          'spring.flutter.scene.render=still',
          'spring.flutter.scene.max-frame-rate=24',
          'spring.flutter.scene.pixel-ratio=1.5',
          'spring.flutter.scene.pause-off-screen=false',
          'spring.flutter.scene.preload=eager',
          'spring.flutter.scene.models.hero.source=resources:models/hero.glb',
          'spring.flutter.scene.models.hero.preload=lazy',
          'spring.flutter.scene.app.camera.position=0,1.5,-4',
          'spring.flutter.scene.app.camera.fov=30',
        ])
        .run((context) {
          expect(context.startupFailure, isNull);
          final properties = context.getBean<SceneProperties>();
          expect(properties.render, SceneRenderMode.still);
          expect(properties.maxFrameRate, 24);
          expect(properties.pixelRatio, 1.5);
          expect(properties.pauseOffScreen, isFalse);
          expect(properties.preload, SceneLoad.eager);
          expect(properties.app.camera.position, [0, 1.5, -4]);
          expect(properties.app.camera.fov, 30);
          final hero = context.getBean<SceneModels>()['hero'];
          expect(hero.location, 'resources:models/hero.glb');
          expect(hero.eager, isFalse);
        });
  });

  test("the application's scene, under every screen unless placed", () {
    runner.withPropertyValues(['spring.flutter.scene.app.enabled=true']).run((
      context,
    ) {
      expect(context.startupFailure, isNull);
      expect(context, hasSingleBean<ApplicationScene>());
      expect(context, hasSingleBean<ApplicationSceneBackground>());
      expect(
        context.getBean<FlutterAppCustomizer>(
          qualifier: 'applicationSceneBackground',
        ),
        isNotNull,
      );
    });
    runner
        .withPropertyValues([
          'spring.flutter.scene.app.enabled=true',
          'spring.flutter.scene.app.placement=none',
        ])
        .run((context) {
          expect(context, hasSingleBean<ApplicationScene>());
          expect(context, doesNotHaveBean<ApplicationSceneBackground>());
        });
  });

  test('the debug tab, off by its property', () {
    runner.run((context) {
      expect(context, hasSingleBean<SceneDebug>());
      expect(context.getBean<SceneViewObserver>(), isA<SceneDebug>());
      expect(
        context.getBean<DebugPanelSection>(qualifier: 'sceneDebugSection'),
        isA<SceneDebugSection>(),
      );
    });
    runner.withPropertyValues(['spring.flutter.scene.debug.enabled=false']).run(
      (context) {
        expect(context, doesNotHaveBean<SceneDebug>());
        expect(context, doesNotHaveBean<SceneDebugSection>());
        expect(context, hasSingleBean<SceneEngine>());
      },
    );
  });

  group('the start with the splash', () {
    Future<List<double>> start(
      SceneStart task,
      ApplicationContext context,
    ) async {
      final progress = <double>[];
      await task.run(SplashTaskContext(context, progress.add));
      return progress;
    }

    test('nothing eager: nothing starts', () async {
      await runner.runAsync((context) async {
        await start(context.getBean<SceneStart>(), context.context);
        expect(context.getBean<SceneEngine>().state, SceneEngineState.idle);
        expect(context.getBean<SceneStatus>().history, isEmpty);
      });
    });

    test('preload: eager starts the engine', () async {
      await runner
          .withPropertyValues(['spring.flutter.scene.preload=eager'])
          .runAsync((context) async {
            final progress = await start(
              context.getBean<SceneStart>(),
              context.context,
            );
            expect(context.getBean<SceneEngine>().isReady, isTrue);
            expect(progress.last, 1);
            final status = context.getBean<SceneStatus>();
            expect(
              [for (final step in status.history) step.eventName],
              ['SceneEngineStarting', 'SceneEngineReady', 'SceneReady'],
            );
            // Nothing is being loaded any more.
            expect(status.value, isNull);
          });
    });

    test('render: off starts nothing, whatever is eager', () async {
      await runner
          .withPropertyValues([
            'spring.flutter.scene.preload=eager',
            'spring.flutter.scene.render=off',
          ])
          .runAsync((context) async {
            await start(context.getBean<SceneStart>(), context.context);
            expect(context.getBean<SceneEngine>().state, SceneEngineState.idle);
          });
    });

    test(
      "the application's scene: a failure is published, not thrown",
      () async {
        final events = RecordingEvents();
        final scene = ApplicationScene(
          properties: const ApplicationSceneProperties(enabled: true),
          engine: SceneEngine(backend: FakeBackend(), events: events),
          events: events,
          // A scene's object needs a GPU, which a test has not.
          factory: () => throw StateError('no GPU here'),
        );
        await runner
            .withPropertyValues(['spring.flutter.scene.app.enabled=true'])
            .withBeanOverride<ApplicationScene>(scene)
            .runAsync((context) async {
              await start(context.getBean<SceneStart>(), context.context);
              expect(scene.scene, isNull);
              final failed = events.events.whereType<SceneFailedEvent>().single;
              expect(failed.step, SceneStep.application);
            });
      },
    );

    test("the application's scene is not made without an engine", () async {
      var made = 0;
      final scene = ApplicationScene(
        properties: const ApplicationSceneProperties(enabled: true),
        engine: SceneEngine(
          backend: FakeBackend(fails: true),
          events: RecordingEvents(),
        ),
        events: RecordingEvents(),
        factory: () => throw StateError('made ${made++}'),
      );
      expect(await scene.create(), isNull);
      expect(made, 0);
    });

    test('the camera of the properties', () {
      ApplicationScene scene(SceneCameraProperties camera) => ApplicationScene(
        properties: ApplicationSceneProperties(camera: camera),
        engine: SceneEngine(backend: FakeBackend(), events: RecordingEvents()),
        events: RecordingEvents(),
      );
      final camera =
          scene(
                const SceneCameraProperties(position: [0, 1.5, -4], fov: 90),
              ).camera
              as PerspectiveCamera;
      expect(camera.position.storage, [0, 1.5, -4]);
      expect(camera.fovRadiansY, closeTo(1.5708, 0.0001));
      expect(
        () => scene(const SceneCameraProperties(target: [0, 1])).camera,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('spring.flutter.scene.app.camera.target'),
          ),
        ),
      );
    });
  });

  test('the status says the step in words, the app rewords it', () {
    final messages = StaticMessageSource()
      ..addMessage('scene.loading.model', '', 'Fetching {0} ({1}/{2})');
    final status = SceneStatus(messages);
    final source = Object();

    expect(status.text, isNull);
    status.onApplicationEvent(
      SceneEngineStartingEvent(source, backend: 'fake'),
    );
    expect(status.text, 'Compiling shaders');
    status.onApplicationEvent(
      SceneEngineReadyEvent(source, backend: 'fake', took: Duration.zero),
    );
    expect(status.text, isNull);
    status.onApplicationEvent(
      SceneModelLoadingEvent(
        source,
        name: 'hero',
        location: 'a',
        index: 2,
        count: 5,
      ),
    );
    expect(status.text, 'Fetching hero (2/5)');
    status.onApplicationEvent(
      SceneFailedEvent(
        source,
        step: SceneStep.model,
        name: 'hero',
        error: 'x',
      ),
    );
    expect(status.text, isNull);
    expect(status.history, hasLength(4));
  });
}
