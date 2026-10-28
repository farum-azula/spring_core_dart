// The parts of oauth2Login() one by one: every option of the configurer, the
// repositories, the providers and the filter on inputs a normal login never
// produces (another repository, a registration gone, a manager that answers
// something else), and the logout handler's corners.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'app/jwt/keys.dart';
import 'chain_support.dart';
import 'oauth2_support.dart';

/// A repository whose registrations can disappear, and that cannot list
/// them (not an InMemoryClientRegistrationRepository).
final class _Registrations implements ClientRegistrationRepository {
  _Registrations(this.registrations);

  final Map<String, ClientRegistration> registrations;

  @override
  Future<ClientRegistration?> findByRegistrationId(String id) async =>
      registrations[id];
}

final class _Recording implements OAuth2AuthorizationRequestRepository {
  final saved = <OAuth2AuthorizationRequest?>[];
  final delegate = const HttpSessionOAuth2AuthorizationRequestRepository();

  @override
  OAuth2AuthorizationRequest? loadAuthorizationRequest(
    ServerHttpRequest request,
  ) => delegate.loadAuthorizationRequest(request);

  @override
  Future<void> saveAuthorizationRequest(
    OAuth2AuthorizationRequest? authorizationRequest,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) {
    saved.add(authorizationRequest);
    return delegate.saveAuthorizationRequest(
      authorizationRequest,
      request,
      response,
    );
  }

  @override
  OAuth2AuthorizationRequest? removeAuthorizationRequest(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) => delegate.removeAuthorizationRequest(request, response);
}

final class _Handler
    implements AuthenticationSuccessHandler, AuthenticationFailureHandler {
  Authentication? success;
  AuthenticationException? failure;

  @override
  Future<void> onAuthenticationSuccess(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Authentication authentication,
  ) async {
    success = authentication;
    response.statusCode = 204;
    await response.close();
  }

  @override
  Future<void> onAuthenticationFailure(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException exception,
  ) async {
    failure = exception;
    response.statusCode = 401;
    await response.close();
  }
}

final class _Manager implements AuthenticationManager {
  _Manager(this.answer);

  final Future<Authentication> Function(Authentication) answer;

  @override
  Future<Authentication> authenticate(Authentication authentication) =>
      answer(authentication);
}

String? _code(AuthenticationException? e) =>
    e is OAuth2AuthenticationException ? e.error.errorCode : null;

void main() {
  group('the configurer', () {
    test('other paths, handlers and repositories', () async {
      final provider = FakeOidcProvider();
      final registration = ClientRegistration.withClientRegistration(
        await provider.registration(),
      ).redirectUri('{baseUrl}/sso/callback/{registrationId}').build();
      final registrations = InMemoryClientRegistrationRepository([
        registration,
      ]);
      final requests = _Recording();
      final handler = _Handler();
      final chain = oauth2Http(
        provider,
        registrations,
        customizer: (login) => login
            .authorizationEndpoint(
              (endpoint) => endpoint
                  .baseUri('/sso/start/')
                  .authorizationRequestRepository(requests)
                  .authorizationRequestResolver(
                    DefaultOAuth2AuthorizationRequestResolver(
                      registrations,
                      authorizationRequestBaseUri: '/sso/start/',
                      additionalParameters: (request, registration) => {
                        'kc_idp_hint': 'google',
                        'state': 'ignored',
                      },
                    ),
                  ),
            )
            .redirectionEndpoint((endpoint) => endpoint.baseUri('/x/*'))
            .loginProcessingUrl('/sso/callback/*')
            .authorizedClientRepository(
              const HttpSessionOAuth2AuthorizedClientRepository(),
            )
            .successHandler(handler)
            .failureHandler(handler),
      ).build();
      final client = ChainClient(chain);

      expect(
        (await client.get('/private')).header('location'),
        '/sso/start/keycloak',
      );
      final start = await client.get('/sso/start/keycloak');
      final authorization = Uri.parse(start.header('location')!);
      expect(authorization.queryParameters['kc_idp_hint'], 'google');
      expect(authorization.queryParameters['state'], isNot('ignored'));
      expect(
        requests.saved.single?.state,
        authorization.queryParameters['state'],
      );

      final callback = provider.approve(authorization);
      expect(callback.path, '/sso/callback/keycloak');
      final reply = await client.callback(callback);
      expect(reply.status, 204);
      expect(handler.success?.name, 'user-1');
      final (request, _) = await exchange(
        client.sessions,
        cookies: client.cookies,
      );
      final stored = await const HttpSessionOAuth2AuthorizedClientRepository()
          .loadAuthorizedClient('keycloak', handler.success, request);
      expect(stored?.principalName, 'user-1');

      // A replay reaches the failure handler.
      expect((await client.callback(callback)).status, 401);
      expect(_code(handler.failure), 'authorization_request_not_found');
    });

    test('failureUrl', () async {
      final provider = FakeOidcProvider();
      final client = ChainClient(
        oauth2Http(
          provider,
          InMemoryClientRegistrationRepository([await provider.registration()]),
          customizer: (login) => login.failureUrl('/oops'),
        ).build(),
      );
      final reply = await client.get('/login/oauth2/code/keycloak?code=c');
      expect(reply.header('location'), '/oops');
      expect(
        () => HttpSecurity(null).oauth2Login((l) => l.failureUrl('oops')),
        throwsArgumentError,
      );
    });

    test('without a ClientRegistrationRepository the chain fails', () {
      expect(
        () => HttpSecurity(null).oauth2Login().build(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('ClientRegistrationRepository'),
          ),
        ),
      );
    });

    test('without beans: the platform transport, a JWK decoder', () async {
      final registrations = InMemoryClientRegistrationRepository([
        await FakeOidcProvider().registration(),
      ]);
      final chain = HttpSecurity(null)
          .oauth2Login(
            (login) => login.clientRegistrationRepository(registrations),
          )
          .build();
      expect(
        filterTypes(chain),
        containsAllInOrder([
          OAuth2AuthorizationRequestRedirectFilter,
          OAuth2LoginAuthenticationFilter,
          DefaultLoginPageGeneratingFilter,
          DefaultLogoutPageGeneratingFilter,
        ]),
      );
    });

    test('a repository that cannot list: no links, the login page', () async {
      final provider = FakeOidcProvider();
      final client = ChainClient(
        oauth2Http(
          provider,
          _Registrations({'keycloak': await provider.registration()}),
        ).build(),
      );
      expect((await client.get('/private')).header('location'), '/login');
      expect((await client.get('/login')).body, isNot(contains('<a href')));
      // It still logs in.
      await client.loginWith(provider, 'keycloak');
      expect((await client.get('/private')).reached, isTrue);
    });

    test('a provider that cannot be discovered is listed by its id', () async {
      final provider = FakeOidcProvider();
      var down = true;
      final registrations = InMemoryClientRegistrationRepository.lazy({
        'keycloak': () async => down
            ? throw StateError('down')
            : await provider.registration(clientName: 'Keycloak'),
      });
      final client = ChainClient(oauth2Http(provider, registrations).build());
      expect(
        (await client.get('/login')).body,
        contains('>keycloak</a>'),
      );
      expect(
        (await client.get('/private')).header('location'),
        '/oauth2/authorization/keycloak',
      );
      down = false;
      expect((await client.get('/login')).body, contains('>Keycloak</a>'));
    });
  });

  group('the repositories', () {
    test('saving null removes the authorization request', () async {
      final sessions = newSessions();
      const repository = HttpSessionOAuth2AuthorizationRequestRepository();
      final provider = FakeOidcProvider();
      final request = OAuth2AuthorizationRequest.forRegistration(
        await provider.registration(),
        redirectUri: 'http://localhost/login/oauth2/code/keycloak',
      );
      final (setup, response) = await exchange(sessions);
      await repository.saveAuthorizationRequest(request, setup, response);
      final (callback, _) = await exchange(
        sessions,
        path: '/cb?state=${request.state}',
        cookies: {'JSESSIONID': setup.getSession(create: false)!.id},
      );
      expect(repository.loadAuthorizationRequest(callback), request);
      await repository.saveAuthorizationRequest(null, callback, response);
      expect(repository.loadAuthorizationRequest(callback), isNull);
      await expectLater(
        repository.saveAuthorizationRequest(
          OAuth2AuthorizationRequest(
            authorizationUri: 'https://sso.test/auth',
            clientId: clientId,
            redirectUri: 'http://localhost/cb',
            state: '',
          ),
          setup,
          response,
        ),
        throwsArgumentError,
      );
    });

    test('the clients of logged-in users go to the service', () async {
      final provider = FakeOidcProvider();
      final registration = await provider.registration();
      final service = InMemoryOAuth2AuthorizedClientService(
        InMemoryClientRegistrationRepository([registration]),
      );
      final repository = AuthenticatedPrincipalOAuth2AuthorizedClientRepository(
        service,
      );
      final (request, response) = await exchange(newSessions());
      final user = UsernamePasswordAuthenticationToken.authenticated(
        'ada',
        null,
        const [],
      );
      final client = OAuth2AuthorizedClient(
        registration,
        'ada',
        OAuth2AccessToken(TokenType.bearer, 'a'),
      );
      await repository.saveAuthorizedClient(client, user, request, response);
      expect(await service.loadAuthorizedClient('keycloak', 'ada'), client);
      expect(
        await repository.loadAuthorizedClient('keycloak', user, request),
        client,
      );
      await repository.removeAuthorizedClient(
        'keycloak',
        user,
        request,
        response,
      );
      expect(await service.loadAuthorizedClient('keycloak', 'ada'), isNull);
    });

    test('the session keeps the clients of several registrations', () async {
      final provider = FakeOidcProvider();
      final keycloak = await provider.registration();
      final github = provider.oauth2Registration();
      const repository = HttpSessionOAuth2AuthorizedClientRepository();
      final (request, response) = await exchange(newSessions());
      OAuth2AuthorizedClient client(ClientRegistration registration) =>
          OAuth2AuthorizedClient(
            registration,
            'ada',
            OAuth2AccessToken(TokenType.bearer, registration.registrationId),
          );
      await repository.saveAuthorizedClient(
        client(keycloak),
        null,
        request,
        response,
      );
      await repository.saveAuthorizedClient(
        client(github),
        null,
        request,
        response,
      );
      await repository.removeAuthorizedClient(
        'keycloak',
        null,
        request,
        response,
      );
      await repository.removeAuthorizedClient('nope', null, request, response);
      expect(
        await repository.loadAuthorizedClient('keycloak', null, request),
        isNull,
      );
      expect(
        (await repository.loadAuthorizedClient(
          'github',
          null,
          request,
        ))?.accessToken.tokenValue,
        'github',
      );
    });

    test('an unknown registration names itself in the exception', () {
      expect(
        InvalidClientRegistrationIdException('x').toString(),
        'InvalidClientRegistrationIdException: x',
      );
    });
  });

  group('the providers', () {
    Future<OAuth2LoginAuthenticationToken> token({
      String? state,
      String? code = 'code',
    }) async {
      final provider = FakeOidcProvider();
      final registration = await provider.registration();
      final request = OAuth2AuthorizationRequest.forRegistration(
        registration,
        redirectUri: 'http://localhost/login/oauth2/code/keycloak',
      );
      return OAuth2LoginAuthenticationToken.unauthenticated(
        registration,
        OAuth2AuthorizationExchange(
          request,
          OAuth2AuthorizationResponse(
            redirectUri: request.redirectUri,
            code: code,
            state: state ?? request.state,
          ),
        ),
      );
    }

    final transport = MockHttpTransport();
    final oidc = OidcAuthorizationCodeAuthenticationProvider(
      DefaultAuthorizationCodeTokenResponseClient(transport),
      OidcUserService(transport),
    );

    test('a state other than the request (another repository)', () async {
      await expectLater(
        oidc.authenticate(await token(state: 'other')),
        throwsA(
          isA<OAuth2AuthenticationException>().having(
            (e) => e.error.errorCode,
            'code',
            'invalid_state_parameter',
          ),
        ),
      );
      expect(transport.requests, isEmpty);
    });

    test('neither a code nor an error', () async {
      await expectLater(
        oidc.authenticate(await token(code: null)),
        throwsA(
          isA<OAuth2AuthenticationException>().having(
            (e) => e.error.errorCode,
            'code',
            'invalid_request',
          ),
        ),
      );
    });

    test('the default decoder checks signatures', () {
      expect(oidc.idTokenDecoder, isA<OidcIdTokenDecoderFactory>());
    });

    test('the login request shows no token', () async {
      final login = await token();
      expect(login.toString(), isNot(contains('code')));
      expect(login.toString(), contains('authenticated=false'));
      expect(login.credentials, '');
    });
  });

  group('the filter', () {
    Future<(ChainClient, _Handler, Uri)> started(
      AuthenticationManager manager, {
      Map<String, ClientRegistration>? registrations,
    }) async {
      final provider = FakeOidcProvider();
      final repository = _Registrations(
        registrations ?? {'keycloak': await provider.registration()},
      );
      final handler = _Handler();
      final filter = OAuth2LoginAuthenticationFilter(
        repository,
        const HttpSessionOAuth2AuthorizedClientRepository(),
        manager,
        failureHandler: handler,
        successHandler: handler,
      );
      final chain = DefaultSecurityFilterChain(AnyRequestMatcher.instance, [
        OAuth2AuthorizationRequestRedirectFilter(
          DefaultOAuth2AuthorizationRequestResolver(repository),
        ),
        filter,
      ]);
      final client = ChainClient(chain);
      final callback = provider.approve(await client.startLogin('keycloak'));
      return (client, handler, callback);
    }

    test('a refusal that is not an OAuth 2.0 error', () async {
      final (client, handler, callback) = await started(
        _Manager((_) async => throw BadCredentialsException('no')),
      );
      expect((await client.callback(callback)).status, 401);
      expect(handler.failure, isA<BadCredentialsException>());
    });

    test('a registration gone since the login started', () async {
      final provider = FakeOidcProvider();
      final registrations = {'keycloak': await provider.registration()};
      final (client, handler, callback) = await started(
        _Manager((_) async => throw StateError('not called')),
        registrations: registrations,
      );
      registrations.clear();
      await client.callback(callback);
      expect(_code(handler.failure), 'client_registration_not_found');
    });

    test('a manager that answers something else fails closed', () async {
      final (client, handler, callback) = await started(
        _Manager(
          (_) async => UsernamePasswordAuthenticationToken.authenticated(
            'ada',
            null,
            const [],
          ),
        ),
      );
      expect((await client.callback(callback)).status, 401);
      expect(handler.failure, isA<InternalAuthenticationServiceException>());
      expect(handler.success, isNull);
    });
  });

  group('OidcIdTokenDecoderFactory', () {
    test('the transport fetcher refuses errors and huge key sets', () async {
      final transport = MockHttpTransport()
        ..when(HttpMethod.get, 'https://sso.test/missing').respond(404)
        ..when(
          HttpMethod.get,
          'https://sso.test/huge',
        ).respond(200, body: 'x' * ((1 << 20) + 1));
      final fetch = transportJwkFetcher(transport);
      await expectLater(
        fetch(Uri.parse('https://sso.test/missing')),
        throwsA(isA<JwtException>()),
      );
      await expectLater(
        fetch(Uri.parse('https://sso.test/huge')),
        throwsA(isA<JwtException>()),
      );
    });

    test('HS256 without a client secret cannot be checked', () async {
      final registration = ClientRegistration.withClientRegistration(
        await FakeOidcProvider().registration(),
      ).clientSecret(null).build();
      await expectLater(
        OidcIdTokenDecoderFactory(
          jwsAlgorithmResolver: (_) => JwsAlgorithm.hs256,
        ).decode(registration, testKeys.token(alg: 'HS256')),
        throwsA(
          isA<OAuth2AuthenticationException>().having(
            (e) => e.error.errorCode,
            'code',
            'missing_signature_verifier',
          ),
        ),
      );
    });
  });

  group('OidcClientInitiatedLogoutSuccessHandler', () {
    Future<String?> logout(
      ClientRegistrationRepository registrations,
      ServerHttpRequest request, {
      String logoutSuccessUrl = '/',
    }) async {
      final provider = FakeOidcProvider();
      final idToken = OidcIdToken.parse(provider.idToken(nonce: 'n'));
      final user = DefaultOidcUser([OidcUserAuthority(idToken)], idToken);
      final response = MockServerHttpResponse();
      await OidcClientInitiatedLogoutSuccessHandler(
        registrations,
        logoutSuccessUrl: logoutSuccessUrl,
        postLogoutRedirectUri: '{baseUrl}',
      ).onLogoutSuccess(
        request,
        response,
        OAuth2AuthenticationToken(user, user.authorities, 'keycloak'),
      );
      return response.headers['location'];
    }

    test(
      'a registration that cannot be resolved: the plain redirect',
      () async {
        final broken = InMemoryClientRegistrationRepository.lazy({
          'keycloak': () async => throw StateError('down'),
        });
        expect(
          await logout(
            broken,
            MockServerHttpRequest(HttpMethod.post, '/logout'),
            logoutSuccessUrl: 'https://www.example.com/bye',
          ),
          'https://www.example.com/bye',
        );
      },
    );

    test('the context path of a request to its root', () async {
      final provider = FakeOidcProvider();
      final registrations = InMemoryClientRegistrationRepository([
        await provider.registration(),
      ]);
      for (final path in ['/shop', '/shop/']) {
        final location = await logout(
          registrations,
          ContextPathRequest(
            MockServerHttpRequest(HttpMethod.post, path),
            '/shop',
          ),
        );
        expect(
          Uri.parse(location!).queryParameters['post_logout_redirect_uri'],
          'http://localhost/shop',
          reason: path,
        );
      }
    });
  });
}
