/// The starter's auto-configuration, found by the code generator in every
/// application that depends on `spring_boot_starter_flutter_navigation`.
///
/// Applications do not import it: the generated `main.spring.dart` does
/// (the module below is marked `@AutoConfigurationModule()`). A test that
/// builds a context by hand imports it to name the module.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show RouterConfig;
import 'package:flutter_web_plugins/url_strategy.dart' show usePathUrlStrategy;
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show FlutterAppCustomizer;
import 'package:spring_boot_starter_flutter_navigation/src/navigation.dart';
import 'package:spring_boot_starter_flutter_navigation/src/properties/navigation_properties.dart';
import 'package:spring_boot_starter_flutter_navigation/src/properties/properties_beans.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_language.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_location.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_scopes.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_table.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_template.dart';
import 'package:spring_boot_starter_flutter_navigation/src/screen_mappings.dart';
import 'package:spring_boot_starter_flutter_navigation/src/screen_routes.dart';
import 'package:spring_boot_starter_flutter_navigation/src/spring_router.dart';
import 'package:spring_web_dart/spring_web_dart.dart' show MappingDescriptions;

// The auto-configurations this starter builds on (the Flutter starter's,
// and through it logging and spring_boot_dart's), so a test of an
// application that lists only this starter can name them.
export 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';

const _source =
    'package:spring_boot_starter_flutter_navigation/spring_auto_configuration.dart';
const _log = SpringLog('spring.flutter.navigation');

/// Registers the `route` and `branch` scopes before any bean is made, and
/// their holder as the singleton `routeScopes`.
final class NavigationScopesRegistrar implements BeanFactoryPostProcessor {
  /// The registrar.
  const NavigationScopesRegistrar();

  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {
    final scopes = RouteScopes();
    beanFactory
      ..registerScope(NavigationScopes.route, scopes.route)
      ..registerScope(NavigationScopes.branch, scopes.branch)
      ..registerSingleton('routeScopes', scopes, types: const [RouteScopes]);
  }
}

/// The beans the starter adds to every Flutter application with screens
/// (a `ScreenRoutes` bean; the annotated screens make one):
///
/// - the `route` and `branch` scopes (`NavigationScopesRegistrar`);
/// - the `navigation`: every `ScreenRoutes` bean (the annotated screens
///   are one) put together and checked at the start, the `RouteFilter`
///   beans, the redirects and first address of `spring.flutter.navigation.*`;
/// - the `RouteTemplate` (`routeTemplate`);
/// - the router `SpringApp` builds the app widget on (`springRouterConfig`,
///   a `RouterConfig<Object>`), with addresses without `#` in a browser
///   (`spring.flutter.navigation.web.url-strategy`).
@AutoConfigurationModule()
final BeanModule springBootStarterFlutterNavigationAutoConfiguration =
    BeanModule(
      'springBootStarterFlutterNavigationAutoConfiguration',
      [
        BeanDefinition<NavigationScopesRegistrar>(
          name: 'navigationScopesRegistrar',
          types: const [NavigationScopesRegistrar, BeanFactoryPostProcessor],
          source: _source,
          create: (_) => const NavigationScopesRegistrar(),
        ),
        BeanDefinition<Navigation>(
          name: 'navigation',
          conditions: const [
            ConditionGroup('$_source.navigation', [
              ConditionalOnBean(ScreenRoutes),
            ]),
          ],
          source: _source,
          create: (r) {
            final properties = r.dependency<NavigationProperties>();
            return Navigation(
              table: RouteTable(
                r.optionalDependencyList<ScreenRoutes>() ?? const [],
                redirects: properties.redirects ?? const {},
              ),
              conversion:
                  r.optionalDependency<ConversionService>(
                    qualifier: 'conversionService',
                  ) ??
                  r.conversionService,
              scopes: r.dependency<RouteScopes>(),
              filters: r.optionalDependencyList<RouteFilter>() ?? const [],
              messages: r.dependency<ApplicationContext>(),
              initial: properties.initial,
              linkExclude: properties.deepLinks.exclude ?? const [],
              languages: properties.languages ?? const [],
            );
          },
          preDestroy: (navigation) {
            navigation.scopes.destroyAll();
            navigation.dispose();
          },
        ),
        BeanDefinition<RouteLanguageCustomizer>(
          name: 'routeLanguageCustomizer',
          types: const [RouteLanguageCustomizer, FlutterAppCustomizer],
          conditions: const [
            ConditionGroup('$_source.routeLanguageCustomizer', [
              ConditionalOnBean(ScreenRoutes),
            ]),
          ],
          source: _source,
          create: (r) => RouteLanguageCustomizer(r.dependency<Navigation>()),
        ),
        BeanDefinition<RouteTemplate>(
          name: 'routeTemplate',
          conditions: const [
            ConditionGroup('$_source.routeTemplate', [
              ConditionalOnBean(ScreenRoutes),
            ]),
          ],
          source: _source,
          create: (r) => RouteTemplate(r.dependency<Navigation>()),
        ),
        BeanDefinition<ScreenMappings>(
          name: 'screenMappings',
          types: const [ScreenMappings, MappingDescriptions],
          conditions: const [
            ConditionGroup('$_source.screenMappings', [
              ConditionalOnBean(ScreenRoutes),
            ]),
          ],
          source: _source,
          create: (r) => ScreenMappings(r.dependency<Navigation>()),
        ),
        // Lazy: made when SpringApp asks for it, where Flutter's binding
        // exists (a context without widgets, a server test, never makes
        // it), still before the router reads the first address.
        BeanDefinition<SpringRouterConfig>(
          name: 'springRouterConfig',
          lazy: true,
          conditions: const [
            ConditionGroup('$_source.springRouterConfig', [
              ConditionalOnBean(ScreenRoutes),
            ]),
          ],
          types: const [
            SpringRouterConfig,
            RouterConfig<RouteLocation>,
            RouterConfig<Object>,
          ],
          source: _source,
          create: (r) {
            final properties = r.dependency<NavigationProperties>();
            if (kIsWeb &&
                properties.web.urlStrategy == NavigationUrlStrategy.path) {
              _pathUrls();
            }
            return SpringRouterConfig(r.dependency<Navigation>());
          },
        ),
      ],
      imports: [navigationConfigBeans],
    );

// The browser's address bar without `#`. It must be set before the engine
// reads the first address, which the router does: the context starts
// while the splash shows, before any router exists. A second start (a hot
// restart, a test) finds it set and keeps it.
void _pathUrls() {
  try {
    usePathUrlStrategy();
  } on Object catch (e) {
    _log.debug(() => 'The URL strategy was set already: $e');
  }
}
