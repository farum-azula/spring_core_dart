// The design the themes are read with: what it reads, the palettes and
// page transitions it makes, and what it checks at the start.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter/theme_design.dart';
import 'package:spring_boot_starter_flutter_material/spring_boot_starter_flutter_material.dart';

import 'support/color_roles.dart';
import 'support/themes.dart';

void main() {
  const design = MaterialThemeDesign();

  test('the app type, the properties and the variants it reads', () {
    expect(design.appType, 'material');
    expect(design.themeProperties, [
      'components',
      'visual-density',
      'tap-target-size',
      'splash',
    ]);
    expect(design.schemeVariants, [
      for (final variant in DynamicSchemeVariant.values) variant.name,
    ]);
    expect(materialDesigns.own, same(design));
    expect(materialDesigns.reads('visualDensity'), isTrue);
    expect(materialDesigns.schemeVariant('tonal-spot'), 'tonalSpot');
  });

  test('colorScheme: ColorScheme.fromSeed, with its defaults', () {
    Map<String, Color> roles(ColorScheme scheme) => {
      for (final MapEntry(:key, :value) in roleColors(scheme).entries)
        key.toLowerCase(): value,
    };
    expect(
      design
          .colorScheme(const ColorSchemeSpec(brightness: Brightness.dark))
          .roles,
      roles(
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
      ),
    );
    final spec = design.colorScheme(
      const ColorSchemeSpec(
        brightness: Brightness.light,
        seedColor: Color(0xFF00897B),
        schemeVariant: 'fidelity',
        contrast: -0.5,
      ),
    );
    expect(spec.brightness, Brightness.light);
    expect(
      spec.roles,
      roles(
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF00897B),
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
          contrastLevel: -0.5,
        ),
      ),
    );
  });

  test('pageTransition: zoom is Material\'s, the others are not', () {
    expect(
      design.pageTransition(PageTransitionType.zoom),
      isA<ZoomPageTransitionsBuilder>(),
    );
    for (final type in PageTransitionType.values) {
      if (type != PageTransitionType.zoom) {
        expect(design.pageTransition(type), isNull, reason: type.name);
      }
    }
    expect(
      theme(const {'motion.page-transition': 'zoom'}).pageTransition,
      isA<ZoomPageTransitionsBuilder>(),
    );
  });

  group('check', () {
    test('an unknown component names the known ones', () {
      expect(
        () => theme(const {'components.carrd.shape': 'large'}),
        throwsA(
          isA<ThemePropertyException>()
              .having(
                (e) => e.key,
                'key',
                'spring.flutter.theme.components.carrd (theme light)',
              )
              .having((e) => e.value, 'value', '')
              .having(
                (e) => e.expected,
                'expected',
                'a component: ${themeComponentNames.join(', ')}'
                    " (did you mean 'card'?)",
              ),
        ),
      );
    });

    test('every value is read at the start, the design\'s own too', () {
      expect(
        () => theme(const {'visual-density': 'tight'}),
        invalid('visualdensity', 'adaptive, standard, comfortable or compact'),
      );
      expect(
        () => theme(const {'tap-target-size': 'big'}),
        invalid('taptargetsize', 'padded or shrinkWrap'),
      );
      expect(
        () => theme(const {'splash': 'wave'}),
        invalid('splash', 'ripple, sparkle or none'),
      );
      expect(
        () => theme(const {'components.slider.track-height': 'thick'}),
        invalid('components.slider.trackheight'),
      );
    });

    test('in an app of another type the Material theme is checked too', () {
      const widgets = ThemeDesigns(all: [MaterialThemeDesign()]);
      expect(widgets.own, isNull);
      expect(
        () => SpringThemes(const {
          'components.card.colour': 'x',
        }, designs: widgets),
        throwsA(isA<ThemePropertyException>()),
      );
      final seeded = SpringThemes(const {
        'seed-color': 'teal',
      }, designs: widgets).data('light');
      expect(
        seeded.colorScheme.primary,
        ColorScheme.fromSeed(seedColor: Colors.teal).primary,
      );
    });
  });

  group('the properties of Material alone', () {
    test('read from the theme: density, tap targets, ink splash', () {
      final spring = theme(const {
        'visual-density': 'comfortable',
        'tap-target-size': 'shrink-wrap',
        'splash': 'sparkle',
      });
      expect(spring.visualDensity, VisualDensity.comfortable);
      expect(spring.tapTargetSize, MaterialTapTargetSize.shrinkWrap);
      expect(spring.splashFactory, InkSparkle.splashFactory);
      final none = theme(const {});
      expect(none.visualDensity, isNull);
      expect(none.tapTargetSize, isNull);
      expect(none.splashFactory, isNull);
    });

    test('a splash map is the splash of the start, not the ink\'s', () {
      final spring = theme(const {'splash.background': '#101010'});
      expect(spring.splash, isNotNull);
      expect(spring.splashFactory, isNull);
      expect(
        spring.toMaterial().splashFactory,
        ThemeData().splashFactory,
      );
    });

    test('a background shows through the scaffolds', () {
      expect(
        theme(const {'background.color': '#101010'})
            .toMaterial()
            .scaffoldBackgroundColor,
        Colors.transparent,
      );
      expect(
        theme(const {}).toMaterial().scaffoldBackgroundColor,
        ThemeData().scaffoldBackgroundColor,
      );
    });
  });

  group('the reader of Material\'s values', () {
    ThemeReader reader(Map<String, String> properties) {
      final spring = theme(const {});
      return ThemeReader(
        theme: spring,
        properties: ThemeProperties('light', {
          for (final MapEntry(:key, :value) in properties.entries)
            'components.card.$key': value,
        }),
        root: 'components.card',
        label: 'card',
        namedStyle: spring.textStyle,
      );
    }

    test('density: a name or two numbers', () {
      expect(
        reader({'visualdensity': 'compact'}).density('visualDensity'),
        VisualDensity.compact,
      );
      expect(
        reader({'visualdensity': '-1, -2'}).density('visualDensity'),
        const VisualDensity(horizontal: -1, vertical: -2),
      );
      expect(reader(const {}).density('visualDensity'), isNull);
      expect(
        () => reader({'visualdensity': 'airy'}).density('visualDensity'),
        invalid('visualdensity', "'horizontal, vertical'"),
      );
    });

    test('inputBorder: a kind, or a map of type, radius and side', () {
      expect(
        reader({'border': 'outline'}).inputBorder('border'),
        isA<OutlineInputBorder>(),
      );
      expect(
        reader({'border': 'underline'}).inputBorder('border'),
        isA<UnderlineInputBorder>(),
      );
      expect(
        reader({'border': 'none'}).inputBorder('border'),
        InputBorder.none,
      );
      final mapped =
          reader({
                'border.type': 'outline',
                'border.radius': '12',
                'border.side.color': '#FF0000',
                'border.side.width': '2',
              }).inputBorder('border')!
              as OutlineInputBorder;
      expect(mapped.borderRadius, BorderRadius.circular(12));
      expect(mapped.borderSide.color, const Color(0xFFFF0000));
      expect(mapped.borderSide.width, 2);
      expect(
        () => reader({'border': 'wavy'}).inputBorder('border'),
        invalid('border', 'outline, underline or none'),
      );
      expect(
        () => reader({'border.kind': 'outline'}).inputBorder('border'),
        invalid('border.kind', 'a key of an input border'),
      );
    });

    test('splash: ripple, sparkle or none', () {
      expect(
        reader({'splashfactory': 'ripple'}).splash('splashFactory'),
        InkRipple.splashFactory,
      );
      expect(
        reader({'splashfactory': 'none'}).splash('splashFactory'),
        NoSplash.splashFactory,
      );
      expect(
        () => reader({'splashfactory': 'wave'}).splash('splashFactory'),
        invalid('splashfactory', 'ripple, sparkle or none'),
      );
    });

    test('they list themselves among the properties asked for', () {
      final r = reader(const {});
      r
        ..density('visualDensity')
        ..inputBorder('border')
        ..splash('splashFactory');
      expect(
        [for (final property in r.asked) (property.name, property.kind)],
        [
          ('visual-density', 'visual density'),
          ('border', 'input border'),
          ('splash-factory', 'one of: ripple | sparkle | none'),
        ],
      );
    });
  });
}
