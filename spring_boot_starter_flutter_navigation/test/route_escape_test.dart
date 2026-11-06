// An address that could leave a route's folder is refused: an encoded
// slash or backslash, `%00`, a `.` or `..` segment. Otherwise
// `/docs/..%2Fprivate%2Fsecret` stays on the public `/docs/{*path}` while
// its rest names a file of `/private`'s folder, past that screen's guard.
// The app stays on its screen, or opens its first one on a first visit.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

SpringApplication _application() => SpringApplication(
  [
    BeanModule(
      'test',
      [
        BeanDefinition<ScreenRoutes>(
          name: 'routes',
          create: (_) => ScreenRoutes.route()
              .screen(
                '/docs/{*path}',
                (r) => const Text('docs'),
                content: 'resources:content/docs/',
              )
              .screen(
                '/private/{*path}',
                (r) => const Text('private'),
                content: 'resources:content/private/',
              )
              .redirect('/', '/docs')
              .build(),
        ),
      ],
      resources: {
        'application.properties': const EmbeddedResource.text(
          'spring.flutter.app.type=material',
        ),
        'content/docs/index.md': const EmbeddedResource.text('# Docs'),
        'content/private/secret.md': const EmbeddedResource.text('# Secret'),
      },
    ),
  ],
  autoConfigurations: [
    springBootStarterFlutterAutoConfiguration,
    springBootStarterFlutterNavigationAutoConfiguration,
  ],
  bannerMode: BannerMode.off,
);

const _escapes = [
  '/docs/..%2Fprivate%2Fsecret',
  '/docs/%2E%2E%2Fprivate%2Fsecret',
  '/docs/..%5Cprivate%5Csecret',
  '/docs/x%00',
  '/docs/%2e%2e',
];

void main() {
  test('the refused paths', () {
    for (final path in _escapes) {
      expect(Navigation.refusedPath(path), isTrue, reason: path);
    }
    expect(Navigation.refusedPath(r'/docs/..\private'), isTrue);
    expect(Navigation.refusedPath('/docs/a.b/c..d'), isFalse);
    expect(Navigation.refusedPath('/docs/getting-started'), isFalse);
    expect(Navigation.refusedPath('/books/caf%C3%A9'), isFalse);
  });

  testWidgets('the app stays on its screen', (tester) async {
    await tester.pumpWidget(SpringApplicationWidget(application: _application));
    await tester.pumpAndSettle();
    final route = SpringScope.of(
      tester.element(find.text('docs')),
    ).getBean<RouteTemplate>();
    for (final address in _escapes) {
      debugPrint('go $address');
      await route.go(address);
      debugPrint('went');
      await tester.pump();
      debugPrint('pumped');
      await tester.pumpAndSettle();
      debugPrint('settled ${route.uri}');
      expect(route.uri.path, '/docs', reason: address);
      expect(route.content, 'resources:content/docs/index.md');
      expect(find.text('private'), findsNothing);
      expect(route.stack, hasLength(1), reason: address);
    }
  });

  testWidgets('a first visit to such an address opens the first screen', (
    tester,
  ) async {
    await tester.pumpWidget(SpringApplicationWidget(application: _application));
    await tester.pump();
    final navigation = SpringScope.of(
      tester.element(find.byType(Navigator).first),
    ).getBean<Navigation>();
    await navigation.openLink(RouteLocation.parse(_escapes.first));
    await tester.pumpAndSettle();
    expect(find.text('docs'), findsOneWidget);
    expect(find.text('private'), findsNothing);
  });
}
