// spring.flutter.navigation.languages: [en, ja]: an address under /ja opens
// the same screen in Japanese (the app's locale, context.message), the
// address keeps the prefix while the app navigates, switchLanguage changes
// both; the default language has no prefix; without languages /ja is no
// address of the app.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

SpringApplication Function() _application({bool languages = true}) =>
    () => SpringApplication(
      [
        BeanModule(
          'test',
          [
            BeanDefinition<ScreenRoutes>(
              name: 'routes',
              create: (_) => ScreenRoutes.route()
                  .screen(
                    '/docs',
                    (r) => Builder(
                      builder: (context) => Text(context.message('title')),
                    ),
                  )
                  .screen('/about', (r) => const Text('about'))
                  .screen(
                    '/guide/{*path}',
                    (r) => const RouteContentView(selectable: false),
                    content: 'resources:content/guide/',
                  )
                  .redirect('/', '/docs')
                  .build(),
            ),
          ],
          resources: {
            'application.properties': EmbeddedResource.text(
              'spring.flutter.app.type=material\n'
              'spring.messages.basename=messages\n'
              '${languages ? 'spring.flutter.navigation.languages=en,ja\n' : ''}',
            ),
            'messages.properties': const EmbeddedResource.text('title=Docs'),
            'messages_ja.properties': const EmbeddedResource.text(
              'title=ドキュメント',
            ),
            'content/guide/index.md': const EmbeddedResource.text(
              '# Guide\n\nSee [setup](setup.md).',
            ),
            'content/guide/index.ja.md': const EmbeddedResource.text(
              '# ガイド\n\n[設定](setup.ja.md)を見てください。',
            ),
            'content/guide/setup.md': const EmbeddedResource.text('# Setup'),
          },
        ),
      ],
      autoConfigurations: [
        springBootAutoConfiguration,
        springBootStarterFlutterAutoConfiguration,
        springBootStarterFlutterNavigationAutoConfiguration,
      ],
      bannerMode: BannerMode.off,
    );

Future<(RouteTemplate, SpringRouterConfig)> _start(
  WidgetTester tester, {
  bool languages = true,
}) async {
  await tester.pumpWidget(
    SpringApplicationWidget(application: _application(languages: languages)),
  );
  await tester.pumpAndSettle();
  final context = SpringScope.of(tester.element(find.byType(Navigator).first));
  return (
    context.getBean<RouteTemplate>(),
    context.getBean<SpringRouterConfig>(),
  );
}

String? _address(SpringRouterConfig router) =>
    router.routerDelegate.currentConfiguration?.uri.toString();

void main() {
  testWidgets('an address under /ja: the same screen, in Japanese', (
    tester,
  ) async {
    final (route, router) = await _start(tester);
    expect(find.text('Docs'), findsOneWidget);
    expect(route.language, 'en');
    expect(_address(router), '/docs');

    await route.go('/ja/docs');
    await tester.pumpAndSettle();
    expect(find.text('ドキュメント'), findsOneWidget);
    expect(route.language, 'ja');
    expect(route.uri.path, '/docs');
    expect(_address(router), '/ja/docs');

    // The app's own paths have no prefix: the language stays.
    await route.go('/about');
    await tester.pumpAndSettle();
    expect(_address(router), '/ja/about');

    route.switchLanguage('en');
    await tester.pumpAndSettle();
    expect(_address(router), '/about');
    await route.go('/docs');
    await tester.pumpAndSettle();
    expect(find.text('Docs'), findsOneWidget);
    expect(() => route.switchLanguage('fr'), throwsArgumentError);
  });

  // Off the web the platform's address is a link (openLink): without a
  // prefix, the default language's, as in a browser.
  testWidgets("the platform's address: no prefix is the default language", (
    tester,
  ) async {
    final (route, router) = await _start(tester);
    await route.go('/ja/docs');
    await tester.pumpAndSettle();
    await router.routerDelegate.setNewRoutePath(RouteLocation('/docs'));
    await tester.pumpAndSettle();
    expect(route.language, 'en');
    expect(find.text('Docs'), findsOneWidget);
  });

  testWidgets('a Markdown screen shows its translation, links included', (
    tester,
  ) async {
    final (route, router) = await _start(tester);
    await route.go('/ja/guide');
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('ガイド'), findsOneWidget);
    await tester.tapOnText(find.textRange.ofSubstring('設定'));
    await tester.pumpAndSettle();
    expect(_address(router), '/ja/guide/setup');
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    // No translation: the default language's file.
    expect(find.text('Setup'), findsOneWidget);
  });

  testWidgets('a refused address under /ja stays refused', (tester) async {
    final (route, router) = await _start(tester);
    await route.go('/ja/..%2Fabout');
    await tester.pumpAndSettle();
    expect(route.uri.path, '/docs');
    expect(_address(router), '/docs');
  });

  testWidgets('without languages, /ja is no address of the app', (
    tester,
  ) async {
    final (route, _) = await _start(tester, languages: false);
    expect(route.language, isNull);
    await route.go('/ja/docs');
    await tester.pumpAndSettle();
    expect(route.pattern, isNull);
  });
}
