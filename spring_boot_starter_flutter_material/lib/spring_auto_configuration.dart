/// The starter's auto-configuration, found by the code generator in every
/// application that depends on `spring_boot_starter_flutter_material`.
///
/// Applications do not import it: the generated `main.spring.dart` does
/// (the module below is marked `@AutoConfigurationModule()`). A test that
/// builds a context by hand imports it to name the module.
library;

import 'package:material_ui/material_ui.dart' show ThemeData;
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show DesignControls, DesignPageRoutes, SpringAppFactory, SpringThemes;
import 'package:spring_boot_starter_flutter_material/src/material_app_factory.dart';
import 'package:spring_boot_starter_flutter_material/src/material_design_controls.dart';
import 'package:spring_boot_starter_flutter_material/src/material_page_routes.dart';
import 'package:spring_boot_starter_flutter_material/src/material_theme_design.dart';
import 'package:spring_boot_starter_flutter_material/src/material_themes.dart';
import 'package:spring_boot_starter_flutter_material/src/theme_customizer.dart';

// The auto-configurations this starter builds on (the Flutter starter's,
// and through it logging and spring_boot_dart's), so a test of an
// application that lists only this starter can name them.
export 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';

const _source =
    'package:spring_boot_starter_flutter_material/spring_auto_configuration.dart';

/// What the starter adds to every Flutter application:
///
/// - Material Design for the themes of `spring.flutter.theme.*`
///   ([MaterialThemeDesign], among the module's factories: the themes are
///   read before any bean exists);
/// - the themes as Material's `ThemeData` (`materialThemes`), changed by
///   the `ThemeCustomizer` beans; a `ThemeData` bean named `theme` or
///   `darkTheme` replaces the made `light` or `dark` theme;
/// - the app widget of `spring.flutter.app.type: material`, a
///   `MaterialApp` (`materialAppFactory`);
/// - Material's page route and hero flights for the router of
///   `spring_boot_starter_flutter_navigation` (`materialPageRoutes`).
@AutoConfigurationModule(factories: [MaterialThemeDesign()])
final BeanModule springBootStarterFlutterMaterialAutoConfiguration = BeanModule(
  'springBootStarterFlutterMaterialAutoConfiguration',
  [
    BeanDefinition<MaterialThemes>(
      name: 'materialThemes',
      source: _source,
      create: (r) => MaterialThemes(
        r.dependency<SpringThemes>(),
        customizers: r.optionalDependencyList<ThemeCustomizer>() ?? const [],
        light: r.optionalDependency<ThemeData>(qualifier: 'theme'),
        dark: r.optionalDependency<ThemeData>(qualifier: 'darkTheme'),
      ),
    ),
    BeanDefinition<MaterialAppFactory>(
      name: 'materialAppFactory',
      types: const [MaterialAppFactory, SpringAppFactory],
      source: _source,
      create: (_) => const MaterialAppFactory(),
    ),
    BeanDefinition<MaterialDesignControls>(
      name: 'materialDesignControls',
      types: const [MaterialDesignControls, DesignControls],
      source: _source,
      create: (_) => const MaterialDesignControls(),
    ),
    BeanDefinition<MaterialPageRoutes>(
      name: 'materialPageRoutes',
      types: const [MaterialPageRoutes, DesignPageRoutes],
      source: _source,
      create: (_) => const MaterialPageRoutes(),
    ),
  ],
);
