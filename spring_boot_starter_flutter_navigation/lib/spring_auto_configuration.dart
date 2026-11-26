/// The starter's auto-configuration, found by the code generator in every
/// application that depends on `spring_boot_starter_flutter_navigation`.
///
/// Applications do not import it: the generated `main.spring.dart` does
/// (the module below is marked `@AutoConfigurationModule()`). A test that
/// builds a context by hand imports it to name the module.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show RouterConfig;
import 'package:flutter_web_plugins/url_strategy.dart'
    show BrowserPlatformLocation, PathUrlStrategy, setUrlStrategy;
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show DebugGraphRouteBeans, FlutterAppCustomizer;

import 'package:spring_boot_starter_flutter_navigation/src/navigation.dart';
import 'package:spring_boot_starter_flutter_navigation/src/properties/navigation_properties.dart';
import 'package:spring_boot_starter_flutter_navigation/src/properties/properties_beans.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_language.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_location.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_scopes.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_scopes_graph_beans.dart';
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
      ..registerSingleton(
        'routeScopes',
        scopes,
        types: const [RouteScopes],
      );
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
              events: r.dependency<ApplicationEventPublisher>(),
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

/// The live `route` beans for the application graph of the debug panel's
/// Graph tab (`routeScopesGraphBeans`, a `DebugGraphRouteBeans`), so the
/// graph groups the beans by route. The generator puts this module into
/// the app by `spring.flutter.debug.graph.enabled`, as far as the panel's
/// switch (its parent) lets it in: otherwise the build has no code of it.
@AutoConfigurationModule(
  build: AutoConfigurationBuild(
    'spring.flutter.debug.graph.enabled',
    parents: [AutoConfigurationBuild('spring.flutter.debug.enabled')],
  ),
)
final BeanModule springBootStarterFlutterNavigationDebugGraphAutoConfiguration =
    BeanModule(
      'springBootStarterFlutterNavigationDebugGraphAutoConfiguration',
      [
        _routeScopesGraphBeans,
      ],
    );

/// The live `route` beans for the application graph of the debug
/// console's `graph` pane (`routeScopesGraphBeans`). The generator puts
/// this module into the app only with the console
/// (`spring.flutter.debug.console.enabled: true`) and when
/// `spring.flutter.debug.console.panes` names `graph` or holds `*`.
@AutoConfigurationModule(
  build: AutoConfigurationBuild.named(
    'spring.flutter.debug.console.panes',
    'graph',
    whenMissing: BuildInclusion.never,
    parents: [
      AutoConfigurationBuild(
        'spring.flutter.debug.console.enabled',
        whenMissing: BuildInclusion.never,
      ),
    ],
  ),
)
final BeanModule
springBootStarterFlutterNavigationDebugConsoleGraphAutoConfiguration =
    BeanModule(
      'springBootStarterFlutterNavigationDebugConsoleGraphAutoConfiguration',
      [_routeScopesGraphBeans],
    );

// The adapter of the route scopes, in the module of each view of the
// graph: the first makes it.
final BeanDefinition<RouteScopesGraphBeans> _routeScopesGraphBeans =
    BeanDefinition<RouteScopesGraphBeans>(
      name: 'routeScopesGraphBeans',
      types: const [RouteScopesGraphBeans, DebugGraphRouteBeans],
      source: _source,
      conditions: const [
        ConditionalOnProperty(
          'spring.flutter.debug.graph.enabled',
          havingValue: 'true',
          matchIfMissing: true,
        ),
        ConditionGroup('$_source#routeScopesGraphBeans', [
          ConditionalOnMissingBean(RouteScopesGraphBeans),
        ]),
      ],
      create: (r) => RouteScopesGraphBeans(r.dependency<RouteScopes>()),
    );

// The browser's address bar without `#` for the route, its `#heading`
// kept (a link straight to a heading). It must be set before the engine
// reads the first address, which the router does: the context starts
// while the splash shows, before any router exists. A second start (a hot
// restart, a test) finds it set and keeps it.
void _pathUrls() {
  try {
    setUrlStrategy(PathUrlStrategy(BrowserPlatformLocation(), true));
  } on Object catch (e) {
    _log.debug(() => 'The URL strategy was set already: $e');
  }
}
