// The web attack catalog of roadmap/security_verification.md against the
// rules application: ambiguous paths (the firewall), the security headers,
// CSRF, CORS, cookies and sessions, malformed Basic credentials.
import 'dart:convert';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_security/testing.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app/rules/rules.dart';
import 'support.dart';

void main() {
  Future<void> app(Future<void> Function(MockMvc mvc) body) =>
      withApp(rulesSecurityBeans, (mvc, _) => body(mvc));

  final ada = basic('ada', 'ada-pw');
  final root = basic('root', 'root-pw');

  group('firewall: ambiguous paths are refused with 400 before any rule', () {
    for (final path in [
      '/api/admin;jsessionid=x',
      '/api;/admin',
      '/api/admin%3B',
      '/api%2Fadmin',
      '/api/admin%2f',
      '/api/%5Cadmin',
      '/api/admin%25',
      '/api/admin%252F',
      '/api//admin',
      '/api/admin%00',
      '/api/admin%0a',
      '/api/admin%0D',
      '/api/admin%E2%80%A8',
    ]) {
      test(
        path,
        () => app((mvc) async {
          final result = await mvc.get(path, headers: root);
          expect(result.status, 400, reason: path);
          expect(result.response.bodyText, isEmpty, reason: 'no detail');
        }),
      );
    }

    test(
      'TRACE and unknown methods are refused',
      () => app((mvc) async {
        await mvc
            .perform(MockRequestBuilder(HttpMethod.trace, '/public/hello'))
            .andExpect(status: 400);
      }),
    );

    test(
      'normalized forms are matched like the router sees them',
      () => app((mvc) async {
        // MockMvc, like dart:io, resolves `..` before the application: the
        // rules and the router both see /api/admin.
        await mvc
            .get('/public/../api/admin', headers: ada)
            .andExpect(status: 403);
        await mvc.get('/public/../api/admin').andExpect(status: 401);
      }),
    );

    test(
      "case and trailing slashes: the router's rules, not a way around",
      () => app((mvc) async {
        // /api/ADMIN is not /api/admin for the router either: no handler,
        // and still behind anyRequest().authenticated().
        await mvc.get('/api/ADMIN').andExpect(status: 401);
        await mvc.get('/api/admin/').andExpect(status: 401);
        await mvc.get('/api/admin/', headers: ada).andExpect(status: 403);
      }),
    );
  });

  group('headers', () {
    test(
      "Spring Security's defaults on every answer, also errors",
      () => app((mvc) async {
        for (final result in [
          await mvc.get('/public/hello'),
          await mvc.get('/api/me'),
          await mvc.get('/api/admin', headers: ada),
        ]) {
          final h = result.response.headers;
          expect(h['x-content-type-options'], 'nosniff');
          expect(h['x-frame-options'], 'DENY');
          expect(h['x-xss-protection'], '0');
          expect(
            h['cache-control'],
            'no-cache, no-store, max-age=0, must-revalidate',
          );
          expect(h['pragma'], 'no-cache');
          expect(h['expires'], '0');
          expect(
            h['strict-transport-security'],
            isNull,
            reason: 'not over HTTP',
          );
        }
      }),
    );

    test(
      'HSTS over HTTPS only',
      () => app((mvc) async {
        final result = await mvc.get('https://localhost/public/hello');
        expect(
          result.header('strict-transport-security'),
          'max-age=31536000 ; includeSubDomains',
        );
      }),
    );

    test(
      "a controller's own Cache-Control wins",
      () => app((mvc) async {
        final result = await mvc.get('/api/cached', headers: ada);
        expect(result.header('cache-control'), 'max-age=60');
      }),
    );
  });

  group('CSRF', () {
    test(
      'a state-changing request without a token: 403, even logged in',
      () => app((mvc) async {
        await mvc
            .post('/api/data', body: 'x', headers: ada)
            .andExpect(status: 403);
        await mvc
            .perform(
              request(
                HttpMethod.post,
                '/api/data',
                body: 'x',
                headers: ada,
                processors: [csrf()],
              ),
            )
            .andExpect(status: 200, body: 'got x');
        await mvc
            .perform(
              request(
                HttpMethod.post,
                '/api/data',
                body: 'x',
                headers: ada,
                processors: [csrf().useInvalidToken()],
              ),
            )
            .andExpect(status: 403);
      }),
    );

    test(
      'safe methods need no token',
      () => app((mvc) async {
        for (final method in [
          HttpMethod.get,
          HttpMethod.head,
          HttpMethod.options,
        ]) {
          final result = await mvc.perform(request(method, '/public/hello'));
          expect(result.status, isNot(403), reason: method.value);
        }
      }),
    );

    test(
      'the real token: from the page, masked differently each time, '
      'in a form field or a header',
      () => app((mvc) async {
        final browser = Browser(mvc);
        final first = (await browser.get('/form')).response.bodyText;
        // The token lives in the XSRF-TOKEN cookie (no session before a
        // login): the page carries a masked copy, the browser sends the
        // cookie back.
        expect(browser.cookies['XSRF-TOKEN'], isNotNull);
        expect(browser.cookies['JSESSIONID'], isNull);
        final second = (await browser.get('/form')).response.bodyText;
        expect(first, isNot(second), reason: 'masked (BREACH)');
        final token = first.substring(first.indexOf('=') + 1);
        final form = await browser.send(
          HttpMethod.post,
          '/form',
          form: {'text': 'hi', '_csrf': token},
        );
        expect(form.status, 200);
        expect(form.response.bodyText, 'submitted hi');
        final header = await browser.send(
          HttpMethod.post,
          '/form',
          headers: {'X-XSRF-TOKEN': second.substring(second.indexOf('=') + 1)},
          form: {'text': 'again'},
        );
        expect(header.response.bodyText, 'submitted again');
        // A request without the cookie: the token alone is worthless.
        final cookie = browser.cookies.remove('XSRF-TOKEN');
        final noCookie = await browser.send(
          HttpMethod.post,
          '/form',
          form: {'text': 'x', '_csrf': token},
        );
        expect(noCookie.status, 403);
        browser.cookies['XSRF-TOKEN'] = cookie!;
        // A token of another browser (another cookie) is worthless.
        final other = Browser(mvc);
        await other.get('/form');
        final foreign = await other.send(
          HttpMethod.post,
          '/form',
          form: {'text': 'x', '_csrf': token},
        );
        expect(foreign.status, 403);
        // A made-up one too.
        final forged = await browser.send(
          HttpMethod.post,
          '/form',
          form: {'text': 'x', '_csrf': base64Url.encode(List.filled(64, 1))},
        );
        expect(forged.status, 403);
      }),
    );

    test(
      'the controller still reads the form after the CSRF check',
      () => app((mvc) async {
        final browser = Browser(mvc);
        final page = (await browser.get('/form')).response.bodyText;
        final token = page.substring(page.indexOf('=') + 1);
        final result = await browser.send(
          HttpMethod.post,
          '/form',
          form: {'_csrf': token, 'text': 'a&b=c'},
        );
        expect(result.response.bodyText, 'submitted a&b=c');
      }),
    );
  });

  group('CORS', () {
    Map<String, String> preflight(String origin, [String method = 'GET']) => {
      'origin': origin,
      'access-control-request-method': method,
    };

    test(
      'a pre-flight from an allowed origin passes without credentials',
      () => app((mvc) async {
        final result = await mvc.perform(
          request(
            HttpMethod.options,
            '/api/me',
            headers: preflight('https://trusted.example'),
          ),
        );
        expect(result.status, 200);
        expect(
          result.header('access-control-allow-origin'),
          'https://trusted.example',
        );
        expect(result.header('access-control-allow-credentials'), 'true');
      }),
    );

    test(
      'a pre-flight from another origin gets no CORS headers',
      () => app((mvc) async {
        final result = await mvc.perform(
          request(
            HttpMethod.options,
            '/api/me',
            headers: preflight('https://evil.example'),
          ),
        );
        expect(result.status, 403);
        expect(result.header('access-control-allow-origin'), isNull);
      }),
    );

    test(
      "under the CorsConfigurationSource bean's paths its rules alone "
      'apply: the @CrossOrigin of a handler does not widen them, as in '
      'Spring (the ninth review)',
      () => app((mvc) async {
        final result = await mvc.perform(
          request(
            HttpMethod.options,
            '/api/cors',
            headers: preflight('https://app.example'),
          ),
        );
        expect(result.status, 403);
        expect(result.header('access-control-allow-origin'), isNull);
        final actual = await mvc.get(
          '/api/cors',
          headers: {'origin': 'https://app.example', ...ada},
        );
        expect(actual.status, 403);
        expect(actual.header('access-control-allow-origin'), isNull);
      }),
    );

    test(
      'an actual cross-origin request still needs a login',
      () => app((mvc) async {
        final anonymous = await mvc.get(
          '/api/me',
          headers: {'origin': 'https://trusted.example'},
        );
        expect(anonymous.status, 401);
        final logged = await mvc.get(
          '/api/me',
          headers: {'origin': 'https://trusted.example', ...ada},
        );
        expect(logged.status, 200);
        expect(
          logged.header('access-control-allow-origin'),
          'https://trusted.example',
        );
      }),
    );
  });

  group('sessions and cookies', () {
    test(
      'Basic is stateless: no session',
      () => app((mvc) async {
        final result = await mvc.get('/api/me', headers: ada);
        expect(result.response.cookies, isEmpty);
      }),
    );

    // The login page and a protected page set no session: the CSRF token
    // and the page to come back to are signed or random cookies. The
    // session starts at a login.
    test(
      'the cookies: HttpOnly, SameSite=Lax, Secure over HTTPS; the session '
      'only after a login',
      () => app((mvc) async {
        void expectFlags(MvcResult result, String name, {required bool https}) {
          final cookie = result.response.cookies.singleWhere(
            (c) => c.name == name,
          );
          expect(cookie.httpOnly, isTrue, reason: name);
          expect(cookie.sameSite, 'Lax', reason: name);
          expect(cookie.secure, https, reason: name);
          expect(cookie.path, '/', reason: name);
        }

        for (final (origin, https) in [
          ('http://localhost', false),
          ('https://localhost', true),
        ]) {
          final browser = Browser(mvc);
          final protected = await browser.get('$origin/api/me');
          expect(protected.status, 302);
          expectFlags(protected, 'REDIRECT_URI', https: https);
          final page = await browser.get('$origin/login');
          expectFlags(page, 'XSRF-TOKEN', https: https);
          expect(
            [
              ...protected.response.cookies,
              ...page.response.cookies,
            ].where((c) => c.name == 'JSESSIONID'),
            isEmpty,
            reason: 'no session before a login',
          );
          final login = await browser.send(
            HttpMethod.post,
            '$origin/login',
            form: {
              'username': 'ada',
              'password': 'ada-pw',
              '_csrf': Browser.csrfField(page.response.bodyText),
            },
          );
          expect(login.status, 302);
          expectFlags(login, 'JSESSIONID', https: https);
          // The saved page is used up.
          expect(
            login.response.cookies
                .singleWhere((c) => c.name == 'REDIRECT_URI')
                .maxAge,
            Duration.zero,
          );
        }
      }),
    );

    // Only a login starts a session, and the number of sessions is
    // limited: anonymous requests cannot fill the store.
    Future<Browser> loggedIn(MockMvc mvc, String user) async {
      final browser = Browser(mvc);
      final page = await browser.get('/login');
      final login = await browser.send(
        HttpMethod.post,
        '/login',
        form: {
          'username': user,
          'password': '$user-pw',
          '_csrf': Browser.csrfField(page.response.bodyText),
        },
      );
      expect(login.status, 302);
      return browser;
    }

    Future<void> stillLoggedIn(List<Browser> users) async {
      for (final user in users) {
        final me = await user.get('/api/me', accept: 'application/json');
        expect(me.status, 200, reason: 'a logged-in session was dropped');
      }
    }

    int stored(ApplicationContext context) =>
        (context.getBean<HttpSessionRepository>()
                as InMemoryHttpSessionRepository)
            .size;

    test(
      'anonymous requests ten times over the session limit start no '
      'session and leave every login in place',
      () => withApp(
        rulesSecurityBeans,
        properties: ['server.servlet.session.max-sessions=20'],
        (mvc, context) async {
          final users = [
            for (var i = 0; i < 6; i++)
              await loggedIn(mvc, i.isEven ? 'ada' : 'root'),
          ];
          await stillLoggedIn(users);
          expect(stored(context), 6);
          for (var i = 0; i < 70; i++) {
            // A client without cookies: the login page, a protected page.
            for (final (path, expected) in [
              ('/login', 200),
              ('/api/me', 302),
            ]) {
              final result = await mvc.get(
                path,
                headers: {'accept': 'text/html'},
              );
              expect(result.status, expected, reason: path);
              expect(
                result.response.cookies.where((c) => c.name == 'JSESSIONID'),
                isEmpty,
                reason: path,
              );
            }
            // A client that keeps its cookies and comes back with them.
            final returning = Browser(mvc);
            await returning.get('/api/me');
            await returning.get('/login');
            await returning.get('/login');
          }
          expect(stored(context), 6, reason: 'no anonymous session');
          await stillLoggedIn(users);
        },
      ),
    );

    test(
      'only logins left at the limit: a new login is refused with 503, '
      'the logins stay and the pages still work',
      () => withApp(
        rulesSecurityBeans,
        properties: ['server.servlet.session.max-sessions=2'],
        (mvc, context) async {
          final users = [
            await loggedIn(mvc, 'ada'),
            await loggedIn(mvc, 'root'),
          ];
          // Anonymous requests need no session: the pages work.
          for (var i = 0; i < 50; i++) {
            final page = await mvc.get(
              '/login',
              headers: {'accept': 'text/html'},
            );
            expect(page.status, 200);
            expect(page.response.cookies.map((c) => c.name), ['XSRF-TOKEN']);
          }
          final protected = await mvc.get(
            '/api/me',
            headers: {'accept': 'text/html'},
          );
          expect(protected.status, 302);
          expect(protected.header('location'), '/login');
          // A third login finds no room, whoever it is (even the same
          // account): refused, nobody is pushed out.
          for (final user in ['ada', 'root']) {
            final browser = Browser(mvc);
            final page = await browser.get('/login');
            final refused = await browser.send(
              HttpMethod.post,
              '/login',
              form: {
                'username': user,
                'password': '$user-pw',
                '_csrf': Browser.csrfField(page.response.bodyText),
              },
            );
            expect(refused.status, 503, reason: user);
            expect(
              refused.response.cookies.where((c) => c.name == 'JSESSIONID'),
              isEmpty,
            );
            final me = await browser.get('/api/me', accept: 'application/json');
            expect(me.status, 401, reason: 'not logged in');
          }
          expect(stored(context), 2);
          await stillLoggedIn(users);
        },
      ),
    );

    test(
      'at the limit, expired sessions make room for a new login; no live '
      'one is pushed out',
      () => withApp(
        rulesSecurityBeans,
        properties: [
          'server.servlet.session.max-sessions=2',
          'server.servlet.session.timeout=2s',
        ],
        (mvc, context) async {
          final first = await loggedIn(mvc, 'ada');
          final second = await loggedIn(mvc, 'root');
          expect(stored(context), 2);
          // Full, nothing expired yet: refused, both stay.
          final browser = Browser(mvc);
          final page = await browser.get('/login');
          final refused = await browser.send(
            HttpMethod.post,
            '/login',
            form: {
              'username': 'ada',
              'password': 'ada-pw',
              '_csrf': Browser.csrfField(page.response.bodyText),
            },
          );
          expect(refused.status, 503);
          await stillLoggedIn([first, second]);
          // Nobody comes back for the whole timeout: both expire.
          await Future<void>.delayed(const Duration(milliseconds: 2200));
          final third = await loggedIn(mvc, 'ada');
          await stillLoggedIn([third]);
          // ada's expired session went at her login (the per-user count
          // asks the store); root's at the next purge or at the limit.
          expect(stored(context), lessThanOrEqualTo(2));
        },
      ),
    );

    test(
      'one account logging in again and again keeps at most 10 sessions: '
      'its least recently used one ends, other users are untouched',
      () => withApp(
        rulesSecurityBeans,
        properties: ['server.servlet.session.max-sessions=30'],
        (mvc, context) async {
          final root = await loggedIn(mvc, 'root');
          final ada = [for (var i = 0; i < 11; i++) await loggedIn(mvc, 'ada')];
          expect(stored(context), 11, reason: "root's and 10 of ada");
          final oldest = await ada.first.get(
            '/api/me',
            accept: 'application/json',
          );
          expect(oldest.status, isNot(200), reason: 'the oldest one ended');
          await stillLoggedIn([root, ...ada.skip(1)]);
        },
      ),
    );

    test(
      'spring.security.session.maximum-sessions sets the limit per user',
      () => withApp(
        rulesSecurityBeans,
        properties: ['spring.security.session.maximum-sessions=2'],
        (mvc, context) async {
          final first = await loggedIn(mvc, 'ada');
          final second = await loggedIn(mvc, 'ada');
          final third = await loggedIn(mvc, 'ada');
          final oldest = await first.get(
            '/api/me',
            accept: 'application/json',
          );
          expect(oldest.status, isNot(200));
          await stillLoggedIn([second, third]);
          expect(stored(context), 2);
        },
      ),
    );

    test(
      'spring.security.session.max-sessions-prevents-login refuses the '
      'login above the limit, the session in use stays',
      () => withApp(
        rulesSecurityBeans,
        properties: [
          'spring.security.session.maximum-sessions=1',
          'spring.security.session.max-sessions-prevents-login=true',
        ],
        (mvc, context) async {
          final first = await loggedIn(mvc, 'ada');
          final browser = Browser(mvc);
          final page = await browser.get('/login');
          final refused = await browser.send(
            HttpMethod.post,
            '/login',
            form: {
              'username': 'ada',
              'password': 'ada-pw',
              '_csrf': Browser.csrfField(page.response.bodyText),
            },
          );
          expect(refused.status, 302);
          expect(
            refused.response.headers['location'],
            endsWith('/login?error'),
          );
          final me = await browser.get('/api/me', accept: 'application/json');
          expect(me.status, isNot(200));
          await stillLoggedIn([first]);
          expect(stored(context), 1);
        },
      ),
    );

    test('a wrong spring.security.session.* value stops the start', () async {
      for (final property in [
        'spring.security.session.maximum-sessions=0',
        'spring.security.session.maximum-sessions=-5',
        'spring.security.session.maximum-sessions=many',
        'spring.security.session.max-sessions-prevents-login=maybe',
      ]) {
        final failure = await securityRunner(rulesSecurityBeans, [
          property,
        ]).runAsync((started) async => started.startupFailure);
        expect(failure, isNotNull, reason: property);
      }
    });
  });

  group('Basic credentials', () {
    Future<int> status(MockMvc mvc, String header) async =>
        (await mvc.get('/api/me', headers: {'authorization': header})).status;

    test(
      'a flood of password checks above the bound is refused at once with '
      '503 and Retry-After, never as a failed login; then logins work again',
      () => withApp(
        rulesSecurityBeans,
        properties: [
          'spring.security.password-checks.max-concurrent=1',
          'spring.security.password-checks.max-queued=1',
        ],
        (mvc, context) async {
          final wrong = 'Basic ${base64.encode(utf8.encode('ada:wrong'))}';
          final results = await Future.wait([
            for (var i = 0; i < 8; i++)
              mvc.get('/api/me', headers: {'authorization': wrong}),
          ]);
          final statuses = [for (final r in results) r.status];
          expect(statuses.where((s) => s == 503), isNotEmpty);
          expect(statuses.toSet(), {401, 503});
          final busy = results.firstWhere((r) => r.status == 503);
          expect(busy.response.headers['retry-after'], '1');
          expect(busy.response.headers['www-authenticate'], isNull);
          final right = 'Basic ${base64.encode(utf8.encode('ada:ada-pw'))}';
          expect(await status(mvc, right), 200);
        },
      ),
    );

    test(
      'a wrong spring.security.password-checks.* value stops the start',
      () async {
        for (final property in [
          'spring.security.password-checks.max-concurrent=0',
          'spring.security.password-checks.max-queued=-1',
          'spring.security.password-checks.max-concurrent=many',
        ]) {
          final failure = await securityRunner(rulesSecurityBeans, [
            property,
          ]).runAsync((started) async => started.startupFailure);
          expect(failure, isNotNull, reason: property);
        }
      },
    );

    test(
      'malformed headers are bad credentials, never a login',
      () => app((mvc) async {
        for (final header in [
          'Basic',
          'Basic !!!',
          'Basic ${base64.encode(utf8.encode('no-colon'))}',
          'Basic ${base64.encode(utf8.encode(':'))}',
          'Basicxyz',
        ]) {
          expect(await status(mvc, header), 401, reason: header);
        }
      }),
    );

    test(
      'another scheme is ignored (anonymous)',
      () => app((mvc) async {
        expect(await status(mvc, 'Digest username="ada"'), 401);
        expect(
          (await mvc.get(
            '/public/hello',
            headers: {'authorization': 'Digest x'},
          )).status,
          200,
        );
      }),
    );

    test(
      'a password with a colon, unicode',
      () => withApp(null, (mvc, _) async {
        await mvc
            .get('/api/me', headers: basic('user', 'a:b:ü✓'))
            .andExpect(status: 200);
      }, properties: ['spring.security.user.password=a:b:ü✓']),
    );

    test(
      'two Authorization headers are refused',
      () => app((mvc) async {
        final builder = MockRequestBuilder(HttpMethod.get, '/api/me');
        final result = await mvc.perform(
          builder..with_(
            FunctionRequestPostProcessor((request) {
              request.headers
                ..add('authorization', ada['authorization']!)
                ..add('authorization', root['authorization']!);
              return request;
            }),
          ),
        );
        expect(result.status, 401);
      }),
    );
  });
}
