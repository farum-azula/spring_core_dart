// Themes from spring.flutter.theme.*: the shared part, named themes with
// extends, Material / Cupertino conversion, selection at run time and
// themes loaded from YAML.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

SpringThemes themes(Map<String, String> properties) => SpringThemes(properties);

Matcher throwsProperty(String key) => throwsA(
  isA<ThemePropertyException>().having((e) => e.key, 'key', contains(key)),
);

void main() {
  group('defaults', () {
    test('no properties: Flutter\'s own Material 3 themes', () {
      final t = themes(const {});
      expect(t.names, ['light', 'dark']);
      final light = t.material('light');
      expect(light.colorScheme, ThemeData().colorScheme);
      expect(light.textTheme, ThemeData().textTheme);
      expect(light.cardTheme, ThemeData().cardTheme);
      expect(
        t.material('dark').colorScheme,
        ThemeData(brightness: Brightness.dark).colorScheme,
      );
      // Cupertino keeps iOS's look: no primary color forced.
      expect(t.cupertino('light').primaryColor, CupertinoColors.systemBlue);
    });

    test('made once', () {
      final t = themes(const {'seed-color': 'teal'});
      expect(t.material('light'), same(t.material('light')));
      expect(t.data('Light'), same(t.data('light')));
    });
  });

  group('colors', () {
    test('seed, variant, contrast and explicit roles', () {
      final t = themes(const {
        'seed-color': 'deepPurple',
        'scheme-variant': 'vibrant',
        'colors.error': '#B3261E',
        'colors.surfaceContainer': 'grey.shade200',
      });
      final scheme = t.material('light').colorScheme;
      final seeded = ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
      );
      expect(scheme.primary, seeded.primary);
      expect(scheme.error, const Color(0xFFB3261E));
      expect(scheme.surfaceContainer, Colors.grey.shade200);
    });

    test('an invalid color or role names the property', () {
      expect(
        () => themes(const {'seed-color': 'purpel'}),
        throwsProperty('spring.flutter.theme.seedcolor'),
      );
      expect(
        () => themes(const {'colors.primery': '#000'}),
        throwsProperty('colors.primery'),
      );
    });
  });

  group('typography', () {
    test('family, fallback, groups and single styles', () {
      final t = themes(const {
        'typography.font-family': 'Inter',
        'typography.font-family-fallback': 'Noto Sans JP, Roboto',
        'typography.display.font-family': 'Playfair Display',
        'typography.display.weight': 'bold',
        'typography.display-small.size': '30',
        'typography.title-large.weight': '600',
        'typography.code.font-family': 'JetBrains Mono',
      });
      final text = t.material('light').textTheme;
      expect(text.bodyMedium!.fontFamily, 'Inter');
      expect(text.bodyMedium!.fontFamilyFallback, ['Noto Sans JP', 'Roboto']);
      expect(text.displayLarge!.fontFamily, 'Playfair Display');
      expect(text.displayLarge!.fontWeight, FontWeight.w700);
      expect(text.displayLarge!.fontVariations, [
        const FontVariation('wght', 700),
      ]);
      expect(text.displaySmall!.fontSize, 30);
      expect(text.displaySmall!.fontFamily, 'Playfair Display');
      expect(text.titleLarge!.fontWeight, FontWeight.w600);
      expect(t.data('light').textStyle('code').fontFamily, 'JetBrains Mono');
    });

    test('a list in a theme replaces the shared one', () {
      final t = themes(const {
        'typography.font-family-fallback.0': 'A',
        'typography.font-family-fallback.1': 'B',
        'themes.sepia.typography.font-family-fallback': 'C',
      });
      expect(t.data('light').fontFamilyFallback, ['A', 'B']);
      expect(t.data('sepia').fontFamilyFallback, ['C']);
    });

    test('an unknown style names the property', () {
      expect(
        () => themes(const {'typography.headline-huge.size': '40'}),
        throwsProperty('typography.headlinehuge'),
      );
    });
  });

  group('shapes and components', () {
    test('a changed scale value reaches the components using it', () {
      final t = themes(const {'shape.medium': '20'});
      expect(
        t.material('light').cardTheme.shape,
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      );
      // Untouched components keep Material's defaults.
      expect(t.material('light').dialogTheme, ThemeData().dialogTheme);
    });

    test('component properties reference tokens', () {
      final t = themes(const {
        'components.card.shape': 'large',
        'components.card.color': 'surface-container',
        'components.card.elevation': 'level2',
        'components.app-bar.center-title': 'true',
        'components.app-bar.title-style': 'title-medium',
        'components.button.shape': 'full',
        'components.filled-button.padding': '24, 10',
        'components.input.style': 'outline',
        'components.navigation-bar.label-behavior': 'onlyShowSelected',
      });
      final theme = t.material('light');
      expect(
        theme.cardTheme.shape,
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      );
      expect(theme.cardTheme.color, theme.colorScheme.surfaceContainer);
      expect(theme.cardTheme.elevation, 3);
      expect(theme.appBarTheme.centerTitle, isTrue);
      expect(
        theme.appBarTheme.titleTextStyle!.fontSize,
        theme.textTheme.titleMedium!.fontSize,
      );
      expect(
        theme.filledButtonTheme.style!.shape!.resolve({}),
        const StadiumBorder(),
      );
      expect(
        theme.filledButtonTheme.style!.padding!.resolve({}),
        const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      );
      expect(
        theme.outlinedButtonTheme.style!.shape!.resolve({}),
        const StadiumBorder(),
      );
      expect(theme.inputDecorationTheme.border, isA<OutlineInputBorder>());
      expect(
        theme.navigationBarTheme.labelBehavior,
        NavigationDestinationLabelBehavior.onlyShowSelected,
      );
    });

    test('unknown components, properties and references fail', () {
      expect(
        () => themes(const {'components.carrd.shape': 'large'}),
        throwsProperty('components.carrd'),
      );
      expect(
        () => themes(const {'components.card.radius': '4'}),
        throwsProperty('components.card.radius'),
      );
      expect(
        () => themes(const {'components.card.shape': 'hugee'}),
        throwsProperty('components.card.shape'),
      );
      expect(
        () => themes(const {'components.card.color': 'surfase'}),
        throwsProperty('components.card.color'),
      );
    });

    test('density, splash, page transitions', () {
      final theme = themes(const {
        'visual-density': 'compact',
        'splash': 'none',
        'motion.page-transition': 'zoom',
      }).material('light');
      expect(theme.visualDensity, VisualDensity.compact);
      expect(theme.splashFactory, NoSplash.splashFactory);
      expect(
        theme.pageTransitionsTheme.builders[TargetPlatform.iOS],
        isA<ZoomPageTransitionsBuilder>(),
      );
    });
  });

  group('named themes', () {
    final properties = {
      'seed-color': 'deepPurple',
      'shape.large': '20',
      'themes.dark.seed-color': 'deepPurple.shade200',
      'themes.ocean.seed-color': 'teal',
      'themes.ocean.shape.large': '28',
      'themes.ocean-night.extends': 'ocean',
      'themes.ocean-night.brightness': 'dark',
      'themes.sepia.colors.surface': '#F4ECD8',
      'tokens.brand.accent': '#FF6B00',
      'themes.sepia.tokens.brand.accent': '#8B4513',
    };

    test('standard and custom themes, in order', () {
      expect(themes(properties).names, [
        'light',
        'dark',
        'ocean',
        'ocean-night',
        'sepia',
      ]);
    });

    test('a theme is the shared part with its own on top', () {
      final t = themes(properties);
      expect(t.data('dark').brightness, Brightness.dark);
      expect(
        t.data('dark').seedColor!.toARGB32(),
        Colors.deepPurple.shade200.toARGB32(),
      );
      expect(t.data('ocean').brightness, Brightness.light);
      expect(t.data('ocean').seedColor!.toARGB32(), Colors.teal.toARGB32());
      expect(t.data('ocean').shape('large'), 28);
      expect(t.data('sepia').shape('large'), 20); // shared
      expect(t.data('sepia').colorScheme.surface, const Color(0xFFF4ECD8));
      expect(
        t.data('light').tokenColor('brand.accent'),
        const Color(0xFFFF6B00),
      );
      expect(
        t.data('sepia').tokenColor('brand.accent'),
        const Color(0xFF8B4513),
      );
    });

    test('extends: the parent, then the theme', () {
      final night = themes(properties).data('ocean-night');
      expect(night.seedColor!.toARGB32(), Colors.teal.toARGB32());
      expect(night.shape('large'), 28);
      expect(night.brightness, Brightness.dark);
    });

    test('extends: unknown themes and cycles fail', () {
      expect(
        () => themes(const {'themes.a.extends': 'nope'}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains("extends 'nope'"),
          ),
        ),
      );
      expect(
        () => themes(const {'themes.a.extends': 'b', 'themes.b.extends': 'a'}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('a → b → a'),
          ),
        ),
      );
    });
  });

  group('ThemeSelection', () {
    test('system by default, the device picks light or dark', () {
      final selection = ThemeSelection(themes(const {}));
      expect(selection.active, 'system');
      expect(selection.current(Brightness.light), 'light');
      expect(selection.current(Brightness.dark), 'dark');
    });

    test('active, system-light / system-dark and select', () {
      final selection = ThemeSelection(
        themes(const {
          'active': 'ocean',
          'system-dark': 'ocean-night',
          'themes.ocean.seed-color': 'teal',
          'themes.ocean-night.extends': 'ocean',
          'themes.ocean-night.brightness': 'dark',
        }),
      );
      expect(selection.active, 'ocean');
      var notified = 0;
      selection
        ..addListener(() => notified++)
        ..select('system');
      expect(selection.current(Brightness.dark), 'ocean-night');
      selection.select('Ocean');
      expect(selection.active, 'ocean');
      expect(notified, 2);
      expect(() => selection.select('lava'), throwsArgumentError);
    });

    test('an unknown active theme fails', () {
      expect(
        () => ThemeSelection(themes(const {'active': 'lava'})),
        throwsArgumentError,
      );
    });
  });

  group('themes at run time', () {
    test('loadYaml adds themes; invalid ones change nothing', () {
      final t = themes(const {'seed-color': 'deepPurple'});
      final selection = ThemeSelection(t);
      var notified = 0;
      t.addListener(() => notified++);

      t.loadYaml('''
spring:
  flutter:
    theme:
      themes:
        winter:
          seed-color: lightBlue
          typography:
            font-family-fallback: [Noto Sans JP]
''');
      expect(t.names, contains('winter'));
      expect(
        t.data('winter').seedColor!.toARGB32(),
        Colors.lightBlue.toARGB32(),
      );
      expect(t.data('winter').fontFamilyFallback, ['Noto Sans JP']);
      expect(notified, 1);
      selection.select('winter');

      expect(
        () => t.loadYaml('themes:\n  storm:\n    seed-color: purpel\n'),
        throwsProperty('seedcolor'),
      );
      expect(t.names, isNot(contains('storm')));

      t.unload();
      expect(t.names, isNot(contains('winter')));
      expect(selection.active, 'system'); // the shown theme went away
    });
  });

  group('in the app', () {
    SpringApplication application(Map<String, String> properties) =>
        SpringApplication([
          BeanModule(
            'test',
            const [],
            resources: {
              'application.properties': EmbeddedResource.text(
                [
                  for (final MapEntry(:key, :value) in properties.entries)
                    '$key=$value',
                ].join('\n'),
              ),
            },
          ),
        ], bannerMode: BannerMode.off);

    testWidgets('the active theme, switched at run time', (tester) async {
      await tester.pumpWidget(
        SpringApplicationWidget(
          application: () => application({
            'spring.flutter.app.type': 'material',
            'spring.flutter.theme.active': 'ocean',
            'spring.flutter.theme.themes.ocean.seed-color': 'teal',
          }),
          home: Builder(
            builder: (context) => Text(
              '${SpringTheme.of(context).name} ${Theme.of(context).colorScheme.primary.toARGB32()}',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final teal = ColorScheme.fromSeed(seedColor: Colors.teal).primary
          .toARGB32();
      expect(find.text('ocean $teal'), findsOneWidget);

      final context = SpringScope.of(tester.element(find.byType(Text)));
      ThemeSelection.of(context).select('light');
      await tester.pumpAndSettle();
      final purple = ThemeData().colorScheme.primary.toARGB32();
      expect(find.text('light $purple'), findsOneWidget);
    });

    testWidgets('an invalid theme property fails the start', (tester) async {
      await tester.pumpWidget(
        SpringApplicationWidget(
          application: () =>
              application({'spring.flutter.theme.seed-color': 'purpel'}),
          home: const Text('home'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('spring.flutter.theme.seedcolor'),
        findsOneWidget,
      );
      expect(find.text('home'), findsNothing);
    });

    testWidgets('a WidgetsApp gets the theme too', (tester) async {
      await tester.pumpWidget(
        SpringApplicationWidget(
          application: () => application({
            'spring.flutter.theme.typography.font-family': 'Inter',
          }),
          home: Builder(
            builder: (context) =>
                Text(DefaultTextStyle.of(context).style.fontFamily ?? '-'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Inter'), findsOneWidget);
    });
  });
}
