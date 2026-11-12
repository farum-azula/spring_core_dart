// The navigation on a running app: SpringApplicationWidget without a home
// builds SpringApp on the router; screens, shells with a stack per branch,
// redirects, filters, conversions, the not-found and error screens, the
// `route` scope, push and pop with a result, the back button.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

import 'support/design_starters.dart';

class Page extends StatelessWidget {
  const Page(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(body: Text(label));
}

class Tabs extends StatelessWidget {
  const Tabs(this.shell, {super.key});

  final ShellState shell;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: shell.child,
    bottomNavigationBar: Row(
      children: [
        for (var i = 0; i < shell.branches.length; i++)
          TextButton(
            onPressed: () => shell.select(i),
            child: Text('tab ${shell.branches[i]}'),
          ),
      ],
    ),
  );
}

// A bean that lives as long as its screen.
class ScreenState {
  static var created = 0;
  static var destroyed = 0;

  ScreenState() {
    created++;
  }

  void destroy() => destroyed++;
}

// A bean that lives as long as its shell branch.
class BranchState {
  static var destroyed = 0;

  void destroy() => destroyed++;
}

class _OwnIsbn extends StatelessWidget {
  const _OwnIsbn();

  @override
  Widget build(BuildContext context) {
    final branch = context.bean<BranchState>();
    return Scaffold(
      body: Text(
        'own ${context.route.pathVariable('isbn')} '
        'branch ${identityHashCode(branch)}',
      ),
    );
  }
}

class LoggedIn {
  var value = false;
}

ScreenRoutes routes(LoggedIn user) =>
    ScreenRoutes.route(source: 'test routes')
        .shell(
          (shell) => Tabs(shell),
          (tabs) => tabs
              .branch(
                '/catalog',
                (b) => b
                    .screen('/catalog', (r) => const Page('catalog'))
                    .screen(
                      '/catalog/books/{isbn}',
                      (r) => Page(
                        'book ${r.pathVariable('isbn')} page '
                        '${r.param<int>('page')}',
                      ),
                      params: {'page': int},
                      title: 'Book',
                    )
                    .screen('/catalog/own/{isbn}', (r) => const _OwnIsbn()),
              )
              .branch(
                '/profile',
                (b) => b
                    .screen('/profile', (r) => const Page('profile'))
                    .filter(
                      RouteFilterFunction(
                        (request) =>
                            user.value ? null : RouteLocation('/login'),
                      ),
                    ),
              ),
          key: Tabs,
        )
        .screen('/login', (r) => const Page('login'))
        .screen('/checkout', (r) => const _Checkout())
        .screen('/state', (r) => const _StatePage())
        .redirect('/', '/catalog')
        .notFound((r) => Page('missing ${r.path}'))
        .error((r) => Page('broken ${r.error}'))
        .build();

class _Checkout extends StatelessWidget {
  const _Checkout();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      onPressed: () => context.route.pop(true),
      child: const Text('pay'),
    ),
  );
}

class _StatePage extends StatelessWidget {
  const _StatePage();

  @override
  Widget build(BuildContext context) {
    context.bean<ScreenState>();
    return const Scaffold(body: Text('state'));
  }
}

SpringApplication application({
  Map<String, String> properties = const {},
  LoggedIn? user,
}) {
  final logged = user ?? LoggedIn();
  return SpringApplication(
    [
      BeanModule(
        'test',
        [
          BeanDefinition<ScreenRoutes>(
            name: 'routes',
            source: 'test routes',
            create: (_) => routes(logged),
          ),
          BeanDefinition<BranchState>(
            name: 'branchState',
            scope: NavigationScopes.branch,
            create: (_) => BranchState(),
            preDestroy: (state) => state.destroy(),
          ),
          BeanDefinition<ScreenState>(
            name: 'screenState',
            scope: NavigationScopes.route,
            create: (_) => ScreenState(),
            preDestroy: (state) => state.destroy(),
          ),
        ],
        resources: {
          'application.properties': EmbeddedResource.text(
            [
              'spring.flutter.app.type=material',
              for (final MapEntry(:key, :value) in properties.entries)
                '$key=$value',
            ].join('\n'),
          ),
        },
      ),
    ],
    autoConfigurations: [
      springBootStarterFlutterAutoConfiguration,
      springBootStarterFlutterNavigationAutoConfiguration,
      ...DesignStarters.onlyMaterial.autoConfigurations,
    ],
    autoConfigurationMetadata: DesignStarters.onlyMaterial.metadata,
    bannerMode: BannerMode.off,
  );
}

Future<RouteTemplate> start(
  WidgetTester tester, {
  Map<String, String> properties = const {},
  LoggedIn? user,
}) async {
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => application(properties: properties, user: user),
    ),
  );
  await tester.pumpAndSettle();
  final context = SpringScope.of(tester.element(find.byType(Router<Object>)));
  return context.getBean<RouteTemplate>();
}

void main() {
  testWidgets('the start: `/` is redirected into the shell', (tester) async {
    final route = await start(tester);
    expect(find.text('catalog'), findsOneWidget);
    expect(find.text('tab /catalog'), findsOneWidget);
    expect(route.uri.toString(), '/catalog');
    expect(route.branch, '/catalog');
  });

  testWidgets('a deep address puts the screens of its path below it', (
    tester,
  ) async {
    final route = await start(tester);
    await route.go('/catalog/books/978-0?page=2');
    await tester.pumpAndSettle();
    expect(find.text('book 978-0 page 2'), findsOneWidget);
    expect(
      [for (final s in route.stack) s.path],
      [
        '/catalog',
        '/catalog/books/978-0',
      ],
    );
    // The back button goes to the catalog, in the shell.
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('catalog'), findsOneWidget);
    expect(route.uri.toString(), '/catalog');
  });

  testWidgets('a branch keeps its stack while another is shown', (
    tester,
  ) async {
    final user = LoggedIn()..value = true;
    final route = await start(tester, user: user);
    await route.go('/catalog/books/1');
    await tester.pumpAndSettle();
    await tester.tap(find.text('tab /profile'));
    await tester.pumpAndSettle();
    expect(find.text('profile'), findsOneWidget);
    await tester.tap(find.text('tab /catalog'));
    await tester.pumpAndSettle();
    expect(find.text('book 1 page null'), findsOneWidget);
    // The current tab again: back to its first screen.
    await tester.tap(find.text('tab /catalog'));
    await tester.pumpAndSettle();
    expect(find.text('catalog'), findsOneWidget);
  });

  testWidgets('a filter sends elsewhere', (tester) async {
    final route = await start(tester);
    await route.go('/profile');
    await tester.pumpAndSettle();
    expect(find.text('login'), findsOneWidget);
    expect(route.uri.toString(), '/login');
  });

  testWidgets('a wrong value opens the error screen, not a crash', (
    tester,
  ) async {
    final route = await start(tester);
    await route.go('/catalog/books/1?page=abc');
    await tester.pumpAndSettle();
    expect(find.textContaining('broken'), findsOneWidget);
    expect(find.textContaining('"abc" of "page"'), findsOneWidget);
  });

  testWidgets('an unknown address opens the not-found screen', (tester) async {
    final route = await start(tester);
    await route.go('/nowhere');
    await tester.pumpAndSettle();
    expect(find.text('missing /nowhere'), findsOneWidget);
  });

  testWidgets('push completes with what the screen is popped with', (
    tester,
  ) async {
    final route = await start(tester);
    final paid = route.push<bool>('/checkout');
    await tester.pumpAndSettle();
    expect(route.canPop, isTrue);
    await tester.tap(find.text('pay'));
    await tester.pumpAndSettle();
    expect(await paid, isTrue);
    expect(find.text('catalog'), findsOneWidget);
  });

  testWidgets('a route bean lives as long as its screen', (tester) async {
    ScreenState.created = 0;
    ScreenState.destroyed = 0;
    final route = await start(tester);
    unawaited(route.push<void>('/state'));
    await tester.pumpAndSettle();
    expect(ScreenState.created, 1);
    expect(route.pop(), isTrue);
    await tester.pumpAndSettle();
    expect(ScreenState.destroyed, 1);
  });

  testWidgets('replaceParams rebuilds the screen in place', (tester) async {
    final route = await start(tester);
    await route.go(
      '/catalog/books/{isbn}',
      pathVariables: {'isbn': '7'},
      params: {'page': 1},
    );
    await tester.pumpAndSettle();
    expect(find.text('book 7 page 1'), findsOneWidget);
    route.replaceParams({'page': 3});
    await tester.pumpAndSettle();
    expect(find.text('book 7 page 3'), findsOneWidget);
    expect(route.stack, hasLength(2));
  });

  testWidgets('spring.flutter.navigation.initial is where the app starts', (
    tester,
  ) async {
    final route = await start(
      tester,
      properties: {'spring.flutter.navigation.initial': '/login'},
    );
    expect(find.text('login'), findsOneWidget);
    expect(route.uri.toString(), '/login');
  });

  testWidgets('context.route is the widget own screen, not the top one', (
    tester,
  ) async {
    final route = await start(tester);
    await route.go('/catalog/own/1');
    await tester.pumpAndSettle();
    unawaited(route.push<void>('/catalog/own/2'));
    await tester.pumpAndSettle();
    String text(String isbn) => tester
        .widget<Text>(
          find.textContaining('own $isbn ', skipOffstage: false),
        )
        .data!;
    expect(route.pathVariable('isbn'), '2');
    expect(text('1'), startsWith('own 1 '));
    expect(text('2'), startsWith('own 2 '));
    // Both screens are in the catalog branch: one branch bean.
    expect(text('1').split('branch ').last, text('2').split('branch ').last);
  });

  testWidgets('a branch bean goes when its shell closes', (tester) async {
    BranchState.destroyed = 0;
    final route = await start(tester);
    await route.go('/catalog/own/1');
    await tester.pumpAndSettle();
    expect(BranchState.destroyed, 0);
    await route.go('/login');
    await tester.pumpAndSettle();
    expect(BranchState.destroyed, 1);
  });

  testWidgets('the browser tab and task switcher show the route title', (
    tester,
  ) async {
    final labels = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setApplicationSwitcherDescription') {
          labels.add(
            (call.arguments as Map<Object?, Object?>)['label']! as String,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final route = await start(
      tester,
      properties: {'spring.flutter.app.title': 'Shop'},
    );
    await route.go('/catalog/books/1');
    await tester.pumpAndSettle();
    expect(labels, contains('Book'));
    await route.go('/login');
    await tester.pumpAndSettle();
    expect(labels.last, 'Shop');
  });

  testWidgets('a link from outside opens its screen, unless excluded', (
    tester,
  ) async {
    final route = await start(
      tester,
      properties: {
        'spring.flutter.navigation.deep-links.exclude': '/checkout',
      },
    );
    Future<void> link(String location) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.navigation.name,
        SystemChannels.navigation.codec.encodeMethodCall(
          MethodCall('pushRouteInformation', {'location': location}),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    await link('/catalog/books/5?page=2');
    expect(find.text('book 5 page 2'), findsOneWidget);
    // Excluded: the app's first screen instead.
    await link('/checkout');
    expect(route.uri.toString(), '/catalog');
  });

  testWidgets('the first screen is in the first frame of the app', (
    tester,
  ) async {
    await tester.pumpWidget(
      SpringApplicationWidget(application: () => application()),
    );
    // The context starts asynchronously; then one frame shows the screen.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump();
    expect(find.text('catalog'), findsOneWidget);
  });

  testWidgets('an async filter decides too', (tester) async {
    final route = await start(tester);
    final navigation = SpringScope.of(
      tester.element(find.byType(Router<Object>)),
    ).getBean<Navigation>();
    final slow = Navigation(
      table: navigation.table,
      conversion: navigation.conversion,
      scopes: RouteScopes(),
      filters: [
        RouteFilterFunction(
          (request) async => request.location.path == '/checkout'
              ? RouteLocation('/login')
              : null,
        ),
      ],
    );
    await slow.go(RouteLocation('/checkout'));
    expect(slow.top?.state.location.path, '/login');
    expect(route.uri.toString(), '/catalog');
    slow.dispose();
  });
}
