// Cupertino's page route for the navigation starter's router: when it is
// the design's, its duration and curve, and the hero flights.
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_cupertino/spring_boot_starter_flutter_cupertino.dart';

// A page of a router, as the navigation starter has them: its route comes
// from the design.
final class DesignedPage extends Page<Object?> {
  const DesignedPage({
    required this.child,
    this.duration,
    this.curve,
    super.key,
    super.name,
  });

  final Widget child;
  final Duration? duration;
  final Curve? curve;

  @override
  Route<Object?> createRoute(BuildContext context) =>
      const CupertinoPageRoutes().pageRoute(
        PageTransitionType.cupertino,
        'widgets',
        SpringPageRequest(
          settings: this,
          child: child,
          duration: duration,
          curve: curve,
        ),
      )!;
}

void main() {
  const routes = CupertinoPageRoutes();
  const page = DesignedPage(name: '/books', child: Text('books'));

  SpringPageRequest request({Duration? duration, Curve? curve}) =>
      SpringPageRequest(
        settings: page,
        child: page.child,
        duration: duration,
        curve: curve,
      );

  group('pageRoute', () {
    test('cupertino in an app of any type', () {
      for (final appType in ['widgets', 'material', 'cupertino', 'ocean']) {
        expect(
          routes.pageRoute(PageTransitionType.cupertino, appType, request()),
          isA<CupertinoRouteTransitionMixin<Object?>>(),
          reason: appType,
        );
      }
    });

    test('platform in an app of type cupertino, whatever the case', () {
      for (final appType in ['cupertino', 'Cupertino', ' CUPERTINO ']) {
        expect(
          routes.pageRoute(PageTransitionType.platform, appType, request()),
          isA<CupertinoRouteTransitionMixin<Object?>>(),
          reason: appType,
        );
      }
      for (final appType in ['widgets', 'material', 'ocean']) {
        expect(
          routes.pageRoute(PageTransitionType.platform, appType, request()),
          isNull,
          reason: appType,
        );
      }
    });

    test('no route for the other transitions', () {
      for (final transition in PageTransitionType.values) {
        if (transition == PageTransitionType.cupertino ||
            transition == PageTransitionType.platform) {
          continue;
        }
        expect(
          routes.pageRoute(transition, 'cupertino', request()),
          isNull,
          reason: transition.name,
        );
      }
    });

    test('the route of the page: its settings, no title, kept in memory', () {
      final route = routes.pageRoute(
        PageTransitionType.cupertino,
        'widgets',
        request(),
      )!;
      expect(route.settings, same(page));
      expect(route.maintainState, isTrue);
      expect(
        (route as CupertinoRouteTransitionMixin<Object?>).title,
        isNull,
      );
      expect(route.debugLabel, endsWith('(/books)'));
    });

    test('the page\'s duration both ways, else iOS\'s own', () {
      final own = routes.pageRoute(
        PageTransitionType.cupertino,
        'widgets',
        request(),
      )!;
      expect(
        own.transitionDuration,
        CupertinoRouteTransitionMixin.kTransitionDuration,
      );
      expect(
        own.reverseTransitionDuration,
        CupertinoRouteTransitionMixin.kTransitionDuration,
      );
      final timed = routes.pageRoute(
        PageTransitionType.cupertino,
        'widgets',
        request(duration: const Duration(milliseconds: 120)),
      )!;
      expect(timed.transitionDuration, const Duration(milliseconds: 120));
      expect(
        timed.reverseTransitionDuration,
        const Duration(milliseconds: 120),
      );
    });
  });

  group('in a navigator', () {
    // The width of the test's screen: where a page that comes in starts.
    const width = 800.0;

    Widget app(List<Page<Object?>> pages) => Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(width, 600)),
        child: Navigator(pages: pages, onDidRemovePage: (_) {}),
      ),
    );

    const first = DesignedPage(key: ValueKey('first'), child: Text('first'));

    // How far the page that comes in is from its place, at a moment of the
    // transition.
    Future<double> offsetAt(
      WidgetTester tester,
      DesignedPage second,
      Duration moment,
    ) async {
      await tester.pumpWidget(app(const [first]));
      await tester.pumpWidget(app([first, second]));
      await tester.pump();
      await tester.pump(moment);
      final left = tester.getTopLeft(find.text('second')).dx;
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('second')).dx, 0);
      await tester.pumpWidget(const SizedBox());
      return left;
    }

    testWidgets('shows the page\'s child with the iOS slide', (tester) async {
      await tester.pumpWidget(app(const [first]));
      expect(find.text('first'), findsOneWidget);
      await tester.pumpWidget(
        app(const [
          first,
          DesignedPage(key: ValueKey('second'), child: Text('second')),
        ]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // On its way in from the right.
      final left = tester.getTopLeft(find.text('second')).dx;
      expect(left, greaterThan(0));
      expect(left, lessThan(width));
      expect(find.byType(CupertinoPageTransition), findsWidgets);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('second')).dx, 0);
    });

    testWidgets('the page\'s duration is the transition\'s', (tester) async {
      await tester.pumpWidget(app(const [first]));
      await tester.pumpWidget(
        app(const [
          first,
          DesignedPage(
            key: ValueKey('second'),
            duration: Duration(milliseconds: 100),
            child: Text('second'),
          ),
        ]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getTopLeft(find.text('second')).dx, greaterThan(0));
      // iOS's own transition is still on its way at this moment.
      await tester.pump(const Duration(milliseconds: 51));
      expect(tester.getTopLeft(find.text('second')).dx, 0);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('the page\'s curve shapes the transition', (tester) async {
      const moment = Duration(milliseconds: 100);
      final plain = await offsetAt(
        tester,
        const DesignedPage(key: ValueKey('second'), child: Text('second')),
        moment,
      );
      // A curve that stays at its start for the first half.
      final late = await offsetAt(
        tester,
        const DesignedPage(
          key: ValueKey('second'),
          curve: Interval(0.5, 1),
          child: Text('second'),
        ),
        moment,
      );
      expect(plain, lessThan(width));
      expect(late, width);
    });
  });

  group('heroController', () {
    test('Cupertino\'s in an app of type cupertino, none in the others', () {
      final hero = routes.heroController('Cupertino');
      expect(hero, isA<HeroController>());
      expect(hero!.createRectTween, isNull); // flights in a straight line
      expect(routes.heroController('cupertino'), isNot(same(hero)));
      expect(routes.heroController('material'), isNull);
      expect(routes.heroController('widgets'), isNull);
    });
  });

  testWidgets('iOS dims the page below; not over a theme background, which '
      'shows through every screen', (tester) async {
    Future<Color?> barrier(Map<String, String> properties) async {
      final theme = SpringThemes(properties).data('light');
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        CupertinoApp(
          navigatorKey: navigator,
          builder: (context, child) => SpringTheme(data: theme, child: child!),
          home: const Text('home'),
        ),
      );
      final route =
          routes.pageRoute(
                PageTransitionType.cupertino,
                'cupertino',
                request(),
              )!
              as ModalRoute<Object?>;
      navigator.currentState!.push<Object?>(route).ignore();
      await tester.pumpAndSettle();
      return route.barrierColor;
    }

    expect(await barrier(const {}), const Color(0x18000000));
    expect(await barrier(const {'background.color': '#FF102030'}), isNull);
  });
}
