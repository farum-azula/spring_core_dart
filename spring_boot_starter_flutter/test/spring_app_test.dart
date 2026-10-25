// SpringApp: the app widget built from `spring.flutter.app.*` and the
// theme beans, put at the root by `SpringApplicationWidget(home: ...)`.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

class Page extends StatelessWidget {
  const Page({super.key});

  @override
  Widget build(BuildContext context) => const Text('page');
}

class Observer extends NavigatorObserver {}

class AddDelegate implements FlutterAppCustomizer {
  @override
  void customize(FlutterAppSettings app) {
    app.title = 'customized';
  }
}

SpringApplication application({
  List<BeanDefinition<Object>> beans = const [],
  Map<String, String> properties = const {},
  Map<String, String> files = const {},
  bool autoConfiguration = false,
}) => SpringApplication(
  [
    BeanModule(
      'test',
      beans,
      resources: {
        if (properties.isNotEmpty)
          'application.properties': EmbeddedResource.text(
            [
              for (final MapEntry(:key, :value) in properties.entries)
                '$key=$value',
            ].join('\n'),
          ),
        for (final MapEntry(:key, :value) in files.entries)
          key: EmbeddedResource.text(value),
      },
    ),
  ],
  autoConfigurations: [
    if (autoConfiguration) springBootStarterFlutterAutoConfiguration,
  ],
  bannerMode: BannerMode.off,
);

Future<void> pump(WidgetTester tester, SpringApplication Function() app) async {
  await tester.pumpWidget(
    SpringApplicationWidget(application: app, home: const Page()),
  );
  await tester.pumpAndSettle();
}

FlutterAppSettings settings(WidgetTester tester) =>
    FlutterAppSettings.of(SpringScope.of(tester.element(find.byType(Page))));

void main() {
  testWidgets('a WidgetsApp with Flutter defaults by default', (tester) async {
    await pump(tester, application);
    expect(find.text('page'), findsOneWidget);
    expect(find.byType(WidgetsApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsNothing);
    expect(find.byType(CupertinoApp), findsNothing);
    expect(find.byType(CheckedModeBanner), findsOneWidget);
    expect(settings(tester).supportedLocales, [const Locale('en')]);
  });

  testWidgets('properties: type, title, debug banner, theme, locales', (
    tester,
  ) async {
    await pump(
      tester,
      () => application(
        properties: {
          'spring.flutter.app.type': 'material',
          'spring.flutter.app.title': 'Counter',
          'spring.flutter.app.debug-banner': 'false',
          'spring.flutter.theme.active': 'dark',
          'spring.flutter.app.locales': 'en, pt_BR, zh_Hant_TW',
        },
      ),
    );
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'Counter');
    expect(app.debugShowCheckedModeBanner, isFalse);
    expect(app.theme!.brightness, Brightness.dark);
    expect(app.themeMode, ThemeMode.light); // one theme picked, not system
    expect(app.supportedLocales, [
      const Locale('en'),
      const Locale('pt', 'BR'),
      const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
        countryCode: 'TW',
      ),
    ]);
    expect(
      app.localizationsDelegates,
      containsAll(GlobalMaterialLocalizations.delegates),
    );
    expect(find.byType(CheckedModeBanner), findsNothing);
  });

  testWidgets('the locales of the messages files by default', (tester) async {
    await pump(
      tester,
      () => application(
        files: {
          'messages.properties': 'a=A',
          'messages_ja.properties': 'a=エー',
          'messages_pt_BR.properties': 'a=Á',
          'other_de.properties': 'a=Ä',
        },
      ),
    );
    expect(settings(tester).supportedLocales, [
      const Locale('en'),
      const Locale('ja'),
      const Locale('pt', 'BR'),
    ]);
  });

  testWidgets('the ThemeData beans theme and darkTheme', (tester) async {
    final light = ThemeData(colorSchemeSeed: Colors.teal);
    final dark = ThemeData(
      colorSchemeSeed: Colors.teal,
      brightness: Brightness.dark,
    );
    await pump(
      tester,
      () => application(
        properties: {'spring.flutter.app.type': 'material'},
        autoConfiguration: true,
        beans: [
          BeanDefinition<ThemeData>(
            name: 'theme',
            types: const [ThemeData],
            create: (_) => light,
          ),
          BeanDefinition<ThemeData>(
            name: 'darkTheme',
            types: const [ThemeData],
            create: (_) => dark,
          ),
        ],
      ),
    );
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme, same(light));
    expect(app.darkTheme, same(dark));
    // Made once per context: the same settings on every build.
    expect(settings(tester), same(settings(tester)));
  });

  testWidgets('cupertino: the CupertinoThemeData bean', (tester) async {
    const theme = CupertinoThemeData(primaryColor: Color(0xFF0057B8));
    await pump(
      tester,
      () => application(
        properties: {'spring.flutter.app.type': 'cupertino'},
        autoConfiguration: true,
        beans: [
          BeanDefinition<CupertinoThemeData>(
            name: 'cupertinoTheme',
            types: const [CupertinoThemeData],
            create: (_) => theme,
          ),
        ],
      ),
    );
    expect(tester.widget<CupertinoApp>(find.byType(CupertinoApp)).theme, theme);
    expect(find.text('page'), findsOneWidget);
  });

  testWidgets('NavigatorObserver beans and customizers', (tester) async {
    final observer = Observer();
    await pump(
      tester,
      () => application(
        properties: {'spring.flutter.app.title': 'from properties'},
        beans: [
          BeanDefinition<Observer>(
            name: 'observer',
            types: const [Observer, NavigatorObserver],
            create: (_) => observer,
          ),
          BeanDefinition<AddDelegate>(
            name: 'customizer',
            types: const [AddDelegate, FlutterAppCustomizer],
            create: (_) => AddDelegate(),
          ),
        ],
      ),
    );
    final app = tester.widget<WidgetsApp>(find.byType(WidgetsApp));
    expect(app.navigatorObservers, [observer]);
    expect(app.title, 'customized');
  });

  testWidgets('locales: script tags, messages in a directory', (tester) async {
    await pump(
      tester,
      () => application(
        properties: {
          'spring.messages.basename': 'i18n/texts, other',
          'spring.flutter.app.title': 'x',
        },
        files: {
          'i18n/texts.properties': 'a=A',
          'i18n/texts_zh_Hant.properties': 'a=A',
          'other_de-AT.properties': 'a=A',
          'messages_ja.properties': 'a=A', // not a basename here
        },
      ),
    );
    expect(settings(tester).supportedLocales, [
      const Locale('en'),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      const Locale('de', 'AT'),
    ]);
  });

  testWidgets('an invalid boolean fails the start', (tester) async {
    await pump(
      tester,
      () =>
          application(properties: {'spring.flutter.app.debug-banner': 'maybe'}),
    );
    expect(
      find.textContaining('spring.flutter.app.debug-banner'),
      findsOneWidget,
    );
    expect(find.textContaining('true or false'), findsOneWidget);
  });

  test('settings made by hand: Flutter\'s defaults', () {
    final app = FlutterAppSettings();
    expect(app.type, AppType.widgets);
    expect(app.debugShowCheckedModeBanner, isTrue);
    expect(app.supportedLocales, [const Locale('en')]);
    expect(app.localizationsDelegates, isEmpty);
    expect(app.navigatorObservers, isEmpty);
  });

  testWidgets('removed before the start ends: the context is closed', (
    tester,
  ) async {
    ConfigurableApplicationContext? started;
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => application(
          beans: [
            BeanDefinition<_Probe>(
              name: 'probe',
              types: const [_Probe],
              create: (r) => _Probe((context) => started = context),
            ),
          ],
        ),
        home: const Page(),
      ),
    );
    await tester.pumpWidget(const SizedBox()); // before the start finished
    await tester.pumpAndSettle();
    expect(started, isNotNull);
    expect(started!.isActive, isFalse);
  });

  testWidgets('an invalid value fails the start with the key', (tester) async {
    await pump(
      tester,
      () => application(properties: {'spring.flutter.app.type': 'swing'}),
    );
    expect(find.textContaining('spring.flutter.app.type'), findsOneWidget);
    expect(find.textContaining('widgets, material, cupertino'), findsOneWidget);
    expect(find.text('page'), findsNothing);
  });
}

/// Remembers the context it runs in.
class _Probe implements ApplicationContextAware {
  _Probe(this.onContext);
  final void Function(ConfigurableApplicationContext context) onContext;

  @override
  void setApplicationContext(ApplicationContext context) =>
      onContext(context as ConfigurableApplicationContext);
}
