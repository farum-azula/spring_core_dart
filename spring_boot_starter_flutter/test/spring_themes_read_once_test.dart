// SpringThemes.fromEnvironment reads the themes once per environment: the
// splash reads them while the app starts, and the bean made later from the
// same environment and the same designs reuses them instead of reading
// every theme again.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

StandardEnvironment _env(Map<String, String> properties) =>
    StandardEnvironment()
      ..propertySources.addFirst(MapPropertySource('test', {...properties}));

// A design that reads nothing: two of them are equal, as the constants of
// a starter's module are.
final class _Design implements ThemeDesign {
  const _Design(this.appType);

  @override
  final String appType;

  @override
  List<String> get themeProperties => const [];

  @override
  List<String> get schemeVariants => const [];

  @override
  SpringColorScheme colorScheme(ColorSchemeSpec spec) =>
      SpringColorScheme.baseline(spec.brightness);

  @override
  PageTransitionsBuilder? pageTransition(PageTransitionType type) => null;

  @override
  void check(SpringThemeData theme) {}
}

void main() {
  const props = {
    'spring.flutter.theme.colors.primary': 'teal',
    'spring.flutter.theme.themes.ocean.colors.primary': 'indigo',
  };

  test('the same environment: the themes read once are reused', () {
    final environment = _env(props);
    final splash = SpringThemes.fromEnvironment(environment);
    final bean = SpringThemes.fromEnvironment(environment);
    expect(bean, isNot(same(splash)));
    expect(bean.data('light'), same(splash.data('light')));
    expect(bean.data('ocean'), same(splash.data('ocean')));
    // What a theme makes once is made once for both: its palette.
    expect(
      bean.data('light').colorScheme,
      same(splash.data('light').colorScheme),
    );
  });

  test('other properties, or another environment: read again', () {
    final environment = _env(props);
    final first = SpringThemes.fromEnvironment(environment);
    environment.propertySources.addFirst(
      MapPropertySource('more', {'spring.flutter.theme.colors.primary': 'red'}),
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

  test('the same designs: reused; another app type, other designs or '
      'another order: read again', () {
    const ocean = ThemeDesigns(all: [_Design('ocean')], appType: 'ocean');
    final environment = _env(props);
    final first = SpringThemes.fromEnvironment(environment, designs: ocean);
    expect(first.designs, same(ocean));
    expect(first.data('light').designs, same(ocean));

    // Equal designs in another list: the same themes.
    final again = SpringThemes.fromEnvironment(
      environment,
      designs: ThemeDesigns(all: [const _Design('ocean')], appType: 'ocean'),
    );
    expect(again.data('light'), same(first.data('light')));

    // Each differs from the one before it in one thing.
    var before = again.data('light');
    for (final designs in const [
      ThemeDesigns(all: [_Design('ocean')]),
      ThemeDesigns(all: [_Design('ocean'), _Design('sand')]),
      ThemeDesigns(all: [_Design('sand'), _Design('ocean')]),
      ThemeDesigns.none,
    ]) {
      final themes = SpringThemes.fromEnvironment(
        environment,
        designs: designs,
      );
      final reason =
          '${designs.appType}: ${[
            for (final design in designs.all) design.appType,
          ]}';
      expect(themes.designs, same(designs), reason: reason);
      expect(themes.data('light'), isNot(same(before)), reason: reason);
      expect(themes.data('light').designs, same(designs), reason: reason);
      before = themes.data('light');
    }
  });
}
