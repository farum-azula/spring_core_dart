// SpringThemes, ThemeSelection, SpringTheme and SpringApp beyond the
// basics: bean overrides, customizers, property sources and their
// precedence, run-time loading, the device's light / dark mode, every
// app type with a picked theme.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

final class Rounded implements ThemeCustomizer {
  Rounded(this.log);
  final List<String> log;

  @override
  ThemeData customize(ThemeData theme, SpringThemeData spring) {
    log.add('rounded ${spring.name}');
    return theme.copyWith(
      chipTheme: const ChipThemeData(shape: StadiumBorder()),
    );
  }
}

final class Dense implements ThemeCustomizer {
  Dense(this.log);
  final List<String> log;

  @override
  ThemeData customize(ThemeData theme, SpringThemeData spring) {
    log.add('dense ${spring.name}');
    return theme.copyWith(visualDensity: VisualDensity.compact);
  }
}

final class Blue implements CupertinoThemeCustomizer {
  @override
  CupertinoThemeData customize(
    CupertinoThemeData theme,
    SpringThemeData spring,
  ) => theme.copyWith(primaryColor: CupertinoColors.activeBlue);
}

SpringApplication application({
  Map<String, String> properties = const {},
  Map<String, String> files = const {},
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

void main() {
  group('SpringThemes', () {
    test('customizers in order on every Material theme, once each', () {
      final log = <String>[];
      final themes = SpringThemes(
        const {'themes.ocean.seed-color': 'teal'},
        customizers: [Rounded(log), Dense(log)],
        cupertinoCustomizers: [Blue()],
      );
      final ocean = themes.material('ocean');
      expect(ocean.chipTheme.shape, const StadiumBorder());
      expect(ocean.visualDensity, VisualDensity.compact);
      themes.material('ocean');
      expect(log, ['rounded ocean', 'dense ocean']);
      expect(
        themes.cupertino('ocean').primaryColor,
        CupertinoColors.activeBlue,
      );
      expect(themes.cupertino('ocean'), same(themes.cupertino('Ocean')));
    });

    test(
      'bean overrides: theme / darkTheme / CupertinoThemeData, customized too',
      () {
        final light = ThemeData(colorSchemeSeed: Colors.orange);
        final dark = ThemeData(
          colorSchemeSeed: Colors.orange,
          brightness: Brightness.dark,
        );
        const cupertino = CupertinoThemeData(
          primaryColor: CupertinoColors.systemPink,
        );
        final log = <String>[];
        final themes = SpringThemes(
          const {'themes.ocean.seed-color': 'teal'},
          light: light,
          dark: dark,
          cupertino: cupertino,
          customizers: [Rounded(log)],
        );
        expect(themes.material('light').colorScheme, light.colorScheme);
        expect(themes.material('light').chipTheme.shape, const StadiumBorder());
        expect(themes.material('dark').colorScheme, dark.colorScheme);
        // Custom themes are still made from the properties.
        expect(
          themes.material('ocean').colorScheme.primary,
          themes.data('ocean').colorScheme.primary,
        );
        expect(themes.cupertino('ocean'), cupertino);
      },
    );

    test('unknown names throw with the known ones', () {
      final themes = SpringThemes(const {});
      expect(
        () => themes.material('lava'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('light, dark'),
          ),
        ),
      );
      expect(themes.nameOf('LIGHT'), 'light');
      expect(themes.nameOf('lava'), isNull);
    });

    test('load: relative keys, over the files, replacing the last load', () {
      final themes = SpringThemes(const {
        'seed-color': 'deepPurple',
        'themes.ocean.seed-color': 'teal',
      });
      var notified = 0;
      themes.addListener(() => notified++);
      themes.load(const {
        'themes.ocean.seed-color': 'indigo',
        'themes.winter.seed-color': 'lightBlue',
      });
      expect(
        themes.data('ocean').seedColor!.toARGB32(),
        Colors.indigo.toARGB32(),
      );
      expect(themes.names, ['light', 'dark', 'ocean', 'winter']);
      themes.load(const {'themes.spring.seed-color': 'green'});
      expect(themes.names, [
        'light',
        'dark',
        'ocean',
        'spring',
      ]); // winter replaced
      expect(
        themes.data('ocean').seedColor!.toARGB32(),
        Colors.teal.toARGB32(),
      );
      expect(notified, 2);
    });

    test(
      'loadYaml: prefixed or relative keys, lists, merged with the last one',
      () {
        final themes = SpringThemes(const {});
        themes.loadYaml('''
themes:
  winter:
    typography:
      font-family-fallback: [A, B]
''');
        themes.loadYaml('''
spring.flutter.theme.themes.summer.seed-color: orange
''');
        expect(themes.names, ['light', 'dark', 'summer', 'winter']);
        expect(themes.data('winter').fontFamilyFallback, ['A', 'B']);
        themes.unload();
        expect(themes.names, ['light', 'dark']);
      },
    );

    test('an invalid load changes nothing and tells no one', () {
      final themes = SpringThemes(const {'themes.ocean.seed-color': 'teal'});
      final before = themes.material('ocean');
      var notified = 0;
      themes.addListener(() => notified++);
      expect(
        () => themes.load(const {'themes.ocean.extends': 'ocean'}),
        throwsStateError,
      );
      expect(
        () => themes.loadYaml('themes: {x: {splash: wave}}'),
        throwsA(isA<ThemePropertyException>()),
      );
      expect(themes.material('ocean'), same(before));
      expect(notified, 0);
    });

    test(
      'fromEnvironment: every source, relaxed names, profile files',
      () async {
        final context =
            await application(
              files: {
                'application.yml': '''
spring.flutter.theme:
  seed-color: deepPurple
  themes:
    ocean: { seed-color: teal }
''',
                'application-prod.properties':
                    'spring.flutter.theme.themes.ocean.seed-color=indigo',
              },
            ).runAsync(const [
              '--spring.profiles.active=prod',
              '--spring.flutter.theme.shape.large=24',
            ]);
        addTearDown(context.close);
        final themes = context.getBean<SpringThemes>();
        expect(
          themes.data('light').seedColor!.toARGB32(),
          Colors.deepPurple.toARGB32(),
        );
        expect(
          themes.data('ocean').seedColor!.toARGB32(),
          Colors.indigo.toARGB32(),
        ); // profile wins
        expect(themes.data('ocean').shape('large'), 24); // command line
        expect(SpringThemes.of(context), same(themes)); // the bean
        expect(
          ThemeSelection.of(context),
          same(context.getBean<ThemeSelection>()),
        );
      },
    );

    test('dart defines with relaxed names', () async {
      final context = await SpringApplication(
        [BeanModule('m', const [])],
        dartDefines: const {'SPRING_FLUTTER_THEME_ACTIVE': 'dark'},
        autoConfigurations: [springBootStarterFlutterAutoConfiguration],
        bannerMode: BannerMode.off,
      ).runAsync(const []);
      addTearDown(context.close);
      expect(context.getBean<ThemeSelection>().active, 'dark');
    });

    test(
      'a context whose environment cannot be bound: no theme properties',
      () {
        final context = _PlainContext();
        expect(SpringThemes.of(context).names, ['light', 'dark']);
        expect(SpringThemes.of(context), same(SpringThemes.of(context)));
      },
    );

    test('without the auto-configuration: made once per context', () async {
      final context = await application(autoConfiguration: false)
          .runAsync(const []);
      addTearDown(context.close);
      expect(SpringThemes.of(context), same(SpringThemes.of(context)));
      expect(ThemeSelection.of(context), same(ThemeSelection.of(context)));
    });
  });

  group('ThemeSelection', () {
    test('invalid system-light / system-dark names fail when read', () {
      final selection = ThemeSelection(
        SpringThemes(const {'system-dark': 'nope'}),
      );
      expect(selection.systemLight, 'light');
      expect(() => selection.systemDark, throwsArgumentError);
    });

    test(
      'selecting the shown theme again tells no one; dispose stops listening',
      () {
        final themes = SpringThemes(const {'themes.ocean.seed-color': 'teal'});
        final selection = ThemeSelection(themes);
        var notified = 0;
        selection
          ..addListener(() => notified++)
          ..select('system')
          ..select('SYSTEM');
        expect(notified, 0);
        selection.select('ocean');
        expect(selection.followsSystem, isFalse);
        expect(selection.current(Brightness.dark), 'ocean');
        expect(notified, 1);
        selection.dispose();
        themes.load(const {});
        expect(selection.active, 'ocean'); // no longer follows the themes
      },
    );

    test('a load keeping the shown theme only tells', () {
      final themes = SpringThemes(const {'themes.ocean.seed-color': 'teal'});
      final selection = ThemeSelection(themes)..select('ocean');
      var notified = 0;
      selection.addListener(() => notified++);
      themes.load(const {'themes.ocean.seed-color': 'indigo'});
      expect(selection.active, 'ocean');
      expect(notified, 1);
    });
  });

  group('SpringTheme', () {
    testWidgets('of throws without a SpringTheme, maybeOf is null', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      expect(SpringTheme.maybeOf(context), isNull);
      expect(() => SpringTheme.of(context), throwsFlutterError);
    });

    testWidgets('dependents rebuild when the theme changes', (tester) async {
      final themes = SpringThemes(const {'themes.ocean.seed-color': 'teal'});
      _ThemeName.builds = 0;
      Widget app(String name) =>
          SpringTheme(data: themes.data(name), child: const _ThemeName());
      await tester.pumpWidget(app('light'));
      await tester.pumpWidget(app('light'));
      expect(_ThemeName.builds, 1); // the same data: no rebuild
      await tester.pumpWidget(app('ocean'));
      expect(_ThemeName.builds, 2);
      expect(find.text('ocean'), findsOneWidget);
    });
  });

  group('SpringApp', () {
    Future<ApplicationContext> pump(
      WidgetTester tester,
      Map<String, String> properties,
    ) async {
      await tester.pumpWidget(
        SpringApplicationWidget(
          application: () => application(properties: properties),
          home: Builder(
            builder: (context) => Text(
              SpringTheme.of(context).name,
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return SpringScope.of(tester.element(find.byType(Text)));
    }

    testWidgets('system: follows the device\'s light and dark mode', (
      tester,
    ) async {
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await pump(tester, const {
        'spring.flutter.app.type': 'material',
        'spring.flutter.theme.system-dark': 'night',
        'spring.flutter.theme.themes.night.brightness': 'dark',
        'spring.flutter.theme.themes.night.seed-color': 'indigo',
      });
      expect(find.text('light'), findsOneWidget);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.system);
      expect(app.darkTheme!.colorScheme.brightness, Brightness.dark);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(find.text('night'), findsOneWidget);
    });

    testWidgets('cupertino: the picked theme\'s CupertinoThemeData', (
      tester,
    ) async {
      final context = await pump(tester, const {
        'spring.flutter.app.type': 'cupertino',
        'spring.flutter.theme.active': 'ocean',
        'spring.flutter.theme.themes.ocean.cupertino.primary-color': '#00ACC1',
      });
      expect(
        tester
            .widget<CupertinoApp>(find.byType(CupertinoApp))
            .theme!
            .primaryColor,
        const Color(0xFF00ACC1),
      );
      ThemeSelection.of(context).select('light');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CupertinoApp>(find.byType(CupertinoApp))
            .theme!
            .primaryColor,
        CupertinoColors.systemBlue,
      );
      expect(find.text('light'), findsOneWidget);
    });

    testWidgets('widgets: color and text style of the picked theme', (
      tester,
    ) async {
      final context = await pump(tester, const {
        'spring.flutter.theme.typography.font-family': 'Inter',
        'spring.flutter.theme.themes.serif.typography.font-family':
            'Merriweather',
      });
      WidgetsApp app() => tester.widget<WidgetsApp>(find.byType(WidgetsApp));
      expect(app().textStyle!.fontFamily, 'Inter');
      ThemeSelection.of(context).select('serif');
      await tester.pumpAndSettle();
      expect(app().textStyle!.fontFamily, 'Merriweather');
      expect(app().color, SpringThemes.of(context).data('serif').appColor);
    });

    testWidgets('a theme loaded at run time shows at once', (tester) async {
      final context = await pump(tester, const {
        'spring.flutter.app.type': 'material',
      });
      SpringThemes.of(context)
          .loadYaml('themes: {winter: {seed-color: lightBlue}}');
      ThemeSelection.of(context).select('winter');
      await tester.pumpAndSettle();
      expect(find.text('winter'), findsOneWidget);
      final theme = Theme.of(tester.element(find.text('winter')));
      expect(
        theme.colorScheme.primary,
        SpringThemes.of(context).material('winter').colorScheme.primary,
      );
    });
  });
}

class _ThemeName extends StatelessWidget {
  const _ThemeName();

  static int builds = 0;

  @override
  Widget build(BuildContext context) {
    builds++;
    return Text(SpringTheme.of(context).name, textDirection: TextDirection.ltr);
  }
}

class _PlainEnvironment extends Fake implements Environment {}

class _PlainContext extends Fake implements ApplicationContext {
  final _environment = _PlainEnvironment();

  @override
  Environment get environment => _environment;

  @override
  Map<String, T> getBeansOfType<T extends Object>({
    bool includeNonSingletons = true,
  }) => {};
}
