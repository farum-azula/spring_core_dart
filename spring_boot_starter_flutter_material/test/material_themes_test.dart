// The themes of spring.flutter.theme.* as Material's ThemeData: Flutter's
// own Material 3 themes without properties, the seed's palette, the text
// theme, the components, and the MaterialThemes bean: customizers, the
// replacing ThemeData beans, themes loaded at run time.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_material/spring_boot_starter_flutter_material.dart';

import 'support/themes.dart';

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
        'components.card.color': r'$colors.surface-container',
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
        invalid('components.carrd'),
      );
      expect(
        () => themes(const {'components.card.radius': '4'}),
        invalid('components.card.radius'),
      );
      expect(
        () => themes(const {'components.card.shape': 'hugee'}),
        invalid('components.card.shape'),
      );
      expect(
        () => themes(const {'components.card.color': 'surfase'}),
        invalid('components.card.color'),
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

  group('MaterialThemes', () {
    test('customizers in order on every theme, once each', () {
      final log = <String>[];
      final material = MaterialThemes(
        themes(const {'themes.ocean.seed-color': 'teal'}),
        customizers: [Rounded(log), Dense(log)],
      );
      final ocean = material.theme('ocean');
      expect(ocean.chipTheme.shape, const StadiumBorder());
      expect(ocean.visualDensity, VisualDensity.compact);
      expect(material.theme('Ocean'), same(ocean));
      expect(log, ['rounded ocean', 'dense ocean']);
    });

    test('bean overrides: theme / darkTheme, customized too', () {
      final light = ThemeData(colorSchemeSeed: Colors.orange);
      final dark = ThemeData(
        colorSchemeSeed: Colors.orange,
        brightness: Brightness.dark,
      );
      final log = <String>[];
      final material = MaterialThemes(
        themes(const {'themes.ocean.seed-color': 'teal'}),
        light: light,
        dark: dark,
        customizers: [Rounded(log)],
      );
      expect(material.theme('light').colorScheme, light.colorScheme);
      expect(material.theme('light').chipTheme.shape, const StadiumBorder());
      expect(material.theme('dark').colorScheme, dark.colorScheme);
      // Custom themes are still made from the properties.
      expect(
        material.theme('ocean').colorScheme.primary,
        material.themes.data('ocean').colorScheme.primary,
      );
    });

    test('without customizers: the theme made from the properties', () {
      final material = MaterialThemes(themes(const {'seed-color': 'teal'}));
      expect(
        material.theme('light'),
        same(material.themes.data('light').toMaterial()),
      );
    });

    test('unknown names throw with the known ones', () {
      final material = MaterialThemes(themes(const {}));
      expect(
        () => material.theme('lava'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('light, dark'),
          ),
        ),
      );
    });

    test('an invalid load changes nothing and tells no one', () {
      final material = MaterialThemes(
        themes(const {'themes.ocean.seed-color': 'teal'}),
      );
      final before = material.theme('ocean');
      var notified = 0;
      material.themes.addListener(() => notified++);
      expect(
        () => material.themes.load(const {'themes.ocean.extends': 'ocean'}),
        throwsStateError,
      );
      expect(
        () => material.themes.loadYaml('themes: {x: {splash: wave}}'),
        throwsA(isA<ThemePropertyException>()),
      );
      expect(material.theme('ocean'), same(before));
      expect(notified, 0);
    });

    test('themes loaded at run time are made again, customized again', () {
      final log = <String>[];
      final material = MaterialThemes(
        themes(const {'themes.ocean.seed-color': 'teal'}),
        customizers: [Rounded(log)],
      );
      final before = material.theme('ocean');
      material.themes.load(const {'themes.ocean.seed-color': 'indigo'});
      final after = material.theme('ocean');
      expect(after, isNot(same(before)));
      expect(
        after.colorScheme.primary,
        ColorScheme.fromSeed(seedColor: Colors.indigo).primary,
      );
      expect(after.chipTheme.shape, const StadiumBorder());
      expect(log, ['rounded ocean', 'rounded ocean']);
      expect(material.theme('ocean'), same(after));
    });

    test('themes read once per environment: their ThemeData made once, '
        'each bean with its own customizers', () {
      final environment = StandardEnvironment()
        ..propertySources.addFirst(
          MapPropertySource('test', {
            'spring.flutter.theme.seed-color': 'teal',
            'spring.flutter.theme.themes.ocean.seed-color': 'indigo',
          }),
        );
      final splash = SpringThemes.fromEnvironment(
        environment,
        designs: materialDesigns,
      );
      final bean = SpringThemes.fromEnvironment(
        environment,
        designs: materialDesigns,
      );
      expect(bean.data('light'), same(splash.data('light')));
      // The Material theme made for the splash is made once, too.
      expect(
        bean.data('light').toMaterial(),
        same(splash.data('light').toMaterial()),
      );
      final plain = MaterialThemes(splash);
      final custom = MaterialThemes(bean, customizers: [Dense([])]);
      expect(custom.theme('light').visualDensity, VisualDensity.compact);
      expect(
        plain.theme('light').visualDensity,
        isNot(VisualDensity.compact),
      );
    });

    test('of: without the auto-configuration, made once per context', () async {
      final context = await SpringApplication(
        [BeanModule('test', const [])],
        bannerMode: BannerMode.off,
      ).runAsync(const []);
      addTearDown(context.close);
      final made = MaterialThemes.of(context);
      expect(MaterialThemes.of(context), same(made));
      expect(made.themes, same(SpringThemes.of(context)));
      expect(made.customizers, isEmpty);
    });
  });
}
