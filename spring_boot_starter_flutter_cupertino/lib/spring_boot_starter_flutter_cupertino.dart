/// Cupertino for Spring Boot Flutter apps: a `CupertinoApp` set up by
/// properties, the themes of `spring.flutter.theme.*` as Cupertino's
/// `CupertinoThemeData`, and the iOS page route for the navigation
/// starter. Built on the Flutter team's `cupertino_ui`.
///
/// `spring_boot_starter_flutter` knows no design library; this package
/// adds Cupertino's. With it in the dependencies an app of type
/// `cupertino` needs no app widget of its own:
///
/// ```properties
/// # lib/resources/application.properties
/// spring.flutter.app.type=cupertino
/// spring.flutter.app.title=Counter
/// spring.flutter.theme.seed-color=teal
/// spring.flutter.theme.cupertino.bar-background-color=#F2F2F7
/// ```
///
/// ```dart
/// @SpringBootApplication()
/// void main() => runApp(
///   SpringApplicationWidget(
///     application: () => springApplication,
///     home: const CounterPage(),
///   ),
/// );
/// ```
///
/// The package brings and exports `spring_boot_starter_flutter` (and
/// through it `spring_boot_dart`), so an app depends on and imports only
/// this package, and `package:cupertino_ui/cupertino_ui.dart` for the
/// widgets.
library;

export 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

export 'src/cupertino_app_factory.dart';
export 'src/cupertino_design_controls.dart';
export 'src/cupertino_page_routes.dart';
export 'src/cupertino_theme_data.dart';
export 'src/cupertino_theme_design.dart';
export 'src/cupertino_themes.dart';
