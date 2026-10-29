// The widgets that follow the user: PrincipalNotifier hears logins and
// logouts (through the holder's strategy and through the authentication
// events), context.principal, PrincipalBuilder and PrincipalView rebuild
// with them. Display only: nothing here protects anything.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

SecurityContextImpl _user(String name, [List<String> authorities = const []]) =>
    SecurityContextImpl(TestingAuthenticationToken(name, null, authorities));

/// Reads `context.principal`, nothing of Spring's widgets.
class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) =>
      Text('Hello, ${context.principal?.name ?? 'guest'}');
}

void main() {
  late ConfigurableApplicationContext context;
  late PrincipalNotifier notifier;

  setUp(() async {
    SecurityContextHolder.clearContext();
    context = await SpringApplication(
      const [],
      autoConfigurations: [
        springSecurityCoreAutoConfiguration,
        springBootStarterFlutterSecurityAutoConfiguration,
      ],
      bannerMode: BannerMode.off,
    ).runAsync(const []);
    notifier = context.getBean<PrincipalNotifier>();
  });

  tearDown(() async {
    await context.closeAsync();
    SecurityContextHolder.clearContext();
  });

  Widget app(Widget child) => SpringScope(
    applicationContext: context,
    child: MaterialApp(home: Scaffold(body: child)),
  );

  group('PrincipalNotifier', () {
    test('is a bean that follows setContext and clearContext', () {
      var notified = 0;
      notifier.addListener(() => notified++);
      expect(notifier.authentication, isNull);

      SecurityContextHolder.setContext(_user('ada'));
      expect(notifier.authentication?.name, 'ada');
      expect(notifier.isAuthenticated, isTrue);

      SecurityContextHolder.setContext(_user('bob'));
      expect(notifier.authentication?.name, 'bob');

      SecurityContextHolder.clearContext();
      expect(notifier.authentication, isNull);
      expect(notified, 3);
    });

    test('work run as another user does not count', () {
      var notified = 0;
      notifier.addListener(() => notified++);

      SecurityContextHolder.runWithContext(
        () => SecurityContextHolder.setContext(_user('job')),
      );

      expect(notifier.authentication, isNull);
      expect(notified, 0);
    });

    test('an anonymous user counts as nobody', () {
      SecurityContextHolder.setContext(
        SecurityContextImpl(
          AnonymousAuthenticationToken('key', 'anonymousUser', [
            SimpleGrantedAuthority('ROLE_ANONYMOUS'),
          ]),
        ),
      );
      expect(notifier.authentication, isNull);
    });

    test('hears the login events of code that kept the old strategy', () {
      final strategy =
          SecurityContextHolder.getContextHolderStrategy()
              as ListeningSecurityContextHolderStrategy;
      var notified = 0;
      notifier.addListener(() => notified++);
      final ada = _user('ada');

      // As OAuth2LoginService does when it was created before the
      // notifier: the context changes behind the listening strategy.
      strategy.delegate.setContext(ada);
      expect(notified, 0);
      context.publishEvent(AuthenticationSuccessEvent(ada.authentication!));
      expect(notifier.authentication?.name, 'ada');

      strategy.delegate.clearContext();
      context.publishEvent(LogoutSuccessEvent(ada.authentication!));
      expect(notifier.authentication, isNull);
      expect(notified, 2);
    });

    test('stops listening when the context closes', () async {
      final old = notifier;
      var notified = 0;
      old.addListener(() => notified++);
      await context.closeAsync();

      SecurityContextHolder.setContext(_user('ada'));
      expect(notified, 0);

      // The next context listens again, on the same strategy.
      context = await SpringApplication(
        const [],
        autoConfigurations: [springBootStarterFlutterSecurityAutoConfiguration],
        bannerMode: BannerMode.off,
      ).runAsync(const []);
      expect(context.getBean<PrincipalNotifier>().authentication?.name, 'ada');
    });
  });

  testWidgets('context.principal rebuilds a plain widget', (tester) async {
    await tester.pumpWidget(app(const _Greeting()));
    expect(find.text('Hello, guest'), findsOneWidget);

    SecurityContextHolder.setContext(_user('ada'));
    await tester.pump();
    expect(find.text('Hello, ada'), findsOneWidget);

    SecurityContextHolder.clearContext();
    await tester.pump();
    expect(find.text('Hello, guest'), findsOneWidget);
  });

  testWidgets('PrincipalBuilder builds with the authentication', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        PrincipalBuilder(
          builder: (context, authentication) => authentication == null
              ? const Text('Sign in')
              : Text('Signed in as ${authentication.name}'),
        ),
      ),
    );
    expect(find.text('Sign in'), findsOneWidget);

    SecurityContextHolder.setContext(_user('ada'));
    await tester.pump();
    expect(find.text('Signed in as ada'), findsOneWidget);
  });

  group('PrincipalView', () {
    Future<void> show(WidgetTester tester, PrincipalView view) =>
        tester.pumpWidget(app(view));

    testWidgets('hasRole', (tester) async {
      await show(
        tester,
        const PrincipalView(
          hasRole: 'ADMIN',
          otherwise: Text('no'),
          child: Text('admin menu'),
        ),
      );
      expect(find.text('no'), findsOneWidget);

      SecurityContextHolder.setContext(_user('bob', ['ROLE_USER']));
      await tester.pump();
      expect(find.text('no'), findsOneWidget);

      SecurityContextHolder.setContext(_user('ada', ['ROLE_ADMIN']));
      await tester.pump();
      expect(find.text('admin menu'), findsOneWidget);
    });

    testWidgets('hasAuthority, written in full', (tester) async {
      SecurityContextHolder.setContext(_user('ada', ['SCOPE_orders:write']));
      await show(
        tester,
        const PrincipalView(
          hasAuthority: 'SCOPE_orders:write',
          child: Text('edit'),
        ),
      );
      expect(find.text('edit'), findsOneWidget);
    });

    testWidgets('authenticated: false shows the child to nobody', (
      tester,
    ) async {
      await show(
        tester,
        const PrincipalView(
          authenticated: false,
          otherwise: Text('account'),
          child: Text('sign in'),
        ),
      );
      expect(find.text('sign in'), findsOneWidget);

      SecurityContextHolder.setContext(_user('ada'));
      await tester.pump();
      expect(find.text('account'), findsOneWidget);
    });

    testWidgets('a SpEL expression as in @PreAuthorize', (tester) async {
      await show(
        tester,
        const PrincipalView(
          expression: "hasRole('ADMIN') or authentication.name == 'ada'",
          child: Text('yes'),
        ),
      );
      // Nobody logged in: no match, no error.
      expect(find.text('yes'), findsNothing);

      SecurityContextHolder.setContext(_user('ada'));
      await tester.pump();
      expect(find.text('yes'), findsOneWidget);

      SecurityContextHolder.setContext(_user('bob'));
      await tester.pump();
      expect(find.text('yes'), findsNothing);

      SecurityContextHolder.setContext(_user('cy', ['ROLE_ADMIN']));
      await tester.pump();
      expect(find.text('yes'), findsOneWidget);
    });

    test('every condition must hold', () {
      final handler = MethodSecurityExpressionHandler();
      const view = PrincipalView(
        hasRole: 'ADMIN',
        authenticated: true,
        expression: "authentication.name == 'ada'",
        child: SizedBox(),
      );
      final ada = TestingAuthenticationToken('ada', null, ['ROLE_ADMIN']);
      final bob = TestingAuthenticationToken('bob', null, ['ROLE_ADMIN']);
      expect(view.matches(ada, handler), isTrue);
      expect(view.matches(bob, handler), isFalse);
      expect(view.matches(null, handler), isFalse);
    });

    test('a broken expression with a user is an error', () {
      const view = PrincipalView(expression: "'not a bool'", child: SizedBox());
      expect(
        () => view.matches(
          TestingAuthenticationToken('ada', null),
          MethodSecurityExpressionHandler(),
        ),
        throwsArgumentError,
      );
    });
  });
}
