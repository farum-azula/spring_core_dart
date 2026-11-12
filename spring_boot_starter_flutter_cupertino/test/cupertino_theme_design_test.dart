// The Cupertino design of the themes: its properties, its page
// transition, and the palette of a seed color, which is the one Material's
// ColorScheme.fromSeed gives.
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart'
    show ColorScheme, DynamicSchemeVariant;
import 'package:spring_boot_starter_flutter_cupertino/spring_boot_starter_flutter_cupertino.dart';

import 'support/themes.dart';

// Every role of Material's scheme, by the name a theme gives it.
Map<String, Color> rolesOf(ColorScheme scheme) => {
  'primary': scheme.primary,
  'onprimary': scheme.onPrimary,
  'primarycontainer': scheme.primaryContainer,
  'onprimarycontainer': scheme.onPrimaryContainer,
  'primaryfixed': scheme.primaryFixed,
  'primaryfixeddim': scheme.primaryFixedDim,
  'onprimaryfixed': scheme.onPrimaryFixed,
  'onprimaryfixedvariant': scheme.onPrimaryFixedVariant,
  'secondary': scheme.secondary,
  'onsecondary': scheme.onSecondary,
  'secondarycontainer': scheme.secondaryContainer,
  'onsecondarycontainer': scheme.onSecondaryContainer,
  'secondaryfixed': scheme.secondaryFixed,
  'secondaryfixeddim': scheme.secondaryFixedDim,
  'onsecondaryfixed': scheme.onSecondaryFixed,
  'onsecondaryfixedvariant': scheme.onSecondaryFixedVariant,
  'tertiary': scheme.tertiary,
  'ontertiary': scheme.onTertiary,
  'tertiarycontainer': scheme.tertiaryContainer,
  'ontertiarycontainer': scheme.onTertiaryContainer,
  'tertiaryfixed': scheme.tertiaryFixed,
  'tertiaryfixeddim': scheme.tertiaryFixedDim,
  'ontertiaryfixed': scheme.onTertiaryFixed,
  'ontertiaryfixedvariant': scheme.onTertiaryFixedVariant,
  'error': scheme.error,
  'onerror': scheme.onError,
  'errorcontainer': scheme.errorContainer,
  'onerrorcontainer': scheme.onErrorContainer,
  'surface': scheme.surface,
  'onsurface': scheme.onSurface,
  'onsurfacevariant': scheme.onSurfaceVariant,
  'surfacedim': scheme.surfaceDim,
  'surfacebright': scheme.surfaceBright,
  'surfacecontainerlowest': scheme.surfaceContainerLowest,
  'surfacecontainerlow': scheme.surfaceContainerLow,
  'surfacecontainer': scheme.surfaceContainer,
  'surfacecontainerhigh': scheme.surfaceContainerHigh,
  'surfacecontainerhighest': scheme.surfaceContainerHighest,
  'surfacetint': scheme.surfaceTint,
  'inversesurface': scheme.inverseSurface,
  'oninversesurface': scheme.onInverseSurface,
  'inverseprimary': scheme.inversePrimary,
  'outline': scheme.outline,
  'outlinevariant': scheme.outlineVariant,
  'shadow': scheme.shadow,
  'scrim': scheme.scrim,
};

void main() {
  const design = CupertinoThemeDesign();

  test('the app type, the property and the variants it reads', () {
    expect(design.appType, 'cupertino');
    expect(design.themeProperties, ['cupertino']);
    expect(design.schemeVariants, [
      for (final variant in DynamicSchemeVariant.values) variant.name,
    ]);
    expect(design.schemeVariants, [
      'tonalSpot',
      'fidelity',
      'monochrome',
      'neutral',
      'vibrant',
      'expressive',
      'content',
      'rainbow',
      'fruitSalad',
    ]);
  });

  group('the palette of a seed', () {
    const seeds = <Color?>[
      null,
      Color(0xFF6750A4),
      Color(0xFF009688),
      Color(0xFFFF5722),
      Color(0xFF0057B8),
      Color(0xFF000000),
      Color(0xFFFFFFFF),
      Color(0xFF7CB342),
    ];

    test('has the 46 roles of ColorScheme.fromSeed, for every seed, '
        'brightness, variant and contrast', () {
      for (final seed in seeds) {
        for (final brightness in Brightness.values) {
          for (final variant in DynamicSchemeVariant.values) {
            for (final contrast in const [-1.0, 0.0, 0.5, 1.0]) {
              final own = design.colorScheme(
                ColorSchemeSpec(
                  brightness: brightness,
                  seedColor: seed,
                  schemeVariant: variant.name,
                  contrast: contrast,
                ),
              );
              final material = ColorScheme.fromSeed(
                seedColor: seed ?? const Color(0xFF6750A4),
                brightness: brightness,
                dynamicSchemeVariant: variant,
                contrastLevel: contrast,
              );
              final where =
                  '$seed ${brightness.name} ${variant.name} $contrast';
              expect(own.brightness, brightness, reason: where);
              expect(own.roles.keys, colorRoles, reason: where);
              expect(own.roles, rolesOf(material), reason: where);
            }
          }
        }
      }
    });

    test('tonalSpot at contrast 0 when the theme sets neither', () {
      for (final brightness in Brightness.values) {
        expect(
          design
              .colorScheme(
                ColorSchemeSpec(
                  brightness: brightness,
                  seedColor: const Color(0xFF009688),
                ),
              )
              .roles,
          rolesOf(
            ColorScheme.fromSeed(
              seedColor: const Color(0xFF009688),
              brightness: brightness,
            ),
          ),
        );
      }
    });

    test('a variant in any spelling; an unknown one is refused', () {
      ColorSchemeSpec spec(String variant) => ColorSchemeSpec(
        brightness: Brightness.light,
        seedColor: const Color(0xFF009688),
        schemeVariant: variant,
      );
      expect(
        design.colorScheme(spec('fruit-salad')),
        design.colorScheme(spec('fruitSalad')),
      );
      expect(() => design.colorScheme(spec('pastel')), throwsArgumentError);
    });

    test('is the palette of a theme with a seed color', () {
      final t = theme({
        'seed-color': '#009688',
        'scheme-variant': 'vibrant',
        'contrast': '0.5',
        'colors.primary': '#111111',
      }, name: 'dark');
      final material = ColorScheme.fromSeed(
        seedColor: const Color(0xFF009688),
        brightness: Brightness.dark,
        dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
        contrastLevel: 0.5,
      );
      expect(t.schemeVariant, 'vibrant');
      expect(t.colorScheme.secondary, material.secondary);
      expect(t.colorScheme.surfaceContainer, material.surfaceContainer);
      // The explicit role wins.
      expect(t.colorScheme.primary, const Color(0xFF111111));
    });

    test('every variant and a contrast, without a seed', () {
      for (final variant in DynamicSchemeVariant.values) {
        expect(
          theme({
            'scheme-variant': variant.name,
            'contrast': '0.5',
          }).colorScheme.primary,
          ColorScheme.fromSeed(
            seedColor: const Color(0xFF6750A4),
            dynamicSchemeVariant: variant,
            contrastLevel: 0.5,
          ).primary,
          reason: variant.name,
        );
      }
    });

    test('a theme without seed, variant or contrast keeps the baseline', () {
      expect(
        theme(const {}).colorScheme,
        SpringColorScheme.baseline(Brightness.light),
      );
    });
  });

  group('page transition', () {
    test('cupertino is the design\'s; the others are not', () {
      expect(
        design.pageTransition(PageTransitionType.cupertino),
        isA<CupertinoPageTransitionsBuilder>(),
      );
      for (final type in PageTransitionType.values) {
        if (type != PageTransitionType.cupertino) {
          expect(design.pageTransition(type), isNull, reason: type.name);
        }
      }
    });

    test('motion.page-transition: cupertino is the iOS slide', () {
      expect(
        theme({'motion.page-transition': 'cupertino'}).pageTransition,
        isA<CupertinoPageTransitionsBuilder>(),
      );
    });

    test('without the design the transition names its starter', () {
      expect(
        () => SpringThemes(const {'motion.page-transition': 'cupertino'}),
        throwsA(
          isA<ThemePropertyException>().having(
            (e) => e.expected,
            'expected',
            contains('spring_boot_starter_flutter_cupertino'),
          ),
        ),
      );
    });
  });

  test('check reads the theme\'s cupertino properties', () {
    expect(
      () => theme({'cupertino.primary-color': 'no color'}),
      invalid('cupertino.primarycolor'),
    );
  });
}
