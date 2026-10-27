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
          headers: {'X-CSRF-TOKEN': second.substring(second.indexOf('=') + 1)},
          form: {'text': 'again'},
        );
        expect(header.response.bodyText, 'submitted again');
        // A token of another session is worthless.
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
      '@CrossOrigin of a handler answers its pre-flights',
      () => app((mvc) async {
        final result = await mvc.perform(
          request(
            HttpMethod.options,
            '/api/cors',
            headers: preflight('https://app.example'),
          ),
        );
        expect(result.status, 200);
        expect(
          result.header('access-control-allow-origin'),
          'https://app.example',
        );
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

    test(
      'the session cookie: HttpOnly, SameSite=Lax, Secure over HTTPS',
      () => app((mvc) async {
        final http = await mvc.get('/form');
        final cookie = http.response.cookies.singleWhere(
          (c) => c.name == 'JSESSIONID',
        );
        expect(cookie.httpOnly, isTrue);
        expect(cookie.sameSite, 'Lax');
        expect(cookie.secure, isFalse);
        final https = await mvc.get('https://localhost/form');
        expect(
          https.response.cookies
              .singleWhere((c) => c.name == 'JSESSIONID')
              .secure,
          isTrue,
        );
      }),
    );
  });

  group('Basic credentials', () {
    Future<int> status(MockMvc mvc, String header) async =>
        (await mvc.get('/api/me', headers: {'authorization': header})).status;

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
