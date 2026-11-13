// The scenes on a device, where there is a GPU (a widget test has none):
// the engine starts, the model of the properties is loaded with the
// splash, and each of the three scenes draws frames with something in
// them.
//
//   flutter test integration_test -d macos
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scene_showcase/spring_gen/main.spring.dart';
import 'package:scene_showcase/src/showcase_page.dart';
import 'package:spring_boot_starter_flutter_scene/spring_boot_starter_flutter_scene.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the engine starts and every scene draws', (tester) async {
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => springApplication,
        home: const ShowcasePage(),
      ),
    );
    // The scenes never settle: they draw frame after frame.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final context = SpringScope.of(tester.element(find.byType(ShowcasePage)));
    final availability = context.getBean<SceneAvailability>();
    expect(availability.engine.failure, isNull);
    expect(availability.isReady, isTrue);

    final crate = context.getBean<SceneModels>()['crate'];
    expect(crate.state, SceneModelState.ready);
    expect(context.getBean<ApplicationScene>().scene, isNotNull);

    final views = context.getBean<SceneDebug>().views;
    expect(
      [for (final view in views) view.name],
      unorderedEquals(['application', 'showroom', 'plate-card']),
    );
    for (final view in views) {
      expect(view.frameCount, greaterThan(0), reason: '${view.name}: frames');
      expect(
        view.stats?.counters.draws,
        greaterThan(0),
        reason: '${view.name}: draw calls of its last frame',
      );
    }
    // The placeholders are gone.
    expect(find.textContaining('no 3D here'), findsNothing);
  });

  testWidgets('animations turned off and on again: the scenes stand, then go '
      'on', (tester) async {
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => springApplication,
        home: const ShowcasePage(),
      ),
    );
    Future<void> run() async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await run();
    final context = SpringScope.of(tester.element(find.byType(ShowcasePage)));
    final motion = context.getBean<DebugMotion>();
    final views = context.getBean<SceneDebug>().views;
    int frames() => views.fold(0, (sum, view) => sum + view.frameCount);
    expect(frames(), greaterThan(0));

    // Off: one frame stands in every scene.
    motion.animations = false;
    await run();
    expect(tester.takeException(), isNull);
    expect(views.every((view) => !view.state.animated), isTrue);
    final stood = frames();
    await run();
    expect(frames(), stood);

    // On again: the engine's view made a second ticker here and Flutter
    // refused it, when the starter switched the view's own ticking.
    motion.animations = true;
    await run();
    expect(tester.takeException(), isNull);
    expect(views.every((view) => view.state.animated), isTrue);
    expect(frames(), greaterThan(stood));
    // The scenes did not jump by the time they stood: a frame after the
    // pause is as long as any other.
    for (final view in views) {
      expect(
        view.lastFrame,
        lessThan(const Duration(milliseconds: 500)),
        reason: view.name,
      );
    }
    expect(find.textContaining('SingleTickerProviderStateMixin'), findsNothing);
  });
}
