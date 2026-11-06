// The page transitions: the theme's `motion.page-transition` (a kind, or a
// kind with its duration and curve) for every app type, a screen's own
// (`transition:`), one navigation's (`go(path, transition: ...)`), reduced
// motion; and a screen in a branch its path is not under (`branch:`).
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

class _Page extends StatelessWidget {
  const _Page(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(child: Text(text));
}

ScreenRoutes _routes() => ScreenRoutes.route()
    .shell(
      (shell) => shell.child,
      (tabs) => tabs
          .branch('/home', (b) => b.screen('/home', (r) => const _Page('home')))
          .branch(
            '/more',
            (b) => b
                .screen('/more', (r) => const _Page('more'))
                .screen('/motion', (r) => const _Page('motion')),
          ),
    )
    .screen('/page', (r) => const _Page('page'))
    .screen(
      '/still',
      (r) => const _Page('still'),
      transition: PageTransition.none,
    )
    .screen(
      '/faded',
      (r) => const _Page('faded'),
      transition: PageTransition.fade,
    )
    .redirect('/', '/home')
    .build();

Future<RouteTemplate> _start(
  WidgetTester tester, {
  String type = 'material',
  Map<String, String> theme = const {},
}) async {
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => SpringApplication(
        [
          BeanModule(
            'test',
            [
              BeanDefinition<ScreenRoutes>(
                name: 'routes',
                source: 'test routes',
                create: (_) => _routes(),
              ),
            ],
            resources: {
              'application.properties': EmbeddedResource.text(
                [
                  'spring.flutter.app.type=$type',
                  for (final MapEntry(:key, :value) in theme.entries)
                    'spring.flutter.theme.$key=$value',
                ].join('\n'),
              ),
            },
          ),
        ],
        autoConfigurations: [
          springBootStarterFlutterAutoConfiguration,
          springBootStarterFlutterNavigationAutoConfiguration,
        ],
        bannerMode: BannerMode.off,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return SpringScope.of(
    tester.element(find.byType(Router<Object>)),
  ).getBean<RouteTemplate>();
}

/// The route of the screen showing [text], once its transition is over.
Future<PageRoute<Object?>> _routeOf(
  WidgetTester tester,
  RouteTemplate route,
  String path,
  String text, {
  PageTransition? transition,
}) async {
  // push completes when the screen is closed: not awaited.
  unawaited(route.push<void>(path, transition: transition));
  await tester.pumpAndSettle();
  return ModalRoute.of(tester.element(find.text(text)))! as PageRoute<Object?>;
}

void main() {
  testWidgets('by default no transition, in every app type', (tester) async {
    for (final type in ['material', 'cupertino', 'widgets']) {
      final route = await _start(tester, type: type);
      final page = await _routeOf(tester, route, '/page', 'page');
      expect(page.transitionDuration, Duration.zero, reason: type);
    }
  });

  testWidgets("Material: platform is Material's own", (tester) async {
    final route = await _start(
      tester,
      theme: {'motion.page-transition': 'platform'},
    );
    final page = await _routeOf(tester, route, '/page', 'page');
    expect(page, isA<MaterialRouteTransitionMixin<Object?>>());
    // Flutter's own duration (from the platform's transition builder).
    expect(page.transitionDuration, greaterThan(Duration.zero));
  });

  testWidgets('the theme: page-transition none, as written', (
    tester,
  ) async {
    final route = await _start(
      tester,
      theme: {'motion.page-transition': 'none'},
    );
    final page = await _routeOf(tester, route, '/page', 'page');
    expect(page.transitionDuration, Duration.zero);
  });

  testWidgets('the theme: a kind with its duration and curve', (
    tester,
  ) async {
    final route = await _start(
      tester,
      type: 'cupertino',
      theme: {
        'motion.page-transition.type': 'fade',
        'motion.page-transition.duration': '120ms',
        'motion.page-transition.curve': 'ease-out',
      },
    );
    final page = await _routeOf(tester, route, '/page', 'page');
    expect(page, isNot(isA<CupertinoRouteTransitionMixin<Object?>>()));
    expect(page.transitionDuration, const Duration(milliseconds: 120));
    expect(
      page.buildTransitions(
        tester.element(find.text('page')),
        kAlwaysCompleteAnimation,
        kAlwaysDismissedAnimation,
        const SizedBox(),
      ),
      isA<FadeTransition>(),
    );
  });

  testWidgets('Cupertino: the iOS slide, with the theme duration', (
    tester,
  ) async {
    final route = await _start(
      tester,
      type: 'cupertino',
      theme: {
        'motion.page-transition.type': 'platform',
        'motion.page-transition.duration': '200ms',
      },
    );
    final page = await _routeOf(tester, route, '/page', 'page');
    expect(page, isA<CupertinoRouteTransitionMixin<Object?>>());
    expect(page.transitionDuration, const Duration(milliseconds: 200));
  });

  testWidgets('widgets: platform is none, the theme fade animates', (
    tester,
  ) async {
    var route = await _start(
      tester,
      type: 'widgets',
      theme: {'motion.page-transition': 'platform'},
    );
    var page = await _routeOf(tester, route, '/page', 'page');
    expect(page.transitionDuration, Duration.zero);

    route = await _start(
      tester,
      type: 'widgets',
      theme: {'motion.page-transition': 'fade'},
    );
    page = await _routeOf(tester, route, '/faded', 'faded');
    expect(page.transitionDuration, const Duration(milliseconds: 250));
  });

  testWidgets("a screen's own transition wins over the theme", (
    tester,
  ) async {
    final route = await _start(
      tester,
      theme: {'motion.page-transition': 'fade'},
    );
    final still = await _routeOf(tester, route, '/still', 'still');
    expect(still.transitionDuration, Duration.zero);
  });

  testWidgets("one navigation's transition wins over the screen's", (
    tester,
  ) async {
    final route = await _start(tester);
    final page = await _routeOf(
      tester,
      route,
      '/faded',
      'faded',
      transition: PageTransition.none,
    );
    expect(page.transitionDuration, Duration.zero);
  });

  testWidgets('reduced motion on the device: at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final route = await _start(
      tester,
      theme: {'motion.page-transition': 'fade'},
    );
    final page = await _routeOf(tester, route, '/page', 'page');
    expect(page.transitionDuration, Duration.zero);
  });

  testWidgets('a screen in a branch outside its path: over its first screen', (
    tester,
  ) async {
    final route = await _start(tester);
    await route.go('/motion');
    await tester.pumpAndSettle();
    expect(find.text('motion'), findsOneWidget);
    expect([for (final s in route.stack) s.uri.path], ['/more', '/motion']);
    expect(route.branch, '/more');
    expect(route.pop(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('more'), findsOneWidget);
  });
}
