@Tags(['supabase'])
library;

import 'dart:convert';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'auth_support.dart';
import 'support.dart';

const _callback = 'https://app.example.com/callback';
const _exchange = '/auth/v1/token?grant_type=pkce';

String _s256(String verifier) =>
    base64UrlEncode(sha256Digest(ascii.encode(verifier))).replaceAll('=', '');

void main() {
  late AuthHarness harness;
  late MockHttpTransport transport;

  setUp(() {
    harness = AuthHarness();
    transport = harness.transport;
  });

  Future<String?> storedVerifier() async {
    final text = await harness.store.read(SupabaseAuth.pkceKey);
    return text == null
        ? null
        : (jsonDecode(text) as Map<String, Object?>)['verifier'] as String?;
  }

  group('the redirect allow-list', () {
    const allowed = [_callback, 'myapp://callback'];

    test('an address of the list, exactly, is sent', () async {
      transport.when(HttpMethod.post, '/auth/v1/otp').respond(200, json: {});
      await harness
          .auth(redirectUrls: allowed)
          .signInWithOtp(email: 'a@b.c', redirectTo: 'myapp://callback');
      expect(
        transport.requests.single.url.queryParameters['redirect_to'],
        'myapp://callback',
      );
    });

    test('the first of the list is the default', () async {
      transport.when(HttpMethod.post, '/auth/v1/otp').respond(200, json: {});
      final auth = harness.auth(redirectUrls: allowed);
      await auth.signInWithOtp(email: 'a@b.c');
      expect(
        transport.requests.single.url.queryParameters['redirect_to'],
        _callback,
      );
      final url = await auth.authorizationUrl('github');
      expect(url.queryParameters['redirect_to'], _callback);
    });

    test('anything else is refused before any request', () async {
      final auth = harness.auth(
        redirectUrls: allowed,
        window: FakeWindow((_, _) => fail('The window was opened')),
      );
      for (final redirect in [
        // A longer path, a prefix, another host, scheme, port, case.
        '$_callback/evil',
        '$_callback/',
        '$_callback?next=https://evil.example',
        '$_callback#fragment',
        'https://app.example.com/call',
        'https://app.example.com',
        'https://app.example.com.evil.org/callback',
        'https://evil.org/callback',
        'https://evil.org/?$_callback',
        'https://app.example.com@evil.org/callback',
        'http://app.example.com/callback',
        'https://app.example.com:8443/callback',
        'HTTPS://APP.EXAMPLE.COM/callback',
        ' $_callback',
        'myapp://callback/',
        'myapp://other',
        'other://callback',
        '',
      ]) {
        for (final call in <Future<Object?> Function()>[
          () => auth.signUp(
            email: 'a@b.c',
            password: 'correct horse',
            redirectTo: redirect,
          ),
          () => auth.signInWithOtp(email: 'a@b.c', redirectTo: redirect),
          () => auth.resetPassword('a@b.c', redirectTo: redirect),
          () => auth.authorizationUrl('github', redirectTo: redirect),
          () => auth.signInWithProvider('github', redirectTo: redirect),
        ]) {
          await expectLater(call(), throwsArgumentError, reason: redirect);
        }
      }
      expect(transport.requests, isEmpty);
      expect(await harness.store.keys(), isEmpty);
    });

    test('a redirect asked for with a phone is checked all the same', () async {
      final auth = harness.auth(redirectUrls: allowed);
      await expectLater(
        auth.signInWithOtp(phone: '+15550100', redirectTo: 'https://evil.org'),
        throwsArgumentError,
      );
      expect(transport.requests, isEmpty);
    });

    test('none configured: any redirect is refused', () async {
      final auth = harness.auth();
      await expectLater(
        auth.signInWithOtp(email: 'a@b.c', redirectTo: _callback),
        throwsArgumentError,
      );
      expect(transport.requests, isEmpty);
    });

    test('none configured and one needed: a clear error', () async {
      final auth = harness.auth(
        window: FakeWindow((_, _) => fail('The window was opened')),
      );
      final names = contains('spring.supabase.auth.redirect-urls');
      await expectLater(
        auth.authorizationUrl('github'),
        throwsA(isA<StateError>().having((e) => e.message, 'message', names)),
      );
      await expectLater(
        auth.signInWithProvider('github'),
        throwsA(isA<StateError>().having((e) => e.message, 'message', names)),
      );
      expect(transport.requests, isEmpty);
    });
  });

  group('authorizationUrl', () {
    test('the address of the provider, with the challenge', () async {
      final auth = harness.auth(redirectUrls: [_callback]);
      final url = await auth.authorizationUrl(
        'github',
        scopes: ['read:user', ' repo ', ''],
        queryParameters: {'prompt': 'select account'},
      );
      final verifier = (await storedVerifier())!;
      expect(
        '$url',
        '$projectUrl/auth/v1/authorize?provider=github'
            '&redirect_to=https%3A%2F%2Fapp.example.com%2Fcallback'
            '&scopes=read%3Auser%20repo'
            '&code_challenge=${_s256(verifier)}'
            '&code_challenge_method=s256'
            '&prompt=select%20account',
      );
      // Nothing is asked of Auth, and no key is in the address.
      expect(transport.requests, isEmpty);
      expect('$url', isNot(contains('anon-key')));
      expect('$url', isNot(contains(verifier)));
      expect(auth.isLoggedIn, isFalse);
    });

    test('challenge = base64url(SHA-256(verifier)), RFC 7636', () {
      final flow = SupabasePkceFlow(
        'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
      );
      expect(flow.challenge, 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
      expect(SupabasePkceFlow.method, 's256');
    });

    test('a verifier is 43 characters of base64url, new each time', () {
      final verifiers = {
        for (var i = 0; i < 50; i++) SupabasePkceFlow.start().verifier,
      };
      expect(verifiers, hasLength(50));
      for (final verifier in verifiers) {
        expect(verifier, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      }
    });

    test(
      'what the login sets itself cannot be passed as a parameter',
      () async {
        final auth = harness.auth(redirectUrls: [_callback]);
        for (final name in [
          'redirect_to',
          'Redirect_To',
          'provider',
          'scopes',
          'code_challenge',
          'code_challenge_method',
        ]) {
          await expectLater(
            auth.authorizationUrl(
              'github',
              queryParameters: {name: 'https://evil.org'},
            ),
            throwsArgumentError,
            reason: name,
          );
        }
        await expectLater(auth.authorizationUrl(' '), throwsArgumentError);
        expect(await harness.store.keys(), isEmpty);
      },
    );
  });

  group('completeSignIn', () {
    Future<SupabaseAuth> started({String redirect = _callback}) async {
      final auth = harness.auth(redirectUrls: [redirect]);
      await auth.authorizationUrl('github');
      return auth;
    }

    test('exchanges the code with the verifier, once', () async {
      final auth = await started();
      final verifier = (await storedVerifier())!;
      transport
          .when(HttpMethod.post, _exchange)
          .respond(200, json: sessionJson());
      final authentication = await auth.completeSignIn(
        Uri.parse('$_callback?code=auth-code-1'),
      );
      await settle();
      final request = transport.requests.single;
      expect('${request.url}', '$projectUrl$_exchange');
      expect(request.headers['apikey'], 'anon-key');
      expect(request.headers['Authorization'], 'Bearer anon-key');
      expect(bodyOf(request), {
        'auth_code': 'auth-code-1',
        'code_verifier': verifier,
      });
      expect(authentication.name, userId);
      expect(auth.isLoggedIn, isTrue);
      expect(
        harness.contexts.getContext().authentication,
        same(authentication),
      );
      expect(harness.changes, [same(authentication)]);
      expect(
        harness.publisher.events.single,
        isA<AuthenticationSuccessEvent>(),
      );
      // Used once: the verifier is gone, and the same redirect again
      // (a replayed link) makes no request.
      expect(await storedVerifier(), isNull);
      await expectLater(
        auth.completeSignIn(Uri.parse('$_callback?code=auth-code-1')),
        throwsA(isA<SupabaseAuthenticationException>()),
      );
      expect(transport.requests, hasLength(1));
    });

    test('a refused code spends the verifier too', () async {
      final auth = await started();
      transport
          .when(HttpMethod.post, _exchange)
          .respond(
            400,
            json: errorJson(400, 'bad_code_verifier', 'code verifier mismatch'),
          );
      await expectLater(
        auth.completeSignIn(Uri.parse('$_callback?code=stolen-code')),
        throwsA(isA<BadCredentialsException>()),
      );
      expect(auth.isLoggedIn, isFalse);
      expect(await storedVerifier(), isNull);
      await expectLater(
        auth.completeSignIn(Uri.parse('$_callback?code=auth-code-1')),
        throwsA(isA<SupabaseAuthenticationException>()),
      );
      expect(transport.requests, hasLength(1));
    });

    test('a redirect to another address is refused, the login stays', () async {
      final auth = await started();
      for (final redirect in [
        'https://app.example.com.evil.org/callback?code=c',
        'https://evil.org/callback?code=c',
        'https://app.example.com/callback/more?code=c',
        'https://app.example.com/other?code=c',
        'https://app.example.com/?code=c',
        'http://app.example.com/callback?code=c',
        'https://app.example.com:8443/callback?code=c',
        'https://user@app.example.com/callback?code=c',
        'myapp://callback?code=c',
      ]) {
        await expectLater(
          auth.completeSignIn(Uri.parse(redirect)),
          throwsA(
            isA<SupabaseAuthenticationException>().having(
              (e) => e.message,
              'message',
              contains('not the address the login asked for'),
            ),
          ),
          reason: redirect,
        );
      }
      expect(transport.requests, isEmpty);
      expect(auth.isLoggedIn, isFalse);
      // The login still waits for its own redirect.
      expect(await storedVerifier(), isNotNull);
    });

    test('a redirect with an error is a failed login', () async {
      for (final (redirect, code, matcher) in <(String, String, Matcher)>[
        (
          '$_callback?error=access_denied'
              '&error_description=The+user+denied+access',
          'access_denied',
          isA<SupabaseAuthenticationException>(),
        ),
        (
          '$_callback?error=access_denied&error_code=user_banned'
              '&error_description=User+is+banned',
          'user_banned',
          isA<LockedException>(),
        ),
        (
          // Auth still repeats the error in the fragment.
          '$_callback#error=server_error&error_code=unexpected_failure'
              '&error_description=Database+error',
          'unexpected_failure',
          isA<SupabaseAuthenticationException>(),
        ),
        (
          // An error wins over a code that comes with it.
          '$_callback?code=auth-code-1&error=access_denied',
          'access_denied',
          isA<SupabaseAuthenticationException>(),
        ),
      ]) {
        harness = AuthHarness();
        transport = harness.transport;
        final auth = await started();
        await expectLater(
          auth.completeSignIn(Uri.parse(redirect)),
          throwsA(
            allOf(
              matcher,
              isA<AuthenticationException>(),
              isA<SupabaseAuthFailure>().having(
                (e) => e.errorCode,
                'errorCode',
                code,
              ),
            ),
          ),
          reason: redirect,
        );
        expect(transport.requests, isEmpty, reason: redirect);
        expect(auth.isLoggedIn, isFalse);
        expect(await storedVerifier(), isNull);
      }
    });

    test('a redirect without a code is refused', () async {
      for (final redirect in [
        _callback,
        '$_callback?code=',
        '$_callback?state=x',
        // Tokens in the address (the implicit flow) are never taken.
        '$_callback#access_token=stolen-access&refresh_token=stolen-refresh',
        '$_callback#code=in-the-fragment',
      ]) {
        harness = AuthHarness();
        transport = harness.transport;
        final auth = await started();
        await expectLater(
          auth.completeSignIn(Uri.parse(redirect)),
          throwsA(isA<SupabaseAuthenticationException>()),
          reason: redirect,
        );
        expect(transport.requests, isEmpty);
        expect(auth.isLoggedIn, isFalse);
      }
    });

    test('no login waiting: refused without a request', () async {
      final auth = harness.auth(redirectUrls: [_callback]);
      await expectLater(
        auth.completeSignIn(Uri.parse('$_callback?code=auth-code-1')),
        throwsA(isA<SupabaseAuthenticationException>()),
      );
      await expectLater(
        auth.exchangeCode('auth-code-1'),
        throwsA(isA<SupabaseAuthenticationException>()),
      );
      expect(transport.requests, isEmpty);
    });

    test('an app address and a query of its own', () async {
      final auth = await started(redirect: 'myapp://callback?from=login');
      transport
          .when(HttpMethod.post, _exchange)
          .respond(200, json: sessionJson());
      await expectLater(
        auth.completeSignIn(Uri.parse('myapp://callback?code=c')),
        throwsA(isA<SupabaseAuthenticationException>()),
      );
      await auth.completeSignIn(
        Uri.parse('myapp://callback?from=login&code=auth-code-1'),
      );
      expect(auth.isLoggedIn, isTrue);
    });

    test('the login survives a restart of the application', () async {
      await started();
      final verifier = (await storedVerifier())!;
      transport
          .when(HttpMethod.post, _exchange)
          .respond(200, json: sessionJson());
      final restarted = harness.auth(redirectUrls: [_callback]);
      await restarted.completeSignIn(Uri.parse('$_callback?code=auth-code-1'));
      expect(bodyOf(transport.requests.single)['code_verifier'], verifier);
      expect(restarted.isLoggedIn, isTrue);
    });

    test('a new login replaces the one that waited', () async {
      final auth = await started();
      final first = await storedVerifier();
      await auth.authorizationUrl('google');
      final second = await storedVerifier();
      expect(second, isNot(first));
      transport
          .when(HttpMethod.post, _exchange)
          .respond(200, json: sessionJson());
      await auth.completeSignIn(Uri.parse('$_callback?code=auth-code-1'));
      expect(bodyOf(transport.requests.single)['code_verifier'], second);
    });

    test('exchangeCode sends the code with the verifier, once', () async {
      final auth = await started();
      final verifier = (await storedVerifier())!;
      transport
          .when(HttpMethod.post, _exchange)
          .respond(200, json: sessionJson());
      await auth.exchangeCode('auth-code-1');
      expect(bodyOf(transport.requests.single), {
        'auth_code': 'auth-code-1',
        'code_verifier': verifier,
      });
      expect(auth.isLoggedIn, isTrue);
      await expectLater(
        auth.exchangeCode('auth-code-1'),
        throwsA(isA<SupabaseAuthenticationException>()),
      );
      expect(transport.requests, hasLength(1));
    });
  });

  group('links of emails', () {
    test(
      'a magic link is finished with the verifier of signInWithOtp',
      () async {
        transport.when(HttpMethod.post, '/auth/v1/otp').respond(200, json: {});
        transport
            .when(HttpMethod.post, _exchange)
            .respond(200, json: sessionJson());
        final auth = harness.auth(redirectUrls: ['myapp://callback']);
        await auth.signInWithOtp(email: 'ada@example.com');
        final challenge = bodyOf(transport.requests.single)['code_challenge'];
        final verifier = (await storedVerifier())!;
        expect(challenge, _s256(verifier));
        await auth.completeSignIn(Uri.parse('myapp://callback?code=link-code'));
        expect(bodyOf(transport.requests.last), {
          'auth_code': 'link-code',
          'code_verifier': verifier,
        });
        expect(auth.isLoggedIn, isTrue);
      },
    );

    test('a password recovery: signed in, then the new password', () async {
      transport
          .when(HttpMethod.post, '/auth/v1/recover')
          .respond(200, json: {});
      transport
          .when(HttpMethod.post, _exchange)
          .respond(200, json: sessionJson());
      transport
          .when(HttpMethod.put, '/auth/v1/user')
          .respond(200, json: userJson());
      final auth = harness.auth(redirectUrls: ['myapp://reset']);
      await auth.resetPassword('ada@example.com');
      final challenge = bodyOf(transport.requests.single)['code_challenge'];
      expect(challenge, _s256((await storedVerifier())!));
      await auth.completeSignIn(Uri.parse('myapp://reset?code=recovery-code'));
      await auth.updateUser(password: 'new correct horse');
      expect(bodyOf(transport.requests.last), {
        'password': 'new correct horse',
      });
    });

    test('the code typed by the user works with a link pending', () async {
      transport.when(HttpMethod.post, '/auth/v1/otp').respond(200, json: {});
      transport
          .when(HttpMethod.post, '/auth/v1/verify')
          .respond(200, json: sessionJson());
      final auth = harness.auth();
      await auth.signInWithOtp(email: 'ada@example.com');
      await auth.verifyOtp(
        email: 'ada@example.com',
        token: '482913',
        type: SupabaseOtpType.email,
      );
      expect(auth.isLoggedIn, isTrue);
    });

    test('a refused request keeps no verifier; no answer keeps it', () async {
      transport
          .when(HttpMethod.post, '/auth/v1/otp')
          .respond(
            429,
            json: errorJson(429, 'over_email_send_rate_limit', 'Slow down'),
          );
      transport
          .when(HttpMethod.post, '/auth/v1/otp')
          .fail(HttpTransportException('timed out', isTimeout: true));
      final auth = harness.auth(redirectUrls: ['myapp://callback']);
      await expectLater(
        auth.signInWithOtp(email: 'a@b.c'),
        throwsA(isA<SupabaseAuthenticationException>()),
      );
      expect(await storedVerifier(), isNull);
      // The email may be on its way.
      await expectLater(
        auth.signInWithOtp(email: 'a@b.c'),
        throwsA(isA<SupabaseUnavailableException>()),
      );
      expect(await storedVerifier(), isNotNull);
    });

    test('without redirect addresses no link can be finished', () async {
      transport.when(HttpMethod.post, '/auth/v1/otp').respond(200, json: {});
      final auth = harness.auth();
      await auth.signInWithOtp(email: 'a@b.c');
      await expectLater(
        auth.completeSignIn(Uri.parse('myapp://callback?code=c')),
        throwsA(isA<SupabaseAuthenticationException>()),
      );
      expect(transport.requests, hasLength(1));
    });

    test('logout forgets the login that waited', () async {
      final auth = await harness.signedIn(redirectUrls: [_callback]);
      transport.when(HttpMethod.post, '/auth/v1/logout').respond(204);
      await auth.authorizationUrl('github');
      await auth.logout();
      expect(await harness.store.keys(), isEmpty);
    });
  });

  group('signInWithProvider', () {
    test('opens the page in the window and exchanges the code', () async {
      late Uri askedRedirect;
      final window = FakeWindow((redirect, authorization) {
        askedRedirect = redirect;
        return Uri.parse('$redirect?code=auth-code-1');
      });
      transport
          .when(HttpMethod.post, _exchange)
          .respond(200, json: sessionJson());
      final auth = harness.auth(
        redirectUrls: ['com.example.app:/oauth2redirect'],
        window: window,
      );
      final authentication = await auth.signInWithProvider(
        'google',
        scopes: ['email'],
        queryParameters: {'access_type': 'offline'},
      );
      final opened = window.opened.single;
      expect('$askedRedirect', 'com.example.app:/oauth2redirect');
      expect(opened.path, '/auth/v1/authorize');
      expect(opened.host, 'abcd.supabase.co');
      final sent = bodyOf(transport.requests.single);
      expect(opened.queryParameters, {
        'provider': 'google',
        'redirect_to': 'com.example.app:/oauth2redirect',
        'scopes': 'email',
        'code_challenge': _s256(sent['code_verifier']! as String),
        'code_challenge_method': 's256',
        'access_type': 'offline',
      });
      expect(sent['auth_code'], 'auth-code-1');
      expect('${transport.requests.single.url}', '$projectUrl$_exchange');
      expect(authentication.name, userId);
      expect(auth.isLoggedIn, isTrue);
      // The verifier lived in the call only.
      expect(await harness.store.read(SupabaseAuth.pkceKey), isNull);
    });

    test('without a window: a clear StateError, nothing asked', () async {
      final auth = harness.auth(redirectUrls: [_callback]);
      await expectLater(
        auth.signInWithProvider('github'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('AuthorizationWindow'),
              contains('authorizationUrl'),
            ),
          ),
        ),
      );
      expect(transport.requests, isEmpty);
      expect(await harness.store.keys(), isEmpty);
    });

    test('a redirect to another address is refused', () async {
      for (final redirect in [
        'https://app.example.com.evil.org/callback?code=c',
        'https://evil.org/callback?code=c',
        'https://app.example.com/callback2?code=c',
        'myapp://callback?code=c',
      ]) {
        final auth = harness.auth(
          redirectUrls: [_callback],
          window: FakeWindow((_, _) => Uri.parse(redirect)),
        );
        await expectLater(
          auth.signInWithProvider('github'),
          throwsA(isA<SupabaseAuthenticationException>()),
          reason: redirect,
        );
        expect(auth.isLoggedIn, isFalse);
      }
      expect(transport.requests, isEmpty);
    });

    test('a redirect with an error or without a code is refused', () async {
      for (final redirect in [
        '$_callback?error=access_denied&error_description=No',
        '$_callback?code=c&error=server_error',
        _callback,
        '$_callback#access_token=stolen-access',
      ]) {
        final auth = harness.auth(
          redirectUrls: [_callback],
          window: FakeWindow((_, _) => Uri.parse(redirect)),
        );
        await expectLater(
          auth.signInWithProvider('github'),
          throwsA(isA<AuthenticationException>()),
          reason: redirect,
        );
        expect(auth.isLoggedIn, isFalse);
      }
      expect(transport.requests, isEmpty);
    });

    test("a closed window is the window's own exception", () async {
      final auth = harness.auth(
        redirectUrls: [_callback],
        window: FakeWindow(
          (_, _) => throw const AuthorizationCancelledException(),
        ),
      );
      await expectLater(
        auth.signInWithProvider('github'),
        throwsA(isA<AuthorizationCancelledException>()),
      );
      expect(transport.requests, isEmpty);
      expect(auth.isLoggedIn, isFalse);
    });

    test('a refused code signs nobody in', () async {
      transport
          .when(HttpMethod.post, _exchange)
          .respond(
            404,
            json: errorJson(404, 'flow_state_not_found', 'invalid flow state'),
          );
      final auth = harness.auth(
        redirectUrls: [_callback],
        window: FakeWindow((redirect, _) => Uri.parse('$redirect?code=c')),
      );
      await expectLater(
        auth.signInWithProvider('github'),
        throwsA(isA<BadCredentialsException>()),
      );
      expect(auth.isLoggedIn, isFalse);
    });

    test('a window on a desktop may take a port of the loopback', () async {
      final loopback = Uri.parse('http://127.0.0.1:51234/callback');
      final window = FakeWindow(
        (redirect, _) => Uri.parse('$redirect?code=auth-code-1'),
        redirect: loopback,
      );
      transport
          .when(HttpMethod.post, _exchange)
          .respond(200, json: sessionJson());
      final auth = harness.auth(
        redirectUrls: ['http://127.0.0.1/callback'],
        window: window,
      );
      await auth.signInWithProvider('github');
      expect(
        window.opened.single.queryParameters['redirect_to'],
        'http://127.0.0.1:51234/callback',
      );
      expect(auth.isLoggedIn, isTrue);
    });

    test('and the redirect must then come back to that port', () async {
      final auth = harness.auth(
        redirectUrls: ['http://127.0.0.1/callback'],
        window: FakeWindow(
          (_, _) => Uri.parse('http://127.0.0.1:1/callback?code=c'),
          redirect: Uri.parse('http://127.0.0.1:51234/callback'),
        ),
      );
      await expectLater(
        auth.signInWithProvider('github'),
        throwsA(isA<SupabaseAuthenticationException>()),
      );
      expect(transport.requests, isEmpty);
    });

    test('a window that changes anything else is refused', () async {
      for (final changed in [
        'https://evil.org/callback',
        'http://evil.org/callback',
        'http://127.0.0.1:51234/other',
        'https://127.0.0.1:51234/callback',
        'http://user@127.0.0.1:51234/callback',
      ]) {
        final window = FakeWindow(
          (redirect, _) => Uri.parse('$redirect?code=c'),
          redirect: Uri.parse(changed),
        );
        final auth = harness.auth(
          redirectUrls: ['http://127.0.0.1/callback'],
          window: window,
        );
        await expectLater(
          auth.signInWithProvider('github'),
          throwsStateError,
          reason: changed,
        );
        expect(window.opened, isEmpty);
      }
      expect(transport.requests, isEmpty);
    });
  });
}
