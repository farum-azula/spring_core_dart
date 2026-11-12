import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter_material/src/material_theme_data.dart';
import 'package:spring_boot_starter_flutter_material/src/theme_customizer.dart';

/// The app's themes as Material's `ThemeData`: each theme of
/// `spring.flutter.theme.*` made Material, then changed by the
/// [ThemeCustomizer] beans.
///
/// The `MaterialApp` the starter builds shows these. Inject the bean for a
/// `MaterialApp` of your own, or to show a part of the UI in another theme:
///
/// ```dart
/// // A preview of every theme in a settings page.
/// class ThemePreviews extends SpringStatelessWidget<(MaterialThemes,)> {
///   const ThemePreviews({super.key});
///
///   @override
///   Widget build(BuildContext context) {
///     final (material,) = beans;
///     return Row(
///       children: [
///         for (final name in material.themes.names)
///           Theme(data: material.theme(name), child: const PreviewCard()),
///       ],
///     );
///   }
/// }
/// ```
///
/// A `ThemeData` bean named `theme` replaces the made `light` theme, one
/// named `darkTheme` the `dark` one; the customizers change those too.
final class MaterialThemes {
  /// The Material themes of [themes], each changed by [customizers] in
  /// order. [light] and [dark] replace the made `light` and `dark` themes;
  /// the starter passes the `ThemeData` beans named `theme` and
  /// `darkTheme` here.
  MaterialThemes(
    this.themes, {
    this.customizers = const [],
    ThemeData? light,
    ThemeData? dark,
  }) : _replacing = {'light': ?light, 'dark': ?dark};

  /// The Material themes of [context]: its bean, else, for a context
  /// without the starter's auto-configuration (in a test), ones made once
  /// from `SpringThemes.of(context)`, with no customizer.
  static MaterialThemes of(ApplicationContext context) =>
      context.getBeansOfType<MaterialThemes>().values.firstOrNull ??
      (_made[context] ??= MaterialThemes(SpringThemes.of(context)));

  static final _made = Expando<MaterialThemes>('MaterialThemes');

  /// The themes as read from the properties.
  final SpringThemes themes;

  /// The customizers applied to every theme, in order.
  final List<ThemeCustomizer> customizers;

  final Map<String, ThemeData> _replacing;

  // By theme as read, not by name: themes loaded at run time
  // (`SpringThemes.load`) are other objects under the same names.
  final _material = Expando<ThemeData>('MaterialThemes.theme');

  /// Theme [name] as Material's `ThemeData` ([material] of the theme as
  /// read). Throws an `ArgumentError` for an unknown name.
  ThemeData theme(String name) => material(themes.data(name));

  /// [spring] as Material's `ThemeData`: the one made from the properties
  /// (or the replacing one, for `light` and `dark`), then changed by the
  /// customizers; made once per theme read.
  ThemeData material(SpringThemeData spring) =>
      _material[spring] ??= customizers.fold<ThemeData>(
        _replacing[spring.name] ?? spring.toMaterial(),
        (theme, customizer) => customizer.customize(theme, spring),
      );
}
