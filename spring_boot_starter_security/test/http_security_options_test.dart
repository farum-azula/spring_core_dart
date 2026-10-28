// The remaining options of the HttpSecurity DSL, each seen in an answer:
// the rules denyAll, fullyAuthenticated, anonymous, hasAnyRole and
// hasAnyAuthority, more than four patterns in one rule, every setting of
// the resource server (decoder, converter, manager, entry point, denied
// handler, token resolver), and how the authentication manager is found
// among the beans of the application.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app/jwt/keys.dart';
import 'chain_support.dart';
import 'support.dart';

UserDetailsService _users() => InMemoryUserDetailsManager([
  User.withUsername('user').password('{noop}pw').roles(['USER']).build(),
  User.withUsername('admin').password('{noop}pw').roles(['ADMIN']).build(),
  User.withUsername('auditor').password('{noop}pw').roles(['AUDITOR']).build(),
  User.withUsername('reader')
      .password('{noop}pw')
      .authorities(AuthorityUtils.createAuthorityList(['read']))
      .build(),
  User.withUsername('writer')
      .password('{noop}pw')
      .authorities(AuthorityUtils.createAuthorityList(['write']))
      .build(),
]);

HttpSecurity _http() => HttpSecurity(null)..userDetailsService(_users());

Future<int> _status(
  SecurityFilterChain chain,
  String path, [
  String? user,
]) async {
  final client = ChainClient(chain);
  final reply = await client.get(
    path,
    accept: 'application/json',
    headers: user == null ? const {} : basicHeader(user, 'pw'),
  );
  return reply.status;
}

final class _Store implements UserDetailsService, UserDetailsPasswordService {
  final updates = <String, String>{};

  @override
  UserDetails loadUserByUsername(String username) =>
      User.withUsername(username).password('{noop}pw').roles(['USER']).build();

  @override
  UserDetails updatePassword(UserDetails user, String newPassword) {
    updates[user.username] = newPassword;
    return user;
  }
}

final class _Events implements AuthenticationEventPublisher {
  int successes = 0;
  int failures = 0;

  @override
  void publishAuthenticationSuccess(Authentication authentication) =>
      successes++;

  @override
  void publishAuthenticationFailure(
    AuthenticationException exception,
    Authentication authentication,
  ) => failures++;
}

/// A bean factory with fixed beans, without the core auto-configuration's
/// own `AuthenticationManager`; types in [failing] fail on lookup.
final class _Beans implements BeanFactory {
  _Beans(this.beans, {this.failing = const {}, this.hidden = const {}});

  final List<Object> beans;
  final Set<Type> failing;

  /// Types looked up as if no bean had them (the factory knows a bean only
  /// by the types it was registered under).
  final Set<Type> hidden;

  @override
  ObjectProvider<T> getBeanProvider<T extends Object>({String? qualifier}) =>
      _Provider<T>(
        hidden.contains(T)
            ? const []
            : [
                for (final bean in beans)
                  if (bean is T) bean,
              ],
        failing.contains(T),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Provider<T extends Object> implements ObjectProvider<T> {
  _Provider(this.found, this.fails);

  final List<T> found;
  final bool fails;

  @override
  T? getIfUnique([T Function()? defaultSupplier]) {
    if (fails) {
      throw StateError('the bean cannot be created');
    }
    return found.length == 1 ? found.single : defaultSupplier?.call();
  }

  @override
  List<T> orderedList() => found;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FixedProvider implements AuthenticationProvider {
  @override
  bool supports(Authentication authentication) =>
      authentication is UsernamePasswordAuthenticationToken;

  @override
  Future<Authentication?> authenticate(Authentication authentication) async =>
      UsernamePasswordAuthenticationToken.authenticated(
        'from-provider',
        null,
        AuthorityUtils.createAuthorityList(['ROLE_USER']),
      );
}

final class _Status implements AuthenticationEntryPoint, AccessDeniedHandler {
  const _Status(this.status);

  final int status;

  @override
  Future<void> commence(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException authException,
  ) async {
    response.statusCode = status;
    await response.close();
  }

  @override
  Future<void> handle(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AccessDeniedException accessDeniedException,
  ) async {
    response.statusCode = status;
    await response.close();
  }
}

final class _FixedManager implements AuthenticationManager {
  @override
  Future<Authentication> authenticate(Authentication authentication) async =>
      JwtAuthenticationToken(
        Jwt('t', headers: const {}, claims: const {'sub': 'from-manager'}),
        AuthorityUtils.createAuthorityList(['SCOPE_x']),
      );
}

void main() {
  group('authorization rules', () {
    test('denyAll: no one, logged in or not', () async {
      final chain = _http()
          .authorizeHttpRequests((a) => a.anyRequest().denyAll())
          .httpBasic()
          .build();
      expect(await _status(chain, '/x'), 401);
      expect(await _status(chain, '/x', 'admin'), 403);
    });

    test('fullyAuthenticated: logged-in users, not anonymous ones', () async {
      final chain = _http()
          .authorizeHttpRequests((a) => a.anyRequest().fullyAuthenticated())
          .httpBasic()
          .build();
      expect(await _status(chain, '/x'), 401);
      expect(await _status(chain, '/x', 'user'), 200);
    });

    test('anonymous: only those not logged in', () async {
      final chain = _http()
          .authorizeHttpRequests(
            (a) =>
                a.requestMatchers('/join').anonymous().anyRequest().denyAll(),
          )
          .httpBasic()
          .build();
      expect(await _status(chain, '/join'), 200);
      expect(await _status(chain, '/join', 'user'), 403);
    });

    test('hasAnyRole: one of the roles is enough, a prefix is added', () async {
      final chain = _http()
          .authorizeHttpRequests(
            (a) => a.anyRequest().hasAnyRole(['ADMIN', 'AUDITOR']),
          )
          .httpBasic()
          .build();
      expect(await _status(chain, '/x', 'admin'), 200);
      expect(await _status(chain, '/x', 'auditor'), 200);
      expect(await _status(chain, '/x', 'user'), 403);
      expect(await _status(chain, '/x'), 401);
    });

    test('hasAnyRole does not take an authority of the same name', () async {
      final chain = _http()
          .authorizeHttpRequests((a) => a.anyRequest().hasAnyRole(['read']))
          .httpBasic()
          .build();
      expect(await _status(chain, '/x', 'reader'), 403);
    });

    test('hasAnyAuthority: as written, no prefix', () async {
      final chain = _http()
          .authorizeHttpRequests(
            (a) => a.anyRequest().hasAnyAuthority(['read', 'write']),
          )
          .httpBasic()
          .build();
      expect(await _status(chain, '/x', 'reader'), 200);
      expect(await _status(chain, '/x', 'writer'), 200);
      expect(await _status(chain, '/x', 'admin'), 403);
      expect(await _status(chain, '/x', 'user'), 403);
    });

    test('hasAnyAuthority does not take a role', () async {
      final chain = _http()
          .authorizeHttpRequests(
            (a) => a.anyRequest().hasAnyAuthority(['ROLE_ADMIN']),
          )
          .httpBasic()
          .build();
      expect(await _status(chain, '/x', 'admin'), 200);
      expect(await _status(chain, '/x', 'auditor'), 403);
    });

    test('one rule takes up to six patterns', () async {
      final chain = _http()
          .authorizeHttpRequests(
            (a) => a
                .requestMatchers('/a', '/b', '/c', '/d', '/e', '/f')
                .permitAll()
                .anyRequest()
                .denyAll(),
          )
          .build();
      for (final path in ['/a', '/b', '/c', '/d', '/e', '/f']) {
        expect(await _status(chain, path), 200, reason: path);
      }
      expect(await _status(chain, '/g'), isNot(200));
    });

    test('two to five patterns are all used', () async {
      for (var count = 2; count <= 5; count++) {
        final paths = [for (var i = 0; i < count; i++) '/p$i'];
        final chain = _http()
            .authorizeHttpRequests(
              (a) => a
                  .requestMatchers(
                    paths[0],
                    paths[1],
                    count > 2 ? paths[2] : null,
                    count > 3 ? paths[3] : null,
                    count > 4 ? paths[4] : null,
                  )
                  .permitAll()
                  .anyRequest()
                  .denyAll(),
            )
            .build();
        for (final path in paths) {
          expect(await _status(chain, path), 200, reason: '$count: $path');
        }
        expect(await _status(chain, '/p9'), isNot(200));
      }
    });
  });

  group('the resource server settings', () {
    final keys = testKeys;
    NimbusJwtDecoder decoder() =>
        NimbusJwtDecoder.withPublicKey(keys.rsa.verificationKey);

    HttpSecurity server(
      void Function(OAuth2ResourceServerConfigurer server) configure, {
      String? authority,
    }) => HttpSecurity(null).authorizeHttpRequests(
      (a) => authority == null
          ? a.anyRequest().authenticated()
          : a.anyRequest().hasAuthority(authority),
    )..oauth2ResourceServer(configure);

    Future<Reply> call(
      SecurityFilterChain chain, {
      String? token,
      String path = '/x',
    }) => ChainClient(chain).get(
      path,
      accept: 'application/json',
      headers: token == null ? const {} : {'authorization': 'Bearer $token'},
    );

    test('jwt() with a decoder: a valid token logs in', () async {
      final chain = server((s) => s.jwt((j) => j.decoder(decoder()))).build();
      final reply = await call(
        chain,
        token: keys.token(claims: {'sub': 'ada', 'scope': 'read'}),
      );
      expect(reply.reached, isTrue);
      expect(reply.authentication, isA<JwtAuthenticationToken>());
      expect(reply.authentication!.name, 'ada');
    });

    test('jwt() called again keeps what was set', () async {
      final chain = server(
        (s) => s
          ..jwt((j) => j.decoder(decoder()))
          ..jwt(),
      ).build();
      expect((await call(chain, token: keys.token())).reached, isTrue);
    });

    test('a bad token and no token: 401 with a Bearer challenge', () async {
      final chain = server((s) => s.jwt((j) => j.decoder(decoder()))).build();
      final bad = await call(chain, token: 'not.a.jwt');
      expect(bad.status, 401);
      expect(bad.header('www-authenticate'), startsWith('Bearer'));
      expect(bad.header('www-authenticate'), contains('invalid_token'));
      final none = await call(chain);
      expect(none.status, 401);
      expect(none.header('www-authenticate'), 'Bearer');
    });

    test(
      'jwtAuthenticationConverter names the user and the authorities',
      () async {
        final chain = server(
          (s) => s.jwt(
            (j) => j
                .decoder(decoder())
                .jwtAuthenticationConverter(
                  const JwtAuthenticationConverter(
                    principalClaimName: 'email',
                    authoritiesConverter: JwtGrantedAuthoritiesConverter(
                      authorityPrefix: 'ROLE_',
                      authoritiesClaimName: 'roles',
                    ),
                  ),
                ),
          ),
          authority: 'ROLE_staff',
        ).build();
        final reply = await call(
          chain,
          token: keys.token(
            claims: {
              'sub': 'id-1',
              'email': 'ada@example.com',
              'roles': 'staff',
            },
          ),
        );
        expect(reply.reached, isTrue);
        expect(reply.authentication!.name, 'ada@example.com');
        expect((await call(chain, token: keys.token())).status, 403);
      },
    );

    test(
      'authenticationManager replaces the decoder and the provider',
      () async {
        final chain = server(
          (s) => s.jwt((j) => j.authenticationManager(_FixedManager())),
        ).build();
        final reply = await call(chain, token: 'anything.at.all');
        expect(reply.reached, isTrue);
        expect(reply.authentication!.name, 'from-manager');
      },
    );

    test('authenticationEntryPoint answers a missing or bad token', () async {
      final chain = server(
        (s) => s
          ..jwt((j) => j.decoder(decoder()))
          ..authenticationEntryPoint(const _Status(418)),
      ).build();
      expect((await call(chain)).status, 418);
      expect((await call(chain, token: 'x.y.z')).status, 418);
    });

    test(
      'accessDeniedHandler answers a token without the right scope',
      () async {
        final chain = server(
          (s) => s
            ..jwt((j) => j.decoder(decoder()))
            ..accessDeniedHandler(const _Status(419)),
          authority: 'SCOPE_admin',
        ).build();
        expect(
          (await call(
            chain,
            token: keys.token(claims: {'scope': 'read'}),
          )).status,
          419,
        );
        expect(
          (await call(
            chain,
            token: keys.token(claims: {'scope': 'admin'}),
          )).reached,
          isTrue,
        );
      },
    );

    test('the default denied answer is insufficient_scope', () async {
      final chain = server(
        (s) => s.jwt((j) => j.decoder(decoder())),
        authority: 'SCOPE_admin',
      ).build();
      final reply = await call(
        chain,
        token: keys.token(claims: {'scope': 'read'}),
      );
      expect(reply.status, 403);
      expect(reply.header('www-authenticate'), contains('insufficient_scope'));
    });

    test('bearerTokenResolver: the query parameter, when allowed', () async {
      final token = keys.token();
      final off = server((s) => s.jwt((j) => j.decoder(decoder()))).build();
      expect((await call(off, path: '/x?access_token=$token')).status, 401);
      final on = server(
        (s) => s
          ..jwt((j) => j.decoder(decoder()))
          ..bearerTokenResolver(
            const DefaultBearerTokenResolver(allowUriQueryParameter: true),
          ),
      ).build();
      expect((await call(on, path: '/x?access_token=$token')).reached, isTrue);
    });
  });

  group('the authentication manager among the beans', () {
    HttpSecurity http(ApplicationContext context) =>
        context.getBean<HttpSecurity>();

    Future<void> chainOf(
      ApplicationContextRunner runner,
      Future<void> Function(SecurityFilterChain chain) body,
    ) => runner.runAsync((started) async {
      expect(started.startupFailure, isNull);
      await body(
        http(started.context)
            .authorizeHttpRequests((a) => a.anyRequest().authenticated())
            .httpBasic()
            .build(),
      );
    });

    ApplicationContextRunner base() => securityRunner(null, [
      'spring.security.user.name=bean-user',
      'spring.security.user.password=bean-pw',
    ]);

    test(
      'the default user backs the chain when nothing else is there',
      () async {
        await chainOf(base(), (chain) async {
          final client = ChainClient(chain);
          expect(
            (await client.get(
              '/x',
              headers: basicHeader('bean-user', 'bean-pw'),
            )).reached,
            isTrue,
          );
          expect(
            (await client.get(
              '/x',
              headers: basicHeader('bean-user', 'no'),
            )).status,
            401,
          );
        });
      },
    );

    test('AuthenticationProvider beans make the manager', () async {
      await chainOf(
        base().withBean<AuthenticationProvider>(_FixedProvider.new),
        (chain) async {
          final reply = await ChainClient(chain)
              .get('/x', headers: basicHeader('whoever', 'whatever'));
          expect(reply.reached, isTrue);
          expect(reply.authentication!.name, 'from-provider');
        },
      );
    });

    test('an AuthenticationManager bean wins over providers', () async {
      final runner = base()
          .withBean<AuthenticationProvider>(_FixedProvider.new)
          .withBean<AuthenticationManager>(
            () => ProviderManager([DaoAuthenticationProvider(_users())]),
          );
      await chainOf(runner, (chain) async {
        final client = ChainClient(chain);
        expect(
          (await client.get(
            '/x',
            headers: basicHeader('admin', 'pw'),
          )).authentication!.name,
          'admin',
        );
        expect(
          (await client.get('/x', headers: basicHeader('whoever', 'x'))).status,
          401,
        );
      });
    });

    test(
      'a UserDetailsService that stores passwords is told to upgrade',
      () async {
        final store = _Store();
        final runner = base().withBean<UserDetailsService>(
          () => store,
          name: 'store',
        );
        await runner.runAsync((started) async {
          expect(started.startupFailure, isNull);
          final chain = started.context
              .getBean<HttpSecurity>()
              .authorizeHttpRequests((a) => a.anyRequest().authenticated())
              .httpBasic()
              .build();
          final reply = await ChainClient(chain)
              .get('/x', headers: basicHeader('ada', 'pw'));
          expect(reply.reached, isTrue);
          expect(store.updates.keys, ['ada']);
          // An argon2 hash, not the password: checking that the hash does
          // not contain `pw` failed now and then, as a random salt can.
          expect(store.updates['ada'], startsWith(r'{argon2}$argon2id$'));
        });
      },
    );

    test(
      'two beans of one optional type are not a choice: none is used',
      () async {
        final first = _Events();
        final second = _Events();
        final runner = base()
            .withBean<AuthenticationEventPublisher>(() => first, name: 'first')
            .withBean<AuthenticationEventPublisher>(
              () => second,
              name: 'second',
            );
        await runner.runAsync((started) async {
          expect(started.startupFailure, isNull);
          final chain = started.context
              .getBean<HttpSecurity>()
              .authorizeHttpRequests((a) => a.anyRequest().authenticated())
              .httpBasic()
              .build();
          final reply = await ChainClient(chain)
              .get('/x', headers: basicHeader('bean-user', 'bean-pw'));
          expect(reply.reached, isTrue);
          expect(first.successes + second.successes, 0);
        });
      },
    );

    test('one event publisher bean is told of the logins', () async {
      final events = _Events();
      final runner = base().withBean<AuthenticationEventPublisher>(
        () => events,
      );
      await runner.runAsync((started) async {
        final chain = started.context
            .getBean<HttpSecurity>()
            .authorizeHttpRequests((a) => a.anyRequest().authenticated())
            .httpBasic()
            .build();
        final client = ChainClient(chain);
        await client.get('/x', headers: basicHeader('bean-user', 'bean-pw'));
        await client.get('/x', headers: basicHeader('bean-user', 'wrong'));
        expect(events.successes, 1);
        expect(events.failures, 1);
      });
    });

    test(
      'one RoleHierarchy bean widens hasAnyRole and the role prefix',
      () async {
        final runner = base().withBean<RoleHierarchy>(
          () => RoleHierarchyImpl.fromHierarchy('ROLE_ADMIN > ROLE_USER'),
        );
        await runner.runAsync((started) async {
          final chain = started.context
              .getBean<HttpSecurity>()
              .userDetailsService(_users())
              .authorizeHttpRequests(
                (a) => a.anyRequest().hasAnyRole(['USER', 'NOBODY']),
              )
              .httpBasic()
              .build();
          expect(await _status(chain, '/x', 'admin'), 200);
          expect(await _status(chain, '/x', 'auditor'), 403);
        });
      },
    );
  });

  group('the authentication manager without the core auto-configuration', () {
    SecurityFilterChain basicChain(BeanFactory beans) =>
        HttpSecurity(beans)
            .authorizeHttpRequests((a) => a.anyRequest().authenticated())
            .httpBasic()
            .build();

    test('providers alone make the manager', () async {
      final chain = basicChain(_Beans([_FixedProvider()]));
      final reply = await ChainClient(chain)
          .get('/x', headers: basicHeader('whoever', 'whatever'));
      expect(reply.reached, isTrue);
      expect(reply.authentication!.name, 'from-provider');
    });

    test('a user service that stores passwords is told to upgrade', () async {
      final store = _Store();
      final chain = basicChain(_Beans([store]));
      final reply = await ChainClient(chain)
          .get('/x', headers: basicHeader('ada', 'pw'));
      expect(reply.reached, isTrue);
      expect(store.updates['ada'], startsWith('{argon2}'));
    });

    test(
      'a user service known only as such is still told to upgrade',
      () async {
        final store = _Store();
        final chain = basicChain(
          _Beans([store], hidden: {UserDetailsPasswordService}),
        );
        await ChainClient(chain).get('/x', headers: basicHeader('ada', 'pw'));
        expect(store.updates['ada'], startsWith('{argon2}'));
      },
    );

    test('a wrong password does not touch the stored one', () async {
      final store = _Store();
      final chain = basicChain(_Beans([store]));
      final reply = await ChainClient(chain)
          .get('/x', headers: basicHeader('ada', 'wrong'));
      expect(reply.status, 401);
      expect(store.updates, isEmpty);
    });

    test('no bean at all: building the chain says what is missing', () {
      expect(() => basicChain(_Beans(const [])), throwsStateError);
    });

    test('a bean that fails to be created fails the chain, never replaced '
        'by a default (like Spring)', () {
      for (final type in [PasswordEncoder, AuthenticationEventPublisher]) {
        expect(
          () => basicChain(_Beans([_Store()], failing: {type})),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'the bean cannot be created',
            ),
          ),
          reason: '$type',
        );
      }
    });
  });
}
