// CSRF protection piece by piece: the token repositories (session and
// cookie, every attribute of the cookie), the masking of tokens and what a
// forged or damaged token does, and the filter's decisions.
import 'dart:convert';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'chain_support.dart';

void main() {
  group('the session repository', () {
    const repository = HttpSessionCsrfTokenRepository();

    test('keeps a token in the session and removes it', () async {
      final sessions = newSessions();
      final (request, response) = await exchange(sessions);
      expect(repository.loadToken(request), isNull);
      final token = repository.generateToken(request);
      repository.saveToken(token, request, response);
      final (next, _) = await exchange(
        sessions,
        cookies: {'JSESSIONID': request.getSession()!.id},
      );
      expect(repository.loadToken(next)?.token, token.token);
      repository.saveToken(null, next, response);
      expect(repository.loadToken(next), isNull);
    });

    test('removing a token creates no session', () async {
      final (request, response) = await exchange(newSessions());
      repository.saveToken(null, request, response);
      expect(request.getSession(create: false), isNull);
      expect(response.cookies, isEmpty);
    });

    test('tokens are random, with the names of the repository', () async {
      final (request, _) = await exchange(newSessions());
      final custom = const HttpSessionCsrfTokenRepository(
        headerName: 'X-T',
        parameterName: 'tok',
      ).generateToken(request);
      expect(custom.headerName, 'X-T');
      expect(custom.parameterName, 'tok');
      final a = repository.generateToken(request);
      final b = repository.generateToken(request);
      expect(a.token, isNot(b.token));
      expect(a.token.length, greaterThanOrEqualTo(43));
      expect(a.headerName, 'X-CSRF-TOKEN');
      expect(a.parameterName, '_csrf');
    });
  });

  group('the cookie repository', () {
    Future<ResponseCookie> saved(
      CookieCsrfTokenRepository repository, {
      CsrfToken? token = const CsrfToken('X-XSRF-TOKEN', '_csrf', 'abc'),
      String path = '/',
    }) async {
      final (request, response) = await exchange(newSessions(), path: path);
      repository.saveToken(token, request, response);
      return response.cookies.single;
    }

    test('scripts cannot read the cookie by default', () async {
      final cookie = await saved(const CookieCsrfTokenRepository());
      expect(cookie.name, 'XSRF-TOKEN');
      expect(cookie.value, 'abc');
      expect(cookie.httpOnly, isTrue);
      expect(cookie.path, '/');
      expect(cookie.maxAge, isNull);
    });

    test('withHttpOnlyFalse lets scripts read it', () async {
      final cookie = await saved(
        const CookieCsrfTokenRepository.withHttpOnlyFalse(
          cookieName: 'T',
          headerName: 'X-T',
          sameSite: 'Strict',
        ),
      );
      expect(cookie.httpOnly, isFalse);
      expect(cookie.name, 'T');
      expect(cookie.sameSite, 'Strict');
      const repository = CookieCsrfTokenRepository.withHttpOnlyFalse(
        headerName: 'X-T',
      );
      final (request, _) = await exchange(newSessions());
      expect(repository.generateToken(request).headerName, 'X-T');
    });

    test('path, domain and SameSite are the ones given', () async {
      final cookie = await saved(
        const CookieCsrfTokenRepository(
          cookiePath: '/app',
          cookieDomain: 'example.test',
          sameSite: 'Lax',
        ),
      );
      expect(cookie.path, '/app');
      expect(cookie.domain, 'example.test');
      expect(cookie.sameSite, 'Lax');
    });

    test('the cookie is Secure on HTTPS requests only', () async {
      const repository = CookieCsrfTokenRepository();
      expect((await saved(repository)).secure, isFalse);
      final secure = MockServerHttpRequest(HttpMethod.get, 'https://h/');
      final response = MockServerHttpResponse();
      repository.saveToken(
        const CsrfToken('X-XSRF-TOKEN', '_csrf', 'abc'),
        secure,
        response,
      );
      expect(response.cookies.single.secure, isTrue);
    });

    test('removing a token expires the cookie', () async {
      final cookie = await saved(
        const CookieCsrfTokenRepository(),
        token: null,
      );
      expect(cookie.value, isEmpty);
      expect(cookie.maxAge, Duration.zero);
      expect(cookie.httpOnly, isTrue);
    });

    test(
      'loads the cookie as the token, an empty or missing one is none',
      () async {
        const repository = CookieCsrfTokenRepository(
          cookieName: 'T',
          headerName: 'X-T',
          parameterName: 'p',
        );
        final sessions = newSessions();
        final (held, _) = await exchange(sessions, cookies: {'T': 'abc'});
        final token = repository.loadToken(held)!;
        expect(
          (token.token, token.headerName, token.parameterName),
          ('abc', 'X-T', 'p'),
        );
        final (empty, _) = await exchange(sessions, cookies: {'T': ''});
        expect(repository.loadToken(empty), isNull);
        final (other, _) = await exchange(
          sessions,
          cookies: {'XSRF-TOKEN': 'a'},
        );
        expect(repository.loadToken(other), isNull);
      },
    );
  });

  group('masked tokens', () {
    const handler = XorCsrfTokenRequestAttributeHandler();
    const token = CsrfToken('X-CSRF-TOKEN', '_csrf', 'the-real-token');

    String? resolve({String? header, String? field}) {
      final request = MockServerHttpRequest(HttpMethod.post, '/');
      if (header != null) {
        request.headers.set('X-CSRF-TOKEN', header);
      }
      return handler.resolveCsrfTokenValue(request, token, {
        '_csrf': ?(field == null ? null : [field]),
      });
    }

    test('a page gets other bytes every time, the check unmasks them', () {
      final first = handler.present(token).token;
      final second = handler.present(token).token;
      expect(first, isNot(token.token));
      expect(first, isNot(second));
      expect(resolve(header: first), token.token);
      expect(resolve(field: second), token.token);
    });

    test('the header comes before the form field', () {
      final masked = handler.present(token).token;
      expect(resolve(header: masked, field: 'other'), token.token);
      expect(resolve(), isNull);
    });

    test('bytes that cannot be a masked token are no token', () {
      final masked = base64Url.decode(handler.present(token).token);
      expect(
        resolve(field: base64Url.encode([...masked, 0])),
        isNull,
        reason: 'an odd number of bytes',
      );
      expect(resolve(field: ''), isNull, reason: 'no bytes');
      expect(resolve(field: '!!not base64!!'), isNull);
    });

    test('bytes that decode to broken UTF-8 are a wrong token', () {
      final broken = base64Url.encode([0, 0xff]);
      final value = resolve(field: broken);
      expect(value, isNotNull);
      expect(value, isNot(token.token));
    });

    test('the plain handler sends and reads the token as it is', () {
      const plain = CsrfTokenRequestAttributeHandler();
      expect(plain.present(token), same(token));
      final request = MockServerHttpRequest(HttpMethod.post, '/')
        ..headers.set('X-CSRF-TOKEN', 'raw');
      expect(plain.resolveCsrfTokenValue(request, token, null), 'raw');
    });
  });

  group('the filter', () {
    Future<(Application, MockServerHttpResponse, MockServerHttpRequest)> run(
      CsrfFilter filter,
      HttpSessionManager sessions, {
      HttpMethod method = HttpMethod.post,
      Map<String, String> headers = const {},
      Map<String, String> cookies = const {},
      Map<String, String>? form,
    }) async {
      final (request, response) = await exchange(
        sessions,
        method: method,
        path: '/pay',
        headers: headers,
        cookies: cookies,
      );
      if (form != null) {
        setForm(request, form);
      }
      final application = Application();
      await filter.doFilter(request, response, application);
      return (application, response, request);
    }

    /// A page read: the token as the page shows it, and the session.
    Future<(String, Map<String, String>)> page(
      CsrfFilter filter,
      HttpSessionManager sessions, {
      Map<String, String> cookies = const {},
    }) async {
      final (request, response) = await exchange(
        sessions,
        path: '/form',
        cookies: cookies,
      );
      final reader = _Page();
      await filter.doFilter(request, response, reader);
      return (reader.shown!, {'JSESSIONID': request.getSession()!.id});
    }

    test('safe methods pass without a token and create none', () async {
      final sessions = newSessions();
      const filter = CsrfFilter(HttpSessionCsrfTokenRepository());
      for (final method in [
        HttpMethod.get,
        HttpMethod.head,
        HttpMethod.trace,
        HttpMethod.options,
      ]) {
        final (application, response, request) = await run(
          filter,
          sessions,
          method: method,
        );
        expect(application.reached, isTrue, reason: '$method');
        expect(response.cookies, isEmpty, reason: 'nothing read the token');
        expect(request.getSession(create: false), isNull);
      }
    });

    test('every token shown on a page of the session opens the POST', () async {
      final sessions = newSessions();
      const filter = CsrfFilter(HttpSessionCsrfTokenRepository());
      final (shown, cookies) = await page(filter, sessions);
      final byHeader = await run(
        filter,
        sessions,
        headers: {'X-CSRF-TOKEN': shown},
        cookies: cookies,
      );
      expect(byHeader.$1.reached, isTrue);
      final byField = await run(
        filter,
        sessions,
        form: {'_csrf': shown},
        cookies: cookies,
      );
      expect(byField.$1.reached, isTrue);
      final (again, _) = await page(filter, sessions, cookies: cookies);
      expect(again, isNot(shown), reason: 'masked again for each page');
      final second = await run(
        filter,
        sessions,
        headers: {'X-CSRF-TOKEN': again},
        cookies: cookies,
      );
      expect(second.$1.reached, isTrue);
    });

    test('a POST without a token, with a wrong one or with another session '
        'is refused', () async {
      final sessions = newSessions();
      const filter = CsrfFilter(HttpSessionCsrfTokenRepository());
      final (shown, cookies) = await page(filter, sessions);
      final (otherShown, _) = await page(filter, sessions);
      for (final (name, headers, form, jar) in [
        ('none', <String, String>{}, null, cookies),
        ('wrong header', {'X-CSRF-TOKEN': 'nope'}, null, cookies),
        ('wrong field', <String, String>{}, {'_csrf': 'nope'}, cookies),
        ('another session', {'X-CSRF-TOKEN': otherShown}, null, cookies),
        ('no session', {'X-CSRF-TOKEN': shown}, null, <String, String>{}),
      ]) {
        final (application, response, _) = await run(
          filter,
          sessions,
          headers: headers,
          form: form,
          cookies: jar,
        );
        expect(application.reached, isFalse, reason: name);
        expect(response.statusCode, 403, reason: name);
      }
    });

    test(
      'the header is checked instead of the form when it is there',
      () async {
        final sessions = newSessions();
        const filter = CsrfFilter(HttpSessionCsrfTokenRepository());
        final (shown, cookies) = await page(filter, sessions);
        final (application, response, _) = await run(
          filter,
          sessions,
          headers: {'X-CSRF-TOKEN': 'nope'},
          form: {'_csrf': shown},
          cookies: cookies,
        );
        expect(application.reached, isFalse);
        expect(response.statusCode, 403);
      },
    );

    test('a damaged masked token is a 403, not an error', () async {
      final sessions = newSessions();
      const filter = CsrfFilter(HttpSessionCsrfTokenRepository());
      final (shown, cookies) = await page(filter, sessions);
      final bytes = base64Url.decode(shown);
      for (final damaged in [
        base64Url.encode([...bytes, 1]),
        base64Url.encode([0, 0xff]),
        base64Url.encode(const []),
        '%%%',
      ]) {
        final (application, response, _) = await run(
          filter,
          sessions,
          headers: {'X-CSRF-TOKEN': damaged},
          cookies: cookies,
        );
        expect(application.reached, isFalse, reason: damaged);
        expect(response.statusCode, 403, reason: damaged);
      }
    });

    test(
      'with no token stored, a POST fails and a token is made for the next one',
      () async {
        final sessions = newSessions();
        final denied = <Object>[];
        final filter = CsrfFilter(
          const CookieCsrfTokenRepository(),
          accessDeniedHandler: _Recording(denied),
        );
        final (application, response, _) = await run(filter, sessions);
        expect(application.reached, isFalse);
        expect(denied.single, isA<MissingCsrfTokenException>());
        expect(response.cookies.single.name, 'XSRF-TOKEN');
        expect(response.cookies.single.value, isNotEmpty);
      },
    );

    test('a wrong token is reported as an invalid one', () async {
      final denied = <Object>[];
      final filter = CsrfFilter(
        const CookieCsrfTokenRepository(),
        requestHandler: const CsrfTokenRequestAttributeHandler(),
        accessDeniedHandler: _Recording(denied),
      );
      final sessions = newSessions();
      await run(
        filter,
        sessions,
        headers: {'X-XSRF-TOKEN': 'wrong'},
        cookies: {'XSRF-TOKEN': 'right'},
      );
      expect(denied.single, isA<InvalidCsrfTokenException>());
    });

    test('the cookie pattern: the script sends the cookie back', () async {
      final sessions = newSessions();
      const filter = CsrfFilter(
        CookieCsrfTokenRepository.withHttpOnlyFalse(),
        requestHandler: CsrfTokenRequestAttributeHandler(),
      );
      final ok = await run(
        filter,
        sessions,
        headers: {'X-XSRF-TOKEN': 'right'},
        cookies: {'XSRF-TOKEN': 'right'},
      );
      expect(ok.$1.reached, isTrue);
      final wrong = await run(
        filter,
        sessions,
        headers: {'X-XSRF-TOKEN': 'wrong'},
        cookies: {'XSRF-TOKEN': 'right'},
      );
      expect(wrong.$1.reached, isFalse);
      expect(wrong.$2.statusCode, 403);
    });

    test('the matcher decides which requests need a token', () async {
      final filter = CsrfFilter(
        const HttpSessionCsrfTokenRepository(),
        requireCsrfProtectionMatcher: PathPatternRequestMatcher(
          '/pay',
          method: HttpMethod.put,
        ),
      );
      final sessions = newSessions();
      expect((await run(filter, sessions)).$1.reached, isTrue);
      final put = await run(filter, sessions, method: HttpMethod.put);
      expect(put.$1.reached, isFalse);
      expect(put.$2.statusCode, 403);
    });

    test('the test support attribute stands in for a token', () async {
      const filter = CsrfFilter(HttpSessionCsrfTokenRepository());
      for (final (valid, reached) in [(true, true), (false, false)]) {
        final (request, response) = await exchange(
          newSessions(),
          method: HttpMethod.post,
        );
        request.attributes[CsrfFilter.testTokenAttribute] = valid;
        final application = Application();
        await filter.doFilter(request, response, application);
        expect(application.reached, reached);
        expect(response.statusCode, reached ? 200 : 403);
      }
    });

    test('csrfTokenOf is null where the filter did not run', () {
      expect(csrfTokenOf(MockServerHttpRequest(HttpMethod.get, '/')), isNull);
    });
  });
}

final class _Page implements WebFilterChain {
  String? shown;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    shown = csrfTokenOf(request)!.token;
    await response.close();
  }
}

final class _Recording implements AccessDeniedHandler {
  _Recording(this.into);

  final List<Object> into;

  @override
  Future<void> handle(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AccessDeniedException accessDeniedException,
  ) async {
    into.add(accessDeniedException);
    response.statusCode = 403;
    await response.close();
  }
}
