import 'package:spring_boot_starter_flutter/theme_design.dart';

import 'designs.dart';

/// The properties every component of the theme reads, by component name
/// in kebab case, in the order of the reference (`cupertino` last):
/// found by running each component's mapping of the Material starter over
/// an empty theme, so the list is the mapping itself, then what the
/// Cupertino starter reads under `cupertino`. The reference in
/// `docs/configuration.md` is generated from it
/// (`theme_reference_test.dart`).
Map<String, List<ThemeProperty>> themeCatalog() {
  final theme = SpringThemeData.of(
    ThemeConfig(const {}, designs: testDesigns),
    'light',
  );
  final material = theme.toMaterial();
  final properties = ThemeProperties('light', const {});
  ThemeReader reader(ThemeComponent component) => ThemeReader(
    theme: theme,
    properties: properties,
    root: 'components.${ThemeValues.canonical(component.name)}',
    label: component.name,
    namedStyle: theme.textStyle,
    shapeToken: component.shapeToken,
    topShape: component.topShape,
  );
  ThemeReader other(String name) =>
      reader(themeComponents[ThemeValues.canonical(name)]!);
  return {
    for (final component in themeComponents.values)
      component.name: (() {
        final r = reader(component);
        component.apply(material, r, other);
        return r.asked;
      })(),
    'cupertino': theme.cupertinoProperties,
  };
}
