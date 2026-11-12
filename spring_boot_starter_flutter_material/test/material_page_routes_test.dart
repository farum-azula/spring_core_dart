// Material's page route and hero flights for the navigation starter's
// router: only for `platform` in an app of type `material`, with the
// page's duration and curve over the route's own.
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_material/spring_boot_starter_flutter_material.dart';

import 'support/themes.dart';

// Keeps the animations Material's route hands to the theme's transition,
// by route.
class _Recording extends PageTransitionsBuilder {
  final animations = <Route<Object?>, List<Animation<double>>>{};

  @override
  Duration get transitionDuration => const Duration(milliseconds: 280);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 180);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    animations[route] = [animation, secondaryAnimation];
    return child;
  }
}

// A page of a router, which makes its route of Material's.
class _BookPage extends Page<Object?> {
  const _BookPage(this.child)
    : super(key: const ValueKey('book'), name: '/book');

  final Widget child;

  @override
  Route<Object?> createRoute(BuildContext context) =>
      const MaterialPageRoutes().pageRoute(
        PageTransitionType.platform,
        'material',
        SpringPageRequest(
          settings: this,
          child: child,
          content: (settings) => (settings as _BookPage).child,
        ),
      )!;
}

SpringPageRequest page({Duration? duration, Curve? curve}) => SpringPageRequest(
  settings: const RouteSettings(name: '/books', arguments: 7),
  child: const Text('books'),
  duration: duration,
  curve: curve,
);

void main() {
  const routes = MaterialPageRoutes();

  test('a route for platform in an app of type material only', () {
    expect(
      routes.pageRoute(PageTransitionType.platform, 'material', page()),
      isNotNull,
    );
    expect(
      routes.pageRoute(PageTransitionType.platform, ' Material ', page()),
      isNotNull,
    );
    for (final type in ['widgets', 'cupertino', 'ocean', '']) {
      expect(
        routes.pageRoute(PageTransitionType.platform, type, page()),
        isNull,
        reason: type,
      );
    }
    for (final transition in PageTransitionType.values) {
      if (transition != PageTransitionType.platform) {
        expect(
          routes.pageRoute(transition, 'material', page()),
          isNull,
          reason: transition.name,
        );
      }
    }
  });

  test('the route: the page\'s settings, kept in memory, named', () {
    final request = page();
    final route = routes.pageRoute(
      PageTransitionType.platform,
      'material',
      request,
    )!;
    expect(route.settings, same(request.settings));
    expect(route.maintainState, isTrue);
    expect(route.debugLabel, endsWith('(/books)'));
    expect(route, isA<MaterialRouteTransitionMixin<Object?>>());
  });

  test('the page\'s duration replaces the route\'s, both ways', () {
    PageRoute<Object?> route(Duration duration) => routes.pageRoute(
      PageTransitionType.platform,
      'material',
      page(duration: duration),
    )!;
    const quick = Duration(milliseconds: 120);
    expect(route(quick).transitionDuration, quick);
    expect(route(quick).reverseTransitionDuration, quick);
    expect(route(Duration.zero).transitionDuration, Duration.zero);
    expect(route(Duration.zero).reverseTransitionDuration, Duration.zero);
  });

  testWidgets('the page shows with the theme\'s transition, along the '
      'page\'s curve when it has one', (tester) async {
    final recording = _Recording();
    final navigator = GlobalKey<NavigatorState>();
    NavigatorState state() => navigator.currentState!;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: ThemeData(
          pageTransitionsTheme: PageTransitionsTheme(
            builders: {
              for (final platform in TargetPlatform.values) platform: recording,
            },
          ),
        ),
        home: const Text('home'),
      ),
    );

    final plain = routes.pageRoute(
      PageTransitionType.platform,
      'material',
      page(),
    )!;
    unawaited(state().push<Object?>(plain));
    await tester.pumpAndSettle();
    expect(find.text('books'), findsOneWidget);
    // Without a duration of its own: those of the theme's transition.
    expect(plain.transitionDuration, recording.transitionDuration);
    expect(
      plain.reverseTransitionDuration,
      recording.reverseTransitionDuration,
    );
    expect(recording.animations[plain], hasLength(2));
    expect(
      recording.animations[plain],
      everyElement(isNot(isA<CurvedAnimation>())),
    );

    final curved = routes.pageRoute(
      PageTransitionType.platform,
      'material',
      page(curve: Curves.easeOutCubic, duration: Duration.zero),
    )!;
    unawaited(state().push<Object?>(curved));
    await tester.pumpAndSettle();
    expect(
      recording.animations[curved],
      everyElement(
        isA<CurvedAnimation>().having(
          (animation) => animation.curve,
          'curve',
          Curves.easeOutCubic,
        ),
      ),
    );
  });

  for (final (motion, label) in [
    (const <String, String>{}, 'sets no page transition (none)'),
    (const {'motion.page-transition': 'fade-upwards'}, 'sets fade-upwards'),
  ]) {
    testWidgets('a page that asks for platform gets the platform\'s own '
        'transition when the theme $label', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: themes(motion).data('light').toMaterial(),
          home: const Text('home'),
        ),
      );
      final route = routes.pageRoute(
        PageTransitionType.platform,
        'material',
        page(),
      )!;
      unawaited(navigator.currentState!.push<Object?>(route));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // macOS: Flutter's own there (Cupertino's slide), with its duration.
      expect(
        route.transitionDuration,
        const PageTransitionsTheme()
            .builders[TargetPlatform.macOS]!
            .transitionDuration,
      );
      final slides = tester
          .widgetList<SlideTransition>(find.byType(SlideTransition))
          .where((slide) => slide.position.value != Offset.zero);
      expect(slides, isNotEmpty, reason: 'the page is sliding in');
      await tester.pumpAndSettle();
      expect(find.text('books'), findsOneWidget);
    });
  }

  testWidgets('a page replaced in place shows its new child, in the same '
      'route', (tester) async {
    Widget app(Widget child) => MaterialApp(
      home: Navigator(
        pages: [_BookPage(child)],
        onDidRemovePage: (_) {},
      ),
    );
    await tester.pumpWidget(app(const Text('first edition')));
    await tester.pumpAndSettle();
    expect(find.text('first edition'), findsOneWidget);
    final route = ModalRoute.of(tester.element(find.text('first edition')));

    await tester.pumpWidget(app(const Text('second edition')));
    await tester.pumpAndSettle();
    expect(find.text('first edition'), findsNothing);
    expect(find.text('second edition'), findsOneWidget);
    expect(
      ModalRoute.of(tester.element(find.text('second edition'))),
      same(route),
    );
  });

  test('hero flights: Material\'s controller in an app of type material', () {
    final controller = routes.heroController('material');
    addTearDown(() => controller?.dispose());
    expect(controller, isA<HeroController>());
    final upper = routes.heroController('MATERIAL');
    addTearDown(() => upper?.dispose());
    expect(upper, isNotNull);
    expect(routes.heroController('widgets'), isNull);
    expect(routes.heroController('cupertino'), isNull);
  });
}

void unawaited(Future<Object?> future) {}
