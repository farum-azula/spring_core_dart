// The page transitions: the theme's `motion.page-transition` (a kind, or a
// kind with its duration and curve) for every app type, a screen's own
// (`transition:`), one navigation's (`go(path, transition: ...)`), reduced
// motion; and a screen in a branch its path is not under (`branch:`).
//
// The router knows no design library: Material's and Cupertino's routes
// and hero flights come from the design starters' beans, so each app here
// says which starters it has. Without them `platform` has no transition,
// and `zoom` and `cupertino` name the starter to add.
import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoRouteTransitionMixin;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

import 'support/design_starters.dart';

class _Page extends StatelessWidget {
  const _Page(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(child: Text(text));
}

// A dot that flies from one screen of a branch to the next.
class _HeroPage extends StatelessWidget {
  const _HeroPage(this.alignment);

  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
    child: const Hero(tag: 'dot', child: _Dot()),
  );
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => const SizedBox.square(dimension: 40);
}

ScreenRoutes _routes() => ScreenRoutes.route()
    .shell(
      (shell) => shell.child,
      (tabs) => tabs
          .branch(
            '/home',
            (b) => b
                .screen('/home', (r) => const _Page('home'))
                .screen(
                  '/home/small',
                  (r) => const _HeroPage(Alignment.topLeft),
                )
                .screen(
                  '/home/small/large',
                  (r) => const _HeroPage(Alignment.bottomRight),
                ),
          )
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
    .screen(
      '/numbered',
      (r) => _Page('number ${r.param<int>('n')}'),
      params: {'n': int},
    )
    .redirect('/', '/home')
    .build();

/// Starts a new app of [type] with [starters] (those its type needs when
/// not given) and the theme properties [theme]; with [app], the app widget
/// is that one, written by hand on the application's router, instead of
/// the one of the app's type.
Future<RouteTemplate> _start(
  WidgetTester tester, {
  String type = 'material',
  Map<String, String> theme = const {},
  DesignStarters? starters,
  Widget Function(SpringRouterConfig router)? app,
}) async {
  final design = starters ?? DesignStarters.of(type);
  await tester.pumpWidget(
    SpringApplicationWidget(
      // A new application each time: the widget starts one per state.
      key: UniqueKey(),
      child: app == null
          ? null
          : Builder(
              builder: (context) =>
                  app(SpringScope.of(context).getBean<SpringRouterConfig>()),
            ),
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
          ...design.autoConfigurations,
        ],
        autoConfigurationMetadata: design.metadata,
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

/// The errors reported while `/page` opens with [transition], which needs
/// a design starter the app does not have; checks that the page is shown
/// all the same, at once, and that the app navigates on after it.
Future<List<FlutterErrorDetails>> _reported(
  WidgetTester tester,
  RouteTemplate route,
  PageTransition transition,
) async {
  final reported = <FlutterErrorDetails>[];
  final onError = FlutterError.onError;
  FlutterError.onError = reported.add;
  try {
    // push completes when the screen is closed: not awaited.
    unawaited(route.push<void>('/page', transition: transition));
    await tester.pumpAndSettle();
  } finally {
    FlutterError.onError = onError;
  }
  final page =
      ModalRoute.of(tester.element(find.text('page')))! as PageRoute<Object?>;
  expect(page.settings.name, '/page', reason: transition.name);
  expect(page.transitionDuration, Duration.zero, reason: transition.name);
  expect(page.reverseTransitionDuration, Duration.zero);
  // The tree is still whole: back, and on to another screen.
  expect(route.pop(), isTrue);
  await tester.pumpAndSettle();
  expect(find.text('page'), findsNothing);
  final faded = await _routeOf(tester, route, '/faded', 'faded');
  expect(faded.transitionDuration, const Duration(milliseconds: 250));
  expect(route.pop(), isTrue);
  await tester.pumpAndSettle();
  expect(find.text('faded'), findsNothing);
  return reported;
}

/// The error reported for page transition [transition] without [starter].
Matcher _needs(PageTransition transition, String starter) =>
    isA<FlutterErrorDetails>()
        .having(
          (details) => details.library,
          'library',
          'spring_boot_starter_flutter_navigation',
        )
        .having(
          (details) => details.exception,
          'exception',
          isA<FlutterError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains(
                'The page transition ${transition.name} needs $starter.',
              ),
              contains('add $starter to the dependencies'),
              contains('platform, fadeUpwards, fade, content or none'),
            ),
          ),
        );

/// What the transition of [route] wraps a page in, shown in full.
Widget _transition(
  WidgetTester tester,
  PageRoute<Object?> route,
  String text,
) => route.buildTransitions(
  tester.element(find.text(text)),
  kAlwaysCompleteAnimation,
  kAlwaysDismissedAnimation,
  const SizedBox(),
);

/// The hero controllers of the shell's branch navigators, those of the
/// branches not shown too (the root navigator's, when the app gives one,
/// is above them).
List<HeroController> _shellHeroes(WidgetTester tester) => [
  for (final scope in tester.widgetList<HeroControllerScope>(
    find.descendant(
      of: find.byType(IndexedStack),
      matching: find.byType(HeroControllerScope, skipOffstage: false),
      skipOffstage: false,
    ),
  ))
    // A navigator gives the routes below it none: those are not a shell's.
    ?scope.controller,
];

const _from = Rect.fromLTWH(0, 0, 10, 10);
const _to = Rect.fromLTWH(200, 300, 10, 10);

void main() {
  testWidgets('by default the platform\'s, as in Flutter: Material\'s, '
      'Cupertino\'s, none without a design library', (tester) async {
    final material = await _routeOf(
      tester,
      await _start(tester, type: 'material'),
      '/page',
      'page',
    );
    expect(material, isA<MaterialRouteTransitionMixin<Object?>>());
    expect(material.transitionDuration, greaterThan(Duration.zero));

    final cupertino = await _routeOf(
      tester,
      await _start(tester, type: 'cupertino'),
      '/page',
      'page',
    );
    expect(cupertino, isA<CupertinoRouteTransitionMixin<Object?>>());
    expect(cupertino.transitionDuration, greaterThan(Duration.zero));

    // A WidgetsApp has no transition of its own platform.
    final widgets = await _routeOf(
      tester,
      await _start(tester, type: 'widgets'),
      '/page',
      'page',
    );
    expect(widgets.transitionDuration, Duration.zero);
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
    expect(_transition(tester, page, 'page'), isA<FadeTransition>());
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
    page = await _routeOf(tester, route, '/page', 'page');
    expect(page.transitionDuration, const Duration(milliseconds: 250));
    expect(_transition(tester, page, 'page'), isA<FadeTransition>());
  });

  testWidgets('without a design library: platform has no transition, as a '
      "screen's own and as one navigation's too", (tester) async {
    final route = await _start(tester, type: 'widgets');
    final page = await _routeOf(
      tester,
      route,
      '/page',
      'page',
      transition: PageTransition.platform,
    );
    expect(page.transitionDuration, Duration.zero);
    expect(page.reverseTransitionDuration, Duration.zero);
    expect(page, isNot(isA<MaterialRouteTransitionMixin<Object?>>()));
    expect(page, isNot(isA<CupertinoRouteTransitionMixin<Object?>>()));
    const child = SizedBox();
    expect(
      page.buildTransitions(
        tester.element(find.text('page')),
        kAlwaysCompleteAnimation,
        kAlwaysDismissedAnimation,
        child,
      ),
      same(child),
    );
  });

  testWidgets('widgets with both starters: platform is still none', (
    tester,
  ) async {
    final route = await _start(
      tester,
      type: 'widgets',
      starters: DesignStarters.both,
      theme: {'motion.page-transition': 'platform'},
    );
    final page = await _routeOf(tester, route, '/page', 'page');
    expect(page.transitionDuration, Duration.zero);
    expect(page, isNot(isA<MaterialRouteTransitionMixin<Object?>>()));
    expect(page, isNot(isA<CupertinoRouteTransitionMixin<Object?>>()));
  });

  testWidgets('without a design library: zoom and cupertino are reported, '
      'naming their starter, and the page shows at once', (tester) async {
    final route = await _start(tester, type: 'widgets');
    for (final (transition, starter) in [
      (PageTransition.zoom, 'spring_boot_starter_flutter_material'),
      (PageTransition.cupertino, 'spring_boot_starter_flutter_cupertino'),
    ]) {
      expect(await _reported(tester, route, transition), [
        _needs(transition, starter),
      ], reason: transition.name);
    }
    // With both starters there the same pages have their routes.
    final designed = await _start(
      tester,
      type: 'widgets',
      starters: DesignStarters.both,
    );
    final zoom = await _routeOf(
      tester,
      designed,
      '/page',
      'page',
      transition: PageTransition.zoom,
    );
    expect(zoom.transitionDuration, const Duration(milliseconds: 300));
    expect(designed.pop(), isTrue);
    await tester.pumpAndSettle();
    final slide = await _routeOf(
      tester,
      designed,
      '/page',
      'page',
      transition: PageTransition.cupertino,
    );
    expect(slide, isA<CupertinoRouteTransitionMixin<Object?>>());
  });

  testWidgets("Material's starter alone: cupertino is reported, naming "
      "Cupertino's", (tester) async {
    final route = await _start(tester);
    final zoom = await _routeOf(
      tester,
      route,
      '/page',
      'page',
      transition: PageTransition.zoom,
    );
    expect(zoom.transitionDuration, const Duration(milliseconds: 300));
    expect(route.pop(), isTrue);
    await tester.pumpAndSettle();
    expect(await _reported(tester, route, PageTransition.cupertino), [
      _needs(PageTransition.cupertino, 'spring_boot_starter_flutter_cupertino'),
    ]);
  });

  testWidgets("Cupertino's starter alone: zoom is reported, naming "
      "Material's", (tester) async {
    final route = await _start(tester, type: 'cupertino');
    final slide = await _routeOf(
      tester,
      route,
      '/page',
      'page',
      transition: PageTransition.cupertino,
    );
    expect(slide, isA<CupertinoRouteTransitionMixin<Object?>>());
    expect(route.pop(), isTrue);
    await tester.pumpAndSettle();
    expect(await _reported(tester, route, PageTransition.zoom), [
      _needs(PageTransition.zoom, 'spring_boot_starter_flutter_material'),
    ]);
  });

  testWidgets("an app widget of the app's own, no SpringTheme above the "
      "router: zoom from the themes' designs", (tester) async {
    Widget app(SpringRouterConfig router) => WidgetsApp.router(
      routerConfig: router,
      color: const Color(0xFF000000),
    );
    // Material's starter in the application: its zoom.
    var route = await _start(
      tester,
      type: 'widgets',
      starters: DesignStarters.onlyMaterial,
      app: app,
    );
    final page = await _routeOf(
      tester,
      route,
      '/page',
      'page',
      transition: PageTransition.zoom,
    );
    expect(SpringTheme.maybeOf(tester.element(find.text('page'))), isNull);
    expect(page.transitionDuration, const Duration(milliseconds: 300));
    expect(
      _transition(tester, page, 'page').runtimeType,
      const ZoomPageTransitionsBuilder()
          .buildTransitions(
            page,
            tester.element(find.text('page')),
            kAlwaysCompleteAnimation,
            kAlwaysDismissedAnimation,
            const SizedBox(),
          )
          .runtimeType,
    );
    // Without it: reported, and the page shows at once.
    route = await _start(
      tester,
      type: 'widgets',
      starters: DesignStarters.none,
      app: app,
    );
    expect(await _reported(tester, route, PageTransition.zoom), [
      _needs(PageTransition.zoom, 'spring_boot_starter_flutter_material'),
    ]);
  });

  testWidgets("with Material's starter: zoom is Material's, in any app "
      'type', (tester) async {
    for (final type in ['material', 'widgets']) {
      final route = await _start(
        tester,
        type: type,
        starters: DesignStarters.onlyMaterial,
      );
      final page = await _routeOf(
        tester,
        route,
        '/page',
        'page',
        transition: PageTransition.zoom,
      );
      expect(
        page.transitionDuration,
        const Duration(milliseconds: 300),
        reason: type,
      );
      final context = tester.element(find.text('page'));
      expect(
        _transition(tester, page, 'page').runtimeType,
        const ZoomPageTransitionsBuilder()
            .buildTransitions(
              page,
              context,
              kAlwaysCompleteAnimation,
              kAlwaysDismissedAnimation,
              const SizedBox(),
            )
            .runtimeType,
        reason: type,
      );
    }
  });

  testWidgets('the theme: zoom in a Material app, with its duration', (
    tester,
  ) async {
    final route = await _start(
      tester,
      theme: {
        'motion.page-transition.type': 'zoom',
        'motion.page-transition.duration': '150ms',
      },
    );
    final page = await _routeOf(tester, route, '/page', 'page');
    expect(page.transitionDuration, const Duration(milliseconds: 150));
    expect(page, isNot(isA<MaterialRouteTransitionMixin<Object?>>()));
  });

  testWidgets("with Cupertino's starter: cupertino is the iOS slide, in any "
      'app type', (tester) async {
    for (final type in ['material', 'widgets', 'cupertino']) {
      final route = await _start(
        tester,
        type: type,
        starters: type == 'material'
            ? DesignStarters.both
            : DesignStarters.onlyCupertino,
      );
      final page = await _routeOf(
        tester,
        route,
        '/page',
        'page',
        transition: PageTransition.cupertino,
      );
      expect(
        page,
        isA<CupertinoRouteTransitionMixin<Object?>>(),
        reason: type,
      );
      expect(page.transitionDuration, greaterThan(Duration.zero), reason: type);
    }
  });

  testWidgets('with both starters: platform is the route of the app type', (
    tester,
  ) async {
    var route = await _start(tester, starters: DesignStarters.both);
    var page = await _routeOf(
      tester,
      route,
      '/page',
      'page',
      transition: PageTransition.platform,
    );
    expect(page, isA<MaterialRouteTransitionMixin<Object?>>());
    expect(page, isNot(isA<CupertinoRouteTransitionMixin<Object?>>()));

    route = await _start(
      tester,
      type: 'cupertino',
      starters: DesignStarters.both,
    );
    page = await _routeOf(
      tester,
      route,
      '/page',
      'page',
      transition: PageTransition.platform,
    );
    expect(page, isA<CupertinoRouteTransitionMixin<Object?>>());
    expect(page, isNot(isA<MaterialRouteTransitionMixin<Object?>>()));
  });

  testWidgets("Material's route: the theme duration and curve", (
    tester,
  ) async {
    final route = await _start(
      tester,
      theme: {
        'motion.page-transition.type': 'platform',
        'motion.page-transition.duration': '180ms',
      },
    );
    final page = await _routeOf(tester, route, '/page', 'page');
    expect(page, isA<MaterialRouteTransitionMixin<Object?>>());
    expect(page.transitionDuration, const Duration(milliseconds: 180));
    expect(page.reverseTransitionDuration, const Duration(milliseconds: 180));
  });

  // The router gives a route a new page (its settings) on every change of
  // the navigation: the route shows that page's child, and has its name.
  for (final (label, type, transition) in [
    ("Material's route", 'material', PageTransition.platform),
    ("Cupertino's route", 'cupertino', PageTransition.platform),
    ('a plain route', 'widgets', PageTransition.fade),
  ]) {
    testWidgets('a page replaced in place shows its new child: $label', (
      tester,
    ) async {
      final route = await _start(tester, type: type);
      unawaited(
        route.push<void>(
          '/numbered',
          params: {'n': 1},
          transition: transition,
        ),
      );
      await tester.pumpAndSettle();
      final page = ModalRoute.of(tester.element(find.text('number 1')))!;
      final first = page.settings;
      expect(first.name, '/numbered?n=1');
      // The page's widget, as the router made it.
      Widget childOf(RouteSettings settings) =>
          (settings as dynamic).child as Widget;
      expect(find.byWidget(childOf(first)), findsOneWidget);

      route.replaceParams({'n': 2});
      await tester.pumpAndSettle();
      expect(find.text('number 2'), findsOneWidget);
      expect(find.text('number 1'), findsNothing);
      // The same route, with the new page.
      expect(ModalRoute.of(tester.element(find.text('number 2'))), same(page));
      expect(page.settings, isNot(same(first)));
      expect(page.settings.name, '/numbered?n=2');
      expect(find.byWidget(childOf(page.settings)), findsOneWidget);
      expect(find.byWidget(childOf(first)), findsNothing);
    });
  }

  testWidgets("a shell's heroes: Material's arc in a Material app", (
    tester,
  ) async {
    final route = await _start(tester);
    expect(find.text('home'), findsOneWidget);
    var heroes = _shellHeroes(tester);
    expect(heroes, hasLength(1));
    expect(
      heroes.single.createRectTween!(_from, _to),
      isA<MaterialRectArcTween>(),
    );

    // A controller per branch, kept while the shell is.
    await route.go('/more');
    await tester.pumpAndSettle();
    heroes = _shellHeroes(tester);
    expect(heroes, hasLength(2));
    expect(heroes[1], isNot(same(heroes[0])));
    expect(heroes[1].createRectTween!(_from, _to), isA<MaterialRectArcTween>());
    await route.go('/home');
    await tester.pumpAndSettle();
    expect(_shellHeroes(tester), [same(heroes[0]), same(heroes[1])]);
  });

  testWidgets("a shell's heroes: straight in a Cupertino app and without a "
      'design library', (tester) async {
    for (final (type, starters) in [
      ('cupertino', DesignStarters.onlyCupertino),
      ('cupertino', DesignStarters.both),
      ('widgets', DesignStarters.none),
      ('widgets', DesignStarters.both),
    ]) {
      await _start(tester, type: type, starters: starters);
      expect(find.text('home'), findsOneWidget, reason: type);
      final heroes = _shellHeroes(tester);
      expect(heroes, hasLength(1), reason: type);
      // No tween of its own: Flutter's straight line.
      expect(heroes.single.createRectTween, isNull, reason: type);
    }
  });

  testWidgets('a hero of a shell flies straight without a design library, '
      "along Material's arc in a Material app", (tester) async {
    // How far the hero is from the straight line between its two places,
    // in the middle of the flight.
    Future<double> offLine(String type) async {
      final route = await _start(tester, type: type);
      await route.go('/home/small');
      await tester.pumpAndSettle();
      final from = tester.getCenter(find.byType(_Dot));
      unawaited(route.go('/home/small/large', transition: PageTransition.fade));
      await tester.pump();
      // Half of the fade's 250 ms.
      await tester.pump(const Duration(milliseconds: 125));
      final middle = tester.getCenter(find.byType(_Dot));
      await tester.pumpAndSettle();
      final to = tester.getCenter(find.byType(_Dot));
      expect(to, isNot(from), reason: type);
      expect(middle, isNot(from), reason: type);
      expect(middle, isNot(to), reason: type);
      final line = to - from;
      final flown = middle - from;
      return (line.dx * flown.dy - line.dy * flown.dx).abs() / line.distance;
    }

    expect(await offLine('widgets'), lessThan(0.5));
    expect(await offLine('cupertino'), lessThan(0.5));
    expect(await offLine('material'), greaterThan(20));
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
