// The starter's beans: the router only for an app with routes (an app
// with a `home` keeps Flutter's own addresses), and a route that asks for
// a user (@PreAuthorize) stops the start when nothing enforces it.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show ApplicationContextRunner, doesNotHaveBean, hasSingleBean;

Widget _screen(RouteState route) => const SizedBox();

void main() {
  // The router reads the platform's first address from the binding.
  TestWidgetsFlutterBinding.ensureInitialized();
  final runner = const ApplicationContextRunner()
      .withAutoConfiguration(springBootAutoConfiguration)
      .withAutoConfiguration(springBootStarterFlutterAutoConfiguration)
      .withAutoConfiguration(
        springBootStarterFlutterNavigationAutoConfiguration,
      );

  test('without routes: no navigation, no router', () {
    runner.run((context) {
      expect(context.startupFailure, isNull);
      expect(context, doesNotHaveBean<SpringRouterConfig>());
      expect(context, doesNotHaveBean<RouteTemplate>());
    });
  });

  test('with routes: the navigation, the template and the router', () {
    runner
        .withBean<ScreenRoutes>(
          () => ScreenRoutes.route().screen('/', _screen).build(),
        )
        .run((context) {
          expect(context.startupFailure, isNull);
          expect(context, hasSingleBean<SpringRouterConfig>());
          expect(context, hasSingleBean<RouteTemplate>());
          expect(
            context.getBean<RouterConfig<Object>>(),
            isA<SpringRouterConfig>(),
          );
        });
  });

  test('a route that asks for a user and nothing to enforce it', () {
    runner
        .withBean<ScreenRoutes>(
          () => ScreenRoutes.route()
              .screen(
                '/admin',
                _screen,
                attributes: {RouteAttributes.preAuthorize: "hasRole('ADMIN')"},
                source: 'AdminPage',
              )
              .build(),
        )
        .run((context) {
          expect(
            context.startupFailure.toString(),
            allOf(
              contains('AdminPage'),
              contains('spring_boot_starter_flutter_security'),
            ),
          );
        });
  });

  test('the screens for /actuator/mappings', () {
    runner
        .withBean<ScreenRoutes>(
          () => ScreenRoutes.route()
              .shell(
                (shell) => shell.child,
                (tabs) => tabs.branch('/catalog', (b) => b),
                key: 'tabs',
              )
              .screen(
                '/catalog/books/{isbn}',
                _screen,
                name: 'book',
                params: {'page': int},
                attributes: {RouteAttributes.preAuthorize: 'isAuthenticated()'},
              )
              .build(),
        )
        .withBean<RouteFilter>(_AllowAll.new)
        .run((context) {
          final mappings = context.getBean<MappingDescriptions>();
          expect(mappings.mappingsName, 'screens');
          expect(mappings.describeMappings(), [
            {
              'path': '/catalog/books/{isbn}',
              'name': 'book',
              'shell': 'tabs',
              'branch': '/catalog',
              'variables': ['isbn'],
              'params': {'page': 'int'},
              'security': 'isAuthenticated()',
            },
          ]);
        });
  });
}

final class _AllowAll implements RouteAuthorizationFilter {
  @override
  RouteLocation? filter(RouteRequest request) => null;
}
