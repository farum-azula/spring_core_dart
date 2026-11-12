// The MaterialApp that SpringApp builds for spring.flutter.app.type:
// material: the settings of spring.flutter.app.*, the themes (the picked
// one, the device's light and dark, the ThemeData beans, themes loaded at
// run time) and the DesignScope the starter's own widgets read.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_material/spring_boot_starter_flutter_material.dart';

import 'support/application.dart';

class Page extends StatelessWidget {
  const Page({super.key});

  @override
  Widget build(BuildContext context) => Text(SpringTheme.of(context).name);
}

// The choice of a theme is not kept: a test has no files.
const _material = {
  'spring.flutter.app.type': 'material',
  'spring.flutter.theme.remember': 'false',
};

Future<ApplicationContext> pump(
  WidgetTester tester, {
  Map<String, String> properties = const {},
  List<BeanDefinition<Object>> beans = const [],
  Widget home = const Page(),
}) async {
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () =>
          application(properties: {..._material, ...properties}, beans: beans),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
  return SpringScope.of(tester.element(find.byType(MaterialApp)));
}

MaterialApp app(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp));

void main() {
  test('the factory: its type and Material\'s localizations', () {
    const factory = MaterialAppFactory();
    expect(factory.type, 'material');
    expect(MaterialAppFactory.typeName, 'material');
    expect(
      factory.localizationsDelegates,
      GlobalMaterialLocalizations.delegates,
    );
  });

  testWidgets('properties: type, title, debug banner, theme, locales', (
    tester,
  ) async {
    await pump(
      tester,
      properties: {
        'spring.flutter.app.title': 'Counter',
        'spring.flutter.app.debug-banner': 'false',
        'spring.flutter.theme.active': 'dark',
        'spring.flutter.app.locales': 'en, pt_BR, zh_Hant_TW',
      },
    );
    final material = app(tester);
    expect(material.title, 'Counter');
    expect(material.debugShowCheckedModeBanner, isFalse);
    expect(material.theme!.brightness, Brightness.dark);
    expect(material.darkTheme, isNull);
    expect(material.themeMode, ThemeMode.light); // one theme picked
    expect(material.supportedLocales, [
      const Locale('en'),
      const Locale('pt', 'BR'),
      const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
        countryCode: 'TW',
      ),
    ]);
    expect(
      material.localizationsDelegates,
      containsAll(GlobalMaterialLocalizations.delegates),
    );
    expect(find.byType(CheckedModeBanner), findsNothing);
    expect(find.byType(WidgetsApp), findsOneWidget); // MaterialApp's own
  });

  testWidgets('the active theme, switched at run time', (tester) async {
    final context = await pump(
      tester,
      properties: {
        'spring.flutter.theme.active': 'ocean',
        'spring.flutter.theme.themes.ocean.seed-color': 'teal',
      },
      home: Builder(
        builder: (context) => Text(
          '${SpringTheme.of(context).name} '
          '${Theme.of(context).colorScheme.primary.toARGB32()}',
        ),
      ),
    );
    final teal = ColorScheme.fromSeed(
      seedColor: Colors.teal,
    ).primary.toARGB32();
    expect(find.text('ocean $teal'), findsOneWidget);
    expect(
      app(tester).color,
      ColorScheme.fromSeed(seedColor: Colors.teal).primary,
    );

    ThemeSelection.of(context).select('light');
    await tester.pumpAndSettle();
    final purple = ThemeData().colorScheme.primary.toARGB32();
    expect(find.text('light $purple'), findsOneWidget);
  });

  testWidgets('system: follows the device\'s light and dark mode', (
    tester,
  ) async {
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await pump(
      tester,
      properties: {
        'spring.flutter.theme.system-dark': 'night',
        'spring.flutter.theme.themes.night.brightness': 'dark',
        'spring.flutter.theme.themes.night.seed-color': 'indigo',
      },
    );
    expect(find.text('light'), findsOneWidget);
    final material = app(tester);
    expect(material.themeMode, ThemeMode.system);
    expect(material.theme!.colorScheme, ThemeData().colorScheme);
    expect(
      material.darkTheme!.colorScheme,
      ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: Brightness.dark,
      ),
    );
    expect(
      Theme.of(tester.element(find.byType(Page))).brightness,
      Brightness.light,
    );

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(find.text('night'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(Page))).colorScheme.primary,
      material.darkTheme!.colorScheme.primary,
    );
  });

  testWidgets('a theme loaded at run time shows at once', (tester) async {
    final context = await pump(tester);
    SpringThemes.of(
      context,
    ).loadYaml('themes: {winter: {seed-color: lightBlue}}');
    ThemeSelection.of(context).select('winter');
    await tester.pumpAndSettle();
    expect(find.text('winter'), findsOneWidget);
    final theme = Theme.of(tester.element(find.text('winter')));
    expect(
      theme.colorScheme.primary,
      ColorScheme.fromSeed(seedColor: Colors.lightBlue).primary,
    );
    expect(
      app(tester).theme,
      same(MaterialThemes.of(context).theme('winter')),
    );
  });

  testWidgets('the ThemeData beans theme and darkTheme', (tester) async {
    final light = ThemeData(colorSchemeSeed: Colors.teal);
    final dark = ThemeData(
      colorSchemeSeed: Colors.teal,
      brightness: Brightness.dark,
    );
    await pump(
      tester,
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
    );
    expect(app(tester).theme, same(light));
    expect(app(tester).darkTheme, same(dark));
  });

  testWidgets('a ThemeCustomizer bean changes the themes shown', (
    tester,
  ) async {
    await pump(
      tester,
      beans: [
        BeanDefinition<_Compact>(
          name: 'compact',
          types: const [_Compact, ThemeCustomizer],
          create: (_) => _Compact(),
        ),
      ],
    );
    expect(app(tester).theme!.visualDensity, VisualDensity.compact);
    expect(app(tester).darkTheme!.visualDensity, VisualDensity.compact);
  });

  testWidgets('without a home: MaterialApp.router on the router bean', (
    tester,
  ) async {
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => application(
          properties: {..._material, 'spring.flutter.app.title': 'Routed'},
          beans: [
            BeanDefinition<RouterConfig<Object>>(
              name: 'router',
              types: const [RouterConfig<Object>],
              create: (_) => RouterConfig<Object>(routerDelegate: _Delegate()),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('routed'), findsOneWidget);
    final material = app(tester);
    expect(material.routerConfig, isNotNull);
    expect(material.title, 'Routed');
    expect(material.themeMode, ThemeMode.system);
    expect(material.darkTheme!.brightness, Brightness.dark);
    expect(
      DesignScope.maybeOf(tester.element(find.text('routed'))),
      isNotNull,
    );
  });

  testWidgets('motion.overscroll: none turns the stretch off', (tester) async {
    bool overscroll(WidgetTester tester) {
      final context = tester.element(find.byType(Page));
      return ScrollConfiguration.of(context).buildOverscrollIndicator(
        context,
        const SizedBox(),
        const ScrollableDetails.vertical(),
      ) is! SizedBox;
    }

    await pump(tester);
    expect(overscroll(tester), isTrue); // Android in tests: the stretch
    await tester.pumpWidget(const SizedBox());
    await pump(
      tester,
      properties: {'spring.flutter.theme.motion.overscroll': 'none'},
    );
    expect(overscroll(tester), isFalse);
  });

  group('the DesignScope', () {
    testWidgets('text styles are those of Theme.of, by name', (tester) async {
      await pump(
        tester,
        properties: {'spring.flutter.theme.typography.title-large.size': '23'},
      );
      final context = tester.element(find.byType(Page));
      final design = DesignScope.maybeOf(context)!;
      final text = Theme.of(context).textTheme;
      expect(design.textStyle(context, 'titlelarge'), text.titleLarge);
      expect(design.textStyle(context, 'titlelarge')!.fontSize, 23);
      expect(design.textStyle(context, 'bodymedium'), text.bodyMedium);
      // The sizes of the type scale, which the SpringTheme's own lack.
      expect(design.textStyle(context, 'bodymedium')!.fontSize, 14);
      expect(design.textStyle(context, 'code'), isNull);
      expect(design.textStyle(context, 'huge'), isNull);
    });

    testWidgets('selectable text is Material\'s SelectionArea', (tester) async {
      await pump(tester);
      final context = tester.element(find.byType(Page));
      final design = DesignScope.maybeOf(context)!;
      const child = Text('text');
      expect(
        design.selectable(context, child),
        isA<SelectionArea>().having((area) => area.child, 'child', child),
      );
      expect(design.controls, isA<MaterialDesignControls>());
    });

    testWidgets('it stays the same over rebuilds, around the app\'s builder', (
      tester,
    ) async {
      final context = await pump(
        tester,
        beans: [
          BeanDefinition<_Framed>(
            name: 'framed',
            types: const [_Framed, FlutterAppCustomizer],
            create: (_) => _Framed(),
          ),
        ],
      );
      final before = tester.widget<DesignScope>(find.byType(DesignScope));
      expect(
        find.descendant(
          of: find.byType(DesignScope),
          matching: find.byKey(_Framed.key),
        ),
        findsOneWidget,
      );
      ThemeSelection.of(context).select('dark');
      await tester.pumpAndSettle();
      final after = tester.widget<DesignScope>(find.byType(DesignScope));
      expect(after.updateShouldNotify(before), isFalse);
    });

    testWidgets('a MarkdownView below reads Material\'s theme', (tester) async {
      await pump(
        tester,
        properties: {'spring.flutter.theme.typography.body-large.size': '19'},
        home: const SingleChildScrollView(
          child: MarkdownView('Some text'),
        ),
      );
      expect(find.byType(SelectionArea), findsOneWidget);
      final text = tester.widget<RichText>(
        find.descendant(
          of: find.byType(MarkdownView),
          matching: find.byType(RichText),
        ),
      );
      expect(text.text.style!.fontSize, 19);
    });
  });
}

class _Delegate extends RouterDelegate<Object> with ChangeNotifier {
  @override
  Widget build(BuildContext context) => const Text('routed');

  @override
  Future<bool> popRoute() async => false;

  @override
  Future<void> setNewRoutePath(Object configuration) async {}
}

final class _Compact implements ThemeCustomizer {
  @override
  ThemeData customize(ThemeData theme, SpringThemeData spring) =>
      theme.copyWith(visualDensity: VisualDensity.compact);
}

final class _Framed implements FlutterAppCustomizer {
  static const key = Key('frame');

  @override
  void customize(FlutterAppSettings app) {
    app.builder = (context, child) => KeyedSubtree(key: key, child: child!);
  }
}
