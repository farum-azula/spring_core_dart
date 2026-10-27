// The login and logout filters one by one: what a login does to the session
// and the CSRF token, where it sends the user, how a Basic header is read
// (padding, size, the first colon), what a logout leaves behind, and the
// default pages.
import 'dart:convert';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'chain_support.dart';

final _someone = UsernamePasswordAuthenticationToken.unauthenticated('a', 'b');

AuthenticationManager _manager() =>
    ProviderManager([DaoAuthenticationProvider(testUsers())]);

void main() {
  group('WebAuthenticationDetails', () {
    test('equal for one address and one session, each part counts', () async {
      final sessions = newSessions();
      final (first, _) = await exchange(sessions);
      final id = first.getSession()!.id;
      Future<MockServerHttpRequest> again({String? address}) async {
        final (request, _) = await exchange(
          sessions,
          cookies: {'JSESSIONID': id},
        );
        request.remoteAddress = address ?? request.remoteAddress;
        return request;
      }

      final details = WebAuthenticationDetails.of(await again());
      final same = WebAuthenticationDetails.of(await again());
      expect(same, details);
      expect(same.hashCode, details.hashCode);
      expect(details.sessionId, id);
      expect(
        WebAuthenticationDetails.of(await again(address: '10.0.0.7')),
        isNot(details),
        reason: 'another address',
      );
      final (bare, _) = await exchange(sessions);
      expect(
        WebAuthenticationDetails.of(bare),
        isNot(details),
        reason: 'another session',
      );
    });

    test('a request without the session filter has no session id', () {
      final request = MockServerHttpRequest(HttpMethod.get, '/');
      expect(WebAuthenticationDetails.of(request).sessionId, isNull);
    });
  });

  group('session strategies', () {
    test('a new id for an existing session, sent to the client', () async {
      final sessions = newSessions();
      final (setup, _) = await exchange(sessions);
      final before = setup.getSession()!.id;
      final (request, response) = await exchange(
        sessions,
        cookies: {'JSESSIONID': before},
      );
      await const ChangeSessionIdAuthenticationStrategy().onAuthentication(
        _someone,
        request,
        response,
      );
      final after = request.getSession(create: false)!.id;
      expect(after, isNot(before));
      expect(response.cookies.single.value, after);
      expect(await sessions.repository.findById(before), isNull);
    });

    test('without a session none is created for the id change', () async {
      final sessions = newSessions();
      final (request, response) = await exchange(sessions);
      await const ChangeSessionIdAuthenticationStrategy().onAuthentication(
        _someone,
        request,
        response,
      );
      expect(request.getSession(create: false), isNull);
      expect(response.cookies, isEmpty);
    });

    test('the CSRF token of the session is dropped at login', () async {
      final sessions = newSessions();
      const repository = HttpSessionCsrfTokenRepository();
      final (setup, setupResponse) = await exchange(sessions);
      repository.saveToken(
        const CsrfToken('X-CSRF-TOKEN', '_csrf', 'seen-before-login'),
        setup,
        setupResponse,
      );
      final (request, response) = await exchange(
        sessions,
        cookies: {'JSESSIONID': setup.getSession()!.id},
      );
      expect(repository.loadToken(request)?.token, 'seen-before-login');
      await const CsrfAuthenticationStrategy(repository)
          .onAuthentication(_someone, request, response);
      expect(repository.loadToken(request), isNull);
    });

    test('the CSRF cookie is expired at login only if there was one', () async {
      final sessions = newSessions();
      const repository = CookieCsrfTokenRepository();
      const strategy = CsrfAuthenticationStrategy(repository);
      final (none, noneResponse) = await exchange(sessions);
      await strategy.onAuthentication(_someone, none, noneResponse);
      expect(noneResponse.cookies, isEmpty);

      final (held, heldResponse) = await exchange(
        sessions,
        cookies: {'XSRF-TOKEN': 'seen-before-login'},
      );
      await strategy.onAuthentication(_someone, held, heldResponse);
      final cookie = heldResponse.cookies.single;
      expect(cookie.name, 'XSRF-TOKEN');
      expect(cookie.maxAge, Duration.zero);
    });

    test('the composite runs its strategies in order', () async {
      final order = <String>[];
      final strategy = CompositeSessionAuthenticationStrategy([
        _Noting('first', order),
        _Noting('second', order),
      ]);
      final (request, response) = await exchange(newSessions());
      await strategy.onAuthentication(_someone, request, response);
      expect(order, ['first', 'second']);
    });
  });

  group('success and failure handlers', () {
    Future<String?> redirect(
      SavedRequestAwareAuthenticationSuccessHandler handler,
      HttpSessionManager sessions,
      String sessionId,
    ) async {
      final (request, response) = await exchange(
        sessions,
        method: HttpMethod.post,
        path: '/login',
        cookies: {'JSESSIONID': sessionId},
      );
      await handler.onAuthenticationSuccess(request, response, _someone);
      expect(response.statusCode, 302);
      return response.headers['location'];
    }

    Future<String> savedRequest(
      HttpSessionManager sessions,
      RequestCache cache,
    ) async {
      final (request, response) = await exchange(sessions, path: '/secret');
      await cache.saveRequest(request, response);
      return request.getSession(create: false)!.id;
    }

    test('the saved request first, the default URL by default', () async {
      final sessions = newSessions();
      final cache = HttpSessionRequestCache();
      final handler = SavedRequestAwareAuthenticationSuccessHandler(
        requestCache: cache,
        defaultTargetUrl: '/home',
      );
      final id = await savedRequest(sessions, cache);
      expect(await redirect(handler, sessions, id), '/secret?continue');
      expect(
        await redirect(handler, sessions, id),
        '/home',
        reason: 'the saved request is used once',
      );
    });

    test('always the default URL when told so', () async {
      final sessions = newSessions();
      final cache = HttpSessionRequestCache();
      final id = await savedRequest(sessions, cache);
      final handler = SavedRequestAwareAuthenticationSuccessHandler(
        requestCache: cache,
        defaultTargetUrl: '/home',
        alwaysUseDefaultTargetUrl: true,
        contextPath: '/app',
      );
      expect(await redirect(handler, sessions, id), '/app/home');
    });

    test(
      'the failure handlers answer with the URL or the entry point',
      () async {
        final (request, response) = await exchange(newSessions());
        await const SimpleUrlAuthenticationFailureHandler(
          '/login?error',
          contextPath: '/app',
        ).onAuthenticationFailure(
          request,
          response,
          BadCredentialsException('x'),
        );
        expect(response.headers['location'], '/app/login?error');

        final (second, secondResponse) = await exchange(newSessions());
        await const AuthenticationEntryPointFailureHandler(
          BasicAuthenticationEntryPoint('Mine'),
        ).onAuthenticationFailure(
          second,
          secondResponse,
          BadCredentialsException('x'),
        );
        expect(secondResponse.statusCode, 401);
        expect(
          secondResponse.headers['www-authenticate'],
          contains('realm="Mine"'),
        );
      },
    );
  });

  group('Basic', () {
    UsernamePasswordAuthenticationToken? convert(
      String authorization, {
      int maxHeaderLength = 8192,
    }) {
      final request = MockServerHttpRequest(HttpMethod.get, '/')
        ..headers.set('authorization', authorization);
      return BasicAuthenticationFilter(
        _manager(),
        maxHeaderLength: maxHeaderLength,
      ).convert(request);
    }

    final rejected = throwsA(isA<BadCredentialsException>());

    test('base64 with missing padding is read, like Java does', () {
      for (final header in [
        'Basic YTpiYw',
        'Basic YTpiYw==',
        'Basic YTpiYw== ',
      ]) {
        final token = convert(header)!;
        expect(token.principal, 'a', reason: header);
        expect(token.credentials, 'bc', reason: header);
      }
      expect(convert('Basic YTpi')!.credentials, 'b');
    });

    test('padding that is cut short is refused, not repaired', () {
      expect(() => convert('Basic YTpiYw='), rejected);
    });

    test('text that is not base64 is refused', () {
      expect(() => convert('Basic !!!!'), rejected);
      expect(() => convert('Basic YT*iYw=='), rejected);
    });

    test('the header may be as long as the limit, not longer', () {
      final header =
          'Basic ${base64.encode(utf8.encode('ada:a-long-enough-password'))}';
      expect(convert(header, maxHeaderLength: header.length), isNotNull);
      expect(
        () => convert(header, maxHeaderLength: header.length - 1),
        rejected,
      );
    });

    test('the first colon separates, an empty user name is still one', () {
      String header(String credentials) =>
          'Basic ${base64.encode(utf8.encode(credentials))}';
      final empty = convert(header(':secret'))!;
      expect(empty.principal, '');
      expect(empty.credentials, 'secret');
      final many = convert(header('ada:pw:with:colons'))!;
      expect(many.principal, 'ada');
      expect(many.credentials, 'pw:with:colons');
      expect(() => convert(header('no-colon')), rejected);
    });

    test('no header, another scheme, an empty or doubled header', () {
      final plain = MockServerHttpRequest(HttpMethod.get, '/');
      final filter = BasicAuthenticationFilter(_manager());
      expect(filter.convert(plain), isNull);
      expect(convert('Bearer abc'), isNull);
      expect(() => convert('Basic'), rejected);
      final twice = MockServerHttpRequest(HttpMethod.get, '/')
        ..headers.add('authorization', 'Basic YTpi')
        ..headers.add('authorization', 'Basic YTpi');
      expect(() => filter.convert(twice), rejected);
    });

    Future<Application> run(
      Map<String, String> headers,
      MockServerHttpResponse response, {
      String? loggedIn,
    }) async {
      final application = Application();
      final request = MockServerHttpRequest(HttpMethod.get, '/');
      for (final MapEntry(:key, :value) in headers.entries) {
        request.headers.set(key, value);
      }
      await SecurityContextHolder.runWithContext(() async {
        if (loggedIn != null) {
          final user = User.withUsername(loggedIn)
              .password('x')
              .roles(['USER'])
              .build();
          SecurityContextHolder.setContext(
            SecurityContextHolder.createEmptyContext()
              ..authentication =
                  UsernamePasswordAuthenticationToken.authenticated(
                    user,
                    null,
                    user.authorities,
                  ),
          );
        }
        await BasicAuthenticationFilter(_manager())
            .doFilter(request, response, application);
      });
      return application;
    }

    test('the user already logged in is not checked again', () async {
      final response = MockServerHttpResponse();
      final application = await run(
        basicHeader('ada', 'not-the-password'),
        response,
        loggedIn: 'ada',
      );
      expect(application.reached, isTrue);
      expect(application.seen!.name, 'ada');
      expect(response.statusCode, 200);
    });

    test('another user in the header replaces the one logged in', () async {
      final response = MockServerHttpResponse();
      final application = await run(
        basicHeader('root', 'root-pw'),
        response,
        loggedIn: 'ada',
      );
      expect(application.seen!.name, 'root');
      final refused = MockServerHttpResponse();
      final second = await run(
        basicHeader('root', 'wrong'),
        refused,
        loggedIn: 'ada',
      );
      expect(second.reached, isFalse);
      expect(refused.statusCode, 401);
    });
  });

  group('logout', () {
    test('the session ends by default', () async {
      final sessions = newSessions();
      final (request, response) = await exchange(sessions);
      final session = request.getSession()!;
      await const SecurityContextLogoutHandler().logout(
        request,
        response,
        null,
      );
      expect(session.isInvalidated, isTrue);
      expect(await sessions.repository.findById(session.id), isNull);
    });

    test('the session stays when told so', () async {
      final sessions = newSessions();
      final (request, response) = await exchange(sessions);
      final session = request.getSession()!;
      await const SecurityContextLogoutHandler(invalidateHttpSession: false)
          .logout(request, response, null);
      expect(session.isInvalidated, isFalse);
    });

    test('no session is created to end one', () async {
      final sessions = newSessions();
      final (request, response) = await exchange(sessions);
      await const SecurityContextLogoutHandler().logout(
        request,
        response,
        null,
      );
      expect(request.getSession(create: false), isNull);
      expect(response.cookies, isEmpty);
    });

    test('the context is emptied', () async {
      final (request, response) = await exchange(newSessions());
      await SecurityContextHolder.runWithContext(() async {
        SecurityContextHolder.getContext().authentication = _someone;
        await const SecurityContextLogoutHandler().logout(
          request,
          response,
          _someone,
        );
        expect(SecurityContextHolder.getContext().authentication, isNull);
      });
    });

    test('cookies are expired, hidden from scripts, on the path', () async {
      final sessions = newSessions();
      final (request, response) = await exchange(sessions);
      CookieClearingLogoutHandler([
        'a',
        'b',
      ], path: '/app').logout(request, response, null);
      expect([for (final c in response.cookies) c.name], ['a', 'b']);
      for (final cookie in response.cookies) {
        expect(cookie.value, isEmpty);
        expect(cookie.maxAge, Duration.zero);
        expect(cookie.httpOnly, isTrue);
        expect(cookie.path, '/app');
        expect(cookie.secure, isFalse);
      }
      final secure = MockServerHttpRequest(HttpMethod.post, 'https://h/logout');
      final secureResponse = MockServerHttpResponse();
      CookieClearingLogoutHandler(['a']).logout(secure, secureResponse, null);
      expect(secureResponse.cookies.single.secure, isTrue);
    });

    test('the CSRF token is removed', () async {
      final sessions = newSessions();
      const repository = CookieCsrfTokenRepository();
      final (request, response) = await exchange(
        sessions,
        cookies: {'XSRF-TOKEN': 'abc'},
      );
      await const CsrfLogoutHandler(repository).logout(request, response, null);
      expect(response.cookies.single.maxAge, Duration.zero);
    });

    test('the success handlers redirect or answer a status', () async {
      final (request, response) = await exchange(newSessions());
      await const SimpleUrlLogoutSuccessHandler(
        '/login?logout',
        contextPath: '/app',
      ).onLogoutSuccess(request, response, null);
      expect(response.statusCode, 302);
      expect(response.headers['location'], '/app/login?logout');

      final (second, secondResponse) = await exchange(newSessions());
      await const HttpStatusReturningLogoutSuccessHandler(HttpStatus.noContent)
          .onLogoutSuccess(second, secondResponse, null);
      expect(secondResponse.statusCode, 204);
      expect(secondResponse.isClosed, isTrue);
    });

    test('the filter logs out the configured method on the URL only', () async {
      final calls = <String>[];
      final filter = LogoutFilter(
        [_Noting('handler', calls)],
        logoutUrl: '/bye',
        methods: const {HttpMethod.post, HttpMethod.delete},
        successHandler: const HttpStatusReturningLogoutSuccessHandler(),
      );
      for (final (method, path, logsOut) in [
        (HttpMethod.post, '/bye', true),
        (HttpMethod.delete, '/bye', true),
        (HttpMethod.get, '/bye', false),
        (HttpMethod.post, '/logout', false),
      ]) {
        calls.clear();
        final (request, response) = await exchange(
          newSessions(),
          method: method,
          path: path,
        );
        final application = Application();
        await filter.doFilter(request, response, application);
        expect(calls.isNotEmpty, logsOut, reason: '$method $path');
        expect(application.reached, !logsOut, reason: '$method $path');
      }
    });
  });

  group('the default pages', () {
    Future<MockServerHttpResponse> page(
      WebFilter filter,
      String path, {
      CsrfToken? token,
    }) async {
      final (request, response) = await exchange(newSessions(), path: path);
      if (token != null) {
        request.attributes[CsrfTokenRequestAttributeHandler.attributeName] =
            () => token;
      }
      await filter.doFilter(request, response, Application());
      return response;
    }

    test('the login page posts where and with what names it is told', () async {
      final response = await page(
        DefaultLoginPageGeneratingFilter(
          loginPageUrl: '/enter',
          loginProcessingUrl: '/do-login',
          usernameParameter: 'who',
          passwordParameter: 'secret',
          contextPath: '/app',
        ),
        '/enter',
        token: const CsrfToken('X-CSRF-TOKEN', '_t', 'a"b<c'),
      );
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('text/html'));
      final html = response.bodyText;
      expect(html, contains('action="&#47;app&#47;do-login"'));
      expect(html, contains('name="who"'));
      expect(html, contains('name="secret"'));
      expect(html, contains('name="_t" type="hidden" value="a&quot;b&lt;c"'));
      expect(html, isNot(contains('Bad credentials')));
    });

    test('?error and ?logout show their message, only on the page', () async {
      final filter = DefaultLoginPageGeneratingFilter();
      expect(
        (await page(filter, '/login?error')).bodyText,
        contains('Bad credentials'),
      );
      expect(
        (await page(filter, '/login?logout')).bodyText,
        contains('signed out'),
      );
      final (request, response) = await exchange(
        newSessions(),
        method: HttpMethod.post,
        path: '/login',
      );
      final application = Application();
      await filter.doFilter(request, response, application);
      expect(application.reached, isTrue, reason: 'only GET is the page');
    });

    test('the logout page posts the logout with the token', () async {
      final response = await page(
        DefaultLogoutPageGeneratingFilter(logoutUrl: '/bye', contextPath: '/a'),
        '/bye',
        token: const CsrfToken('X-CSRF-TOKEN', '_csrf', 'tok'),
      );
      final html = response.bodyText;
      expect(html, contains('action="&#47;a&#47;bye"'));
      expect(html, contains('name="_csrf" type="hidden" value="tok"'));
      expect(html, contains('Log Out'));
    });
  });
}

final class _Noting implements SessionAuthenticationStrategy, LogoutHandler {
  _Noting(this.name, this.into);

  final String name;
  final List<String> into;

  @override
  void onAuthentication(
    Authentication authentication,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) => into.add(name);

  @override
  void logout(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Authentication? authentication,
  ) => into.add(name);
}
