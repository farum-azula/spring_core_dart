@Tags(['supabase'])
library;

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_boot_starter_supabase/src/auth/auth_auto_configuration.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app_support.dart';
import 'auth_support.dart';
import 'support.dart';

// The bean definitions of Auth in a real context, beside the starter's
// own: the module the generator will make of them is stood in for by one
// made here.
void main() {
  late MockHttpTransport transport;

  setUp(() => transport = MockHttpTransport());

  ApplicationContextRunner runner([List<String> properties = const []]) =>
      appRunner(transport, [
        // No timer of the real clock in a test.
        'spring.supabase.auth.auto-refresh=false',
        ...properties,
      ]).withAutoConfiguration(
        BeanModule('supabaseAuthTestAutoConfiguration', [
          ...supabaseAuthAutoConfiguration,
        ]),
        const AutoConfigurationModule(
          after: ['springBootStarterSupabaseAutoConfiguration'],
        ),
      );

  void answerLogin() => transport
      .when(HttpMethod.post, '/auth/v1/token?grant_type=password')
      .respond(200, json: sessionJson());

  test("the login is a bean, and the application's LoginSession", () async {
    await runner().runAsync((context) async {
      expect(context.startupFailure, isNull);
      expect(context, hasSingleBean<SupabaseAuth>());
      expect(context, hasSingleBean<SupabaseAuthAdmin>());
      expect(context, hasSingleBean<SupabaseAuthErrors>());
      expect(context, hasBeanNamed('supabaseAuth'));
      expect(context, hasBeanNamed('supabaseAuthAdmin'));
      final auth = context.getBean<SupabaseAuth>();
      expect(context.getBean<LoginSession>(), same(auth));
      expect(auth, isA<AsyncStartup>());
      expect(auth, isA<DisposableBean>());
      expect(auth.http, same(context.getBean<SupabaseHttp>()));
      expect(auth.errors, same(context.getBean<SupabaseAuthErrors>()));
    });
  });

  test('spring.supabase.auth.enabled=false: no bean of Auth', () async {
    await runner(['spring.supabase.auth.enabled=false']).runAsync((context) {
      expect(context.startupFailure, isNull);
      expect(context, doesNotHaveBean<SupabaseAuth>());
      expect(context, doesNotHaveBean<LoginSession>());
      expect(context, doesNotHaveBean<SupabaseAuthAdmin>());
      expect(context, doesNotHaveBean<SupabaseAuthErrors>());
    });
  });

  test('one session: every call is made as the signed-in user', () async {
    answerLogin();
    transport
        .when(HttpMethod.post, '/storage/v1/object/avatars/a.png')
        .respond(200, json: {'Key': 'avatars/a.png'});
    transport.when(HttpMethod.post, '/auth/v1/logout').respond(204);
    await runner().runAsync((context) async {
      final auth = context.getBean<SupabaseAuth>();
      final storage = context.getBean<StorageTemplate>();
      final credentials = context.getBean<SupabaseCredentials>();
      expect(credentials.caller, const SupabaseCaller.anon());
      await auth.signInWithPassword(email: 'a@b.c', password: 'correct horse');
      expect(credentials.caller, const SupabaseCaller.user(userId));
      expect(
        SecurityContextHolder.getContext().authentication,
        same(auth.authentication),
      );
      await storage.upload('avatars', 'a.png', const [1]);
      expect(transport.requests.last.headers['apikey'], 'anon-key');
      expect(
        transport.requests.last.headers['Authorization'],
        'Bearer access-token-1',
      );
      await auth.logout();
      expect(credentials.caller, const SupabaseCaller.anon());
      expect(SecurityContextHolder.getContext().authentication, isNull);
      await storage.upload('avatars', 'a.png', const [1]);
      expect(
        transport.requests.last.headers['Authorization'],
        'Bearer anon-key',
      );
    });
  });

  test(
    "the login and logout events reach the application's listeners",
    () async {
      answerLogin();
      transport.when(HttpMethod.post, '/auth/v1/logout').respond(204);
      await runner().runAsync((context) async {
        final events = <ApplicationEvent>[];
        context.context.addApplicationListener(
          ApplicationListenerAdapter.of<AbstractAuthenticationEvent>(
            events.add,
          ),
        );
        final auth = context.getBean<SupabaseAuth>();
        await auth.signInWithPassword(
          email: 'a@b.c',
          password: 'correct horse',
        );
        await auth.logout();
        expect(events, [
          isA<AuthenticationSuccessEvent>(),
          isA<LogoutSuccessEvent>(),
        ]);
      });
    },
  );

  test(
    'the SecretStore bean keeps the session, and startup restores it',
    () async {
      final store = InMemorySecretStore();
      await store.write(
        SupabaseAuth.sessionKey,
        SupabaseSession.fromResponse(sessionJson(), DateTime.now())!.encode(),
      );
      await runner().withBean<SecretStore>(() => store).runAsync((
        context,
      ) async {
        final auth = context.getBean<SupabaseAuth>();
        expect(auth.secretStore, same(store));
        expect(auth.isLoggedIn, isFalse);
        // What SpringApplication awaits of every AsyncStartup bean.
        await auth.awaitStartup();
        expect(auth.isLoggedIn, isTrue);
        expect(auth.user!.id, userId);
        expect(transport.requests, isEmpty);
      });
    },
  );

  test('persist-session=false leaves the SecretStore bean alone', () async {
    final store = InMemorySecretStore();
    answerLogin();
    await runner(['spring.supabase.auth.persist-session=false'])
        .withBean<SecretStore>(() => store)
        .runAsync((context) async {
          final auth = context.getBean<SupabaseAuth>();
          await auth.signInWithPassword(
            email: 'a@b.c',
            password: 'correct horse',
          );
          expect(auth.isLoggedIn, isTrue);
          expect(await store.keys(), isEmpty);
        });
  });

  test('redirect-urls are read from the properties', () async {
    await runner([
      'spring.supabase.auth.redirect-urls=myapp://callback,myapp://reset',
    ]).runAsync((context) async {
      final auth = context.getBean<SupabaseAuth>();
      final url = await auth.authorizationUrl('github');
      expect(url.queryParameters['redirect_to'], 'myapp://callback');
      await expectLater(
        auth.authorizationUrl('github', redirectTo: 'myapp://other'),
        throwsArgumentError,
      );
    });
  });

  test("the AuthorizationWindow bean opens the provider's page", () async {
    transport
        .when(HttpMethod.post, '/auth/v1/token?grant_type=pkce')
        .respond(200, json: sessionJson());
    final window = FakeWindow((redirect, _) => Uri.parse('$redirect?code=c1'));
    await runner(['spring.supabase.auth.redirect-urls=myapp://callback'])
        .withBean<AuthorizationWindow>(() => window)
        .runAsync((context) async {
          final auth = context.getBean<SupabaseAuth>();
          await auth.signInWithProvider('github');
          expect(window.opened, hasLength(1));
          expect(auth.isLoggedIn, isTrue);
        });
  });

  test('the application stopping closes the login', () async {
    answerLogin();
    var done = false;
    late SupabaseAuth auth;
    await runner().runAsync((context) async {
      auth = context.getBean<SupabaseAuth>();
      auth.authenticationChanges.listen(null, onDone: () => done = true);
      await auth.signInWithPassword(email: 'a@b.c', password: 'correct horse');
    });
    await settle();
    expect(done, isTrue);
  });

  test('a translator bean of the application is asked first', () async {
    transport
        .when(HttpMethod.post, '/auth/v1/token?grant_type=password')
        .respond(400, json: errorJson(400, 'trial_ended', 'The trial is over'));
    await runner()
        .withBean<SupabaseAuthErrorTranslator>(
          () => SupabaseAuthErrorCodes(const {
            'trial_ended',
          }, (e) => AccountExpiredException(e.message)),
        )
        .runAsync((context) async {
          await expectLater(
            context.getBean<SupabaseAuth>().signInWithPassword(
              email: 'a@b.c',
              password: 'correct horse',
            ),
            throwsA(isA<AccountExpiredException>()),
          );
        });
  });

  test("a SupabaseAuth of the application replaces the starter's", () async {
    final own = SupabaseAuth(http: http(transport));
    await runner().withBean<SupabaseAuth>(() => own).runAsync((context) {
      expect(context.startupFailure, isNull);
      expect(context.getBean<SupabaseAuth>(), same(own));
      expect(context, hasSingleBean<SupabaseAuth>());
    });
  });

  test('the admin bean calls as the service role', () async {
    transport
        .when(HttpMethod.get, '/auth/v1/admin/users')
        .respond(200, json: {'users': <Object?>[]});
    await runner().runAsync((context) async {
      await context.getBean<SupabaseAuthAdmin>().users();
      expect(transport.requests.single.headers['apikey'], 'service-key');
      expect(
        transport.requests.single.headers['Authorization'],
        'Bearer service-key',
      );
    });
  });
}
