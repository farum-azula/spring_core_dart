import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter/theme_design.dart';
import 'package:spring_boot_starter_flutter_material/spring_boot_starter_flutter_material.dart';

/// The designs of an app of type `material` with this starter alone.
const materialDesigns = ThemeDesigns(
  all: [MaterialThemeDesign()],
  appType: 'material',
);

/// The themes of [properties], read with Material's design.
SpringThemes themes(Map<String, String> properties) =>
    SpringThemes(properties, designs: materialDesigns);

/// Theme [name] of [properties], read with Material's design.
SpringThemeData theme(
  Map<String, String> properties, [
  String name = 'light',
]) => SpringThemeData.of(
  ThemeConfig(properties, designs: materialDesigns),
  name,
);

/// The `ThemeData` of the `light` theme of [properties].
ThemeData material(Map<String, String> properties) =>
    theme(properties).toMaterial();

/// Throws a [ThemePropertyException] whose key contains [key] and, when
/// given, whose expectation contains [expected].
Matcher invalid(String key, [String? expected]) => throwsA(
  isA<ThemePropertyException>()
      .having((e) => e.key, 'key', contains(key))
      .having(
        (e) => e.expected,
        'expected',
        expected == null ? anything : contains(expected),
      ),
);

/// A theme of [SpringThemes] as Material's `ThemeData`, with no
/// customizer.
extension MaterialOfThemes on SpringThemes {
  /// Theme [name] made Material.
  ThemeData material(String name) => data(name).toMaterial();
}
