// oauth2Login() with response_mode=form_post (Sign in with Apple's when it
// asks for the name and e-mail): the provider posts the response to the
// callback. The whole login over a POST, the CSRF exemption (only for the
// callback's POST), the `user` parameter handed to the user service (never
// to the identity), and the attacks: a missing, wrong or replayed state, a
// post without the session cookie, a GET for a form_post login and a POST
// for a query login (both leave the login in progress alone), the response
// split between query and body, another content type.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:test/test.dart';

import 'chain_support.dart';
import 'oauth2_support.dart';

final class _Failures implements AuthenticationFailureHandler {
  final List<AuthenticationException> errors = [];

  String? get lastCode => switch (errors.lastOrNull) {
    final OAuth2AuthenticationException e => e.error.errorCode,
    final Object e => '${e.runtimeType}',
    null => null,
  };

  @override
  Future<void> onAuthenticationFailure(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException exception,
  ) async {
    errors.add(exception);
    await sendRedirect(response, '/login?error');
  }
}

// Records what the user service was given.
final class _RecordingOidcUserService
    implements OAuth2UserService<OidcUserRequest, OidcUser> {
  _RecordingOidcUserService(this._delegate);

  final OAuth2UserService<OidcUserRequest, OidcUser> _delegate;
  final List<OidcUserRequest> requests = [];

  @override
  Future<OidcUser> loadUser(OidcUserRequest userRequest) {
    requests.add(userRequest);
    return _delegate.loadUser(userRequest);
  }
}

final class _Fixture {
  _Fixture(this.provider, this.client, this.failures, this.users);

  final FakeOidcProvider provider;
  final ChainClient client;
  final _Failures failures;
  final _RecordingOidcUserService users;

  Future<Authentication?> who() async {
    final reply = await client.get('/private');
    return reply.reached ? reply.authentication : null;
  }

  /// The provider's answer to [authorization] as the form it posts.
  (String, Map<String, String>) post(
    Uri authorization, {
    Map<String, String> extra = const {},
  }) {
    final redirect = provider.approve(authorization);
    return (redirect.path, {...redirect.queryParameters, ...extra});
  }
}

Future<_Fixture> _fixture({ResponseMode mode = ResponseMode.formPost}) async {
  final provider = FakeOidcProvider();
  final registration = ClientRegistration.withClientRegistration(
    await provider.registration(),
  ).responseMode(mode).build();
  final registrations = InMemoryClientRegistrationRepository([registration]);
  final failures = _Failures();
  final users = _RecordingOidcUserService(OidcUserService(provider.transport));
  final http = oauth2Http(
    provider,
    registrations,
    customizer: (login) => login
        .failureHandler(failures)
        .userInfoEndpoint((userInfo) => userInfo.oidcUserService(users)),
  );
  return _Fixture(provider, ChainClient(http.build()), failures, users);
}

void main() {
  // First on purpose: the warning is logged once per process, so this must
  // be the first post without a session of this file.
  test('a post without a session warns once, with no secret in it, and a '
      'GET or a post with a session does not', () async {
    final warnings = <SpringLogRecord>[];
    final stop = SpringLog.listen((record) {
      if (record.level == SpringLogLevel.warning) {
        warnings.add(record);
      }
    });
    addTearDown(stop);
    final f = await _fixture();
    final authorization = await f.client.startLogin('keycloak');
    final (path, form) = f.post(authorization);

    // A GET (the query is the response) finding nothing: no warning.
    await f.client.send(
      HttpMethod.get,
      Uri(path: path, queryParameters: form).toString(),
      withCookies: false,
    );
    expect(f.failures.lastCode, 'authorization_request_not_found');
    expect(warnings, isEmpty);
    // A post that finds its authorization request (the cookie): no warning.
    final ok = await f.client.post(path, form);
    expect(ok.status, 302);
    expect(f.failures.errors, hasLength(1), reason: 'only the GET failed');
    expect(warnings, isEmpty);

    // A post that finds none (the browser sent no cookie): the warning.
    await f.client.send(
      HttpMethod.post,
      path,
      form: form,
      withCookies: false,
    );
    expect(f.failures.lastCode, 'authorization_request_not_found');
    final warning = warnings.single;
    expect(warning.loggerName, 'spring.security.oauth2.client.web');
    expect(warning.message, contains('form post callback'));
    expect(warning.message, contains('SameSite=None'));
    final code = form['code'] ?? '';
    final state = form['state'] ?? '';
    expect(code, isNotEmpty);
    expect(state, isNotEmpty);
    expect(warning.message, isNot(contains(code)));
    expect(warning.message, isNot(contains(state)));

    // Once only, for any post that finds none.
    final again = await f.client.startLogin('keycloak');
    final (againPath, againForm) = f.post(again);
    await f.client.post(againPath, {...againForm, 'state': 'forged'});
    expect(f.failures.lastCode, 'authorization_request_not_found');
    await f.client.send(
      HttpMethod.post,
      path,
      form: form,
      withCookies: false,
    );
    expect(warnings, hasLength(1));
  });

  test('the whole login over a form post, without a CSRF token', () async {
    final f = await _fixture();
    await f.client.get('/private?tab=1');
    final authorization = await f.client.startLogin('keycloak');
    expect(authorization.queryParameters['response_mode'], 'form_post');

    final (path, form) = f.post(
      authorization,
      extra: {
        'user':
            '{"name":{"firstName":"Ada","lastName":"Lovelace"},'
            '"email":"ada@example.com"}',
      },
    );
    final reply = await f.client.post(path, form);
    expect(reply.status, 302, reason: '${f.failures.lastCode}');
    expect(reply.header('location'), '/private?tab=1&continue');
    expect(f.failures.errors, isEmpty);

    final user = await f.who() as OAuth2AuthenticationToken?;
    expect(user?.name, 'user-1');
    // The first login's `user` reaches the user service, beside the
    // token response; it decides nothing about who logged in.
    final request = f.users.requests.single;
    expect(request.additionalParameters['user'], contains('"Ada"'));
    expect(request.idToken.subject, 'user-1');
  });

  test('the posted user cannot replace a token response parameter', () async {
    final f = await _fixture();
    final authorization = await f.client.startLogin('keycloak');
    final (path, form) = f.post(
      authorization,
      extra: {'id_token': 'forged', 'access_token': 'forged'},
    );
    final reply = await f.client.post(path, form);
    expect(reply.status, 302);
    expect(f.failures.errors, isEmpty);
    final parameters = f.users.requests.single.additionalParameters;
    expect(parameters['id_token'], f.provider.lastIdToken);
    expect(parameters['access_token'], isNull);
  });

  test('a missing state is an invalid request', () async {
    final f = await _fixture();
    final authorization = await f.client.startLogin('keycloak');
    final (path, form) = f.post(authorization);
    await f.client.post(path, {...form}..remove('state'));
    expect(f.failures.lastCode, 'invalid_request');
    expect(await f.who(), isNull);
  });

  test('a wrong state finds no login; the real one still works', () async {
    final f = await _fixture();
    final authorization = await f.client.startLogin('keycloak');
    final (path, form) = f.post(authorization);
    await f.client.post(path, {...form, 'state': 'forged'});
    expect(f.failures.lastCode, 'authorization_request_not_found');
    final reply = await f.client.post(path, form);
    expect(reply.status, 302);
    expect(await f.who(), isNotNull);
  });

  test('a replayed post is refused', () async {
    final f = await _fixture();
    final authorization = await f.client.startLogin('keycloak');
    final (path, form) = f.post(authorization);
    await f.client.post(path, form);
    expect(f.failures.errors, isEmpty);
    await f.client.post(path, form);
    expect(f.failures.lastCode, 'authorization_request_not_found');
  });

  test('a post without the session cookie (SameSite) finds no login', () async {
    final f = await _fixture();
    final authorization = await f.client.startLogin('keycloak');
    final (path, form) = f.post(authorization);
    await f.client.send(
      HttpMethod.post,
      path,
      form: form,
      withCookies: false,
    );
    expect(f.failures.lastCode, 'authorization_request_not_found');
  });

  test('a GET for a form_post login is refused and leaves the login '
      'alone', () async {
    final f = await _fixture();
    final authorization = await f.client.startLogin('keycloak');
    final (path, form) = f.post(authorization);
    await f.client.get(
      Uri(path: path, queryParameters: form).toString(),
    );
    expect(f.failures.lastCode, 'invalid_request');
    expect(await f.who(), isNull);
    final reply = await f.client.post(path, form);
    expect(reply.status, 302);
    expect(await f.who(), isNotNull);
  });

  test('a POST for a query login is refused and leaves the login '
      'alone', () async {
    final f = await _fixture(mode: ResponseMode.query);
    final authorization = await f.client.startLogin('keycloak');
    expect(authorization.queryParameters, isNot(contains('response_mode')));
    final redirect = f.provider.approve(authorization);
    await f.client.post(redirect.path, redirect.queryParameters);
    expect(f.failures.lastCode, 'invalid_request');
    final reply = await f.client.callback(redirect);
    expect(reply.status, 302);
    expect(await f.who(), isNotNull);
  });

  test('the response split between the query and the body is '
      'refused', () async {
    final f = await _fixture();
    final authorization = await f.client.startLogin('keycloak');
    final (path, form) = f.post(authorization);
    await f.client.post(
      '$path?state=${Uri.encodeQueryComponent(form['state']!)}',
      {...form}..remove('state'),
    );
    expect(f.failures.lastCode, 'invalid_request');
  });

  for (final parameter in ['code', 'error', 'state']) {
    test('a form post whose query also has `$parameter` is refused and '
        'leaves the login alone', () async {
      final f = await _fixture();
      final authorization = await f.client.startLogin('keycloak');
      final (path, form) = f.post(authorization);
      final forged = parameter == 'error' ? 'access_denied' : 'forged';
      await f.client.post('$path?$parameter=$forged', form);
      expect(f.failures.lastCode, 'invalid_request');
      expect(await f.who(), isNull);
      // The real response, without the query, still ends the login.
      final reply = await f.client.post(path, form);
      expect(reply.status, 302);
      expect(await f.who(), isNotNull);
    });
  }

  test('a post that is not a form is refused', () async {
    final f = await _fixture();
    final authorization = await f.client.startLogin('keycloak');
    final (path, form) = f.post(authorization);
    await f.client.send(
      HttpMethod.post,
      path,
      headers: {'content-type': 'application/json'},
    );
    expect(f.failures.lastCode, 'invalid_request');
    expect(form, isNotEmpty);
  });

  // The callback's POST is exempt from CSRF and so read by the login
  // filter itself: with its own limit, not the web starter's 1 MiB.
  test('a posted body over 64 KB is a 413 and leaves the login '
      'alone', () async {
    final f = await _fixture();
    final authorization = await f.client.startLogin('keycloak');
    final (path, form) = f.post(authorization);
    await expectLater(
      f.client.post(path, {...form, 'user': 'x' * (64 * 1024)}),
      throwsA(
        isA<ResponseStatusException>().having(
          (e) => e.statusCode,
          'status',
          413,
        ),
      ),
    );
    expect(f.provider.tokenRequests, isEmpty);
    expect(await f.who(), isNull);
    // Just under the limit is read; the real response still ends the
    // login.
    final reply = await f.client.post(path, {
      ...form,
      'user': 'x' * (60 * 1024),
    });
    expect(reply.status, 302, reason: '${f.failures.lastCode}');
    expect(await f.who(), isNotNull);
  });

  test('the CSRF exemption covers the callback POST only', () async {
    final f = await _fixture();
    final other = await f.client.post('/private', {'a': 'b'});
    expect(other.status, 403);
    final authorization = await f.client.startLogin('keycloak');
    final (path, form) = f.post(authorization);
    expect((await f.client.post(path, form)).status, 302);
  });
}
