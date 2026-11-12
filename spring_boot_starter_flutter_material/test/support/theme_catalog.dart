import 'package:spring_boot_starter_flutter/theme_design.dart';
import 'package:spring_boot_starter_flutter_material/spring_boot_starter_flutter_material.dart';

import 'themes.dart';

/// The properties every component of the theme reads, by component name
/// in kebab case, in the order of the reference: found by running each
/// component's mapping over an empty theme, so the list is the mapping
/// itself.
Map<String, List<ThemeProperty>> themeCatalog() {
  final spring = theme(const {});
  final material = spring.toMaterial();
  final properties = ThemeProperties('light', const {});
  ThemeReader reader(ThemeComponent component) => ThemeReader(
    theme: spring,
    properties: properties,
    root: 'components.${ThemeValues.canonical(component.name)}',
    label: component.name,
    namedStyle: spring.textStyle,
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
  };
}
