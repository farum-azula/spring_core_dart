// The showcase as an app: it starts, and without a GPU (a test has none)
// its scenes are their placeholders while the page stays whole.
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_showcase/spring_gen/main.spring.dart';
import 'package:scene_showcase/src/showcase_page.dart';
import 'package:spring_boot_starter_flutter_scene/spring_boot_starter_flutter_scene.dart';

void main() {
  testWidgets('starts, and shows placeholders where scenes do not draw', (
    tester,
  ) async {
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => springApplication,
        home: const ShowcasePage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Scene Showcase'), findsOneWidget);
    // The showroom's placeholder, and the card's text over its own.
    expect(find.textContaining('no 3D here'), findsOneWidget);
    expect(find.textContaining('A scene behind a widget'), findsOneWidget);

    final context = SpringScope.of(tester.element(find.byType(ShowcasePage)));
    final availability = context.getBean<SceneAvailability>();
    expect(availability.draws, isFalse);
    expect(availability.reason, SceneUnavailable.engine);
    // The model is named by the properties; nothing loads without an engine.
    expect(context.getBean<SceneModels>().names, ['crate']);
  });
}
