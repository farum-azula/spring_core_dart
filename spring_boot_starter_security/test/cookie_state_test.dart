// What the chain keeps in the browser instead of a session before a login:
// the signed cookies of CookieSigner, CookieRequestCache and
// CookieOAuth2AuthorizationRequestRepository. A cookie the server did not
// sign, changed, moved, expired or garbage is never read, and nothing
// makes a session.
import 'dart:convert';
import 'dart:math';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

final _key = List<int>.generate(32, (i) => i);

MockServerHttpRequest _get(String target, {Map<String, String>? cookies}) {
  final request = MockServerHttpRequest(HttpMethod.get, target);
  cookies?.forEach(request.addCookie);
  return request;
}

ResponseCookie? _cookie(MockServerHttpResponse response, String name) =>
    response.cookies.where((c) => c.name == name).lastOrNull;

void main() {
  group('CookieSigner', () {
    final signer = CookieSigner(_key);
    final now = DateTime.utc(2026, 10, 31, 12);

    test('opens what it signed, for the same cookie, before it expires', () {
      final signed = signer.sign(
        'c',
        '/orders/42?continue',
        const Duration(
          minutes: 5,
        ),
        now: now,
      );
      expect(signer.open('c', signed, now: now), '/orders/42?continue');
      expect(
        signer.open('c', signed, now: now.add(const Duration(minutes: 4))),
        '/orders/42?continue',
      );
      expect(
        signer.open('c', signed, now: now.add(const Duration(minutes: 5))),
        isNull,
      );
      expect(signer.open('other', signed, now: now), isNull);
    });

    test('another key, a changed value or a changed signature: null', () {
      final signed = signer.sign('c', '/a', const Duration(minutes: 5));
      expect(CookieSigner(List.filled(32, 7)).open('c', signed), isNull);
      final [payload, mac] = signed.split('.');
      final forged = base64Url
          .encode(utf8.encode('99999999999999\u0000//evil.example'))
          .replaceAll('=', '');
      expect(signer.open('c', '$forged.$mac'), isNull);
      final flipped = mac.replaceRange(0, 1, mac[0] == 'A' ? 'B' : 'A');
      expect(signer.open('c', '$payload.$flipped'), isNull);
      expect(signer.open('c', payload), isNull);
    });

    test('garbage never throws and never opens', () {
      final random = Random(42);
      const alphabet =
          'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.=+/'
          '%\u0000\r\n ;"\\é';
      for (var i = 0; i < 2000; i++) {
        final text = String.fromCharCodes([
          for (var j = random.nextInt(200); j > 0; j--)
            alphabet.codeUnitAt(random.nextInt(alphabet.length)),
        ]);
        expect(signer.open('c', text), isNull, reason: text);
      }
      expect(signer.open('c', null), isNull);
      expect(signer.open('c', ''), isNull);
      expect(signer.open('c', '${'A' * 5000}.AAAA'), isNull);
    });

    test('a key shorter than 32 bytes, a secret shorter than 32 characters '
        'are refused', () {
      expect(() => CookieSigner(List.filled(31, 1)), throwsArgumentError);
      expect(() => CookieSigner.fromSecret('short'), throwsArgumentError);
      expect(CookieSigner.fromSecret('x' * 32), isA<CookieSigner>());
    });
  });

  group('CookieRequestCache', () {
    final cache = CookieRequestCache(signer: CookieSigner(_key));

    test('saves the page in a signed HttpOnly cookie, no session', () {
      final request = _get('/orders/42?tab=items');
      final response = MockServerHttpResponse();
      cache.saveRequest(request, response);
      final cookie = _cookie(response, CookieRequestCache.cookieName)!;
      expect(cookie.httpOnly, isTrue);
      expect(cookie.sameSite, 'Lax');
      expect(cookie.secure, isFalse);
      expect(cookie.path, '/');
      expect(cookie.value, isNot(contains('orders')));

      final back = _get(
        '/login',
        cookies: {CookieRequestCache.cookieName: cookie.value},
      );
      expect(cache.getRedirectUrl(back), '/orders/42?tab=items&continue');
    });

    test('Secure over HTTPS', () {
      final response = MockServerHttpResponse();
      cache.saveRequest(_get('https://shop.test/orders'), response);
      expect(_cookie(response, CookieRequestCache.cookieName)!.secure, isTrue);
    });

    test('an unsigned or forged cookie is no redirect', () {
      for (final value in [
        '/orders/42',
        'https://evil.example/',
        '//evil.example',
        CookieSigner(List.filled(32, 9)).sign(
          CookieRequestCache.cookieName,
          '/orders',
          const Duration(minutes: 5),
        ),
      ]) {
        final request = _get(
          '/login',
          cookies: {CookieRequestCache.cookieName: value},
        );
        expect(cache.getRedirectUrl(request), isNull, reason: value);
      }
    });

    test('a signed value is still checked: only a path of this site', () {
      final signer = CookieSigner(_key);
      for (final value in [
        '//evil.example/x',
        r'/\evil.example',
        'https://evil.example/',
        'javascript:alert(1)',
        '/a\r\nSet-Cookie: x=1',
        '',
      ]) {
        final request = _get(
          '/login',
          cookies: {
            CookieRequestCache.cookieName: signer.sign(
              CookieRequestCache.cookieName,
              value,
              const Duration(minutes: 5),
            ),
          },
        );
        expect(cache.getRedirectUrl(request), isNull, reason: value);
      }
    });

    test('a request that is not a page is not saved', () {
      final request = _get('/api/books');
      request.headers.set('Accept', 'application/json');
      final response = MockServerHttpResponse();
      cache.saveRequest(request, response);
      expect(response.cookies, isEmpty);
    });

    test('removeRequest clears the cookie it finds', () {
      final response = MockServerHttpResponse();
      cache.removeRequest(
        _get('/', cookies: {CookieRequestCache.cookieName: 'x'}),
        response,
      );
      final cookie = _cookie(response, CookieRequestCache.cookieName)!;
      expect(cookie.value, '');
      expect(cookie.maxAge, Duration.zero);

      final none = MockServerHttpResponse();
      cache.removeRequest(_get('/'), none);
      expect(none.cookies, isEmpty);
    });
  });

  group('CookieOAuth2AuthorizationRequestRepository', () {
    final repository = CookieOAuth2AuthorizationRequestRepository(
      signer: CookieSigner(_key),
    );
    const name = CookieOAuth2AuthorizationRequestRepository.cookieName;

    OAuth2AuthorizationRequest authorizationRequest({
      Map<String, Object?>? attributes,
      bool formPost = false,
    }) => OAuth2AuthorizationRequest(
      authorizationUri: 'https://idp.test/auth',
      clientId: 'shop',
      redirectUri: 'https://shop.test/login/oauth2/code/idp',
      state: 'the-state',
      scopes: const {'openid', 'profile'},
      additionalParameters: {
        'code_challenge': 'challenge',
        if (formPost) 'response_mode': 'form_post',
      },
      attributes:
          attributes ??
          const {
            'registration_id': 'idp',
            'code_verifier': 'verifier',
            'nonce': 'nonce',
          },
    );

    String saved({
      OAuth2AuthorizationRequest? request,
      String target = 'https://shop.test/oauth2/authorization/idp',
    }) {
      final response = MockServerHttpResponse();
      repository.saveAuthorizationRequest(
        request ?? authorizationRequest(),
        _get(target),
        response,
      );
      return _cookie(response, name)!.value;
    }

    MockServerHttpRequest callback(
      String? cookie, {
      String state = 'the-state',
    }) => _get(
      'https://shop.test/login/oauth2/code/idp?code=c&state=$state',
      cookies: {name: ?cookie},
    );

    test('the callback with the state finds every part again, then the '
        'cookie is removed', () {
      final value = saved();
      final found = repository.loadAuthorizationRequest(callback(value))!;
      expect(found.state, 'the-state');
      expect(found.clientId, 'shop');
      expect(found.redirectUri, 'https://shop.test/login/oauth2/code/idp');
      expect(found.scopes, {'openid', 'profile'});
      expect(found.codeVerifier, 'verifier');
      expect(found.nonce, 'nonce');
      expect(found.registrationId, 'idp');
      expect(found.additionalParameters['code_challenge'], 'challenge');

      final response = MockServerHttpResponse();
      expect(
        repository.removeAuthorizationRequest(callback(value), response),
        isNotNull,
      );
      expect(_cookie(response, name)!.maxAge, Duration.zero);
    });

    test('the cookie: HttpOnly, Lax, Secure over HTTPS; None for a form '
        'post over HTTPS only', () {
      ResponseCookie save(String target, {bool formPost = false}) {
        final response = MockServerHttpResponse();
        repository.saveAuthorizationRequest(
          authorizationRequest(formPost: formPost),
          _get(target),
          response,
        );
        return _cookie(response, name)!;
      }

      final https = save('https://shop.test/oauth2/authorization/idp');
      expect(https.httpOnly, isTrue);
      expect(https.secure, isTrue);
      expect(https.sameSite, 'Lax');
      expect(https.value, isNot(contains('verifier')));
      expect(
        save('https://shop.test/x', formPost: true).sameSite,
        'None',
      );
      final http = save('/oauth2/authorization/idp', formPost: true);
      expect(http.sameSite, 'Lax');
      expect(http.secure, isFalse);
    });

    test('another state finds nothing and leaves the cookie', () {
      final value = saved();
      final response = MockServerHttpResponse();
      expect(
        repository.removeAuthorizationRequest(
          callback(value, state: 'other'),
          response,
        ),
        isNull,
      );
      expect(response.cookies, isEmpty);
    });

    test('a cookie the server did not sign, or signed for another cookie, '
        'is no request', () {
      final json = jsonEncode({
        'authorizationUri': 'https://idp.test/auth',
        'clientId': 'shop',
        'redirectUri': 'https://evil.example/cb',
        'state': 'the-state',
        'scopes': <String>[],
        'additionalParameters': <String, String>{},
        'attributes': <String, String>{},
      });
      for (final value in [
        json,
        base64Url.encode(utf8.encode(json)),
        CookieSigner(_key).sign('REDIRECT_URI', json, const Duration(hours: 1)),
        CookieSigner(List.filled(32, 3)).sign(
          name,
          json,
          const Duration(
            hours: 1,
          ),
        ),
      ]) {
        expect(
          repository.loadAuthorizationRequest(callback(value)),
          isNull,
          reason: value,
        );
      }
    });

    test('a signed value of the wrong shape is no request', () {
      final signer = CookieSigner(_key);
      for (final text in [
        'not json',
        '[]',
        '{"state":"the-state"}',
        jsonEncode({
          'authorizationUri': 'https://idp.test/auth',
          'clientId': 'shop',
          'redirectUri': 'https://shop.test/cb',
          'state': 'the-state',
          'scopes': [1],
          'additionalParameters': <String, String>{},
          'attributes': <String, String>{},
        }),
        jsonEncode({
          'authorizationUri': 'https://idp.test/auth',
          'clientId': 'shop',
          'redirectUri': 'https://shop.test/cb',
          'state': 'the-state',
          'scopes': <String>[],
          'additionalParameters': <String, String>{},
          'attributes': {'code_verifier': 1},
        }),
      ]) {
        final value = signer.sign(name, text, const Duration(minutes: 5));
        expect(
          repository.loadAuthorizationRequest(callback(value)),
          isNull,
          reason: text,
        );
      }
    });

    test('attributes that are not strings cannot be kept', () {
      expect(
        () => saved(
          request: authorizationRequest(attributes: {'when': DateTime(2026)}),
        ),
        throwsArgumentError,
      );
    });

    test('saving null clears the cookie of a login started before', () {
      final response = MockServerHttpResponse();
      repository.saveAuthorizationRequest(
        null,
        _get('/', cookies: {name: 'x'}),
        response,
      );
      expect(_cookie(response, name)!.maxAge, Duration.zero);
    });
  });
}
