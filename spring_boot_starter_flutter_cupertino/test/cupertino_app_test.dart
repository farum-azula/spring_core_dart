// The app widget of spring.flutter.app.type=cupertino: a CupertinoApp
// built by SpringApp from the properties, with the theme picked as a
// CupertinoThemeData and a DesignScope above its pages.
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_cupertino/spring_boot_starter_flutter_cupertino.dart';

import 'support/application.dart';

class Page extends StatelessWidget {
  const Page({super.key});

  @override
  Widget build(BuildContext context) => Text(SpringTheme.of(context).name);
}

class Observer extends NavigatorObserver {}

// A router of one page.
final class OnePage extends RouterDelegate<Object>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Object> {
  @override
  final navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => Navigator(
    key: navigatorKey,
    pages: const [CupertinoPage<void>(child: Page())],
    onDidRemovePage: (_) {},
  );

  @override
  Future<void> setNewRoutePath(Object configuration) async {}
}

Future<ApplicationContext> pump(
  WidgetTester tester,
  SpringApplication Function() app, {
  Widget? home = const Page(),
}) async {
  await tester.pumpWidget(
    SpringApplicationWidget(application: app, home: home),
  );
  await tester.pumpAndSettle();
  return SpringScope.of(tester.element(find.byType(Page)));
}

CupertinoApp shown(WidgetTester tester) =>
    tester.widget<CupertinoApp>(find.byType(CupertinoApp));

void main() {
  const factory = CupertinoAppFactory();

  test('the type and Flutter\'s Cupertino localizations', () {
    expect(factory.type, 'cupertino');
    expect(CupertinoAppFactory.typeName, 'cupertino');
    expect(
      factory.localizationsDelegates,
      GlobalCupertinoLocalizations.delegates,
    );
  });

  testWidgets('properties: type, title, debug banner, theme, locales', (
    tester,
  ) async {
    final observer = Observer();
    final context = await pump(
      tester,
      () => application(
        properties: {
          'spring.flutter.app.type': 'cupertino',
          'spring.flutter.app.title': 'Counter',
          'spring.flutter.app.debug-banner': 'false',
          'spring.flutter.theme.active': 'dark',
          'spring.flutter.theme.seed-color': 'teal',
          'spring.flutter.app.locales': 'en, pt_BR',
        },
        beans: [
          BeanDefinition<NavigatorObserver>(
            name: 'observer',
            types: const [NavigatorObserver],
            create: (_) => observer,
          ),
        ],
      ),
    );
    final app = shown(tester);
    final theme = SpringThemes.of(context).data('dark');
    expect(find.byType(CupertinoApp), findsOneWidget);
    expect(find.text('dark'), findsOneWidget);
    expect(app.title, 'Counter');
    expect(app.debugShowCheckedModeBanner, isFalse);
    expect(find.byType(CheckedModeBanner), findsNothing);
    expect(app.theme, same(CupertinoThemes.of(context).theme('dark')));
    expect(app.theme!.brightness, Brightness.dark);
    expect(app.theme!.primaryColor, theme.colorScheme.primary);
    expect(app.color, theme.appColor);
    expect(app.supportedLocales, [
      const Locale('en'),
      const Locale('pt', 'BR'),
    ]);
    expect(
      app.localizationsDelegates,
      containsAll(GlobalCupertinoLocalizations.delegates),
    );
    expect(app.navigatorObservers, [observer]);
    expect(app.home, isA<Page>());
    expect(
      CupertinoTheme.of(tester.element(find.byType(Page))).primaryColor,
      theme.colorScheme.primary,
    );
  });

  testWidgets('the picked theme\'s CupertinoThemeData', (tester) async {
    final context = await pump(
      tester,
      () => application(
        properties: const {
          'spring.flutter.app.type': 'cupertino',
          'spring.flutter.theme.active': 'ocean',
          'spring.flutter.theme.themes.ocean.cupertino.primary-color':
              '#00ACC1',
        },
      ),
    );
    expect(shown(tester).theme!.primaryColor, const Color(0xFF00ACC1));
    ThemeSelection.of(context).select('light');
    await tester.pumpAndSettle();
    expect(shown(tester).theme!.primaryColor, CupertinoColors.systemBlue);
    expect(find.text('light'), findsOneWidget);
  });

  testWidgets('themes loaded at run time show at once', (tester) async {
    final context = await pump(
      tester,
      () => application(
        properties: const {
          'spring.flutter.app.type': 'cupertino',
          'spring.flutter.theme.cupertino.primary-color': '#00ACC1',
        },
      ),
    );
    expect(shown(tester).theme!.primaryColor, const Color(0xFF00ACC1));
    SpringThemes.of(context).load(const {'cupertino.primary-color': '#FF9500'});
    await tester.pumpAndSettle();
    expect(shown(tester).theme!.primaryColor, const Color(0xFFFF9500));
  });

  testWidgets('the CupertinoThemeData bean', (tester) async {
    const theme = CupertinoThemeData(primaryColor: Color(0xFF0057B8));
    await pump(
      tester,
      () => application(
        properties: {'spring.flutter.app.type': 'cupertino'},
        beans: [
          BeanDefinition<CupertinoThemeData>(
            name: 'cupertinoTheme',
            types: const [CupertinoThemeData],
            create: (_) => theme,
          ),
        ],
      ),
    );
    expect(shown(tester).theme, theme);
    expect(find.text('light'), findsOneWidget);
  });

  testWidgets('a CupertinoThemeCustomizer bean changes the theme shown', (
    tester,
  ) async {
    await pump(
      tester,
      () => application(
        properties: {'spring.flutter.app.type': 'cupertino'},
        beans: [
          BeanDefinition<CupertinoThemeCustomizer>(
            name: 'pink',
            types: const [CupertinoThemeCustomizer],
            create: (_) => _Pink(),
          ),
        ],
      ),
    );
    expect(shown(tester).theme!.primaryColor, CupertinoColors.systemPink);
  });

  testWidgets('on the application\'s router without a home', (tester) async {
    final delegate = OnePage();
    final router = RouterConfig<Object>(routerDelegate: delegate);
    await pump(
      tester,
      () => application(
        properties: {
          'spring.flutter.app.type': 'cupertino',
          'spring.flutter.app.title': 'Routed',
          'spring.flutter.theme.cupertino.primary-color': '#00ACC1',
        },
        beans: [
          BeanDefinition<RouterConfig<Object>>(
            name: 'router',
            types: const [RouterConfig<Object>],
            create: (_) => router,
          ),
        ],
      ),
      home: null,
    );
    final app = shown(tester);
    expect(app.routerConfig, same(router));
    expect(app.title, 'Routed');
    expect(app.theme!.primaryColor, const Color(0xFF00ACC1));
    expect(find.text('light'), findsOneWidget);
    expect(DesignScope.maybeOf(tester.element(find.byType(Page))), isNotNull);
  });

  testWidgets('a factory bean in a context without the auto-configuration', (
    tester,
  ) async {
    await pump(
      tester,
      () => application(
        autoConfiguration: false,
        properties: {'spring.flutter.app.type': 'Cupertino'},
        beans: [
          BeanDefinition<SpringAppFactory>(
            name: 'cupertinoAppFactory',
            types: const [SpringAppFactory],
            create: (_) => const CupertinoAppFactory(),
          ),
        ],
      ),
    );
    expect(shown(tester).theme!.primaryColor, CupertinoColors.systemBlue);
    expect(find.text('light'), findsOneWidget);
  });

  group('the DesignScope above the pages', () {
    Future<(BuildContext, DesignScope)> scope(WidgetTester tester) async {
      await pump(
        tester,
        () => application(
          properties: {'spring.flutter.app.type': 'cupertino'},
        ),
      );
      final context = tester.element(find.byType(Page));
      return (context, DesignScope.maybeOf(context)!);
    }

    testWidgets('no text styles of its own, Cupertino\'s controls', (
      tester,
    ) async {
      final (context, design) = await scope(tester);
      expect(design.textStyle(context, 'titlelarge'), isNull);
      expect(design.controls, isA<CupertinoDesignControls>());
      // The same scope on every build: its dependents do not rebuild.
      await tester.pump();
      final again = DesignScope.maybeOf(tester.element(find.byType(Page)))!;
      expect(again.updateShouldNotify(design), isFalse);
    });

    for (final (platform, controls) in [
      (TargetPlatform.iOS, () => cupertinoTextSelectionHandleControls),
      (
        TargetPlatform.macOS,
        () => cupertinoDesktopTextSelectionHandleControls,
      ),
      for (final other in [
        TargetPlatform.android,
        TargetPlatform.fuchsia,
        TargetPlatform.linux,
        TargetPlatform.windows,
      ])
        (other, () => SpringTextSelectionControls.instance),
    ]) {
      testWidgets('selectable text on ${platform.name}', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final (context, design) = await scope(tester);
          final selectable = design.selectable(context, const Text('text'));
          expect(
            selectable,
            isA<SelectableRegion>()
                .having(
                  (region) => region.selectionControls,
                  'selectionControls',
                  same(controls()),
                )
                .having((region) => region.child, 'child', isA<Text>()),
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets('a MarkdownView is selectable the design\'s way', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await tester.pumpWidget(
          SpringApplicationWidget(
            application: () => application(
              properties: {'spring.flutter.app.type': 'cupertino'},
            ),
            home: const CupertinoPageScaffold(
              child: MarkdownView('# Title\n\nSome text.'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SelectableRegion>(find.byType(SelectableRegion))
              .selectionControls,
          same(cupertinoTextSelectionHandleControls),
        );
        expect(find.text('Title', findRichText: true), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}

final class _Pink implements CupertinoThemeCustomizer {
  @override
  CupertinoThemeData customize(
    CupertinoThemeData theme,
    SpringThemeData spring,
  ) => theme.copyWith(primaryColor: CupertinoColors.systemPink);
}
