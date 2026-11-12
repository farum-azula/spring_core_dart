/// What a design library reads the themes of `spring.flutter.theme.*`
/// with: the properties of a theme, the reader of typed values, the scales
/// and the names of the text styles.
///
/// For the author of a `ThemeDesign` (the Material and Cupertino starters
/// are two); an application needs `spring_boot_starter_flutter.dart` only.
library;

export 'src/theme/spring_color_scheme.dart';
export 'src/theme/spring_theme_data.dart';
export 'src/theme/spring_type_scale.dart';
export 'src/theme/theme_animation.dart' show PageTransitionType;
export 'src/theme/theme_config.dart';
export 'src/theme/theme_design.dart';
export 'src/theme/theme_reader.dart';
export 'src/theme/theme_values.dart';
