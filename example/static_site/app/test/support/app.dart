// What the tests share: the site started as `flutter run` starts it, with
// the network replaced by a MockHttpTransport.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    hide Size;
import 'package:static_site_app/spring_gen/main.spring.dart';
import 'package:static_site_app/src/pages.dart';

/// The site with [http] as its network, on a desktop-sized window; the
/// context once the first page is on screen.
Future<ApplicationContext> startSite(
  WidgetTester tester,
  MockHttpTransport http,
) async {
  tester.view
    ..physicalSize = const Size(1200, 900) * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final app = springApplication;
  final withMock = SpringApplication(
    app.modules,
    autoConfigurations: app.autoConfigurations,
    autoConfigurationMetadata: app.autoConfigurationMetadata,
    dartDefines: app.dartDefines,
    fingerprint: app.fingerprint,
    initializers: [
      ...app.initializers,
      ApplicationContextInitializer.of(
        (context) => context.addBeanFactoryPostProcessor(
          BeanOverrideProcessor([
            BeanOverride<HttpTransport>(http, name: 'httpTransport'),
          ]),
        ),
      ),
    ],
  );
  await tester.pumpWidget(SpringApplicationWidget(application: () => withMock));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
  return SpringScope.of(tester.element(find.byType(SiteFrame)));
}

/// Stops the app the test started.
Future<void> stopSite(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}
