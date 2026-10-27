// The core without a web server: tokens, users, the security context,
// authentication managers and providers (with the timing and enumeration
// protections), authorization managers, the role hierarchy, events, and the
// startup checks of method security.
import 'dart:async';

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_security_core/spring_auto_configuration.dart';
import 'package:spring_security_core/spring_security_core.dart';
import 'package:test/test.dart';

/// An encoder that counts its calls ({noop} underneath), to show the work
/// done per login.
final class CountingEncoder implements PasswordEncoder {
  int matchesCalls = 0;
  int encodeCalls = 0;

  @override
  String encode(String rawPassword) {
    encodeCalls++;
    return rawPassword;
  }

  @override
  bool matches(String rawPassword, String? encodedPassword) {
    matchesCalls++;
    return rawPassword == encodedPassword;
  }

  @override
  bool upgradeEncoding(String? encodedPassword) =>
      encodedPassword?.startsWith('old:') ?? false;
}

final class RecordingPublisher implements AuthenticationEventPublisher {
  final events = <String>[];

  @override
  void publishAuthenticationSuccess(Authentication authentication) =>
      events.add('success ${authentication.name}');

  @override
  void publishAuthenticationFailure(
    AuthenticationException exception,
    Authentication authentication,
  ) => events.add('failure ${exception.runtimeType}');
}

void main() {
  group('tokens', () {
    test('a login request is not authenticated and cannot become so', () {
      final request = UsernamePasswordAuthenticationToken.unauthenticated(
        'ada',
        'secret',
      );
      expect(request.isAuthenticated, isFalse);
      expect(request.authorities, isEmpty);
      expect(() => request.isAuthenticated = true, throwsArgumentError);
      expect(request.name, 'ada');
    });

    test('toString never shows the credentials', () {
      final token = UsernamePasswordAuthenticationToken.authenticated(
        'ada',
        'secret',
        AuthorityUtils.createAuthorityList(['ROLE_USER']),
      );
      expect('$token', isNot(contains('secret')));
      expect('$token', contains('[PROTECTED]'));
      final user = User.withUsername('ada').password('{noop}secret').build();
      expect('$user', isNot(contains('secret')));
    });

    test('erasing credentials reaches the principal', () {
      final user = User.withUsername('ada')
          .password('{noop}secret')
          .roles(['USER'])
          .build();
      final token = UsernamePasswordAuthenticationToken.authenticated(
        user,
        'secret',
        user.authorities,
      )..eraseCredentials();
      expect(token.credentials, isNull);
      expect(user.password, isNull);
    });

    test('authorities need names; anonymous tokens need a key', () {
      expect(() => SimpleGrantedAuthority(''), throwsArgumentError);
      expect(
        () => AnonymousAuthenticationToken('', 'x', [
          SimpleGrantedAuthority('ROLE_ANONYMOUS'),
        ]),
        throwsArgumentError,
      );
      expect(AuthorityUtils.commaSeparatedStringToAuthorityList(' A, ,B '), [
        SimpleGrantedAuthority('A'),
        SimpleGrantedAuthority('B'),
      ]);
    });
  });

  group('users', () {
    test('roles get the prefix; a prefixed role is refused', () {
      final user = User.withUsername('ada').roles(['ADMIN', 'USER']).build();
      expect(AuthorityUtils.authorityListToSet(user.authorities), {
        'ROLE_ADMIN',
        'ROLE_USER',
      });
      expect(
        () => User.withUsername('ada').roles(['ROLE_ADMIN']),
        throwsArgumentError,
      );
      expect(() => User.withUsername('').build(), throwsArgumentError);
    });

    test('the in-memory manager ignores case and hands out copies', () {
      final manager = InMemoryUserDetailsManager([
        User.withUsername('Ada').password('{noop}secret').build(),
      ]);
      final loaded = manager.loadUserByUsername('ada');
      expect(loaded.username, 'Ada');
      (loaded as User).eraseCredentials();
      expect(manager.loadUserByUsername('ADA').password, '{noop}secret');
      expect(
        () => manager.loadUserByUsername('bob'),
        throwsA(isA<UsernameNotFoundException>()),
      );
      expect(() => manager.createUser(loaded), throwsArgumentError);
      manager.deleteUser('ada');
      expect(manager.userExists('Ada'), isFalse);
    });
  });

  group('DaoAuthenticationProvider', () {
    late CountingEncoder encoder;
    late InMemoryUserDetailsManager users;
    late DaoAuthenticationProvider provider;

    setUp(() {
      encoder = CountingEncoder();
      users = InMemoryUserDetailsManager([
        User.withUsername('ada').password('secret').roles(['USER']).build(),
        User.withUsername('old').password('old:x').build(),
        User.withUsername('locked')
            .password('secret')
            .accountLocked(true)
            .build(),
        User.withUsername('disabled').password('secret').disabled(true).build(),
        User.withUsername('expired')
            .password('secret')
            .credentialsExpired(true)
            .build(),
      ]);
      provider = DaoAuthenticationProvider(
        users,
        passwordEncoder: encoder,
        userDetailsPasswordService: users,
        offloadPasswordChecks: false,
      );
    });

    Future<Authentication?> login(String name, String password) =>
        provider.authenticate(
          UsernamePasswordAuthenticationToken.unauthenticated(name, password),
        );

    test('a good password gives an authenticated user', () async {
      final result = (await login('ada', 'secret'))!;
      expect(result.isAuthenticated, isTrue);
      expect(result.name, 'ada');
      expect(result.principal, isA<UserDetails>());
      expect(AuthorityUtils.authorityListToSet(result.authorities), {
        'ROLE_USER',
      });
    });

    test('unknown user and wrong password fail the same way, with the same '
        'work', () async {
      await expectLater(
        login('ada', 'wrong'),
        throwsA(isA<BadCredentialsException>()),
      );
      final afterWrongPassword = encoder.matchesCalls;
      await expectLater(
        login('nobody', 'wrong'),
        throwsA(
          isA<BadCredentialsException>().having(
            (e) => e.message,
            'message',
            'Bad credentials',
          ),
        ),
      );
      // The unknown user's password was hashed too (against a dummy hash).
      expect(encoder.matchesCalls, afterWrongPassword + 1);
    });

    test('account states: locked and disabled before the password, expired '
        'after', () async {
      final before = encoder.matchesCalls;
      await expectLater(
        login('locked', 'wrong'),
        throwsA(isA<LockedException>()),
      );
      await expectLater(
        login('disabled', 'secret'),
        throwsA(isA<DisabledException>()),
      );
      expect(encoder.matchesCalls, before);
      await expectLater(
        login('expired', 'wrong'),
        throwsA(isA<BadCredentialsException>()),
      );
      await expectLater(
        login('expired', 'secret'),
        throwsA(isA<CredentialsExpiredException>()),
      );
    });

    test('an old hash is upgraded at login', () async {
      await expectLater(login('old', 'old:x'), completion(isNotNull));
      expect(users.loadUserByUsername('old').password, 'old:x');
      expect(encoder.encodeCalls, 1);
    });

    test('a hash no encoder knows never logs in', () async {
      final strict = DaoAuthenticationProvider(
        InMemoryUserDetailsManager([
          User.withUsername('ada').password(r'{bcrypt}$2a$10$xyz').build(),
        ]),
        offloadPasswordChecks: false,
      );
      await expectLater(
        strict.authenticate(
          UsernamePasswordAuthenticationToken.unauthenticated('ada', 'x'),
        ),
        throwsA(isA<BadCredentialsException>()),
      );
    });

    test('a failing user store is an internal error, not a login', () async {
      final failing = DaoAuthenticationProvider(
        _FailingUsers(),
        offloadPasswordChecks: false,
      );
      await expectLater(
        failing.authenticate(
          UsernamePasswordAuthenticationToken.unauthenticated('ada', 'x'),
        ),
        throwsA(isA<InternalAuthenticationServiceException>()),
      );
    });

    test('the password check runs on another isolate', () async {
      final offloading = DaoAuthenticationProvider(
        InMemoryUserDetailsManager([
          User.withUsername('ada').password('{noop}secret').build(),
        ]),
      );
      final result = await offloading.authenticate(
        UsernamePasswordAuthenticationToken.unauthenticated('ada', 'secret'),
      );
      expect(result!.isAuthenticated, isTrue);
    });
  });

  group('ProviderManager', () {
    test('first success wins, events published, credentials erased', () async {
      final publisher = RecordingPublisher();
      final manager = ProviderManager([
        DaoAuthenticationProvider(
          InMemoryUserDetailsManager([
            User.withUsername('ada').password('{noop}secret').build(),
          ]),
          offloadPasswordChecks: false,
        ),
      ], eventPublisher: publisher);
      final result = await manager.authenticate(
        UsernamePasswordAuthenticationToken.unauthenticated('ada', 'secret'),
      );
      expect(result.credentials, isNull);
      expect((result.principal! as UserDetails).password, isNull);
      await expectLater(
        manager.authenticate(
          UsernamePasswordAuthenticationToken.unauthenticated('ada', 'nope'),
        ),
        throwsA(isA<BadCredentialsException>()),
      );
      expect(publisher.events, [
        'success ada',
        'failure BadCredentialsException',
      ]);
    });

    test('no provider for the request type', () async {
      final manager = ProviderManager([
        DaoAuthenticationProvider(InMemoryUserDetailsManager()),
      ]);
      await expectLater(
        manager.authenticate(TestingAuthenticationToken('x', null)),
        throwsA(isA<ProviderNotFoundException>()),
      );
    });

    test('the parent is asked last', () async {
      final parent = ProviderManager([
        DaoAuthenticationProvider(
          InMemoryUserDetailsManager([
            User.withUsername('bob').password('{noop}pw').build(),
          ]),
          offloadPasswordChecks: false,
        ),
      ]);
      final manager = ProviderManager([
        DaoAuthenticationProvider(
          InMemoryUserDetailsManager(),
          offloadPasswordChecks: false,
        ),
      ], parent: parent);
      final result = await manager.authenticate(
        UsernamePasswordAuthenticationToken.unauthenticated('bob', 'pw'),
      );
      expect(result.name, 'bob');
    });
  });

  group('SecurityContextHolder', () {
    test('scopes are isolated and end with their body', () async {
      final strategy = ZoneSecurityContextHolderStrategy();
      expect(strategy.isScoped, isFalse);
      await strategy.runWithContext(() async {
        expect(strategy.isScoped, isTrue);
        strategy.getContext().authentication = TestingAuthenticationToken(
          'ada',
          null,
        );
        await Future<void>.delayed(Duration.zero);
        expect(strategy.getContext().authentication!.name, 'ada');
        await strategy.runWithContext(() async {
          expect(strategy.getContext().authentication, isNull);
        });
        expect(strategy.getContext().authentication!.name, 'ada');
      });
      // Nothing leaked into the program-wide context.
      expect(strategy.getContext().authentication, isNull);
    });

    test('work started in a scope keeps its user (timers, streams)', () async {
      final strategy = ZoneSecurityContextHolderStrategy();
      final seen = Completer<String?>();
      strategy.runWithContext(() {
        Timer(const Duration(milliseconds: 5), () {
          seen.complete(strategy.getContext().authentication?.name);
        });
      }, SecurityContextImpl(TestingAuthenticationToken('ada', null)));
      expect(await seen.future, 'ada');
    });

    test('the global strategy restores the previous context', () {
      final strategy = GlobalSecurityContextHolderStrategy()
        ..setContext(
          SecurityContextImpl(TestingAuthenticationToken('app', null)),
        );
      strategy.runWithContext(
        () => expect(strategy.getContext().authentication!.name, 'job'),
        SecurityContextImpl(TestingAuthenticationToken('job', null)),
      );
      expect(strategy.getContext().authentication!.name, 'app');
      strategy.clearContext();
      expect(strategy.getContext().authentication, isNull);
    });
  });

  group('authorization managers', () {
    Authentication? none() => null;
    Authentication user(List<String> authorities) =>
        TestingAuthenticationToken('ada', null, authorities);
    final anonymousToken = AnonymousAuthenticationToken(
      'key',
      'anonymousUser',
      AuthorityUtils.createAuthorityList(['ROLE_ANONYMOUS']),
    );

    test('authorities and roles', () {
      final admin = AuthorityAuthorizationManager<void>.hasRole('ADMIN');
      expect(
        admin.authorize(() => user(['ROLE_ADMIN']), null).isGranted,
        isTrue,
      );
      expect(
        admin.authorize(() => user(['ROLE_USER']), null).isGranted,
        isFalse,
      );
      expect(admin.authorize(none, null).isGranted, isFalse);
      final unauthenticated =
          UsernamePasswordAuthenticationToken.unauthenticated('ada', 'x');
      expect(admin.authorize(() => unauthenticated, null).isGranted, isFalse);
      expect(
        () => AuthorityAuthorizationManager<void>.hasRole('ROLE_ADMIN'),
        throwsArgumentError,
      );
      expect(
        AuthorityAuthorizationManager<void>.hasAnyAuthority([
          'SCOPE_read',
          'SCOPE_write',
        ]).authorize(() => user(['SCOPE_write']), null).isGranted,
        isTrue,
      );
    });

    test('authenticated / anonymous', () {
      const authenticated =
          AuthenticatedAuthorizationManager<void>.authenticated();
      const anonymous = AuthenticatedAuthorizationManager<void>.anonymous();
      expect(authenticated.authorize(() => user([]), null).isGranted, isTrue);
      expect(
        authenticated.authorize(() => anonymousToken, null).isGranted,
        isFalse,
      );
      expect(authenticated.authorize(none, null).isGranted, isFalse);
      expect(anonymous.authorize(() => anonymousToken, null).isGranted, isTrue);
    });

    test('combinations; an abstention is not a grant', () async {
      const yes = SingleResultAuthorizationManager<void>.permitAll();
      const no = SingleResultAuthorizationManager<void>.denyAll();
      final abstain = _Abstain();
      Future<bool?> granted(AuthorizationManager<void> m) async =>
          (await m.authorize(none, null))?.isGranted;
      expect(await granted(AuthorizationManagers.anyOf([no, yes])), isTrue);
      expect(
        await granted(AuthorizationManagers.anyOf([no, abstain])),
        isFalse,
      );
      expect(await granted(AuthorizationManagers.anyOf([abstain])), isNull);
      expect(await granted(AuthorizationManagers.allOf([yes, no])), isFalse);
      expect(
        await granted(AuthorizationManagers.allOf([yes, abstain])),
        isTrue,
      );
      expect(await granted(AuthorizationManagers.not(no)), isTrue);
      await expectLater(
        verifyAuthorization(abstain, none, null),
        throwsA(isA<AuthorizationDeniedException>()),
      );
      await verifyAuthorization(yes, none, null);
    });

    test('the role hierarchy is transitive and refuses cycles', () {
      final hierarchy = RoleHierarchyImpl.fromHierarchy('''
        ROLE_ADMIN > ROLE_STAFF
        ROLE_STAFF > ROLE_USER
      ''');
      expect(
        AuthorityUtils.authorityListToSet(
          hierarchy.getReachableGrantedAuthorities([
            SimpleGrantedAuthority('ROLE_ADMIN'),
          ]),
        ),
        {'ROLE_ADMIN', 'ROLE_STAFF', 'ROLE_USER'},
      );
      expect(
        () => RoleHierarchyImpl.fromHierarchy('A > B\nB > A'),
        throwsArgumentError,
      );
      expect(() => RoleHierarchyImpl.fromHierarchy('A >'), throwsArgumentError);
    });
  });

  group('auto-configuration', () {
    ApplicationContextRunner runner() => const ApplicationContextRunner()
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springSecurityCoreAutoConfiguration)
        .withPropertyValues(['logging.level.root=warn']);

    test('an AuthenticationManager from a UserDetailsService bean', () async {
      final publisher = RecordingPublisher();
      await runner()
          .withBean<UserDetailsService>(
            () => InMemoryUserDetailsManager([
              User.withUsername('ada').password('{noop}secret').build(),
            ]),
          )
          .withBean<AuthenticationEventPublisher>(() => publisher)
          .runAsync((context) async {
            final manager = context.context.getBean<AuthenticationManager>();
            final result = await manager.authenticate(
              UsernamePasswordAuthenticationToken.unauthenticated(
                'ada',
                'secret',
              ),
            );
            expect(result.isAuthenticated, isTrue);
            expect(publisher.events, ['success ada']);
          });
    });

    test('no users, no AuthenticationManager', () async {
      await runner().runAsync((context) async {
        expect(context.context.containsBean('authenticationManager'), isFalse);
      });
    });

    test('a bean with method security annotations but no proxy fails the '
        'startup', () async {
      await runner()
          .withUserConfiguration(
            BeanModule('unproxied', [
              BeanDefinition<_Unproxied>(
                name: 'unproxied',
                create: (_) => _Unproxied(),
                annotatedMethods: [
                  BeanMethod<_Unproxied>(
                    'delete',
                    invoke: (bean, _) => bean.delete(),
                    annotations: const [PreAuthorize("hasRole('ADMIN')")],
                  ),
                ],
              ),
            ]),
          )
          .runAsync((context) async {
            expect(context.startupFailure, isNotNull);
            expect(
              '${context.startupFailure}',
              contains('has method security annotations but no proxy'),
            );
          });
    });
  });
}

final class _Abstain implements AuthorizationManager<void> {
  @override
  AuthorizationResult? authorize(
    Authentication? Function() authentication,
    void object,
  ) => null;
}

final class _FailingUsers implements UserDetailsService {
  @override
  Future<UserDetails> loadUserByUsername(String username) async =>
      throw StateError('database down');
}

class _Unproxied {
  void delete() {}
}
