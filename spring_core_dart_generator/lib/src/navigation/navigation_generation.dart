// spring_boot_starter_flutter_navigation's part of the module build: its
// `@ScreenRoute` and `@RouteShell` widgets, the module's `ScreenRoutes`
// bean, the constants of each screen, and the routes in the metadata.
import 'package:analyzer/dart/element/element.dart';
import 'package:code_builder/code_builder.dart';
import 'package:spring_core_dart_generator/src/core/module_emitter.dart';
import 'package:spring_core_dart_generator/src/core/spring_metadata.dart';
import 'package:spring_core_dart_generator/src/core/starter_generation.dart';
import 'package:spring_core_dart_generator/src/navigation/navigation_emitter.dart';
import 'package:spring_core_dart_generator/src/navigation/navigation_scanning.dart';

/// The part of `spring_boot_starter_flutter_navigation` in the module
/// build.
///
/// It scans the `@ScreenRoute` and `@RouteShell` widgets of each library;
/// the module gets the `ScreenRoutes` bean of its screens and shells, and
/// is followed by the constants of each screen (`extension BookPageRoute
/// on BookPage`). `spring_metadata.json` gets the `routes` and `shells`:
/// the editor completes paths with them, the site's build makes its pages
/// of them.
///
/// ```dart
/// // Output (in the module):
/// BeanDefinition<ScreenRoutes>(
///   name: r'screenRoutes#application',
///   create: (r) => ScreenRoutes.route(source: r'application')
///       .screen(r'/catalog/books/{isbn}', (r) => const BookPage(), ...)
///       .build(),
/// ),
/// ```
final class NavigationGeneration extends StarterGeneration {
  /// The part; it keeps no state of a build.
  const NavigationGeneration();

  @override
  String get package => 'spring_boot_starter_flutter_navigation';

  @override
  List<String> get markers => const ['@ScreenRoute', '@RouteShell'];

  @override
  void scanClass(ClassElement element, ModuleScan scan) => scan.collectErrors(
    () => scanNavigation(element, NavigationModuleModel.of(scan.module)),
  );

  @override
  Iterable<Expression> beanDefinitions(ModuleEmission emission) {
    final navigation = NavigationModuleModel.of(emission.module);
    return [
      if (navigation.screens.isNotEmpty || navigation.shells.isNotEmpty)
        NavigationEmitter(emission, navigation).screenRoutesDefinition(),
    ];
  }

  @override
  Iterable<Spec> declarations(ModuleEmission emission) {
    final navigation = NavigationModuleModel.of(emission.module);
    final emitter = NavigationEmitter(emission, navigation);
    return [
      for (final screen in navigation.screens)
        if (!screen.notFound) emitter.routeExtension(screen),
    ];
  }

  @override
  Future<Map<String, Object?>> metadata(MetadataBuild build) async {
    final navigation = NavigationModuleModel.of(build.module);
    final routes = [
      for (final screen in navigation.screens) screen.toMetadata(),
    ];
    final shells = [for (final shell in navigation.shells) shell.toMetadata()];
    return {
      if (routes.isNotEmpty)
        'routes': [
          for (final route
              in routes.toList()
                ..sort((a, b) => '${a['path']}'.compareTo('${b['path']}')))
            route,
        ],
      if (shells.isNotEmpty) 'shells': SpringMetadata.byName(shells, 'class'),
    };
  }
}
