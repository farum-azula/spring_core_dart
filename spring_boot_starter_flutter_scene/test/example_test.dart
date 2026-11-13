// The example app as generated (example/spring_gen/example.spring.dart):
// it starts, its model is named by the properties, and without a GPU (a
// test has none) its scene is the placeholder.
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_scene/spring_boot_starter_flutter_scene.dart';

import '../example/example.dart';
import '../example/spring_gen/example.spring.dart';

void main() {
  testWidgets('the example starts and shows its placeholder', (tester) async {
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => springApplication,
        home: const Showroom(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('hero'), findsOneWidget);
    final context = SpringScope.of(tester.element(find.byType(Showroom)));
    final hero = context.getBean<SceneModels>()['hero'];
    expect(hero.location, 'asset:assets/models/hero.glb');
    expect(context.getBean<SceneProperties>().maxFrameRate, 30);
    expect(context.getBean<LoadedModels>().names, isEmpty);
  });
}
