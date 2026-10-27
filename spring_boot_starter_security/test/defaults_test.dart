// No security configuration of the application: Spring Boot's defaults.
// Every request needs a login; browsers get the login page, programs a
// Basic challenge; the default user; the whole form login flow with CSRF,
// the saved request, session fixation protection and logout.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app/defaults/defaults.dart';
import 'support.dart';

void main() {
  Future<void> app(Future<void> Function(MockMvc mvc) body) => withApp(
    defaultSecurityBeans,
    (mvc, _) => body(mvc),
    properties: ['spring.security.user.password=secret'],
  );

  test(
    'everything needs a login, even public paths',
    () => app((mvc) async {
      await mvc.get('/public/hello').andExpect(status: 401);
      await mvc.get('/').andExpect(status: 401);
    }),
  );

  test(
    'programs get Basic, browsers the login page',
    () => app((mvc) async {
      for (final accept in ['*/*', 'application/json', '']) {
        final result = await mvc.get('/api/me', headers: {'accept': accept});
        expect(result.status, 401, reason: accept);
        expect(
          result.header('www-authenticate'),
          'Basic realm="Realm", charset="UTF-8"',
        );
      }
      final xhr = await mvc.get(
        '/api/me',
        headers: {'accept': 'text/html', 'x-requested-with': 'XMLHttpRequest'},
      );
      expect(xhr.status, 401);
      final browser = await mvc.get(
        '/api/me',
        headers: {'accept': 'text/html,application/xhtml+xml,*/*;q=0.8'},
      );
      expect(browser.status, 302);
      expect(browser.header('location'), '/login');
    }),
  );

  test(
    'the default user: name user, the configured password',
    () => app((mvc) async {
      await mvc
          .get('/api/me', headers: basic('user', 'secret'))
          .andExpect(
            status: 200,
            json: {'name': 'user', 'authorities': <String>[]},
          );
      await mvc
          .get('/api/me', headers: basic('user', 'other'))
          .andExpect(status: 401);
    }),
  );

  test(
    'the login page carries a CSRF token and no cache',
    () => app((mvc) async {
      final browser = Browser(mvc);
      final page = await browser.get('/login');
      expect(page.status, 200);
      expect(page.response.bodyText, contains('Please sign in'));
      expect(Browser.csrfField(page.response.bodyText), isNotEmpty);
      expect(page.header('cache-control'), contains('no-store'));
      expect(page.header('x-frame-options'), 'DENY');
    }),
  );

  test(
    'the whole form login flow',
    () => app((mvc) async {
      final browser = Browser(mvc);
      // 1. A protected page: saved, sent to the login page.
      final protected = await browser.get('/api/me');
      expect(protected.status, 302);
      expect(protected.header('location'), '/login');
      final before = browser.cookies['JSESSIONID'];
      expect(before, isNotNull);
      // 2. The login page and its token.
      final page = await browser.get('/login');
      final token = Browser.csrfField(page.response.bodyText);
      // 3. Without the token the login is refused.
      final noToken = await browser.send(
        HttpMethod.post,
        '/login',
        form: {'username': 'user', 'password': 'secret'},
      );
      expect(noToken.status, 403);
      // 4. A wrong password: back to the page with ?error.
      final wrong = await browser.send(
        HttpMethod.post,
        '/login',
        form: {'username': 'user', 'password': 'nope', '_csrf': token},
      );
      expect(wrong.status, 302);
      expect(wrong.header('location'), '/login?error');
      // 5. The right one: a new session id, back to the saved page.
      final login = await browser.send(
        HttpMethod.post,
        '/login',
        form: {'username': 'user', 'password': 'secret', '_csrf': token},
      );
      expect(login.status, 302);
      expect(login.header('location'), '/api/me?continue');
      final after = browser.cookies['JSESSIONID'];
      expect(after, isNot(before), reason: 'session fixation protection');
      await browser
          .get('/api/me?continue', accept: 'application/json')
          .then((r) => expect(r.status, 200));
      // 6. The old id does not carry the login.
      final stale = await mvc.get(
        '/api/me',
        headers: {'cookie': 'JSESSIONID=$before', 'accept': 'application/json'},
      );
      expect(stale.status, 401);
      // 7. Logout: GET shows a confirmation page, POST logs out.
      final confirm = await browser.get('/logout');
      expect(confirm.status, 200);
      final logoutToken = Browser.csrfField(confirm.response.bodyText);
      final logout = await browser.send(
        HttpMethod.post,
        '/logout',
        form: {'_csrf': logoutToken},
      );
      expect(logout.status, 302);
      expect(logout.header('location'), '/login?logout');
      final afterLogout = await mvc.get(
        '/api/me',
        headers: {'cookie': 'JSESSIONID=$after', 'accept': 'application/json'},
      );
      expect(afterLogout.status, 401);
    }),
  );

  test(
    'a generated password when none is configured',
    () => withApp(defaultSecurityBeans, (mvc, context) async {
      final users = context.getBean<UserDetailsService>();
      final user = await users.loadUserByUsername('user');
      expect(user.password, matches(RegExp(r'^\{noop\}[0-9a-f-]{36}$')));
    }),
  );
}
