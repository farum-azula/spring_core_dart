// Chapter 4, security: the login of the API, CSRF, the request rules,
// method security, the role hierarchy, authentication events, headers and
// the firewall.
@TestOn('vm')
library;

import 'package:neon_books_server/src/admin/log_service.dart';
import 'package:neon_books_server/src/orders/order_service.dart';
import 'package:neon_books_server/src/security/login_audit.dart';
import 'package:spring_boot_starter_security/testing.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_security_core/spring_security_core.dart'
    show AccessDeniedException;
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

import 'support/app.dart';

const dune = '9780441013593';

void main() {
  final app = neonBooks();
  final logs = captureLogs();

  group('the login of the API', () {
    test('anonymous users read the catalog, nothing else', () async {
      await app.mockMvc.get('/api/books').andExpect(status: 200);
      await app.mockMvc
          .get('/api/me')
          .andExpect(
            status: 401, // no redirect to a login page: an API
            contentType: MediaType.applicationProblemJson,
          );
      await app.mockMvc.get('/api/basket').andExpect(status: 401);
    });

    test('CSRF: the cookie comes with any response, POST needs it', () async {
      final client = ApiClient(app.mockMvc);
      final login = await client.send(
        HttpMethod.post,
        '/api/login',
        form: {'username': 'ada', 'password': 'ada-secret'},
      );
      expect(login.response.statusCode, 403); // no token yet
      expect(client.csrfToken, isNotNull); // ... but now the cookie
      final cookie = login.response.cookies.singleWhere(
        (c) => c.name == 'XSRF-TOKEN',
      );
      expect(cookie.httpOnly, isFalse); // the app's code reads it
    });

    test('POST /api/login: 204 and a session; /api/me; logout', () async {
      final ada = ApiClient(app.mockMvc);
      expect(await ada.login('ada', 'ada-secret'), 204);
      expect(ada.sessionId, isNotNull);
      expect(jsonOf(await ada.get('/api/me')), {
        'name': 'ada',
        'roles': ['USER'],
      });
      final logout = await ada.send(HttpMethod.post, '/api/logout');
      expect(logout.response.statusCode, 204);
      expect((await ada.get('/api/me')).response.statusCode, 401);
    });

    test('a wrong password: 401, an event, a warning', () async {
      final client = ApiClient(app.mockMvc);
      expect(await client.login('ada', 'wrong'), 401);
      expect(await client.login('nobody', 'wrong'), 401); // the same answer
      expect(app.getBean<LoginAudit>().failures['ada'], greaterThan(0));
      expect(
        logs.ofLogger('neon.security').map((r) => r.message),
        contains(startsWith('failed login for "nobody"')),
      );
    });
  });

  group('who may do what', () {
    MockRequestBuilder as(
      String name,
      List<String> roles,
      HttpMethod method,
      String path,
    ) => MockRequestBuilder(method, path)
      ..with_(user(name).roles(roles))
      ..with_(csrf());

    test('request rules: only admins add books or read the logs', () async {
      await app.mockMvc
          .perform(
            as('ada', ['USER'], HttpMethod.post, '/api/books')
              ..json({'isbn': '9780000000001'}),
          )
          .andExpect(status: 403);
      await app.mockMvc
          .perform(as('ada', ['USER'], HttpMethod.get, '/api/admin/logs'))
          .andExpect(status: 403);
      await app.mockMvc
          .perform(
            as('root', ['USER', 'ADMIN'], HttpMethod.get, '/api/admin/logs'),
          )
          .andExpect(status: 200);
    });

    test('method security: @PreAuthorize on the service decides', () async {
      // The request rules let any user send DELETE; the service does not.
      await app.mockMvc
          .perform(as('ada', ['USER'], HttpMethod.delete, '/api/books/$dune'))
          .andExpect(status: 403);
      await app.mockMvc
          .perform(
            as(
              'root',
              ['USER', 'ADMIN'],
              HttpMethod.delete,
              '/api/books/9780451524935',
            ),
          )
          .andExpect(status: 204);
    });

    test('CSRF is checked for logged-in users too', () async {
      await app.mockMvc
          .perform(
            MockRequestBuilder(HttpMethod.post, '/api/orders')
              ..with_(user('ada')),
          )
          .andExpect(status: 403);
    });

    test(
      '@PostFilter and @PostAuthorize: own orders, all for admins',
      () async {
        final orders = app.getBean<OrderService>();
        final adas = await withMockUser(
          () => orders.place('ada', {dune: 1}),
          username: 'ada',
        );
        final roots = await withMockUser(
          () => orders.place('root', {dune: 1}),
          username: 'root',
          roles: ['USER', 'ADMIN'],
        );
        final seenByAda = await withMockUser(orders.all, username: 'ada');
        expect(seenByAda.map((o) => o.customer).toSet(), {'ada'});
        final seenByRoot = await withMockUser(
          orders.all,
          username: 'root',
          roles: ['ADMIN'],
        );
        expect(seenByRoot.map((o) => o.id), containsAll([adas.id, roots.id]));
        // hasPermission(returnObject, 'read'): the PermissionEvaluator.
        await app.mockMvc
            .perform(
              as('ada', ['USER'], HttpMethod.get, '/api/orders/${roots.id}'),
            )
            .andExpect(status: 403);
        await app.mockMvc
            .perform(
              as('ada', ['USER'], HttpMethod.get, '/api/orders/${adas.id}'),
            )
            .andExpect(status: 200, json: containsPair('user', 'ada'));
      },
    );

    test('the role hierarchy: an admin may order (hasRole USER)', () async {
      final order = await withMockUser(
        () => app.getBean<OrderService>().place('boss', {dune: 1}),
        username: 'boss',
        roles: ['ADMIN'], // no USER role: ROLE_ADMIN > ROLE_USER
      );
      expect(order.customer, 'boss');
      expect(
        () => withMockUser(
          () => app.getBean<OrderService>().place('guest', {dune: 1}),
          username: 'guest',
          roles: ['GUEST'],
        ),
        throwsA(isA<AccessDeniedException>()),
      );
    });

    test('@Secured on the log service', () async {
      final logs = app.getBean<LogService>();
      expect(
        () => withMockUser(logs.recent, username: 'ada'),
        throwsA(isA<AccessDeniedException>()),
      );
      expect(
        await withMockUser(logs.recent, username: 'root', roles: ['ADMIN']),
        isNotEmpty,
      );
    });
  });

  group('the protection around it', () {
    test('security headers on every answer', () async {
      await app.mockMvc
          .get('/api/books')
          .andExpect(
            headers: {
              'X-Content-Type-Options': 'nosniff',
              'X-Frame-Options': 'DENY',
              'Content-Security-Policy':
                  "default-src 'none'; img-src 'self'; frame-ancestors 'none'",
            },
          );
    });

    test('the firewall refuses paths that read two ways', () async {
      // `//api/books` too, over a socket: test/server_integration_test.dart
      // (MockMvc would read `//api` as a host).
      for (final path in [
        '/api/books;jsessionid=x',
        '/api/books/%2Fcover', // an encoded slash
      ]) {
        await app.mockMvc.get(path).andExpect(status: 400);
      }
    });

    test('the supplier stub has its own chain (dev only)', () async {
      // Its chain: no session, no CSRF token, no login; its controller
      // checks the API key.
      await app.mockMvc
          .get('/supplier/offers/$dune', headers: {'X-Api-Key': 'dev-key'})
          .andExpect(status: 200, json: containsPair('isbn', dune));
      await app.mockMvc
          .get('/supplier/offers/$dune', headers: {'X-Api-Key': 'wrong'})
          .andExpect(status: 401);
    });
  });
}
