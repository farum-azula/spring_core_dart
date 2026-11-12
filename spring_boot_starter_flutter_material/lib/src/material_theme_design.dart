import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter/theme_design.dart';
import 'package:spring_boot_starter_flutter_material/src/material_color_scheme.dart';
import 'package:spring_boot_starter_flutter_material/src/material_theme_data.dart';
import 'package:spring_boot_starter_flutter_material/src/theme_components.dart';

/// Material Design for the themes of `spring.flutter.theme.*`: the palette
/// Material 3 makes from `seed-color`, the properties only Material's
/// widgets have (`components.*`, `visual-density`, `tap-target-size`, the
/// ink `splash`) and the `zoom` page transition.
///
/// The starter lists it among the factories of its module, so an
/// application that depends on the starter reads its themes with it; a
/// test passes it to its themes:
///
/// ```dart
/// final themes = SpringThemes(
///   {'seed-color': 'teal', 'components.card.elevation': '2'},
///   designs: const ThemeDesigns(
///     all: [MaterialThemeDesign()],
///     appType: 'material',
///   ),
/// );
/// ```
final class MaterialThemeDesign implements ThemeDesign {
  /// The design.
  const MaterialThemeDesign();

  /// `material`, the `spring.flutter.app.type` of a `MaterialApp`.
  static const typeName = 'material';

  @override
  String get appType => typeName;

  @override
  List<String> get themeProperties => const [
    'components',
    'visual-density',
    'tap-target-size',
    'splash',
  ];

  @override
  List<String> get schemeVariants => [
    for (final variant in DynamicSchemeVariant.values) variant.name,
  ];

  @override
  SpringColorScheme colorScheme(ColorSchemeSpec spec) =>
      MaterialColorSchemes.fromSeed(spec).toSpring();

  @override
  PageTransitionsBuilder? pageTransition(PageTransitionType type) =>
      _pageTransitions[type];

  static const _pageTransitions = <PageTransitionType, PageTransitionsBuilder>{
    PageTransitionType.zoom: ZoomPageTransitionsBuilder(),
  };

  @override
  void check(SpringThemeData theme) {
    theme
      ..visualDensity
      ..tapTargetSize
      ..splashFactory;
    final properties = theme.properties;
    for (final component in properties.children('components')) {
      if (!themeComponents.containsKey(component)) {
        throw ThemePropertyException(
          properties.propertyName('components.$component'),
          '',
          'a component: ${themeComponentNames.join(', ')}'
              '${didYouMean(component, themeComponentNames)}',
        );
      }
    }
    // Checks every component value now, not when a widget needs it.
    theme.toMaterial();
  }
}
