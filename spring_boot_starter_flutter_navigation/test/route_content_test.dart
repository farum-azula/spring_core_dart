// RouteContentView: the Markdown of a route's content folder, a page per
// file (`index.md` is the folder's address, a subfolder's too), links
// between the files opening their screens as on the site's pages, and the
// same screen kept from one address of the route to another.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

class _DocsScreen extends StatefulWidget {
  const _DocsScreen();

  @override
  State<_DocsScreen> createState() => _DocsScreenState();
}

class _DocsScreenState extends State<_DocsScreen> {
  static final created = <_DocsScreenState>[];

  final scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    created.add(this);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SingleChildScrollView(
      controller: scroll,
      child: Column(
        children: [
          const RouteContentView(selectable: false),
          const SizedBox(height: 2000),
        ],
      ),
    ),
  );
}

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
                (r) => const _DocsScreen(),
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
        'content/docs/core/beans.md': EmbeddedResource.text(
          '# Beans\n\n${'Text.\n\n' * 80}## Scopes\n\nSingletons.\n',
        ),
        'content/docs/guides/index.md': const EmbeddedResource.text(
          '# Guides\n\nStart with [routing](routing.md).\n',
        ),
        'content/docs/guides/routing.md': const EmbeddedResource.text(
          '# Routing\n',
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

  testWidgets('an address with a / at its end is the same page', (
    tester,
  ) async {
    // Static hosts send /docs/core/beans/ for docs/core/beans/index.html.
    await tester.pumpWidget(SpringApplicationWidget(application: _application));
    await tester.pumpAndSettle();
    final route = SpringScope.of(
      tester.element(find.text('Docs')),
    ).getBean<RouteTemplate>();
    await route.go('/docs/core/beans/');
    await tester.pumpAndSettle();
    expect(find.text('Beans'), findsOneWidget);
    expect(route.uri.path, '/docs/core/beans');
  });

  testWidgets("a folder's index.md at the folder's address", (tester) async {
    await tester.pumpWidget(SpringApplicationWidget(application: _application));
    await tester.pumpAndSettle();
    final route = SpringScope.of(
      tester.element(find.text('Docs')),
    ).getBean<RouteTemplate>();
    await route.go('/docs/guides');
    await tester.pumpAndSettle();
    expect(find.text('Guides'), findsOneWidget);

    // Its links are relative to its own folder.
    await tester.tapOnText(find.textRange.ofSubstring('routing'));
    await tester.pumpAndSettle();
    expect(route.uri.path, '/docs/guides/routing');
    expect(find.text('Routing'), findsOneWidget);
  });

  testWidgets('another address of the same route keeps the screen and '
      'opens its page at the top', (
    tester,
  ) async {
    _DocsScreenState.created.clear();
    await tester.pumpWidget(SpringApplicationWidget(application: _application));
    await tester.pumpAndSettle();
    final route = SpringScope.of(
      tester.element(find.text('Docs')),
    ).getBean<RouteTemplate>();
    final screen = _DocsScreenState.created.single;
    screen.scroll.jumpTo(300);
    await tester.pump();

    await route.go('/docs/core/beans');
    await tester.pumpAndSettle();
    expect(find.text('Beans'), findsOneWidget);
    expect(_DocsScreenState.created, [same(screen)]);
    // Another page: from its top, as a browser opens it.
    expect(screen.scroll.offset, 0);
    expect(route.uri.path, '/docs/core/beans');

    // The same page again (a rebuild, the same address): where it was.
    screen.scroll.jumpTo(300);
    await route.go('/docs/core/beans');
    await tester.pumpAndSettle();
    expect(screen.scroll.offset, 300);
  });

  testWidgets("the address's #anchor scrolls to its heading", (tester) async {
    _DocsScreenState.created.clear();
    await tester.pumpWidget(SpringApplicationWidget(application: _application));
    await tester.pumpAndSettle();
    final route = SpringScope.of(
      tester.element(find.text('Docs')),
    ).getBean<RouteTemplate>();
    await route.go('/docs/core/beans#scopes');
    await tester.pumpAndSettle();
    expect(find.text('Scopes'), findsOneWidget);
    expect(_DocsScreenState.created.single.scroll.offset, greaterThan(0));
  });
}
