import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter/theme_design.dart';

/// Changes, in code, every Material `ThemeData` made from the theme
/// properties: for what the properties do not cover.
///
/// The properties set colors, typography, shapes and a list of components;
/// a customizer can change anything else on the `ThemeData` (a component
/// the properties do not know, a value computed from others). Declare a
/// bean that implements it; every customizer runs, in `@Order`, on each
/// theme when it is first made, also on a `ThemeData` bean named `theme`
/// or `darkTheme` that replaces the made `light` or `dark` theme.
///
/// ```dart
/// // Stadium-shaped chips in every theme.
/// @Component()
/// class RoundedChips implements ThemeCustomizer {
///   @override
///   ThemeData customize(ThemeData theme, SpringThemeData spring) =>
///       theme.copyWith(
///         chipTheme: theme.chipTheme.copyWith(shape: const StadiumBorder()),
///       );
/// }
/// ```
///
/// Spring Boot (Java) adjusts its auto-configured objects the same way,
/// for example with a `Jackson2ObjectMapperBuilderCustomizer` bean.
abstract interface class ThemeCustomizer {
  /// Returns [theme] changed, usually with `copyWith`. [theme] was made
  /// from [spring], whose name, palette and tokens the change may depend
  /// on.
  ThemeData customize(ThemeData theme, SpringThemeData spring);
}
