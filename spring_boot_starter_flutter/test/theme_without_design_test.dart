// A theme in an app without a design library (spring.flutter.app.type:
// widgets, the default): Flutter's baseline palette with the roles of
// colors.* over it; what needs a design's algorithm or routes (a seed
// color, zoom) fails the start and names the starter to add; the
// properties of a design starter's own widgets are accepted and not read.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

import 'support/designs.dart' show testDesigns;

const _material = 'spring_boot_starter_flutter_material';
const _cupertino = 'spring_boot_starter_flutter_cupertino';

SpringThemeData theme(
  Map<String, String> properties, [
  String name = 'light',
]) => SpringThemes(properties).data(name);

/// Fails naming property [key], with [expected] in what the value may be.
Matcher fails(String key, [List<String> expected = const []]) => throwsA(
  isA<ThemePropertyException>()
      .having((e) => e.key, 'key', key)
      .having(
        (e) => e.expected,
        'expected',
        allOf([for (final text in expected) contains(text)]),
      ),
);

void main() {
  group('the palette', () {
    test('no properties: light and dark, each with the baseline', () {
      final themes = SpringThemes(const {});
      expect(themes.designs.all, isEmpty);
      expect(themes.designs.appType, 'widgets');
      expect(themes.names, ['light', 'dark']);
      for (final brightness in Brightness.values) {
        final data = themes.data(brightness.name);
        expect(data.brightness, brightness);
        expect(data.colorScheme, SpringColorScheme.baseline(brightness));
        expect(data.seedColor, isNull);
        expect(data.schemeVariant, isNull);
        expect(data.contrast, isNull);
        expect(data.colors, isEmpty);
        expect(data.unreadDesignProperties, isEmpty);
      }
      // Made once, by any spelling of the name.
      expect(themes.data('Light'), same(themes.data('light')));
      expect(
        themes.data('light').colorScheme,
        same(themes.data('light').colorScheme),
      );
    });

    test('colors.*: the roles set, over the baseline of the brightness', () {
      final themes = SpringThemes(const {
        'colors.primary': '#112233',
        'colors.surface-container': 'teal',
        'themes.night.brightness': 'dark',
        'themes.night.colors.onSurface': '#FFFFFF',
      });
      for (final name in ['light', 'dark', 'night']) {
        final data = themes.data(name);
        final baseline = SpringColorScheme.baseline(data.brightness);
        expect(data.colorScheme.primary, const Color(0xFF112233), reason: name);
        expect(
          data.colorScheme.surfaceContainer,
          const Color(0xFF009688),
          reason: name,
        );
        expect(
          data.colorScheme.onSurface,
          name == 'night' ? const Color(0xFFFFFFFF) : baseline.onSurface,
          reason: name,
        );
        for (final role in colorRoles) {
          if (!const {
            'primary',
            'surfacecontainer',
            'onsurface',
          }.contains(role)) {
            expect(data.role(role), baseline.role(role), reason: '$name $role');
          }
        }
      }
      expect(themes.data('night').colors.keys, {
        'primary',
        'surfacecontainer',
        'onsurface',
      });
    });

    test('every role can be set and read back', () {
      final t = theme({
        for (final (i, role) in colorRoles.indexed)
          'colors.$role':
              '#${(0x101010 + i * 0x010203).toRadixString(16).padLeft(6, '0')}',
      });
      for (final (i, role) in colorRoles.indexed) {
        final expected = Color(0xFF000000 | (0x101010 + i * 0x010203));
        expect(t.role(role), expected, reason: role);
        expect(t.colorScheme.role(role), expected, reason: role);
      }
      expect(
        t.colorScheme.surfaceContainerHighest,
        t.role('surface-container-highest'),
      );
      expect(t.role('unknown'), isNull);
    });

    test(r'a $colors reference to a role not set is the baseline role', () {
      final themes = SpringThemes(const {
        'colors.primary': '#112233',
        'tokens.card.border': r'$colors.outline',
        'tokens.card.accent': r'$colors.primary',
        'tokens.card.soft.color': r'$colors.surface-container',
        'tokens.card.soft.alpha': '50%',
        'styles.card.border': r'$colors.outline-variant',
      });
      final light = themes.data('light');
      expect(light.tokenColor('card.border'), const Color(0xFF79747E));
      // A role the theme sets is the theme's.
      expect(light.tokenColor('card.accent'), const Color(0xFF112233));
      expect(
        light.tokenColor('card.soft'),
        const Color(0xFFF3EDF7).withValues(alpha: 0.5),
      );
      expect(
        light.styles['card']!.resolve(const {}).color('border'),
        const Color(0xFFCAC4D0),
      );
      // In the theme it is read in: dark has the dark baseline.
      expect(
        themes.data('dark').tokenColor('card.border'),
        const Color(0xFF938F99),
      );
    });
  });

  group('what a design makes fails the start, naming the starter', () {
    // The palette of a seed is Material 3's algorithm: either starter has
    // it, and the roles can be set by hand.
    const palette = [_material, _cupertino, 'set the roles under colors'];

    test('seed-color, scheme-variant and contrast', () {
      expect(
        () => theme(const {'seed-color': 'teal'}),
        fails('spring.flutter.theme.seedcolor (theme light)', palette),
      );
      expect(
        () => theme(const {'scheme-variant': 'vibrant'}),
        fails('spring.flutter.theme.schemevariant (theme light)', palette),
      );
      expect(
        () => theme(const {'contrast': '0.5'}),
        fails('spring.flutter.theme.contrast (theme light)', palette),
      );
      // With roles under colors too: the seed is still asked for.
      expect(
        () => theme(const {'seed-color': '#112233', 'colors.primary': 'teal'}),
        fails('spring.flutter.theme.seedcolor (theme light)', palette),
      );
    });

    test('the value as written, in a named theme with its name', () {
      expect(
        () => SpringThemes(const {'themes.ocean.seed-color': 'deepPurple'}),
        throwsA(
          isA<ThemePropertyException>()
              .having(
                (e) => e.key,
                'key',
                'spring.flutter.theme.themes.ocean.seedcolor',
              )
              .having((e) => e.value, 'value', 'deepPurple')
              .having(
                (e) => '$e',
                'message',
                allOf(
                  contains('a design starter in the dependencies'),
                  contains(_material),
                ),
              ),
        ),
      );
      expect(
        () => SpringThemes(const {'themes.ocean.contrast': '1'}),
        fails('spring.flutter.theme.themes.ocean.contrast', palette),
      );
    });

    test('a wrong value is wrong before any design is asked', () {
      expect(
        () => theme(const {'seed-color': 'purpel'}),
        fails('spring.flutter.theme.seedcolor (theme light)', ['a color']),
      );
      expect(
        () => theme(const {'contrast': '2'}),
        fails('spring.flutter.theme.contrast (theme light)', [
          'a number from -1 to 1',
        ]),
      );
    });

    test('the page transitions zoom and cupertino, each its own starter', () {
      for (final (type, starter, other, whose) in [
        ('zoom', _material, _cupertino, "zoom is Material's"),
        ('cupertino', _cupertino, _material, "cupertino is Cupertino's"),
      ]) {
        for (final key in [
          'motion.page-transition',
          'motion.page-transition.type',
        ]) {
          expect(
            () => theme({key: type}),
            throwsA(
              isA<ThemePropertyException>()
                  .having(
                    (e) => e.key,
                    'key',
                    'spring.flutter.theme.motion.pagetransition.type '
                        '(theme light)',
                  )
                  .having((e) => e.value, 'value', type)
                  .having(
                    (e) => e.expected,
                    'expected',
                    allOf(
                      contains(whose),
                      contains('read by $starter (add it to the dependencies)'),
                      isNot(contains(other)),
                      contains('platform, fade-upwards, fade, content or none'),
                    ),
                  ),
            ),
            reason: '$key: $type',
          );
        }
      }
    });

    test('at run time too, and the themes stay as they were', () {
      final themes = SpringThemes(const {
        'themes.ocean.colors.primary': 'teal',
      });
      final before = themes.data('ocean');
      var notified = 0;
      themes.addListener(() => notified++);
      expect(
        () => themes.loadYaml('themes: {winter: {seed-color: lightBlue}}'),
        fails('spring.flutter.theme.themes.winter.seedcolor', palette),
      );
      expect(
        () => themes.load(const {'motion.page-transition': 'zoom'}),
        throwsA(isA<ThemePropertyException>()),
      );
      expect(themes.names, ['light', 'dark', 'ocean']);
      expect(themes.data('ocean'), same(before));
      expect(notified, 0);
    });
  });

  group('the properties of a design starter\'s own widgets', () {
    // A theme of a library has them for the apps of that design; an app
    // of another design shows nothing of them.
    const designed = {
      'components.card.shape': 'large',
      'components.app-bar.center-title': 'true',
      'visual-density': 'compact',
      'tap-target-size': 'shrink-wrap',
      'splash': 'ripple',
      'cupertino.primary-color': '#0057B8',
    };

    test('are accepted, and listed with the starter that reads each', () {
      final t = theme(designed);
      expect(t.unreadDesignProperties, {
        'components': _material,
        'visual-density': _material,
        'tap-target-size': _material,
        'splash': _material,
        'cupertino': _cupertino,
      });
      // Nothing of the theme changes with them.
      expect(t.colorScheme, SpringColorScheme.baseline(Brightness.light));
      expect(t.splash, isNull);
      // They stay in the theme, for whoever reads them.
      expect(t.properties['components.card.shape'], 'large');
      expect(t.properties['cupertino.primarycolor'], '#0057B8');
    });

    test('each alone, in the shared part or in a named theme', () {
      for (final MapEntry(:key, :value) in designed.entries) {
        // By the name as written; a single splash is Material's ink.
        final root = key.split('.').first;
        final expected = {root: root == 'cupertino' ? _cupertino : _material};
        expect(theme({key: value}).unreadDesignProperties, expected);
        final themes = SpringThemes({'themes.ocean.$key': value});
        expect(themes.data('ocean').unreadDesignProperties, expected);
        expect(themes.data('light').unreadDesignProperties, isEmpty);
      }
    });

    test('are not checked: no design reads their values', () {
      final t = theme(const {
        'components.carrd.shape': 'hugee',
        'components.card.color': 'no color',
        'visual-density': 'tight',
        'tap-target-size': 'big',
        'splash': 'wave',
        'cupertino.primary': 'x',
      });
      expect(t.unreadDesignProperties.keys, {
        'components',
        'visual-density',
        'tap-target-size',
        'splash',
        'cupertino',
      });
    });

    test('a misspelled name is still no theme property', () {
      for (final key in [
        'componets.card.shape',
        'component.card.shape',
        'visual-densty',
        'cupertno.primary-color',
        'themes.ocean.componets.card.shape',
      ]) {
        expect(
          () => SpringThemes({key: 'large'}),
          throwsA(
            isA<ThemePropertyException>()
                .having(
                  (e) => e.key,
                  'key',
                  contains(
                    key
                        .split('.')
                        .take(key.startsWith('themes') ? 3 : 1)
                        .join(
                          '.',
                        )
                        .replaceAll('-', ''),
                  ),
                )
                .having(
                  (e) => e.expected,
                  'expected',
                  contains('a theme property: brightness, seed-color'),
                ),
          ),
          reason: key,
        );
      }
    });

    test('with their starters in the application they are read and '
        'checked', () {
      final t = SpringThemes(designed, designs: testDesigns).data('light');
      expect(t.unreadDesignProperties, isEmpty);
      // The property, its value, and the property the failure names.
      for (final (key, value, named) in [
        ('components.carrd.shape', 'large', 'components.carrd'),
        ('components.card.shape', 'hugee', 'components.card.shape'),
        ('visual-density', 'tight', 'visualdensity'),
        ('tap-target-size', 'big', 'taptargetsize'),
        ('splash', 'wave', 'splash'),
        ('cupertino.primary', 'x', 'cupertino.primary'),
        ('cupertino.primary-color', 'no color', 'cupertino.primarycolor'),
      ]) {
        expect(
          () => SpringThemes({key: value}, designs: testDesigns),
          throwsA(
            isA<ThemePropertyException>().having(
              (e) => e.key,
              'key',
              'spring.flutter.theme.$named (theme light)',
            ),
          ),
          reason: '$key: $value',
        );
      }
    });

    test(r'references in them and to them are resolved', () {
      final t = theme(const {
        'colors.primary': '#112233',
        'components.card.color': r'$colors.primary',
        'components.card.elevation': '3',
        'tokens.card.lift': r'$components.card.elevation',
      });
      expect(t.properties['components.card.color'], '#112233');
      expect(t.tokenNumber('card.lift'), 3);
      // A reference to nothing fails there as anywhere.
      expect(
        () => theme(const {'components.card.color': r'$colors.primery'}),
        throwsA(isA<ThemePropertyException>()),
      );
    });
  });

  group('splash', () {
    test('a map is the splash of the start, read without a design', () {
      final t = theme(const {
        'splash.background.color': '#101010',
        'splash.title': 'NEON',
        'splash.min-duration': '300ms',
      });
      expect(t.splash!.background!.color, const Color(0xFF101010));
      expect(t.splash!.title, 'NEON');
      expect(t.splash!.minDuration, const Duration(milliseconds: 300));
      expect(t.unreadDesignProperties, isEmpty);
      // And checked: it is this starter's own.
      expect(
        () => theme(const {'splash.min-duration': 'long'}),
        fails('spring.flutter.theme.splash.minduration (theme light)'),
      );
    });

    test('a single value is Material\'s ink splash: no splash of the '
        'start', () {
      for (final ink in ['ripple', 'sparkle', 'none']) {
        final t = theme({'splash': ink});
        expect(t.splash, isNull, reason: ink);
        expect(t.unreadDesignProperties, {'splash': _material}, reason: ink);
      }
      // With Material's starter it is read: not listed.
      expect(
        SpringThemes(const {
          'splash': 'ripple',
        }, designs: testDesigns).data('light').unreadDesignProperties,
        isEmpty,
      );
    });
  });

  group('page transitions of the starter itself', () {
    PageRoute<void> route() =>
        PageRouteBuilder<void>(pageBuilder: (_, _, _) => const SizedBox());
    const child = SizedBox(key: ValueKey('page'));

    Widget built(SpringThemeData t, Animation<double> animation) =>
        t.pageTransition!.buildTransitions(
          route(),
          _FakeContext(),
          animation,
          kAlwaysDismissedAnimation,
          child,
        );

    test('none: the page as it is', () {
      final t = theme(const {'motion.page-transition': 'none'});
      expect(t.pageTransitions.type, PageTransitionType.none);
      expect(t.isPlatformPageTransition, isFalse);
      expect(built(t, kAlwaysCompleteAnimation), same(child));
      expect(built(t, kAlwaysDismissedAnimation), same(child));
    });

    test('not set, and platform: left to the design of the app, as in '
        'Flutter; the page as it is meanwhile', () {
      for (final properties in [
        const <String, String>{},
        const {'motion.page-transition': 'platform'},
        // A map without a type: the platform's, with that duration.
        const {'motion.page-transition.duration': '400ms'},
      ]) {
        final t = theme(properties);
        expect(t.pageTransitions.type, PageTransitionType.platform);
        expect(t.isPlatformPageTransition, isTrue);
        expect(built(t, kAlwaysCompleteAnimation), same(child));
      }
    });

    test('fade: the page fades in with the route', () {
      final t = theme(const {'motion.page-transition': 'fade'});
      expect(t.isPlatformPageTransition, isFalse);
      final fade =
          built(t, const AlwaysStoppedAnimation(0.25)) as FadeTransition;
      expect(fade.opacity.value, 0.25);
      expect(fade.child, same(child));
    });

    test('fade-upwards and content: builders of the widgets library and '
        'the starter', () {
      expect(
        theme(const {'motion.page-transition': 'fade-upwards'}).pageTransition,
        isA<FadeUpwardsPageTransitionsBuilder>(),
      );
      expect(
        theme(const {'motion.page-transition': 'content'}).pageTransition,
        isA<ContentPageTransitionsBuilder>(),
      );
      // Every kind but the two of a design library.
      for (final type in PageTransitionType.values) {
        if (type != PageTransitionType.zoom &&
            type != PageTransitionType.cupertino) {
          expect(
            theme({'motion.page-transition.type': type.name})
                .pageTransitions
                .type,
            type,
          );
        }
      }
    });
  });
}

class _FakeContext extends Fake implements BuildContext {}
