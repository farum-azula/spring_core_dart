/// Material Design for Spring Boot Flutter apps, on the Flutter team's
/// `material_ui`: a `MaterialApp` set up by properties, the themes of
/// `spring.flutter.theme.*` as Material's `ThemeData` with its component
/// themes (`components.*`), and palettes made from a seed color.
///
/// `spring_boot_starter_flutter` itself knows no design library. With this
/// starter in the dependencies, `spring.flutter.app.type: material` shows a
/// `MaterialApp`:
///
/// ```yaml
/// # lib/resources/application.yml
/// spring.flutter:
///   app.type: material
///   theme:
///     seed-color: deepPurple
///     components.card: { elevation: 2, shape: large }
/// ```
///
/// ```dart
/// @SpringBootApplication()
/// void main() => runApp(
///   SpringApplicationWidget(
///     application: () => springApplication,
///     home: const HomePage(),
///   ),
/// );
/// ```
///
/// Widgets read Material's theme as always (`Theme.of(context)`); the
/// `MaterialThemes` bean has every theme as a `ThemeData`, and a
/// `ThemeCustomizer` bean changes them in code.
///
/// The package brings and exports `spring_boot_starter_flutter` (and
/// through it `spring_boot_dart`), so an app depends on and imports only
/// this package, next to `material_ui` for the widgets.
library;

export 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

export 'src/material_app_factory.dart';
export 'src/material_color_scheme.dart';
export 'src/material_design_controls.dart';
export 'src/material_page_routes.dart';
export 'src/material_text_theme.dart';
export 'src/material_theme_data.dart';
export 'src/material_theme_design.dart';
export 'src/material_theme_reader.dart';
export 'src/material_themes.dart';
export 'src/spring_theme_extension.dart';
export 'src/theme_components.dart'
    show ThemeComponent, themeComponentNames, themeComponents;
export 'src/theme_customizer.dart';
