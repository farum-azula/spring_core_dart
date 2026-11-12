// SpringAppFactory: the bean that builds the app widget of one
// spring.flutter.app.type. The starter's own builds a WidgetsApp for
// `widgets`; a type without a factory fails the start, naming the property
// and, for material and cupertino, the starter to add; a factory bean of
// the application's own type builds the app from what SpringApp gives it.
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

class Page extends StatelessWidget {
  const Page({super.key});

  @override
  Widget build(BuildContext context) =>
      Text('page in ${SpringTheme.of(context).name}');
}

// The app widget of the test's design: a plain box around the page, with
// the app's builder applied as an app widget does.
class OceanApp extends StatelessWidget {
  const OceanApp({required this.app, super.key});

  final SpringAppRequest app;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Localizations(
      locale: const Locale('en'),
      delegates: app.settings.localizationsDelegates,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: Builder(
          builder: (context) => app.builder(
            context,
            app.home ?? Text('router: ${app.router != null}'),
          ),
        ),
      ),
    ),
  );
}

final class OceanAppFactory implements SpringAppFactory {
  OceanAppFactory([this.type = 'ocean']);

  @override
  final String type;

  /// What SpringApp asked for, at every build.
  final requests = <SpringAppRequest>[];

  @override
  List<LocalizationsDelegate<Object?>> get localizationsDelegates => const [
    DefaultWidgetsLocalizations.delegate,
  ];

  @override
  Widget build(BuildContext context, SpringAppRequest app) {
    requests.add(app);
    return OceanApp(app: app);
  }
}

class Shout implements FlutterAppCustomizer {
  @override
  void customize(FlutterAppSettings app) {
    app.builder = (context, child) =>
        KeyedSubtree(key: const ValueKey('customized'), child: child!);
  }
}

class _Router extends RouterConfig<Object> {
  _Router() : super(routerDelegate: _Delegate());
}

class _Delegate extends RouterDelegate<Object> with ChangeNotifier {
  @override
  Widget build(BuildContext context) => const Text('routed');

  @override
  Future<bool> popRoute() async => false;

  @override
  Future<void> setNewRoutePath(Object configuration) async {}
}

BeanDefinition<Object> _factory(OceanAppFactory factory, [String? name]) =>
    BeanDefinition<OceanAppFactory>(
      name: name ?? '${factory.type}AppFactory',
      types: const [OceanAppFactory, SpringAppFactory],
      create: (_) => factory,
    );

SpringApplication application({
  Map<String, String> properties = const {},
  List<BeanDefinition<Object>> beans = const [],
  bool autoConfiguration = true,
}) => SpringApplication(
  [
    BeanModule(
      'test',
      beans,
      resources: {
        'application.properties': EmbeddedResource.text(
          [
            // A widget test has no directories to keep the theme chosen in.
            'spring.flutter.theme.remember=false',
            'logging.level.root=WARN',
            for (final MapEntry(:key, :value) in properties.entries)
              '$key=$value',
          ].join('\n'),
        ),
      },
    ),
  ],
  autoConfigurations: [
    if (autoConfiguration) springBootStarterFlutterAutoConfiguration,
  ],
  bannerMode: BannerMode.off,
);

Future<void> pump(
  WidgetTester tester,
  SpringApplication Function() app, {
  Widget? home = const Page(),
}) async {
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: app,
      failure: (_, error) =>
          Text('failed: $error', textDirection: TextDirection.ltr),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

ApplicationContext contextOf(WidgetTester tester, Finder finder) =>
    SpringScope.of(tester.element(finder), listen: false);

Matcher _noSuchType(String type, String message) => throwsA(
  isA<ArgumentError>()
      .having((e) => e.name, 'name', 'spring.flutter.app.type')
      .having((e) => e.invalidValue, 'value', type)
      .having((e) => e.message, 'message', message),
);

void main() {
  group('WidgetsAppFactory', () {
    test('the type widgets, the widgets library\'s localizations', () {
      const factory = WidgetsAppFactory();
      expect(factory.type, 'widgets');
      expect(WidgetsAppFactory.typeName, 'widgets');
      expect(factory.localizationsDelegates, [
        GlobalWidgetsLocalizations.delegate,
      ]);
    });

    testWidgets('a WidgetsApp of the request: settings, theme, builder, '
        'home', (tester) async {
      final themes = SpringThemes(const {
        'colors.primary': '#112233',
        'typography.font-family': 'Inter',
      });
      final observer = NavigatorObserver();
      final settings = FlutterAppSettings(
        title: 'Shop',
        debugShowCheckedModeBanner: false,
        supportedLocales: const [Locale('en'), Locale('ja')],
        localizationsDelegates: const [GlobalWidgetsLocalizations.delegate],
        navigatorObservers: [observer],
        locale: const Locale('ja'),
      )..shortcuts = const {};
      Widget builder(BuildContext context, Widget? child) =>
          KeyedSubtree(key: const ValueKey('built'), child: child!);
      await tester.pumpWidget(
        Builder(
          builder: (context) => const WidgetsAppFactory().build(
            context,
            SpringAppRequest(
              settings: settings,
              themes: themes,
              selection: ThemeSelection(themes),
              shown: themes.data('light'),
              builder: builder,
              home: const Text('home'),
            ),
          ),
        ),
      );
      final app = tester.widget<WidgetsApp>(find.byType(WidgetsApp));
      expect(app.title, 'Shop');
      expect(app.debugShowCheckedModeBanner, isFalse);
      expect(app.color, const Color(0xFF112233));
      expect(app.textStyle!.fontFamily, 'Inter');
      expect(app.textStyle!.color, const Color(0xFF1D1B20));
      expect(app.locale, const Locale('ja'));
      expect(app.supportedLocales, const [Locale('en'), Locale('ja')]);
      expect(app.localizationsDelegates, [GlobalWidgetsLocalizations.delegate]);
      expect(app.navigatorObservers, [observer]);
      expect(app.shortcuts, isEmpty);
      expect(app.builder, same(builder));
      expect(app.routerConfig, isNull);
      // The home is a page of the app's navigator, inside the builder.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('built')),
          matching: find.text('home'),
        ),
        findsOneWidget,
      );
      expect(observer.navigator, isNotNull);
      expect(
        Localizations.localeOf(tester.element(find.text('home'))),
        const Locale('ja'),
      );
    });

    testWidgets('without a home: on the router of the request', (
      tester,
    ) async {
      final themes = SpringThemes(const {});
      final router = _Router();
      await tester.pumpWidget(
        Builder(
          builder: (context) => const WidgetsAppFactory().build(
            context,
            SpringAppRequest(
              settings: FlutterAppSettings(
                title: 'Routed',
                localizationsDelegates: const [
                  GlobalWidgetsLocalizations.delegate,
                ],
              ),
              themes: themes,
              selection: ThemeSelection(themes),
              shown: themes.data('dark'),
              builder: (context, child) => child!,
              router: router,
            ),
          ),
        ),
      );
      final app = tester.widget<WidgetsApp>(find.byType(WidgetsApp));
      expect(app.routerConfig, same(router));
      expect(app.title, 'Routed');
      expect(app.color, SpringColorScheme.baseline(Brightness.dark).primary);
      expect(find.text('routed'), findsOneWidget);
    });
  });

  group('SpringAppFactories', () {
    test('by type, without case or the spaces around', () {
      final ocean = OceanAppFactory();
      const widgets = WidgetsAppFactory();
      final factories = SpringAppFactories([ocean, widgets]);
      expect(factories.all, [ocean, widgets]);
      expect(factories.named('ocean'), same(ocean));
      expect(factories.named(' Ocean '), same(ocean));
      expect(factories.named('WIDGETS'), same(widgets));
    });

    test('the first of a type wins', () {
      final first = OceanAppFactory();
      final second = OceanAppFactory('Ocean');
      expect(SpringAppFactories([first, second]).named('ocean'), same(first));
      expect(SpringAppFactories([second, first]).named('ocean'), same(second));
    });

    test('the type not set: the one type besides widgets, else widgets, '
        'as Spring Boot deduces the web application type', () {
      const widgets = WidgetsAppFactory();
      final ocean = OceanAppFactory();
      expect(
        const SpringAppFactories([widgets]).resolve(null),
        same(widgets),
      );
      expect(SpringAppFactories([ocean, widgets]).resolve(null), same(ocean));
      expect(SpringAppFactories([ocean, widgets]).resolve('  '), same(ocean));
      // Two factories of one type are one type.
      expect(
        SpringAppFactories([ocean, OceanAppFactory('OCEAN'), widgets])
            .resolve(null),
        same(ocean),
      );
      // Set, it is as named: widgets though a design is there.
      expect(
        SpringAppFactories([ocean, widgets]).resolve('widgets'),
        same(widgets),
      );
      expect(
        () => SpringAppFactories([ocean, widgets]).resolve('swing'),
        _noSuchType('swing', 'one of: ocean, widgets'),
      );
    });

    test('the type not set with factories of several types: the start '
        'fails, naming the property and the types', () {
      expect(
        () => SpringAppFactories([
          OceanAppFactory(),
          OceanAppFactory('sand'),
          const WidgetsAppFactory(),
        ]).resolve(null),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.name, 'name', 'spring.flutter.app.type')
              .having(
                (e) => '${e.message}',
                'message',
                allOf(
                  contains('not set'),
                  contains('ocean, sand'),
                  contains('application-ios.properties'),
                ),
              ),
        ),
      );
    });

    test('a type no factory has names the property and the types there '
        'are', () {
      const none = SpringAppFactories([WidgetsAppFactory()]);
      expect(
        () => none.named('swing'),
        _noSuchType('swing', 'one of: widgets'),
      );
      expect(() => none.named(''), _noSuchType('', 'one of: widgets'));
      expect(
        () => SpringAppFactories([
          OceanAppFactory(),
          const WidgetsAppFactory(),
          OceanAppFactory(),
        ]).named('swing'),
        _noSuchType('swing', 'one of: ocean, widgets'),
      );
    });

    test('material and cupertino without their starter name it', () {
      const none = SpringAppFactories([WidgetsAppFactory()]);
      expect(
        () => none.named('material'),
        _noSuchType(
          'material',
          'the app widget of type material is built by '
              'spring_boot_starter_flutter_material: add it to the '
              'dependencies (this application has: widgets)',
        ),
      );
      expect(
        () => none.named(' Cupertino '),
        _noSuchType(
          ' Cupertino ',
          'the app widget of type cupertino is built by '
              'spring_boot_starter_flutter_cupertino: add it to the '
              'dependencies (this application has: widgets)',
        ),
      );
      // A factory of the type: the design starter's, or the app's own.
      final own = OceanAppFactory('material');
      expect(
        SpringAppFactories([own, const WidgetsAppFactory()]).named('Material'),
        same(own),
      );
    });

    test('of a context: its beans in order, then the starter\'s own for '
        'widgets', () async {
      final ocean = OceanAppFactory();
      final mine = OceanAppFactory('Widgets');
      for (final autoConfiguration in [true, false]) {
        final context = await application(
          autoConfiguration: autoConfiguration,
          beans: [_factory(ocean)],
        ).runAsync(const []);
        addTearDown(context.close);
        final factories = SpringAppFactories.of(context);
        expect(factories.named('ocean'), same(ocean));
        expect(factories.named('widgets'), isA<WidgetsAppFactory>());
        expect(factories.all.first, same(ocean));
        expect(factories.all.last, isA<WidgetsAppFactory>());
      }
      // A bean of the application for widgets is asked before the
      // starter's.
      final context = await application(
        beans: [_factory(mine, 'myWidgets')],
      ).runAsync(const []);
      addTearDown(context.close);
      expect(SpringAppFactories.of(context).named('widgets'), same(mine));
    });
  });

  group('the start', () {
    testWidgets('widgets by default: a WidgetsApp, no DesignScope', (
      tester,
    ) async {
      await pump(tester, application);
      expect(find.text('page in light'), findsOneWidget);
      expect(find.byType(WidgetsApp), findsOneWidget);
      expect(find.byType(DesignScope), findsNothing);
      final settings = FlutterAppSettings.of(
        contextOf(tester, find.byType(Page)),
      );
      expect(settings.type, 'widgets');
      expect(settings.localizationsDelegates, [
        GlobalWidgetsLocalizations.delegate,
      ]);
    });

    for (final (type, starter) in [
      ('material', 'spring_boot_starter_flutter_material'),
      ('cupertino', 'spring_boot_starter_flutter_cupertino'),
    ]) {
      testWidgets('$type without its starter fails, naming the property '
          'and the starter', (tester) async {
        await pump(
          tester,
          () => application(properties: {'spring.flutter.app.type': type}),
        );
        expect(find.byType(Page), findsNothing);
        expect(find.byType(WidgetsApp), findsNothing);
        final failure = tester.widget<Text>(find.textContaining('failed:'));
        expect(
          failure.data,
          allOf(
            contains('spring.flutter.app.type'),
            contains(
              'the app widget of type $type is built by $starter: add it '
              'to the dependencies (this application has: widgets)',
            ),
          ),
        );
      });
    }

    testWidgets('an unknown type fails, naming the property and the types '
        'of the application', (tester) async {
      await pump(
        tester,
        () => application(
          properties: {'spring.flutter.app.type': 'swing'},
          beans: [_factory(OceanAppFactory())],
        ),
      );
      expect(find.byType(Page), findsNothing);
      final failure = tester.widget<Text>(find.textContaining('failed:'));
      expect(
        failure.data,
        allOf(
          contains('spring.flutter.app.type'),
          contains('one of: ocean, widgets'),
          contains('swing'),
        ),
      );
    });
  });

  group('a factory bean of the application\'s own type', () {
    testWidgets('the type not set: the one factory of the application '
        'builds the app', (tester) async {
      final ocean = OceanAppFactory();
      await pump(tester, () => application(beans: [_factory(ocean)]));
      expect(find.byType(OceanApp), findsOneWidget);
      expect(find.byType(WidgetsApp), findsNothing);
      final settings = FlutterAppSettings.of(
        contextOf(tester, find.byType(OceanApp)),
      );
      expect(settings.type, 'ocean');
    });

    testWidgets('widgets set: a WidgetsApp though the factory is there', (
      tester,
    ) async {
      await pump(
        tester,
        () => application(
          properties: {'spring.flutter.app.type': 'widgets'},
          beans: [_factory(OceanAppFactory())],
        ),
      );
      expect(find.byType(OceanApp), findsNothing);
      expect(find.byType(WidgetsApp), findsOneWidget);
    });

    testWidgets('the type not set with two factories: the start fails', (
      tester,
    ) async {
      await pump(
        tester,
        () => application(
          beans: [
            _factory(OceanAppFactory()),
            _factory(OceanAppFactory('sand')),
          ],
        ),
      );
      expect(find.textContaining('spring.flutter.app.type'), findsOneWidget);
      expect(find.textContaining('ocean, sand'), findsOneWidget);
      expect(find.text('page in light'), findsNothing);
    });

    testWidgets('builds the app, from the settings, the themes and the '
        'builder of SpringApp', (tester) async {
      final ocean = OceanAppFactory();
      await pump(
        tester,
        () => application(
          properties: {
            'spring.flutter.app.type': 'OCEAN',
            'spring.flutter.app.title': 'Shop',
            'spring.flutter.app.debug-banner': 'false',
            'spring.flutter.app.locales': 'en,ja',
            'spring.flutter.theme.active': 'night',
            'spring.flutter.theme.themes.night.brightness': 'dark',
            'spring.flutter.theme.themes.night.colors.primary': '#112233',
            'spring.flutter.theme.themes.night.background.color': '#000011',
          },
          beans: [
            _factory(ocean),
            BeanDefinition<Shout>(
              name: 'shout',
              types: const [Shout, FlutterAppCustomizer],
              create: (_) => Shout(),
            ),
          ],
        ),
      );
      expect(find.byType(OceanApp), findsOneWidget);
      expect(find.byType(WidgetsApp), findsNothing);
      expect(find.text('page in night'), findsOneWidget);

      final context = contextOf(tester, find.byType(Page));
      final request = ocean.requests.last;
      // The settings of spring.flutter.app.*, with the factory's type and
      // its localization delegates first.
      expect(request.settings, same(FlutterAppSettings.of(context)));
      expect(request.settings.type, 'ocean');
      expect(request.settings.title, 'Shop');
      expect(request.settings.debugShowCheckedModeBanner, isFalse);
      expect(request.settings.supportedLocales, const [
        Locale('en'),
        Locale('ja'),
      ]);
      expect(request.settings.localizationsDelegates, [
        DefaultWidgetsLocalizations.delegate,
      ]);
      // The themes and the choice are the application's beans.
      expect(request.themes, same(context.getBean<SpringThemes>()));
      expect(request.selection, same(context.getBean<ThemeSelection>()));
      expect(request.shown, same(request.themes.data('night')));
      expect(request.shown.colorScheme.primary, const Color(0xFF112233));
      expect(request.home, isA<Page>());
      expect(request.router, isNull);

      // The builder puts the theme's background around the page, inside
      // the customizers' own builder; the theme shown is above the app.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('customized')),
          matching: find.byType(ThemeBackground),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ThemeBackground),
          matching: find.byType(Page),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == const Color(0xFF000011),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<SpringTheme>(
              find.ancestor(
                of: find.byType(OceanApp),
                matching: find.byType(SpringTheme),
              ),
            )
            .data,
        same(request.shown),
      );
    });

    testWidgets('is asked again with the theme shown when it changes', (
      tester,
    ) async {
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      final ocean = OceanAppFactory();
      await pump(
        tester,
        () => application(
          properties: {
            'spring.flutter.app.type': 'ocean',
            'spring.flutter.theme.themes.sea.colors.primary': '#0000AA',
          },
          beans: [_factory(ocean)],
        ),
      );
      expect(find.text('page in light'), findsOneWidget);
      expect(ocean.requests.last.shown.name, 'light');
      expect(ocean.requests.last.selection.followsSystem, isTrue);

      // The device goes dark: the theme of system-dark.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(find.text('page in dark'), findsOneWidget);
      expect(ocean.requests.last.shown.name, 'dark');

      // A theme picked.
      final context = contextOf(tester, find.byType(Page));
      context.getBean<ThemeSelection>().select('sea');
      await tester.pumpAndSettle();
      expect(find.text('page in sea'), findsOneWidget);
      expect(ocean.requests.last.shown.name, 'sea');
      expect(
        ocean.requests.last.shown.colorScheme.primary,
        const Color(0xFF0000AA),
      );

      // Themes loaded at run time.
      context.getBean<SpringThemes>().load(const {
        'themes.sea.colors.primary': '#00AA00',
      });
      await tester.pumpAndSettle();
      expect(
        ocean.requests.last.shown.colorScheme.primary,
        const Color(0xFF00AA00),
      );
      // The same settings at every build.
      expect(
        {for (final request in ocean.requests) request.settings},
        hasLength(1),
      );
    });

    testWidgets('without a home: the router bean of the application', (
      tester,
    ) async {
      final ocean = OceanAppFactory();
      final router = _Router();
      await pump(
        tester,
        () => application(
          properties: {'spring.flutter.app.type': 'ocean'},
          beans: [
            _factory(ocean),
            BeanDefinition<RouterConfig<Object>>(
              name: 'router',
              types: const [RouterConfig<Object>],
              create: (_) => router,
            ),
          ],
        ),
        home: null,
      );
      expect(find.text('router: true'), findsOneWidget);
      expect(ocean.requests.last.router, same(router));
      expect(ocean.requests.last.home, isNull);
    });

    testWidgets('without a home and a router the start says what to add', (
      tester,
    ) async {
      final ocean = OceanAppFactory();
      await pump(
        tester,
        () => application(
          properties: {'spring.flutter.app.type': 'ocean'},
          beans: [_factory(ocean)],
        ),
        home: null,
      );
      // Checked at the start, before the factory is asked for an app.
      expect(ocean.requests, isEmpty);
      expect(
        tester.widget<Text>(find.textContaining('failed:')).data,
        allOf(
          contains('SpringApp has no home and the application no router'),
          contains('spring_boot_starter_flutter_navigation'),
        ),
      );
    });
  });
}
