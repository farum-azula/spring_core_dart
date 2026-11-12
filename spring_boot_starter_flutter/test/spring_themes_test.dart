// Themes from spring.flutter.theme.*: the shared part, named themes with
// extends, selection at run time and themes loaded from YAML, in an app
// without a design library.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

SpringThemes themes(Map<String, String> properties) => SpringThemes(properties);

Matcher throwsProperty(String key) => throwsA(
  isA<ThemePropertyException>().having((e) => e.key, 'key', contains(key)),
);

// The colors the themes name, as Material's palette has them.
const _deepPurple = Color(0xFF673AB7);
const _deepPurple200 = Color(0xFFB39DDB);
const _teal = Color(0xFF009688);
const _lightBlue = Color(0xFF03A9F4);

void main() {
  group('colors', () {
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

  group('named themes', () {
    final properties = {
      'colors.primary': 'deepPurple',
      'shape.large': '20',
      'themes.dark.colors.primary': 'deepPurple.shade200',
      'themes.ocean.colors.primary': 'teal',
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
      expect(t.data('light').colorScheme.primary, _deepPurple);
      expect(t.data('dark').colorScheme.primary, _deepPurple200);
      expect(t.data('ocean').brightness, Brightness.light);
      expect(t.data('ocean').colorScheme.primary, _teal);
      // What a theme does not set is the baseline of its brightness.
      expect(
        t.data('dark').colorScheme.surface,
        SpringColorScheme.baseline(Brightness.dark).surface,
      );
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
      expect(night.colorScheme.primary, _teal);
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
          'themes.ocean.colors.primary': 'teal',
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
      final t = themes(const {'colors.primary': 'deepPurple'});
      final selection = ThemeSelection(t);
      var notified = 0;
      t.addListener(() => notified++);

      t.loadYaml('''
spring:
  flutter:
    theme:
      themes:
        winter:
          colors:
            primary: lightBlue
          typography:
            font-family-fallback: [Noto Sans JP]
''');
      expect(t.names, contains('winter'));
      expect(t.data('winter').colorScheme.primary, _lightBlue);
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

  test('ownNames: the themes the files declare or choose, not every name', () {
    final t = SpringThemes({
      'themes.ocean.colors.primary': '#000000',
      'active': 'system',
      'system-light': 'ocean',
      'system-dark': 'dark',
    });
    expect(t.names, ['light', 'dark', 'ocean']);
    expect(t.ownNames, ['dark', 'ocean']);
    // Nothing chosen: `light` is active and `dark` the system's dark one.
    expect(SpringThemes(const {}).ownNames, ['light', 'dark']);
  });
}
