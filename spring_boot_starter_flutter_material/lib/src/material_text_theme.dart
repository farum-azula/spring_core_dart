import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter/theme_design.dart';

/// The styles of Material's `TextTheme` by the names the theme properties
/// use for them.
extension TextThemeStyles on TextTheme {
  /// The style called [name] in any spelling (`titleLarge`,
  /// `title-large`); `null` when [name] is none of the 15 or the text
  /// theme has no such style.
  TextStyle? styleNamed(String name) => switch (ThemeValues.canonical(name)) {
    'displaylarge' => displayLarge,
    'displaymedium' => displayMedium,
    'displaysmall' => displaySmall,
    'headlinelarge' => headlineLarge,
    'headlinemedium' => headlineMedium,
    'headlinesmall' => headlineSmall,
    'titlelarge' => titleLarge,
    'titlemedium' => titleMedium,
    'titlesmall' => titleSmall,
    'bodylarge' => bodyLarge,
    'bodymedium' => bodyMedium,
    'bodysmall' => bodySmall,
    'labellarge' => labelLarge,
    'labelmedium' => labelMedium,
    'labelsmall' => labelSmall,
    _ => null,
  };
}
