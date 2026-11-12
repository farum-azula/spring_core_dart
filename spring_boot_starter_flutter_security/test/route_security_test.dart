// The guards of the routes: @PreAuthorize on a screen (the route's
// `preAuthorize` attribute) and RouteSecurity.preAuthorize in Dart
// configuration. Nobody logged in goes to the login and back after it; a
// user without the role gets the error screen; a logout sends a guarded
// screen to the login.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_security/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

import 'support/design_starters.dart';

SecurityContextImpl _user(String name, [List<String> authorities = const []]) =>
    SecurityContextImpl(TestingAuthenticationToken(name, null, authorities));

class _Page extends StatelessWidget {
  const _Page(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(body: Text(label));
}

ScreenRoutes _routes() => ScreenRoutes.route()
    .screen('/', (r) => const _Page('home'))
    .screen('/login', (r) => const _Page('login'))
    .screen(
      '/admin',
      (r) => const _Page('admin'),
      attributes: {RouteAttributes.preAuthorize: "hasRole('ADMIN')"},
    )
    .nest(
      (account) => account
          .screen('/account', (r) => const _Page('account'))
          .filter(RouteSecurity.preAuthorize('isAuthenticated()')),
    )
    .screen(
      '/docs/{*path}',
      (r) => const _Page('docs'),
      content: 'resources:content/docs/',
    )
    .screen(
      '/private/{*path}',
      (r) => const _Page('private'),
      content: 'resources:content/private/',
      attributes: {RouteAttributes.preAuthorize: "hasRole('ADMIN')"},
    )
    .error((r) => _Page('error ${r.error.runtimeType}'))
    .build();

SpringApplication _application() => SpringApplication(
  [
    BeanModule(
      'test',
      [BeanDefinition<ScreenRoutes>(name: 'routes', create: (_) => _routes())],
      resources: {
        'application.properties': EmbeddedResource.text(
          'spring.flutter.app.type=material\n'
          'spring.flutter.navigation.login=/login',
        ),
        'content/docs/index.md': const EmbeddedResource.text('# Docs'),
        'content/private/secret.md': const EmbeddedResource.text('# Secret'),
      },
    ),
  ],
  autoConfigurations: [
    springBootStarterFlutterAutoConfiguration,
    springBootStarterFlutterNavigationAutoConfiguration,
    springSecurityCoreAutoConfiguration,
    springBootStarterFlutterSecurityAutoConfiguration,
    ...DesignStarters.onlyMaterial.autoConfigurations,
  ],
  autoConfigurationMetadata: DesignStarters.onlyMaterial.metadata,
  bannerMode: BannerMode.off,
);

Future<RouteTemplate> _start(WidgetTester tester) async {
  await tester.pumpWidget(SpringApplicationWidget(application: _application));
  await tester.pumpAndSettle();
  return SpringScope.of(
    tester.element(find.byType(Router<Object>)),
  ).getBean<RouteTemplate>();
}

void main() {
  setUp(SecurityContextHolder.clearContext);
  tearDown(SecurityContextHolder.clearContext);

  testWidgets('nobody logged in: to the login, and back after it', (
    tester,
  ) async {
    final route = await _start(tester);
    await route.go('/account');
    await tester.pumpAndSettle();
    expect(find.text('login'), findsOneWidget);
    expect(route.uri.toString(), '/login');

    SecurityContextHolder.setContext(_user('ada'));
    await tester.pumpAndSettle();
    expect(find.text('account'), findsOneWidget);
    expect(route.uri.toString(), '/account');
  });

  testWidgets('a user without the role gets the error screen', (
    tester,
  ) async {
    SecurityContextHolder.setContext(_user('bob', ['ROLE_USER']));
    final route = await _start(tester);
    await route.go('/admin');
    await tester.pumpAndSettle();
    expect(find.text('error AccessDeniedException'), findsOneWidget);

    SecurityContextHolder.setContext(_user('ada', ['ROLE_ADMIN']));
    await route.go('/admin');
    await tester.pumpAndSettle();
    expect(find.text('admin'), findsOneWidget);
  });

  testWidgets('a logout sends a guarded screen to the login', (tester) async {
    SecurityContextHolder.setContext(_user('ada'));
    final route = await _start(tester);
    await route.go('/account');
    await tester.pumpAndSettle();
    expect(find.text('account'), findsOneWidget);

    SecurityContextHolder.clearContext();
    await tester.pumpAndSettle();
    expect(find.text('login'), findsOneWidget);
  });

  // A public `{*path}` screen next to a guarded one: no address reaches the
  // guarded folder past its guard. Dot segments go to the guarded screen
  // (and its guard); an encoded slash or backslash is refused and the app
  // stays where it is.
  testWidgets('a public {*path} screen does not open a guarded folder', (
    tester,
  ) async {
    final route = await _start(tester);
    await route.go('/docs');
    await tester.pumpAndSettle();
    for (final address in [
      '/docs/..%2Fprivate%2Fsecret',
      '/docs/%2E%2E%2Fprivate%2Fsecret',
      '/docs/..%5Cprivate%5Csecret',
    ]) {
      await route.go(address);
      await tester.pumpAndSettle();
      expect(route.uri.path, '/docs', reason: address);
      expect(route.content, 'resources:content/docs/index.md');
      expect(find.text('private'), findsNothing, reason: address);
    }
    await route.go('/docs/../private/secret');
    await tester.pumpAndSettle();
    expect(find.text('login'), findsOneWidget);
    expect(find.text('private'), findsNothing);
  });
}
