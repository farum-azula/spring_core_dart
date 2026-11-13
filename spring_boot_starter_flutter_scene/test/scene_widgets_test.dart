// The scene widgets where scenes do not draw: plain widgets over their
// placeholders, with nothing of the engine built. (A scene that draws
// needs a GPU: that is seen in an app, not here.)
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart' show SceneView;
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_scene/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_scene/spring_boot_starter_flutter_scene.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show ApplicationContextRunner;

import 'support/fakes.dart';

const _placeholder = Text('placeholder', textDirection: TextDirection.ltr);
const _child = Text('child', textDirection: TextDirection.ltr);

Widget _backdrop() => Center(
  child: SizedBox(
    width: 200,
    height: 100,
    child: SceneBackdrop(
      margin: 10,
      placeholder: _placeholder,
      scene: (context, surface) => const [],
      child: _child,
    ),
  ),
);

void main() {
  final runner = const ApplicationContextRunner()
      .withAutoConfiguration(springBootAutoConfiguration)
      .withAutoConfiguration(springBootStarterFlutterAutoConfiguration)
      .withAutoConfiguration(springBootStarterFlutterSceneAutoConfiguration)
      .withAutoConfiguration(
        springBootStarterFlutterSceneDebugAutoConfiguration,
      )
      .withBean<SceneModelImporter>(FakeImporter.new);

  testWidgets('without Spring above: the placeholder', (tester) async {
    await tester.pumpWidget(
      const SpringSceneView.declarative(placeholder: _placeholder),
    );
    expect(find.text('placeholder'), findsOneWidget);
    expect(find.byType(SceneView), findsNothing);
  });

  testWidgets('without a placeholder: nothing', (tester) async {
    await tester.pumpWidget(const SpringSceneView.declarative());
    expect(find.byType(SizedBox), findsOneWidget);
    expect(find.byType(SceneView), findsNothing);
  });

  testWidgets('scenes off: the placeholder, and no engine', (tester) async {
    await runner
        .withBean<SceneBackend>(FakeBackend.new)
        .withPropertyValues(['spring.flutter.scene.enabled=false'])
        .runAsync((context) async {
          await tester.pumpWidget(
            SpringScope(
              applicationContext: context.context,
              child: _backdrop(),
            ),
          );
          expect(find.text('placeholder'), findsOneWidget);
          expect(find.text('child'), findsOneWidget);
          expect(find.byType(SceneView), findsNothing);
        });
  });

  testWidgets('render: off: the placeholder, the engine not asked', (
    tester,
  ) async {
    final backend = FakeBackend();
    await runner
        .withBean<SceneBackend>(() => backend)
        .withPropertyValues(['spring.flutter.scene.render=off'])
        .runAsync((context) async {
          await tester.pumpWidget(
            SpringScope(
              applicationContext: context.context,
              child: _backdrop(),
            ),
          );
          await tester.pump();
          expect(find.text('placeholder'), findsOneWidget);
          expect(find.text('child'), findsOneWidget);
          expect(backend.starts, 0);
        });
  });

  testWidgets('a view starts the engine; a failed start: the placeholder', (
    tester,
  ) async {
    final backend = FakeBackend(fails: true);
    await runner.withBean<SceneBackend>(() => backend).runAsync((
      context,
    ) async {
      await tester.pumpWidget(
        SpringScope(applicationContext: context.context, child: _backdrop()),
      );
      expect(find.text('placeholder'), findsOneWidget);
      await tester.pump();
      await tester.pump();
      expect(backend.starts, 1);
      expect(context.getBean<SceneEngine>().hasFailed, isTrue);
      expect(find.text('placeholder'), findsOneWidget);
      expect(find.text('child'), findsOneWidget);
      expect(find.byType(SceneView), findsNothing);
      // Nothing on the screen for the debug tab.
      expect(context.getBean<SceneDebug>().views, isEmpty);
    });
  });

  testWidgets("the application's view without such a scene", (tester) async {
    await runner.withBean<SceneBackend>(FakeBackend.new).runAsync((
      context,
    ) async {
      await tester.pumpWidget(
        SpringScope(
          applicationContext: context.context,
          child: const SpringSceneView(placeholder: _placeholder),
        ),
      );
      await tester.pump();
      await tester.pump();
      // The engine is ready, but the app has no scene of its own.
      expect(find.text('placeholder'), findsOneWidget);
      expect(find.byType(SceneView), findsNothing);
    });
  });

  test('a widget as a plane of the scene', () {
    const surface = SceneSurface(Size(200, 100));
    expect(surface.width, 2);
    expect(surface.height, 1);
    expect(surface.toScene(const Offset(100, 50)).storage, [0, 0, 0]);
    expect(surface.toScene(Offset.zero).storage, [-1, 0.5, 0]);
    expect(
      surface.toScene(const Offset(200, 100), depth: 0.5).storage,
      [1, -0.5, 0.5],
    );
    expect(surface.length(50), 0.5);
    expect(surface, const SceneSurface(Size(200, 100)));
  });

  test('a colour of the app as linear light', () {
    expect(const Color(0xFF000000).linear.storage, [0, 0, 0]);
    expect(const Color(0xFFFFFFFF).linear.storage, [1, 1, 1]);
    // sRGB 0.5 is about 0.214 of the light.
    expect(const Color(0xFF808080).linear.x, closeTo(0.2158, 0.001));
    expect(const Color(0x80FFFFFF).linearWithAlpha.w, closeTo(0.502, 0.001));
  });

  test("a scene's clock stands while the scene is paused", () async {
    final clock = SceneClock();
    final start = clock.clock.now();

    clock.paused = true;
    final held = clock.clock.now();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    // The time did not move.
    expect(clock.clock.now(), held);

    clock.paused = false;
    // It goes on from where it stood, not from the wall's time.
    final resumed = clock.clock.now();
    expect(
      resumed.difference(held),
      lessThan(const Duration(milliseconds: 20)),
    );
    expect(resumed.isBefore(start), isFalse);
    // Pausing twice is pausing once.
    clock
      ..paused = false
      ..paused = true
      ..paused = true;
    expect(clock.paused, isTrue);
  });

  test('the debug record: frames a second, a change notifies', () async {
    final debug = SceneDebug();
    var notified = 0;
    debug.addListener(() => notified++);
    const state = SceneViewState(
      scene: null,
      animated: true,
      frameRate: 30,
      pixelRatio: null,
    );

    final measure = debug.opened('header', state);
    await Future<void>.delayed(Duration.zero);
    expect(debug.views.single.name, 'header');
    expect(notified, 1);

    for (var i = 0; i < 3; i++) {
      measure.frame(const Duration(milliseconds: 33));
    }
    expect(debug.views.single.framesPerSecond, 3);
    expect(debug.views.single.frameCount, 3);
    // A frame is not a change.
    await Future<void>.delayed(Duration.zero);
    expect(notified, 1);

    measure.changed(state);
    await Future<void>.delayed(Duration.zero);
    expect(notified, 1);
    measure.changed(
      const SceneViewState(
        scene: null,
        animated: false,
        frameRate: 30,
        pixelRatio: null,
        paused: 'off-screen',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(notified, 2);

    measure.closed();
    await Future<void>.delayed(Duration.zero);
    expect(debug.views, isEmpty);
    expect(notified, 3);
  });
}
