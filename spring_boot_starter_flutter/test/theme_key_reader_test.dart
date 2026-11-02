// ThemeKeyReader: what the generated context.theme (lib/spring_keys.dart)
// reads, live from the theme shown now.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

void main() {
  final themes = SpringThemes({
    'colors.surface-container-low': '#112233',
    'spacing.gutter': '20',
    'typography.code.size': '13',
    'tokens.brand.accent': '#FF6B00',
    'tokens.brand.hero-height': '240',
    'tokens.brand.name': 'Neon',
    'themes.ocean.colors.surface-container-low': '#445566',
    'themes.ocean.tokens.brand.accent': '#00BFA5',
    'themes.ocean.spacing.gutter': '24',
  });

  test('reads colors, spacing, text styles and tokens by their keys', () {
    final reader = ThemeKeyReader(themes.data('light'));
    expect(reader.color('surface-container-low'), const Color(0xFF112233));
    expect(reader.color('surfaceContainerLow'), const Color(0xFF112233));
    expect(reader.spacing('gutter'), 20);
    expect(reader.textStyle('code').fontSize, 13);
    expect(reader.tokenColor('brand.accent'), const Color(0xFFFF6B00));
    expect(reader.tokenNumber('brand.hero-height'), 240);
    expect(reader.token('brand.name'), 'Neon');
  });

  test('a role the theme does not declare is the Material one', () {
    final reader = ThemeKeyReader(themes.data('light'));
    expect(reader.color('primary'), themes.data('light').colorScheme.primary);
  });

  test('a missing color or token throws a StateError naming the key', () {
    final reader = ThemeKeyReader(themes.data('ocean'));
    expect(() => reader.color('promo'), throwsStateError);
    expect(
      () => reader.tokenColor('brand.missing'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('ocean'), contains('brand.missing')),
        ),
      ),
    );
  });

  testWidgets('a getter on the context follows the active theme', (
    tester,
  ) async {
    final selection = ThemeSelection(themes);
    addTearDown(selection.dispose);
    final seen = <(Color, double)>[];
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: selection,
        builder: (context, _) => SpringTheme(
          data: themes.data(
            selection.active == 'system' ? 'light' : selection.active,
          ),
          child: Builder(
            builder: (context) {
              final reader = ThemeKeyReader(SpringTheme.of(context));
              seen.add((
                reader.tokenColor('brand.accent'),
                reader.spacing('gutter'),
              ));
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(seen.last, (const Color(0xFFFF6B00), 20.0));

    selection.select('ocean');
    await tester.pump();
    expect(seen.last, (const Color(0xFF00BFA5), 24.0));
  });
}
