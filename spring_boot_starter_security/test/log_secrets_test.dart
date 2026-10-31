// The log, at every level, never holds a secret: the heavy security
// scenarios (form login with a wrong and a right password, HTTP Basic, a JWT
// bearer request, a DPoP request, an OpenID Connect login against the fake
// provider, CSRF success and failure, logout) run with the root level at
// trace and every record captured (message, error, stack trace and fields),
// and none of the secrets those scenarios use may appear in it. The test
// also checks that the main lines are there at debug and trace and silent at
// info, and that a client's text cannot forge a line.
import 'dart:convert';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:test/test.dart';

import 'app/jwt/jwt.dart';
import 'app/jwt/keys.dart';
import 'chain_support.dart';
import 'dpop_support.dart';
import 'oauth2_support.dart';
import 'support.dart';

/// Every record logged while a scenario ran, as text.
final class _Captured {
  final records = <SpringLogRecord>[];

  void add(SpringLogRecord record) => records.add(record);

  String _text(SpringLogRecord r) =>
      '[${r.loggerName}] ${r.level.name}: ${r.message}'
      ' | error=${r.error} | stack=${r.stackTrace} | fields=${r.fields}';

  List<String> get lines => [for (final r in records) _text(r)];

  String get text => lines.join('\n');

  bool has(String part, {SpringLogLevel? at}) => records.any(
    (r) => r.message.contains(part) && (at == null || r.level == at),
  );

  SpringLogRecord? find(String part) =>
      records.where((r) => r.message.contains(part)).firstOrNull;
}

Future<_Captured> _capture(
  SpringLogLevel level,
  Future<void> Function() body,
) async {
  final handler = SpringLog.handler;
  SpringLog.handler = (_) {};
  SpringLog.level = level;
  final captured = _Captured();
  final stop = SpringLog.listen(captured.add);
  try {
    await body();
  } finally {
    stop();
    SpringLog.handler = handler;
    SpringLog.level = SpringLogLevel.info;
    SpringLog.resetLevels();
  }
  return captured;
}

/// The secrets of a scenario, named for the failure message.
final class _Secrets {
  final values = <String, String>{};

  void add(String name, String? value) {
    if (value != null && value.length >= 6) {
      values[name] = value;
    }
  }

  void addToken(String name, String token) {
    add(name, token);
    for (final (i, part) in token.split('.').indexed) {
      add('$name part $i', part);
    }
  }

  void addCookies(Map<String, String> cookies) {
    for (final MapEntry(:key, :value) in cookies.entries) {
      add('cookie $key', value);
    }
  }
}

void _expectNoSecrets(_Captured captured, _Secrets secrets) {
  expect(captured.records, isNotEmpty);
  expect(secrets.values, isNotEmpty);
  final text = captured.text;
  for (final MapEntry(:key, :value) in secrets.values.entries) {
    expect(text, isNot(contains(value)), reason: 'the log holds $key');
  }
}

const _wrong = 'wrong-pw-7731';

HttpSecurity _loginHttp() => newHttp()
    .authorizeHttpRequests(
      (a) => a
          .requestMatchers('/public/**')
          .permitAll()
          .anyRequest()
          .authenticated(),
    )
    .formLogin()
    .httpBasic()
    .logout((l) {});

void main() {
  tearDown(() {
    SpringLog.level = SpringLogLevel.info;
    SpringLog.resetLevels();
  });

  group('no secret at any level', () {
    test('form login (wrong, then right), CSRF success and failure, '
        'logout', () async {
      final secrets = _Secrets();
      final captured = await _capture(SpringLogLevel.trace, () async {
        final client = ChainClient(_loginHttp().build());
        void note() => secrets.addCookies(client.cookies);

        // The application starts a session first: the login changes its id.
        secrets.add('the session id', await client.startSession());
        await client.get('/private');
        note();
        final page = await client.get('/login');
        note();
        secrets.add('csrf of the page', page.csrfField);
        // CSRF failures: no token, a wrong token.
        expect(
          (await client.post('/login', {
            'username': 'ada',
            'password': _wrong,
          })).status,
          403,
        );
        expect(
          (await client.post('/login', {
            'username': 'ada',
            'password': _wrong,
            '_csrf': 'forged-csrf-token-0001',
          })).status,
          403,
        );
        secrets.add('a forged CSRF token', 'forged-csrf-token-0001');
        note();
        // A wrong password, an unknown user, then the right login.
        final failed = await client.login('ada', _wrong);
        expect(failed.header('location'), '/login?error');
        note();
        await client.login('nobody', _wrong);
        note();
        final ok = await client.login('ada', 'ada-pw');
        expect(ok.status, 302);
        note();
        expect((await client.get('/private')).reached, isTrue);
        note();
        // Logout with the token of a page.
        final token = (await client.get('/login')).csrfField;
        secrets.add('csrf at logout', token);
        final out = await client.post('/logout', {'_csrf': token});
        expect(out.status, 302);
        note();
        for (final r in [page, ok, out]) {
          for (final cookie in r.response.cookies) {
            secrets.add('set-cookie ${cookie.name}', cookie.value);
          }
        }
      });
      secrets
        ..add('the password', 'ada-pw')
        ..add('the wrong password', _wrong);
      _expectNoSecrets(captured, secrets);
      // The scenario was seen: the lines of the failures are there.
      expect(captured.has('Invalid CSRF token found for /login'), isTrue);
      expect(
        captured.has('password does not match stored value'),
        isTrue,
      );
    });

    test('HTTP Basic, wrong and right', () async {
      final secrets = _Secrets();
      final captured = await _capture(SpringLogLevel.trace, () async {
        final client = ChainClient(_loginHttp().build());
        for (final (user, password) in [
          ('ada', _wrong),
          ('ada', 'ada-pw'),
          ('root', 'root-pw'),
        ]) {
          final header = basicHeader(user, password)['authorization']!;
          secrets
            ..add('the Basic header of $user', header)
            ..add('the Basic token of $user', header.substring(6))
            ..add('user:password of $user', '$user:$password');
          await client.get('/private', headers: {'authorization': header});
        }
        // A malformed header and a repeated one.
        await client.get('/private', headers: {'authorization': 'Basic !!!'});
        secrets.add('a malformed header', '!!!');
      });
      secrets
        ..add('the password', 'ada-pw')
        ..add('the admin password', 'root-pw')
        ..add('the wrong password', _wrong);
      _expectNoSecrets(captured, secrets);
      expect(captured.has('Set SecurityContextHolder to'), isTrue);
    });

    test('a JWT bearer request and a DPoP request', () async {
      final secrets = _Secrets();
      late final _Captured captured;
      await withApp(jwtSecurityBeans, (mvc, _) async {
        captured = await _capture(SpringLogLevel.trace, () async {
          final good = testKeys.token();
          secrets.addToken('the bearer token', good);
          await mvc
              .get('/api/me', headers: {'authorization': 'Bearer $good'})
              .andExpect(status: 200);
          // A broken signature, and one more bearer request denied (403).
          final tampered = '${good.substring(0, good.length - 4)}AAAA';
          secrets.addToken('a tampered token', tampered);
          await mvc
              .get('/api/me', headers: {'authorization': 'Bearer $tampered'})
              .andExpect(status: 401);
          await mvc
              .get('/api/admin', headers: {'authorization': 'Bearer $good'})
              .andExpect(status: 403);

          final signer = ProofSigner.ec();
          final bound = boundToken(signer);
          final proof = signer.proof(accessToken: bound);
          secrets
            ..addToken('the bound token', bound)
            ..addToken('the DPoP proof', proof);
          await mvc
              .get('/api/me', headers: dPoPHeaders(bound, proof))
              .andExpect(status: 200);
          // The replay of the proof, and a bound token sent as Bearer.
          await mvc
              .get('/api/me', headers: dPoPHeaders(bound, proof))
              .andExpect(status: 401);
          await mvc
              .get('/api/me', headers: {'authorization': 'Bearer $bound'})
              .andExpect(status: 401);
          // A proof of another key.
          final other = ProofSigner.ec();
          final forged = other.proof(accessToken: bound);
          secrets.addToken('a proof of another key', forged);
          await mvc
              .get('/api/me', headers: dPoPHeaders(bound, forged))
              .andExpect(status: 401);
        });
      }, properties: ['logging.level.root=trace']);
      _expectNoSecrets(captured, secrets);
      expect(
        captured.has('Authenticated token', at: SpringLogLevel.debug),
        isTrue,
      );
      expect(captured.has('DPoP proof accepted'), isTrue);
      expect(captured.has('DPoP proof rejected'), isTrue);
    });

    test('an OpenID Connect login and a failed one', () async {
      final secrets = _Secrets();
      final provider = FakeOidcProvider();
      final captured = await _capture(SpringLogLevel.trace, () async {
        final registrations = InMemoryClientRegistrationRepository([
          await provider.registration(),
        ]);
        final client = ChainClient(oauth2Http(provider, registrations).build());
        void note() => secrets.addCookies(client.cookies);

        await client.get('/private');
        final authorization = await client.startLogin('keycloak');
        note();
        final query = authorization.queryParameters;
        secrets
          ..add('state', query['state'])
          ..add('nonce', query['nonce'])
          ..add('the code challenge', query['code_challenge'])
          ..add('the authorization URL', authorization.toString())
          ..add('the authorization query', authorization.query);
        final callback = provider.approve(authorization);
        secrets
          ..add('code', callback.queryParameters['code'])
          ..add('the callback query', callback.query);
        final done = await client.callback(callback);
        expect(done.status, 302);
        note();
        expect((await client.get('/private')).reached, isTrue);
        note();

        // A forged state, and a provider that refuses the code.
        final second = await client.startLogin('keycloak');
        final approved = provider.approve(second);
        final forged = approved.replace(
          queryParameters: {
            ...approved.queryParameters,
            'state': 'forged-state-0001',
          },
        );
        secrets
          ..add('a forged state', 'forged-state-0001')
          ..add('state of the second login', second.queryParameters['state'])
          ..add('code of the second login', approved.queryParameters['code']);
        await client.callback(forged);
        note();
        provider.tokenError = 'invalid_grant';
        final third = await client.startLogin('keycloak');
        final refused = provider.approve(third);
        secrets
          ..add('state of the third login', third.queryParameters['state'])
          ..add('code of the third login', refused.queryParameters['code']);
        await client.callback(refused);
        note();
      });
      // What the provider saw: the verifier, the Basic header, the tokens.
      for (final request in provider.tokenRequests) {
        secrets
          ..add('the code verifier', request['code_verifier'])
          ..add('a code sent to the token endpoint', request['code']);
      }
      for (final request in provider.transport.requests) {
        final header = request.headers['Authorization'];
        if (header != null) {
          secrets
            ..add('Authorization sent to the provider', header)
            ..add('its credentials', header.split(' ').last);
        }
      }
      secrets
        ..add('the client secret', clientSecret)
        ..add(
          'client id and secret',
          base64.encode(utf8.encode('$clientId:$clientSecret')),
        )
        ..addToken('the ID token', provider.lastIdToken!);
      _expectNoSecrets(captured, secrets);
      final text = captured.text;
      expect(text, isNot(matches(RegExp('(access|refresh)-[0-9]+'))));
      expect(text, isNot(matches(RegExp('code-[0-9]+'))));
      expect(
        captured.has('ID token validated for registration keycloak'),
        isTrue,
      );
    });
  });

  group('the lines, at their level', () {
    Future<_Captured> run(SpringLogLevel level) => _capture(level, () async {
      final client = ChainClient(_loginHttp().build());
      await client.startSession();
      await client.get('/private');
      await client.login('ada', _wrong);
      await client.login('ada', 'ada-pw');
      await client.get('/private');
      await client.get('/private', headers: basicHeader('root', 'root-pw'));
      await client.post('/login', {'username': 'ada', 'password': 'x'});
    });

    test('nothing at info', () async {
      final captured = await run(SpringLogLevel.info);
      expect(captured.lines, isEmpty);
    });

    test("debug: Spring Security's lines, not the trace ones", () async {
      final captured = await run(SpringLogLevel.debug);
      const setContext =
          'Set SecurityContextHolder to UsernamePasswordAuthenticationToken '
          '[Principal=ada, Credentials=[PROTECTED], Authenticated=true, '
          'Details=WebAuthenticationDetails ';
      const anonymousDenied =
          'Sending AnonymousAuthenticationToken [Principal=anonymousUser, '
          'Granted Authorities=[ROLE_ANONYMOUS]] to authentication entry '
          'point since access is denied';
      for (final line in [
        'Will secure ',
        'Securing GET /private',
        'Secured GET /private',
        'Securing POST /login',
        setContext,
        'Granted Authorities=[ROLE_USER]]',
        'Failed to authenticate since password does not match stored value',
        'Failed to process authentication request: Bad credentials',
        'Invalid CSRF token found for /login',
        'Changed session id',
        anonymousDenied,
      ]) {
        expect(
          captured.has(line, at: SpringLogLevel.debug),
          isTrue,
          reason: line,
        );
      }
      expect(
        captured.records.where((r) => r.level == SpringLogLevel.trace),
        isEmpty,
      );
      // Credentials are always protected, even in the debug line.
      expect(captured.text, isNot(contains('Credentials=ada')));
    });

    test('trace: the filters, the rules, the context', () async {
      final captured = await run(SpringLogLevel.trace);
      for (final line in [
        'Invoking SecurityContextHolderFilter (1/',
        'Authorizing GET /private',
        'Checking authorization on GET /private using ',
        'Set SecurityContextHolder to anonymous SecurityContext',
        'Stored SecurityContextImpl [Authentication=',
        'Retrieved SecurityContextImpl [Authentication=',
      ]) {
        expect(
          captured.has(line, at: SpringLogLevel.trace),
          isTrue,
          reason: line,
        );
      }
    });

    test("a client's text cannot forge a line", () async {
      final captured = await _capture(SpringLogLevel.debug, () async {
        final client = ChainClient(_loginHttp().build());
        await client.get(
          '/private',
          headers: basicHeader('ada\nINFO forged line\u001b[31m', 'x'),
        );
      });
      final line = captured.find("Failed to find user '")!;
      expect(line.message, contains('ada<EOL>INFO forged line?[31m'));
      expect(captured.text, isNot(contains('\nINFO forged')));
    });
  });
}
