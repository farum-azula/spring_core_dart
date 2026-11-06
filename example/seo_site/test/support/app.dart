// The site started as `flutter run` starts it, on a desktop-sized window.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seo_site_app/spring_gen/main.spring.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

/// The site on [path]; the context once the page is on screen.
Future<ApplicationContext> startSite(WidgetTester tester, String path) async {
  tester.view
    ..physicalSize = const Size(1200, 900) * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => springApplication,
      args: ['--spring.flutter.navigation.initial=$path'],
    ),
  );
  // The Markdown resources are read for real.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
  return SpringScope.of(tester.element(find.byType(Overlay).first));
}

/// Stops the app the test started.
Future<void> stopSite(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}
