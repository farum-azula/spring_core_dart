// The theme properties as named themes: selection keys, the shared part,
// themes.<name>, extends, lists, canonical keys.
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';

void main() {
  test('selection: defaults and properties in any spelling', () {
    final defaults = ThemeConfig(const {});
    expect(
      (defaults.active, defaults.systemLight, defaults.systemDark),
      ('system', 'light', 'dark'),
    );
    final config = ThemeConfig(const {
      'active': ' ocean ',
      'systemLight': 'sepia',
      'SYSTEM_DARK': 'ocean-night',
    });
    expect(
      (config.active, config.systemLight, config.systemDark),
      ('ocean', 'sepia', 'ocean-night'),
    );
  });

  test('names: light, dark, then custom ones sorted; looked up loosely', () {
    final config = ThemeConfig(const {
      'themes.zeta.seed-color': 'teal',
      'themes.Ocean-Night.extends': 'ocean',
      'themes.ocean.seed-color': 'teal',
      'themes.dark.seed-color': 'teal',
    });
    expect(config.names, ['light', 'dark', 'Ocean-Night', 'ocean', 'zeta']);
    expect(config.nameOf('OCEAN_NIGHT'), 'Ocean-Night');
    expect(config.nameOf('oceannight'), 'Ocean-Night');
    expect(config.nameOf('lava'), isNull);
    expect(config.names, same(config.names)); // made once
    expect(() => config.names.add('x'), throwsUnsupportedError);
  });

  test('resolve: brightness, shared part, own keys canonical', () {
    final config = ThemeConfig(const {
      'seed-color': 'deepPurple',
      'typography.fontFamily': 'Inter',
      'themes.sepia.colors.on-surface': '#5B4636',
    });
    expect(config.resolve('light'), {
      'brightness': 'light',
      'seedcolor': 'deepPurple',
      'typography.fontfamily': 'Inter',
    });
    expect(config.resolve('dark')['brightness'], 'dark');
    expect(config.resolve('Sepia'), {
      'brightness': 'light',
      'seedcolor': 'deepPurple',
      'typography.fontfamily': 'Inter',
      'colors.onsurface': '#5B4636',
    });
    expect(() => config.resolve('lava'), throwsArgumentError);
  });

  test('extends: a chain, the child last; not the shared part twice', () {
    final config = ThemeConfig(const {
      'shape.large': '16',
      'themes.a.shape.large': '20',
      'themes.a.seed-color': 'teal',
      'themes.b.extends': 'a',
      'themes.b.brightness': 'dark',
      'themes.c.extends': 'B',
      'themes.c.seed-color': 'red',
    });
    expect(config.resolve('c'), {
      'brightness': 'dark',
      'shape.large': '20',
      'seedcolor': 'red',
    });
    expect(config.resolve('c').containsKey('extends'), isFalse);
  });

  test('extends a standard theme', () {
    final config = ThemeConfig(const {
      'themes.dark.seed-color': 'indigo',
      'themes.night.extends': 'dark',
    });
    expect(config.resolve('night')['brightness'], 'dark');
    expect(config.resolve('night')['seedcolor'], 'indigo');
  });

  test('lists: a theme\'s list replaces the shared one, either form', () {
    final config = ThemeConfig(const {
      'typography.font-family-fallback.0': 'A',
      'typography.font-family-fallback.1': 'B',
      'themes.x.typography.font-family-fallback': 'C, D',
      'themes.y.typography.font-family-fallback.0': 'E',
      'themes.z.extends': 'x',
      'themes.z.typography.font-family-fallback.0': 'F',
    });
    List<String>? list(String theme) => ThemeProperties(
      theme,
      config.resolve(theme),
    ).list('typography.fontfamilyfallback');
    expect(list('light'), ['A', 'B']);
    expect(list('x'), ['C', 'D']);
    expect(list('y'), ['E']);
    expect(list('z'), ['F']);
  });

  group('ThemeProperties', () {
    final p = ThemeProperties('ocean', const {
      'seedcolor': 'teal',
      'empty': '  ',
      'list.0': 'b',
      'list.2': 'c',
      'list.1': ' ',
      'components.card.shape': 'large',
      'components.appbar.elevation': 'level1',
    });

    test('values: trimmed, empty is none', () {
      expect(p['seedcolor'], 'teal');
      expect(p['empty'], isNull);
      expect(p['missing'], isNull);
    });

    test('lists in index order, blank entries dropped', () {
      expect(p.list('list'), ['b', 'c']);
      expect(p.list('missing'), isNull);
    });

    test('children', () {
      expect(p.children('components'), {'card', 'appbar'});
      expect(p.children('nothing'), isEmpty);
    });

    test('read: parsed, or an error naming the property', () {
      expect(p.read('seedcolor', (v) => v.length, 'x'), 4);
      expect(p.read('missing', (v) => 1, 'x'), isNull);
      expect(
        () => p.read('seedcolor', (v) => null, 'a number'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            "Invalid theme property spring.flutter.theme.themes.ocean.seedcolor: 'teal'; expected a number.",
          ),
        ),
      );
      expect(
        ThemeProperties('light', const {}).propertyName('shape.large'),
        'spring.flutter.theme.shape.large (theme light)',
      );
    });
  });
}
