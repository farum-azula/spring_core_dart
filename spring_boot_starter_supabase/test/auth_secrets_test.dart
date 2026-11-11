@Tags(['supabase'])
library;

import 'dart:convert';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'auth_support.dart';
import 'support.dart';

// No token, key, password, one-time code or authorization code is ever in
// a log line (at any level), an exception or a toString: every flow runs,
// succeeding and failing, against an Auth that repeats in its errors
// whatever secret it was sent, with everything logged captured.

const _anonKey = 'anon-KEY-9f3a71c2';
const _serviceKey = 'service-KEY-5be04d17';
const _password = 'pw-Tr0ub4dor-73';
const _newPassword = 'pw-new-Zebra-88';
const _access1 = 'eyJhbGciOi.access-AAAA-1.c2ln';
const _access2 = 'eyJhbGciOi.access-BBBB-2.c2ln';
const _refresh1 = 'rt-refresh-CCCC-1';
const _refresh2 = 'rt-refresh-DDDD-2';
const _otp = '482913';
const _code = 'authcode-EEEE-77';
const _idToken = 'eyJhbGciOi.idtoken-FFFF.c2ln';
const _providerToken = 'ya29.provider-GGGG';
const _nonce = 'nonce-HHHH-41';
const _callback = 'myapp://callback';

void main() {
  late MockHttpTransport transport;
  late AuthHarness harness;
  late Map<String, String> secrets;
  late List<String> texts;

  // Auth, repeating every secret of the request in its refusal.
  HttpResponse echo(HttpRequest request, int status, String code) =>
      HttpResponse(
        status,
        body: utf8.encode(
          jsonEncode({
            'code': status,
            'error_code': code,
            'msg':
                'refused: ${utf8.decode(request.body ?? const [])} '
                'with ${request.headers['Authorization']} '
                'and ${request.headers['apikey']}',
          }),
        ),
      );

  Map<String, Object?> session(String access, String refresh) =>
      sessionJson(accessToken: access, refreshToken: refresh);

  setUp(() {
    harness = AuthHarness();
    transport = harness.transport;
    texts = [];
    secrets = {
      'the anon key': _anonKey,
      'the service role key': _serviceKey,
      'the password': _password,
      'the new password': _newPassword,
      'the first access token': _access1,
      'the second access token': _access2,
      'the first refresh token': _refresh1,
      'the second refresh token': _refresh2,
      'the one-time code': _otp,
      'the authorization code': _code,
      'the ID token': _idToken,
      "the provider's access token": _providerToken,
      'the nonce': _nonce,
    };
    for (final (i, part) in _access1.split('.').indexed) {
      if (part.length >= 6) {
        secrets['part $i of the access token'] = part;
      }
    }
  });

  SupabaseProperties props() => properties()
    ..anonKey = _anonKey
    ..serviceRoleKey = _serviceKey
    ..auth.redirectUrls = [_callback]
    ..auth.autoRefresh = true;

  SupabaseAuth newAuth({AuthorizationWindow? window}) {
    final auth = SupabaseAuth(
      http: http(transport, properties_: props()),
      secretStore: harness.store,
      authorizationWindow: window,
      eventPublisher: harness.publisher,
      securityContextHolderStrategy: harness.contexts,
      clock: harness.clock.call,
      timerFactory: harness.timers.create,
    );
    auth.authenticationChanges.listen((a) => texts.add('$a'));
    return auth;
  }

  // Runs [call], which must fail, and keeps everything its error shows.
  Future<void> failing(Future<Object?> Function() call) async {
    try {
      await call();
    } on Object catch (e, trace) {
      texts
        ..add('$e')
        ..add('$trace');
      if (e is AuthenticationException) {
        texts
          ..add(e.message)
          ..add('${e.cause}');
      }
      if (e is SupabaseException) {
        texts.add(e.message);
      }
      if (e is ArgumentError) {
        texts.add('${e.message} ${e.invalidValue}');
      }
      return;
    }
    fail('The call did not fail');
  }

  Future<void> rememberVerifier() async {
    final text = await harness.store.read(SupabaseAuth.pkceKey);
    if (text != null) {
      final flow = SupabasePkceFlow.decode(text)!;
      secrets['a code verifier (${secrets.length})'] = flow.verifier;
      texts.add('$flow');
    }
  }

  void describe(SupabaseAuth auth) {
    final authentication = auth.authentication;
    texts
      ..add('$auth')
      ..add('$authentication')
      ..add('${authentication?.credentials}')
      ..add('${authentication?.principal}')
      ..add('${authentication?.details}')
      ..add('${auth.user}')
      ..add('${harness.contexts.getContext()}')
      ..addAll(harness.publisher.events.map((e) => '$e'));
  }

  void expectNoSecrets(List<String> logs) {
    expect(logs, isNotEmpty);
    expect(texts, isNotEmpty);
    expect(secrets.length, greaterThan(13));
    for (final MapEntry(key: name, value: secret) in secrets.entries) {
      for (final text in [...logs, ...texts]) {
        expect(
          text.contains(secret),
          isFalse,
          reason: '$name is shown in: ${text.replaceAll(secret, '<HERE>')}',
        );
      }
    }
    // Secrets go in bodies and headers, never in an address.
    for (final request in transport.requests) {
      for (final MapEntry(key: name, value: secret) in secrets.entries) {
        expect(
          '${request.url}'.contains(secret),
          isFalse,
          reason: '$name is in ${request.url.path}',
        );
      }
    }
  }

  test(
    'passwords, codes and tokens: every flow, succeeding and failing',
    () async {
      final logs = await captureLogs(() async {
        final auth = newAuth();

        // Sign-up and password.
        transport
          ..when(
            HttpMethod.post,
            '/auth/v1/signup',
          ).respondWith((r) => echo(r, 422, 'weak_password'))
          ..when(
            HttpMethod.post,
            '/auth/v1/token?grant_type=password',
          ).respondWith((r) => echo(r, 400, 'invalid_credentials'))
          ..when(
            HttpMethod.post,
            '/auth/v1/token?grant_type=password',
          ).fail(HttpTransportException('connection reset'))
          ..when(
            HttpMethod.post,
            '/auth/v1/token?grant_type=password',
          ).respond(200, json: session(_access1, _refresh1));
        await failing(() => auth.signUp(email: 'a@b.c', password: _password));
        await failing(
          () => auth.signInWithPassword(email: 'a@b.c', password: _password),
        );
        await failing(
          () => auth.signInWithPassword(email: 'a@b.c', password: _password),
        );
        await auth.signInWithPassword(email: 'a@b.c', password: _password);
        describe(auth);
        texts.add((await harness.storedSession()).runtimeType.toString());

        // The user's own calls.
        transport
          ..when(
            HttpMethod.put,
            '/auth/v1/user',
          ).respondWith((r) => echo(r, 422, 'same_password'))
          ..when(
            HttpMethod.put,
            '/auth/v1/user',
          ).respond(200, json: userJson());
        await failing(() => auth.updateUser(password: _newPassword));
        await auth.updateUser(password: _newPassword);

        // Refresh: a failure of the service, the timer, success, replay.
        transport
          ..when(
            HttpMethod.post,
            '/auth/v1/token?grant_type=refresh_token',
          ).respondWith((r) => echo(r, 500, 'unexpected_failure'))
          ..when(
            HttpMethod.post,
            '/auth/v1/token?grant_type=refresh_token',
          ).fail(HttpTransportException('no route to host'))
          ..when(
            HttpMethod.post,
            '/auth/v1/token?grant_type=refresh_token',
          ).respond(200, json: session(_access2, _refresh2))
          ..when(
            HttpMethod.post,
            '/auth/v1/token?grant_type=refresh_token',
          ).respondWith((r) => echo(r, 400, 'refresh_token_already_used'));
        await failing(auth.refreshSession);
        harness.timers.active.single.fire();
        await settle();
        await auth.refreshSession();
        describe(auth);
        await failing(auth.refreshSession);
        expect(auth.isLoggedIn, isFalse);

        // One-time codes and ID tokens.
        transport
          ..when(HttpMethod.post, '/auth/v1/otp').respond(200, json: {})
          ..when(
            HttpMethod.post,
            '/auth/v1/verify',
          ).respondWith((r) => echo(r, 403, 'otp_expired'))
          ..when(
            HttpMethod.post,
            '/auth/v1/verify',
          ).respond(200, json: session(_access1, _refresh1))
          ..when(
            HttpMethod.post,
            '/auth/v1/token?grant_type=id_token',
          ).respondWith((r) => echo(r, 400, 'invalid_credentials'));
        await auth.signInWithOtp(email: 'a@b.c');
        await rememberVerifier();
        await failing(
          () => auth.verifyOtp(
            email: 'a@b.c',
            token: _otp,
            type: SupabaseOtpType.email,
          ),
        );
        await auth.verifyOtp(
          email: 'a@b.c',
          token: _otp,
          type: SupabaseOtpType.email,
        );
        await failing(
          () => auth.signInWithIdToken(
            provider: 'google',
            idToken: _idToken,
            accessToken: _providerToken,
            nonce: _nonce,
          ),
        );

        // Logout: refused, then unreachable.
        transport
          ..when(
            HttpMethod.post,
            '/auth/v1/logout',
          ).respondWith((r) => echo(r, 403, 'bad_jwt'))
          ..when(
            HttpMethod.post,
            '/auth/v1/logout',
          ).fail(HttpTransportException('no route to host'));
        await auth.logout();
        transport
            .when(HttpMethod.post, '/auth/v1/token?grant_type=password')
            .respond(200, json: session(_access1, _refresh1));
        await auth.signInWithPassword(email: 'a@b.c', password: _password);
        await auth.logout(scope: SupabaseLogoutScope.global);

        // Providers and links: PKCE.
        transport
          ..when(
            HttpMethod.post,
            '/auth/v1/token?grant_type=pkce',
          ).respondWith((r) => echo(r, 400, 'bad_code_verifier'))
          ..when(
            HttpMethod.post,
            '/auth/v1/token?grant_type=pkce',
          ).respond(200, json: session(_access1, _refresh1));
        texts.add('${await auth.authorizationUrl('github')}');
        await rememberVerifier();
        await failing(
          () => auth.completeSignIn(Uri.parse('https://evil.org/?code=$_code')),
        );
        await failing(
          () => auth.completeSignIn(Uri.parse('$_callback?code=$_code')),
        );
        await auth.authorizationUrl('github');
        await rememberVerifier();
        await failing(
          () => auth.completeSignIn(
            Uri.parse('$_callback?code=$_code&error=access_denied'),
          ),
        );
        await auth.authorizationUrl('github');
        await rememberVerifier();
        await auth.completeSignIn(Uri.parse('$_callback?code=$_code'));
        describe(auth);
        await auth.destroy();

        // The window, with a code that is refused.
        transport
            .when(HttpMethod.post, '/auth/v1/token?grant_type=pkce')
            .respondWith((r) {
              secrets["the window's code verifier"] =
                  bodyOf(r)['code_verifier']! as String;
              return echo(r, 400, 'bad_code_verifier');
            });
        final windowed = newAuth(
          window: FakeWindow(
            (redirect, _) => Uri.parse('$redirect?code=$_code'),
          ),
        );
        await failing(() => windowed.signInWithProvider('github'));
        await failing(
          () => windowed.signInWithProvider(
            'github',
            redirectTo: 'https://evil.org/callback',
          ),
        );

        // Restore: a stored value that cannot be read, then one that is
        // refreshed without a network.
        await harness.store.write(
          SupabaseAuth.sessionKey,
          '{"access_token":"$_access1","refresh_token":"$_refresh1"}',
        );
        final unreadable = newAuth();
        await unreadable.awaitStartup();
        final expired = SupabaseSession.fromResponse(
          session(_access1, _refresh1),
          harness.clock.now.subtract(const Duration(hours: 3)),
        )!;
        texts.add('$expired');
        await harness.store.write(SupabaseAuth.sessionKey, expired.encode());
        transport
            .when(HttpMethod.post, '/auth/v1/token?grant_type=refresh_token')
            .fail(HttpTransportException('no route to host'));
        final offline = newAuth();
        await offline.awaitStartup();
        describe(offline);
        await failing(offline.accessToken);
        await settle();
      });
      expect(
        logs.where((line) => line.contains('[spring.supabase.auth]')),
        isNotEmpty,
      );
      expect(
        logs.where((line) => line.contains('[spring.supabase.http]')),
        isNotEmpty,
      );
      expectNoSecrets(logs);
    },
  );

  test('the admin API: the service role key and the passwords', () async {
    final logs = await captureLogs(() async {
      final admin = SupabaseAuthAdmin(
        http: http(transport, properties_: props()),
      );
      transport
        ..when(
          HttpMethod.post,
          '/auth/v1/admin/users',
        ).respondWith((r) => echo(r, 422, 'weak_password'))
        ..when(
          HttpMethod.post,
          '/auth/v1/admin/users',
        ).fail(HttpTransportException('connection reset'))
        ..when(
          HttpMethod.put,
          '/auth/v1/admin/users/$userId',
        ).respondWith((r) => echo(r, 403, 'not_admin'))
        ..when(
          HttpMethod.delete,
          '/auth/v1/admin/users/$userId',
        ).respondWith((r) => echo(r, 401, 'bad_jwt'));
      await failing(
        () => admin.createUser(email: 'a@b.c', password: _password),
      );
      await failing(
        () => admin.createUser(email: 'a@b.c', password: _password),
      );
      await failing(() => admin.updateUser(userId, password: _newPassword));
      await failing(() => admin.deleteUser(userId));
      texts.add('$admin');
      secrets.addAll({for (var i = 0; i < 4; i++) 'filler $i': 'filler-$i-x'});
    });
    expectNoSecrets(logs);
  });

  test('what repeats a secret is protected in the message', () {
    final message = SupabaseAuthErrors.protect(
      'bad password $_password for\n$_refresh1 and $_password again',
      const [_password, _refresh1, null, ''],
    );
    expect(
      message,
      'bad password [PROTECTED] for [PROTECTED] and [PROTECTED] again',
    );
    // A secret inside another leaves nothing behind.
    expect(
      SupabaseAuthErrors.protect('abcdef', const ['abc', 'abcdef']),
      '[PROTECTED]',
    );
    expect(
      SupabaseAuthErrors.protect('x' * 1000, const []).length,
      lessThan(320),
    );
  });

  test('the types that hold a secret never show it', () {
    final session = SupabaseSession.fromResponse(
      sessionJson(accessToken: _access1, refreshToken: _refresh1),
      DateTime.utc(2026),
    )!;
    final authentication = session.toAuthentication();
    final flow = SupabasePkceFlow.start(redirectTo: _callback);
    final shown = [
      '$session',
      '$authentication',
      '${authentication.credentials}',
      '${authentication.principal}',
      '$flow',
      '${AuthenticationSuccessEvent(authentication)}',
      '${LogoutSuccessEvent(authentication)}',
    ].join('\n');
    expect(shown, isNot(contains(_access1)));
    expect(shown, isNot(contains(_refresh1)));
    expect(shown, isNot(contains(flow.verifier)));
    expect(shown, isNot(contains('ada@example.com')));
    expect(shown, contains('[PROTECTED]'));
    expect(shown, contains(userId));
    // Only what goes to the secret store holds them.
    expect(session.encode(), contains(_refresh1));
    expect(flow.encode(), contains(flow.verifier));
  });
}
