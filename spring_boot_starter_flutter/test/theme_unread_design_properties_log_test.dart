// The theme properties of a design starter that no starter of the
// application reads are told once: one INFO line per property on
// spring_boot_starter_flutter.SpringThemes, naming the starter to add. The
// lines are once per program, so the whole of it is one test.
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show captureLogs;

import 'support/designs.dart'
    show CupertinoThemeDesign, MaterialThemeDesign, testDesigns;

const _logger = 'spring_boot_starter_flutter.SpringThemes';
const _material = 'spring_boot_starter_flutter_material';
const _cupertino = 'spring_boot_starter_flutter_cupertino';

const _designed = {
  'components.card.shape': 'large',
  'visual-density': 'compact',
  'tap-target-size': 'padded',
  'splash': 'ripple',
  'cupertino.primary-color': '#0057B8',
  'themes.ocean.components.card.elevation': 'level2',
  'themes.ocean.cupertino.primary-color': '#00ACC1',
};

void main() {
  final logs = captureLogs(level: SpringLogLevel.info);

  // "The theme property <name> is not shown and not checked: <starter>,
  // which reads it, is not in the application."
  Matcher line(String property, String starter) => matches(
    RegExp(
      '^The theme property $property is not shown and not checked: '
      '$starter, which reads it, is not in the application\\.\$',
    ),
  );

  test('a line per property without its starter, once', () {
    List<String> told() => [
      for (final record in logs.ofLogger(_logger)) record.message,
    ];

    // Both starters: every property is read, nothing to tell.
    final both = SpringThemes(_designed, designs: testDesigns);
    expect(both.data('ocean').unreadDesignProperties, isEmpty);
    expect(told(), isEmpty);

    // A splash map is the splash of the start, no design's: never told,
    // even without a starter (before the ink splash is told below).
    SpringThemes(const {'splash.title': 'NEON'});
    expect(told(), isEmpty);

    // The Material starter alone: cupertino is the Cupertino starter's.
    SpringThemes(
      _designed,
      designs: const ThemeDesigns(
        all: [MaterialThemeDesign()],
        appType: 'material',
      ),
    );
    expect(told(), [line('cupertino', _cupertino)]);
    expect(
      logs.ofLogger(_logger).single.level,
      SpringLogLevel.info,
    );

    // The Cupertino starter alone: what is Material's, each once though
    // two themes have it; cupertino is read here.
    logs.clear();
    SpringThemes(
      _designed,
      designs: const ThemeDesigns(
        all: [CupertinoThemeDesign()],
        appType: 'cupertino',
      ),
    );
    expect(
      told(),
      unorderedMatches([
        line('components', _material),
        line('visual-density', _material),
        line('tap-target-size', _material),
        line('splash', _material),
      ]),
    );
    expect(
      logs.ofLogger(_logger).map((record) => record.level).toSet(),
      {SpringLogLevel.info},
    );

    // No starter at all, other themes, themes loaded at run time: each
    // property was told.
    logs.clear();
    final none = SpringThemes(_designed);
    expect(none.data('ocean').unreadDesignProperties.keys, {
      'components',
      'visual-density',
      'tap-target-size',
      'splash',
      'cupertino',
    });
    none
      ..load(const {'themes.winter.components.chip.shape': 'full'})
      ..loadYaml('themes: {storm: {cupertino: {primary-color: "#000000"}}}');
    SpringThemes(const {'visual-density': 'comfortable'});
    expect(told(), isEmpty);
  });
}
