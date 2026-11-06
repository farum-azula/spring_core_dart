// SpringThemes.fromEnvironment reads the themes once per environment: the
// splash reads them while the app starts, and the bean made later from the
// same environment reuses them instead of reading every theme again.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

StandardEnvironment _env(Map<String, String> properties) =>
    StandardEnvironment()
      ..propertySources.addFirst(MapPropertySource('test', {...properties}));

void main() {
  const props = {
    'spring.flutter.theme.seed-color': 'teal',
    'spring.flutter.theme.themes.ocean.seed-color': 'indigo',
  };

  test('the same environment: the themes read once are reused', () {
    final environment = _env(props);
    final splash = SpringThemes.fromEnvironment(environment);
    final bean = SpringThemes.fromEnvironment(environment);
    expect(bean.data('light'), same(splash.data('light')));
    expect(bean.data('ocean'), same(splash.data('ocean')));
    // The Material theme made for the splash is made once, too.
    expect(
      bean.data('light').toMaterial(),
      same(splash.data('light').toMaterial()),
    );
  });

  test('each instance keeps its own customizers', () {
    final environment = _env(props);
    final plain = SpringThemes.fromEnvironment(environment);
    final custom = SpringThemes.fromEnvironment(
      environment,
      customizers: [_Dense()],
    );
    expect(
      custom.material('light').visualDensity,
      VisualDensity.compact,
    );
    expect(
      plain.material('light').visualDensity,
      isNot(VisualDensity.compact),
    );
  });

  test('other properties, or another environment: read again', () {
    final environment = _env(props);
    final first = SpringThemes.fromEnvironment(environment);
    environment.propertySources.addFirst(
      MapPropertySource('more', {'spring.flutter.theme.seed-color': 'red'}),
    );
    final changed = SpringThemes.fromEnvironment(environment);
    expect(changed.data('light'), isNot(same(first.data('light'))));
    expect(
      changed.data('light').colorScheme.primary,
      isNot(first.data('light').colorScheme.primary),
    );

    final other = SpringThemes.fromEnvironment(_env(props));
    expect(other.data('light'), isNot(same(first.data('light'))));
  });
}

class _Dense implements ThemeCustomizer {
  @override
  ThemeData customize(ThemeData theme, SpringThemeData spring) =>
      theme.copyWith(visualDensity: VisualDensity.compact);
}
