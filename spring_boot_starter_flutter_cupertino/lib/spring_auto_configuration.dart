/// The starter's auto-configuration, found by the code generator in every
/// application that depends on `spring_boot_starter_flutter_cupertino`.
///
/// Applications do not import it: the generated `main.spring.dart` does
/// (the module below is marked `@AutoConfigurationModule()`). A test that
/// builds a context by hand imports it to name the module.
library;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoThemeData;
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show DesignControls, DesignPageRoutes, SpringAppFactory, SpringThemes;
import 'package:spring_boot_starter_flutter_cupertino/src/cupertino_app_factory.dart';
import 'package:spring_boot_starter_flutter_cupertino/src/cupertino_design_controls.dart';
import 'package:spring_boot_starter_flutter_cupertino/src/cupertino_page_routes.dart';
import 'package:spring_boot_starter_flutter_cupertino/src/cupertino_theme_design.dart';
import 'package:spring_boot_starter_flutter_cupertino/src/cupertino_themes.dart';

// The auto-configurations this starter builds on (the Flutter starter's,
// and through it logging and spring_boot_dart's), so a test of an
// application that lists only this starter can name them.
export 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';

const _source =
    'package:spring_boot_starter_flutter_cupertino/spring_auto_configuration.dart';

/// The beans the starter adds to every Flutter application that depends
/// on it:
///
/// - the themes as Cupertino's `CupertinoThemeData` (`cupertinoThemes`):
///   those of `spring.flutter.theme.*`, or the application's own
///   `CupertinoThemeData` bean, changed by the `CupertinoThemeCustomizer`
///   beans;
/// - the app widget of `spring.flutter.app.type: cupertino`
///   (`cupertinoAppFactory`), a `CupertinoApp`;
/// - Cupertino's page route and hero flights for the router of the
///   navigation starter (`cupertinoPageRoutes`).
///
/// Before the beans, the module's factories give the themes their
/// Cupertino part ([CupertinoThemeDesign]): the `cupertino.*` properties,
/// the palette of a seed color, the iOS page transition. A test that
/// builds an application by hand names them with the module:
///
/// ```dart
/// SpringApplication(
///   [appBeans],
///   autoConfigurations: [
///     springBootStarterFlutterAutoConfiguration,
///     springBootStarterFlutterCupertinoAutoConfiguration,
///   ],
///   autoConfigurationMetadata: {
///     springBootStarterFlutterCupertinoAutoConfiguration:
///         const AutoConfigurationModule(factories: [CupertinoThemeDesign()]),
///   },
/// );
/// ```
@AutoConfigurationModule(factories: [CupertinoThemeDesign()])
final BeanModule springBootStarterFlutterCupertinoAutoConfiguration =
    BeanModule('springBootStarterFlutterCupertinoAutoConfiguration', [
      BeanDefinition<CupertinoThemes>(
        name: 'cupertinoThemes',
        types: const [CupertinoThemes],
        source: _source,
        create: (r) => CupertinoThemes(
          r.dependency<SpringThemes>(),
          customizers:
              r.optionalDependencyList<CupertinoThemeCustomizer>() ?? const [],
          theme: r.optionalDependency<CupertinoThemeData>(),
        ),
      ),
      BeanDefinition<CupertinoAppFactory>(
        name: 'cupertinoAppFactory',
        types: const [CupertinoAppFactory, SpringAppFactory],
        source: _source,
        create: (_) => const CupertinoAppFactory(),
      ),
      BeanDefinition<CupertinoDesignControls>(
        name: 'cupertinoDesignControls',
        types: const [CupertinoDesignControls, DesignControls],
        source: _source,
        create: (_) => const CupertinoDesignControls(),
      ),
      BeanDefinition<CupertinoPageRoutes>(
        name: 'cupertinoPageRoutes',
        types: const [CupertinoPageRoutes, DesignPageRoutes],
        source: _source,
        create: (_) => const CupertinoPageRoutes(),
      ),
    ]);
