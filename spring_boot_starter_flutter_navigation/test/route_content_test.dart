// RouteContentView: the Markdown of a route's content folder, a page per
// file (`index.md` is the folder's address), links between the files
// opening their screens as on the site's pages.
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
                (r) => const Scaffold(
                  body: SingleChildScrollView(
                    child: RouteContentView(selectable: false),
                  ),
                ),
                content: 'resources:content/docs/',
              )
              .redirect('/', '/docs')
              .build(),
        ),
      ],
      resources: {
        'application.properties': const EmbeddedResource.text(
          'spring.flutter.app.type=material',
        ),
        'content/docs/index.md': const EmbeddedResource.text(
          '# Docs\n\nRead [configuration](core/configuration.md).\n',
        ),
        'content/docs/core/configuration.md': const EmbeddedResource.text(
          '---\ntitle: Configuration\n---\n# Configuration\n\n'
          'See [beans](beans.md#scopes) and [Dart](https://dart.dev).\n',
        ),
        'content/docs/core/beans.md': const EmbeddedResource.text(
          '# Beans\n',
        ),
      },
    ),
  ],
  autoConfigurations: [
    springBootStarterFlutterAutoConfiguration,
    springBootStarterFlutterNavigationAutoConfiguration,
  ],
  bannerMode: BannerMode.off,
);

void main() {
  testWidgets('a page per file, links between them', (tester) async {
    await tester.pumpWidget(SpringApplicationWidget(application: _application));
    await tester.pumpAndSettle();
    expect(find.text('Docs'), findsOneWidget);
    final route = SpringScope.of(
      tester.element(find.text('Docs')),
    ).getBean<RouteTemplate>();
    expect(route.content, 'resources:content/docs/index.md');

    await tester.tapOnText(find.textRange.ofSubstring('configuration'));
    await tester.pumpAndSettle();
    expect(route.uri.toString(), '/docs/core/configuration');
    expect(find.text('Configuration'), findsOneWidget);

    await tester.tapOnText(find.textRange.ofSubstring('beans'));
    await tester.pumpAndSettle();
    expect(route.uri.toString(), '/docs/core/beans#scopes');
    expect(find.text('Beans'), findsOneWidget);
  });
}
