// The example app as generated (example/spring_gen/example.spring.dart):
// the annotated screens and shell, `BookPageRoute.to(...)` with a value, a
// parameter and an extra, replaceParams, push with a result.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

import '../example/spring_gen/example.spring.dart';

void main() {
  testWidgets('the generated routes of the example', (tester) async {
    await tester.pumpWidget(
      SpringApplicationWidget(application: () => springApplication),
    );
    await tester.pumpAndSettle();
    // spring.flutter.navigation.initial: the catalog, in the tabs.
    expect(find.text('Dune'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('Dune'));
    await tester.pumpAndSettle();
    final route = SpringScope.of(
      tester.element(find.text('page 1')),
    ).getBean<RouteTemplate>();
    expect(route.uri.toString(), '/catalog/books/978-0441013593?page=1');
    expect(find.text('Dune'), findsOneWidget); // the extra's title

    await tester.tap(find.text('next page'));
    await tester.pumpAndSettle();
    expect(find.text('page 2'), findsOneWidget);

    await tester.tap(find.text('buy'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing); // over the tabs
    await tester.tap(find.text('pay'));
    await tester.pumpAndSettle();
    expect(route.uri.toString(), '/catalog');

    await route.go('/nowhere');
    await tester.pumpAndSettle();
    expect(find.text('Nothing at /nowhere'), findsOneWidget);
  });
}
