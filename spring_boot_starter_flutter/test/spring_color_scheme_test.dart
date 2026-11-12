// SpringColorScheme, the palette of a theme without a design library: the
// baseline of each brightness, a role by its name in any spelling, a
// palette with roles changed, and what is not a palette.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

// A color of its own for role [index] of [colorRoles].
Color _color(int index) => Color(0xFF000000 | (0x101010 + index * 0x010203));

Map<String, Color> _everyRole() => {
  for (final (index, role) in colorRoles.indexed) role: _color(index),
};

Matcher _refuses(String role, String why) => throwsA(
  isA<ArgumentError>()
      .having((e) => e.invalidValue, 'role', role)
      .having((e) => e.message, 'message', why),
);

void main() {
  group('baseline', () {
    test('light: the Material 3 baseline, the palette of ThemeData()', () {
      final light = SpringColorScheme.baseline(Brightness.light);
      expect(light.brightness, Brightness.light);
      expect(light.primary, const Color(0xFF6750A4));
      expect(light.onPrimary, const Color(0xFFFFFFFF));
      expect(light.secondary, const Color(0xFF625B71));
      expect(light.error, const Color(0xFFB3261E));
      expect(light.surface, const Color(0xFFFEF7FF));
      expect(light.onSurface, const Color(0xFF1D1B20));
      expect(light.surfaceContainer, const Color(0xFFF3EDF7));
      expect(light.outline, const Color(0xFF79747E));
      expect(light.outlineVariant, const Color(0xFFCAC4D0));
      expect(light.shadow, const Color(0xFF000000));
    });

    test('dark', () {
      final dark = SpringColorScheme.baseline(Brightness.dark);
      expect(dark.brightness, Brightness.dark);
      expect(dark.primary, const Color(0xFFD0BCFF));
      expect(dark.onPrimary, const Color(0xFF381E72));
      expect(dark.error, const Color(0xFFF2B8B5));
      expect(dark.surface, const Color(0xFF141218));
      expect(dark.onSurface, const Color(0xFFE6E0E9));
      expect(dark.surfaceContainer, const Color(0xFF211F26));
      expect(dark.outline, const Color(0xFF938F99));
    });

    test('one per brightness, with a color for each of the 46 roles', () {
      expect(colorRoles, hasLength(46));
      expect(colorRoles.toSet(), hasLength(46));
      for (final brightness in Brightness.values) {
        final palette = SpringColorScheme.baseline(brightness);
        expect(SpringColorScheme.baseline(brightness), same(palette));
        expect(palette.roles.keys.toList(), colorRoles, reason: '$brightness');
      }
      expect(
        SpringColorScheme.baseline(Brightness.light),
        isNot(SpringColorScheme.baseline(Brightness.dark)),
      );
    });
  });

  group('a palette of its own roles', () {
    test('every role by its getter', () {
      final s = SpringColorScheme(Brightness.dark, _everyRole());
      expect(s.brightness, Brightness.dark);
      // In the order of colorRoles.
      expect(
        [
          s.primary, s.onPrimary, s.primaryContainer, s.onPrimaryContainer, //
          s.primaryFixed, s.primaryFixedDim, s.onPrimaryFixed,
          s.onPrimaryFixedVariant,
          s.secondary, s.onSecondary, s.secondaryContainer,
          s.onSecondaryContainer,
          s.secondaryFixed, s.secondaryFixedDim, s.onSecondaryFixed,
          s.onSecondaryFixedVariant,
          s.tertiary, s.onTertiary, s.tertiaryContainer, s.onTertiaryContainer,
          s.tertiaryFixed, s.tertiaryFixedDim, s.onTertiaryFixed,
          s.onTertiaryFixedVariant,
          s.error, s.onError, s.errorContainer, s.onErrorContainer, //
          s.surface, s.onSurface, s.onSurfaceVariant, s.surfaceDim,
          s.surfaceBright,
          s.surfaceContainerLowest, s.surfaceContainerLow, s.surfaceContainer,
          s.surfaceContainerHigh, s.surfaceContainerHighest, s.surfaceTint,
          s.inverseSurface, s.onInverseSurface, s.inversePrimary, //
          s.outline, s.outlineVariant, s.shadow, s.scrim,
        ],
        [for (var i = 0; i < colorRoles.length; i++) _color(i)],
      );
    });

    test('role: the name in any case, with or without - and _', () {
      final s = SpringColorScheme(Brightness.light, _everyRole());
      final highest = _color(colorRoles.indexOf('surfacecontainerhighest'));
      for (final name in [
        'surfacecontainerhighest',
        'surfaceContainerHighest',
        'surface-container-highest',
        'surface_container_highest',
        'Surface Container Highest',
        'SURFACE-CONTAINER-HIGHEST',
      ]) {
        expect(s.role(name), highest, reason: name);
      }
      expect(s.role('onPrimary'), s.onPrimary);
      expect(s.role('surface-container-higher'), isNull);
      expect(s.role(''), isNull);
    });

    test('the names of the constructor in any spelling too', () {
      final s = SpringColorScheme(Brightness.light, {
        for (final MapEntry(:key, :value) in _everyRole().entries)
          if (key == 'onprimary')
            'on-Primary': value
          else if (key == 'outlinevariant')
            'OUTLINE_VARIANT': value
          else
            key: value,
      });
      expect(s.roles, _everyRole());
    });

    test('the roles cannot be changed', () {
      final roles = _everyRole();
      final s = SpringColorScheme(Brightness.light, roles);
      roles['primary'] = const Color(0xFF000000);
      expect(s.primary, _color(0));
      expect(
        () => s.roles['primary'] = const Color(0xFF000000),
        throwsUnsupportedError,
      );
    });

    test('a missing role or an unknown one is refused, by name', () {
      expect(
        () =>
            SpringColorScheme(Brightness.light, _everyRole()..remove('scrim')),
        _refuses('scrim', 'a color role is missing'),
      );
      expect(
        () => SpringColorScheme(Brightness.light, const {}),
        _refuses('primary', 'a color role is missing'),
      );
      expect(
        () => SpringColorScheme(Brightness.light, {
          ..._everyRole(),
          'accent': const Color(0xFF000000),
        }),
        _refuses('accent', 'not a color role'),
      );
    });
  });

  group('withRoles', () {
    final baseline = SpringColorScheme.baseline(Brightness.light);

    test('the roles given are changed, the others and the brightness kept', () {
      final changed = baseline.withRoles(const {
        'primary': Color(0xFF112233),
        'surface-container': Color(0xFF445566),
        'onSurface': Color(0xFF778899),
      });
      expect(changed.brightness, Brightness.light);
      expect(changed.primary, const Color(0xFF112233));
      expect(changed.surfaceContainer, const Color(0xFF445566));
      expect(changed.onSurface, const Color(0xFF778899));
      expect(changed.roles.keys.toList(), colorRoles);
      for (final role in colorRoles) {
        if (!const {
          'primary',
          'surfacecontainer',
          'onsurface',
        }.contains(role)) {
          expect(changed.role(role), baseline.role(role), reason: role);
        }
      }
      // The palette it was made of is as it was.
      expect(baseline.primary, const Color(0xFF6750A4));
    });

    test('no roles: the same palette', () {
      expect(baseline.withRoles(const {}), same(baseline));
    });

    test('an unknown role is refused', () {
      expect(
        () => baseline.withRoles(const {'primery': Color(0xFF000000)}),
        _refuses('primery', 'not a color role'),
      );
    });
  });

  group('equality', () {
    test('the same roles and brightness are equal, with one hash code', () {
      final a = SpringColorScheme(Brightness.light, _everyRole());
      final b = SpringColorScheme(Brightness.light, _everyRole());
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        SpringColorScheme.baseline(Brightness.light).withRoles({
          'primary': SpringColorScheme.baseline(Brightness.light).primary,
        }),
        SpringColorScheme.baseline(Brightness.light),
      );
    });

    test('another brightness or one other role: not equal', () {
      final a = SpringColorScheme(Brightness.light, _everyRole());
      expect(a, isNot(SpringColorScheme(Brightness.dark, _everyRole())));
      expect(a, isNot(a.withRoles(const {'scrim': Color(0xFF123456)})));
      expect(a, isNot(_everyRole()));
    });

    test('toString names the brightness', () {
      expect(
        '${SpringColorScheme.baseline(Brightness.dark)}',
        'SpringColorScheme(dark)',
      );
    });
  });
}
