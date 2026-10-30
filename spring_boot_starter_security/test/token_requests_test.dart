// Requests that carry an access token, in chains with CSRF protection on:
// a `Bearer` or `DPoP` token in the header needs no CSRF token (Spring's
// registerDefaultCsrfOverride), in the default chain and in a chain of the
// application's that also has browser sessions; a token in the query
// string never exempts a request, nor does a header at the logout and
// login URLs; a forged token header never rides a session; and each token
// request publishes exactly one authentication event, after every
// check.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app/jwt/keys.dart';
import 'chain_support.dart';
import 'dpop_support.dart';
import 'support.dart';

const _jwt = 'spring.security.oauth2.resourceserver.jwt';

// Bound to a client certificate (RFC 8705), which no request here has.
final String _certificateBound = testKeys.token(
  claims: {
    'cnf': {'x5t#S256': sha256Base64Url('a client certificate')},
  },
);

JwtDecoder _decoder() => NimbusJwtDecoder.withJwkSource(
  StaticJwkSource([testKeys.rsa.verificationKey, testKeys.ec.verificationKey]),
);

final class _Beans implements BeanFactory {
  _Beans(this.beans);

  final List<Object> beans;

  @override
  ObjectProvider<T> getBeanProvider<T extends Object>({String? qualifier}) =>
      _Provider<T>([
        for (final bean in beans)
          if (bean is T) bean,
      ]);

  // No bean is known by name (the chain looks for a bean named
  // corsConfigurationSource).
  @override
  bool containsBean(String name) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Provider<T extends Object> implements ObjectProvider<T> {
  _Provider(this.found);

  final List<T> found;

  @override
  T? getIfUnique([T Function()? defaultSupplier]) =>
      found.length == 1 ? found.single : defaultSupplier?.call();

  @override
  List<T> orderedList() => found;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Events implements AuthenticationEventPublisher {
  final successes = <Authentication>[];
  final failures = <AuthenticationException>[];

  int get count => successes.length + failures.length;

  void clear() {
    successes.clear();
    failures.clear();
  }

  @override
  void publishAuthenticationSuccess(Authentication authentication) =>
      successes.add(authentication);

  @override
  void publishAuthenticationFailure(
    AuthenticationException exception,
    Authentication authentication,
  ) => failures.add(exception);
}

void main() {
  final client = ProofSigner.ec();

  group('the default chain (issuer properties): token requests need no '
      'CSRF token', () {
    Future<void> app(Future<void> Function(MockMvc mvc) body) =>
        securityRunner(null, [
          '$_jwt.jwk-set-uri=https://issuer.example/jwks',
        ]).withBean<JwtDecoder>(_decoder).runAsync((started) async {
          expect(started.startupFailure, isNull);
          await body(MockMvc.of(started.context));
        });

    MockRequestBuilder post(Map<String, String> headers, {String? method}) =>
        MockRequestBuilder(
            method == null ? HttpMethod.post : HttpMethod.parse(method),
            '/api/data',
          )
          ..headers.addAll(headers)
          ..headers['content-type'] = 'text/plain'
          ..content('order');

    test(
      'POST with a Bearer token',
      () => app((mvc) async {
        final token = testKeys.token();
        await mvc
            .perform(post({'authorization': 'Bearer $token'}))
            .andExpect(status: 200, body: 'got order');
      }),
    );

    test(
      'PUT and DELETE with a Bearer token reach the router (405, not 403)',
      () => app((mvc) async {
        final token = testKeys.token();
        for (final method in ['PUT', 'DELETE', 'PATCH']) {
          final result = await mvc.perform(
            post({'authorization': 'Bearer $token'}, method: method),
          );
          expect(result.status, 405, reason: method);
        }
      }),
    );

    test(
      'POST with a DPoP token and its proof',
      () => app((mvc) async {
        final token = boundToken(client);
        await mvc
            .perform(
              post(
                dPoPHeaders(
                  token,
                  client.proof(
                    accessToken: token,
                    method: 'POST',
                    url: 'http://localhost/api/data',
                  ),
                ),
              ),
            )
            .andExpect(status: 200, body: 'got order');
      }),
    );

    test(
      'a refused token is a 401 of the token filter, not a pass',
      () => app((mvc) async {
        final result = await mvc.perform(
          post({'authorization': 'Bearer not.a.token'}),
        );
        expect(result.status, 401);
        expect(
          result.header('www-authenticate'),
          contains('error="invalid_token"'),
        );
        final dPoP = await mvc.perform(
          post({'authorization': 'DPoP not.a.token', 'dpop': 'x.y.z'}),
        );
        expect(dPoP.status, 401);
        expect(dPoP.header('www-authenticate'), startsWith('DPoP'));
      }),
    );

    test(
      'the logout URL keeps its CSRF check, even with a token header',
      () => app((mvc) async {
        final token = boundToken(client);
        for (final headers in [
          {'authorization': 'Bearer ${testKeys.token()}'},
          dPoPHeaders(
            token,
            client.proof(
              accessToken: token,
              method: 'POST',
              url: 'http://localhost/logout',
            ),
          ),
        ]) {
          final result = await mvc.perform(
            MockRequestBuilder(HttpMethod.post, '/logout')
              ..headers.addAll(headers),
          );
          expect(result.status, 403, reason: '$headers');
        }
      }),
    );

    test(
      'without a token, or with one no token filter takes, the CSRF check '
      'stays (403)',
      () => app((mvc) async {
        for (final headers in [
          <String, String>{},
          {'authorization': 'Bearer a b'}, // malformed
          {'authorization': 'Basic YTpi'},
          {'authorization': 'DPoP ${boundToken(client)}'}, // no proof
        ]) {
          final result = await mvc.perform(post(headers));
          expect(result.status, 403, reason: '$headers');
        }
      }),
    );
  });

  group('a chain of the application: browser sessions and tokens', () {
    // The example server's single sign-on chain in small: sessions with
    // CSRF for the browser, tokens for apps.
    SecurityFilterChain chain() =>
        (HttpSecurity(_Beans([_decoder()]))..userDetailsService(testUsers()))
            .authorizeHttpRequests((a) => a.anyRequest().authenticated())
            .formLogin()
            .oauth2ResourceServer((s) => s.jwt())
            .build();

    Future<ChainClient> browser() async {
      final browser = ChainClient(chain());
      final login = await browser.login('root', 'root-pw');
      expect(login.status, 302);
      expect((await browser.get('/api/me')).authentication?.name, 'root');
      return browser;
    }

    test(
      'the session alone does not post: CSRF still protects it',
      () async {
        final session = await browser();
        final forged = await session.send(HttpMethod.post, '/api/data');
        expect(forged.status, 403);
        expect(forged.reached, isFalse);
      },
    );

    test(
      'a forged token header cannot ride the session: 401, never the '
      'session user',
      () async {
        final session = await browser();
        for (final headers in [
          {'authorization': 'Bearer forged'},
          {'authorization': 'Bearer ${testKeys.token(alg: 'HS256')}'},
          {'authorization': 'DPoP forged', 'dpop': 'forged'},
          // A real DPoP token with a proof of another key.
          {
            'authorization': 'DPoP ${boundToken(client)}',
            'dpop': ProofSigner.ec().proof(method: 'POST'),
          },
        ]) {
          final reply = await session.send(
            HttpMethod.post,
            '/api/data',
            headers: headers,
          );
          expect(reply.status, 401, reason: '$headers');
          expect(reply.reached, isFalse, reason: '$headers');
        }
      },
    );

    test(
      "a valid token decides who calls, not the browser's session",
      () async {
        final session = await browser();
        final reply = await session.send(
          HttpMethod.post,
          '/api/data',
          headers: {'authorization': 'Bearer ${testKeys.token()}'},
        );
        expect(reply.reached, isTrue);
        expect(reply.authentication, isA<JwtAuthenticationToken>());
        expect(reply.authentication?.name, 'ada');
      },
    );

    test('an app posts with its token, no session, no CSRF token', () async {
      final app = ChainClient(chain());
      final bearer = await app.send(
        HttpMethod.delete,
        '/api/data',
        headers: {'authorization': 'Bearer ${testKeys.token()}'},
      );
      expect(bearer.reached, isTrue);
      final token = boundToken(client);
      final dPoP = await app.send(
        HttpMethod.put,
        '/api/data',
        headers: dPoPHeaders(
          token,
          client.proof(
            accessToken: token,
            method: 'PUT',
            url: 'http://localhost/api/data',
          ),
        ),
      );
      expect(dPoP.reached, isTrue);
      expect(dPoP.authentication, isA<JwtAuthenticationToken>());
      expect(app.cookies, isEmpty);
    });

    // The logout and login filters act on the session before the token
    // filters run: a token header there would decide nothing, so the CSRF
    // check stays (Spring exempts them).
    test('a token header does not exempt the logout and login URLs', () async {
      final token = boundToken(client);
      Map<String, String> dPoP(String path) => dPoPHeaders(
        token,
        client.proof(
          accessToken: token,
          method: 'POST',
          url: 'http://localhost$path',
        ),
      );
      final session = await browser();
      for (final headers in [
        {'authorization': 'Bearer ${testKeys.token()}'},
        {'authorization': 'Bearer forged'},
        dPoP('/logout'),
      ]) {
        final logout = await session.send(
          HttpMethod.post,
          '/logout',
          headers: headers,
        );
        expect(logout.status, 403, reason: '$headers');
        expect(
          (await session.get('/api/me')).authentication?.name,
          'root',
          reason: 'still logged in after $headers',
        );
      }
      // Login CSRF: the attacker's credentials posted without the token.
      for (final headers in [
        {'authorization': 'Bearer ${testKeys.token()}'},
        dPoP('/login'),
      ]) {
        final victim = ChainClient(chain());
        final login = await victim.post('/login', {
          'username': 'ada',
          'password': 'ada-pw',
        }, headers: headers);
        expect(login.status, 403, reason: '$headers');
        expect((await victim.get('/api/me')).authentication, isNull);
      }
    });

    test(
      'a token header of another name exempts as Authorization does',
      () async {
        final app = ChainClient(
          (HttpSecurity(_Beans([_decoder()]))..userDetailsService(testUsers()))
              .authorizeHttpRequests((a) => a.anyRequest().authenticated())
              .formLogin()
              .oauth2ResourceServer(
                (s) => s.jwt().bearerTokenResolver(
                  const DefaultBearerTokenResolver(
                    bearerTokenHeaderName: 'X-Token',
                  ),
                ),
              )
              .build(),
        );
        final reply = await app.send(
          HttpMethod.post,
          '/api/data',
          headers: {'x-token': 'Bearer ${testKeys.token()}'},
        );
        expect(reply.reached, isTrue);
        expect(reply.authentication?.name, 'ada');
      },
    );
  });

  // `allowUriQueryParameter`, for server-sent events from a browser: the
  // parameter is read in GET requests only, and never exempts a request
  // from CSRF, since any page can post a form to a URL that carries one.
  group('a token in the query string', () {
    SecurityFilterChain chain() =>
        (HttpSecurity(_Beans([_decoder()]))..userDetailsService(testUsers()))
            .authorizeHttpRequests((a) => a.anyRequest().authenticated())
            .formLogin()
            .oauth2ResourceServer(
              (s) => s.jwt().bearerTokenResolver(
                const DefaultBearerTokenResolver(allowUriQueryParameter: true),
              ),
            )
            .build();

    test('logs a GET in (server-sent events)', () async {
      final reply = await ChainClient(chain()).get(
        '/api/events?access_token=${testKeys.token()}',
        accept: 'text/event-stream',
      );
      expect(reply.reached, isTrue);
      expect(reply.authentication, isA<JwtAuthenticationToken>());
      expect(reply.authentication?.name, 'ada');
    });

    test(
      'a cross-site form to /logout?access_token=x is refused (403), the '
      'user stays logged in',
      () async {
        final session = ChainClient(chain());
        expect((await session.login('root', 'root-pw')).status, 302);
        for (final token in [testKeys.token(), 'x']) {
          final logout = await session.post('/logout?access_token=$token', {});
          expect(logout.status, 403, reason: token);
          expect((await session.get('/api/me')).authentication?.name, 'root');
        }
      },
    );

    test(
      'a cross-site form to /login?access_token=x is refused (403): no '
      "login with the attacker's credentials",
      () async {
        for (final token in [testKeys.token(), 'x']) {
          final victim = ChainClient(chain());
          final login = await victim.post('/login?access_token=$token', {
            'username': 'ada',
            'password': 'ada-pw',
          });
          expect(login.status, 403, reason: token);
          expect((await victim.get('/api/me')).authentication, isNull);
        }
      },
    );

    test(
      'a POST to the API with the session and a query token keeps the CSRF '
      'check (403), the token is not read',
      () async {
        final session = ChainClient(chain());
        expect((await session.login('root', 'root-pw')).status, 302);
        final reply = await session.send(
          HttpMethod.post,
          '/api/data?access_token=${testKeys.token()}',
        );
        expect(reply.status, 403);
        expect(reply.reached, isFalse);
        // An app without a session: no CSRF token, no token read, refused.
        final app = await ChainClient(chain()).send(
          HttpMethod.post,
          '/api/data?access_token=${testKeys.token()}',
          headers: {'accept': 'application/json'},
        );
        expect(app.status, 403);
        expect(app.reached, isFalse);
      },
    );
  });

  group('one authentication event per token request, after every check', () {
    late _Events events;
    late ChainClient api;

    setUp(() {
      events = _Events();
      api = ChainClient(
        HttpSecurity(_Beans([_decoder(), events]))
            .authorizeHttpRequests((a) => a.anyRequest().authenticated())
            .oauth2ResourceServer((s) => s.jwt())
            .build(),
      );
    });

    Future<void> expectEvents(
      Map<String, String> headers, {
      required int status,
      required bool success,
    }) async {
      events.clear();
      final reply = await api.get(
        '/api/me',
        accept: 'application/json',
        headers: headers,
      );
      expect(reply.status, status, reason: '$headers');
      expect(events.count, 1, reason: 'events for $headers');
      expect(events.successes, success ? hasLength(1) : isEmpty);
    }

    test('a valid Bearer token: one success', () async {
      await expectEvents(
        {'authorization': 'Bearer ${testKeys.token()}'},
        status: 200,
        success: true,
      );
    });

    test('a refused Bearer token: one failure', () async {
      await expectEvents(
        {'authorization': 'Bearer ${testKeys.token(alg: 'HS256')}'},
        status: 401,
        success: false,
      );
    });

    test(
      'a DPoP-bound token sent as Bearer: one failure, no success',
      () async {
        await expectEvents(
          {'authorization': 'Bearer ${boundToken(client)}'},
          status: 401,
          success: false,
        );
        expect(
          events.failures.single.message,
          contains('DPoP-bound'),
        );
      },
    );

    test(
      'a token bound to a client certificate: one failure, no success',
      () async {
        await expectEvents(
          {'authorization': 'Bearer $_certificateBound'},
          status: 401,
          success: false,
        );
        expect(
          events.failures.single.message,
          contains('client certificate'),
        );
      },
    );

    test('a Bearer filter built with another manager still refuses a '
        'DPoP-bound or certificate-bound token', () async {
      final filter = BearerTokenAuthenticationFilter(
        ProviderManager([JwtAuthenticationProvider(_decoder())]),
      );
      for (final (token, refusal) in [
        (boundToken(client), 'DPoP-bound'),
        (_certificateBound, 'client certificate'),
      ]) {
        final (request, response) = await exchange(
          newSessions(),
          path: '/api/me',
          headers: {'authorization': 'Bearer $token'},
        );
        final application = Application();
        await filter.doFilter(request, response, application);
        expect(response.statusCode, 401);
        expect(application.reached, isFalse);
        expect(response.headers['www-authenticate'], contains(refusal));
      }
    });

    test('a valid DPoP request: one success', () async {
      final token = boundToken(client);
      await expectEvents(
        dPoPHeaders(token, client.proof(accessToken: token)),
        status: 200,
        success: true,
      );
    });

    test('a valid DPoP token with a refused proof: one failure, no success '
        'for the token checked before the proof', () async {
      final token = boundToken(client);
      for (final proof in [
        ProofSigner.ec().proof(accessToken: token), // another key
        client.proof(accessToken: token, method: 'POST'), // another htm
        client.proof(accessToken: 'another token'), // another ath
      ]) {
        await expectEvents(
          dPoPHeaders(token, proof),
          status: 401,
          success: false,
        );
      }
      // An unbound token with the DPoP scheme.
      final unbound = testKeys.token();
      await expectEvents(
        dPoPHeaders(unbound, client.proof(accessToken: unbound)),
        status: 401,
        success: false,
      );
    });
  });
}
