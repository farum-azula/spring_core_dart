// The rules of test/app/rules: who reaches what, what an anonymous client,
// a logged-in user and an admin get, and how failures are answered.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_security/testing.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app/rules/rules.dart';
import 'support.dart';

void main() {
  Future<void> app(Future<void> Function(MockMvc mvc) body) =>
      withApp(rulesSecurityBeans, (mvc, _) => body(mvc));

  test(
    'public paths need no login',
    () => app((mvc) async {
      await mvc.get('/public/hello').andExpect(status: 200, body: 'hello');
    }),
  );

  test(
    'an anonymous API call gets a Basic challenge as ProblemDetail',
    () => app((mvc) async {
      final result = await mvc
          .get('/api/me')
          .andExpect(
            status: 401,
            headers: {
              'www-authenticate': 'Basic realm="Realm", charset="UTF-8"',
            },
            contentType: 'application/problem+json',
          );
      expect(result.response.json, containsPair('status', 401));
    }),
  );

  test(
    'a browser is sent to the login page',
    () => app((mvc) async {
      final result = await mvc.get('/api/me', headers: {'accept': 'text/html'});
      expect(result.status, 302);
      expect(result.header('location'), '/login');
    }),
  );

  test(
    'Basic credentials log in for the request',
    () => app((mvc) async {
      await mvc
          .get('/api/me', headers: basic('ada', 'ada-pw'))
          .andExpect(
            status: 200,
            json: {
              'name': 'ada',
              'authorities': ['ROLE_USER'],
            },
          );
    }),
  );

  test(
    'wrong credentials: 401, same answer for an unknown user',
    () => app((mvc) async {
      final wrong = await mvc.get('/api/me', headers: basic('ada', 'nope'));
      final unknown = await mvc.get('/api/me', headers: basic('nobody', 'x'));
      expect(wrong.status, 401);
      expect(unknown.status, 401);
      expect(wrong.response.bodyText, unknown.response.bodyText);
      expect(
        wrong.header('www-authenticate'),
        unknown.header('www-authenticate'),
      );
    }),
  );

  test(
    'roles: 403 for a user, 200 for an admin',
    () => app((mvc) async {
      await mvc
          .get('/api/admin', headers: basic('ada', 'ada-pw'))
          .andExpect(status: 403, contentType: 'application/problem+json');
      await mvc
          .get('/api/admin', headers: basic('root', 'root-pw'))
          .andExpect(status: 200, body: 'admin');
    }),
  );

  test(
    'path variables in a rule',
    () => app((mvc) async {
      await mvc
          .get('/api/users/ada', headers: basic('ada', 'ada-pw'))
          .andExpect(status: 200);
      await mvc
          .get('/api/users/root', headers: basic('ada', 'ada-pw'))
          .andExpect(status: 403);
      await mvc
          .get('/api/users/ada', headers: basic('root', 'root-pw'))
          .andExpect(status: 200);
    }),
  );

  test(
    'method security on a service: 403, through the same answers',
    () => app((mvc) async {
      await mvc
          .get('/api/reports/q1', headers: basic('ada', 'ada-pw'))
          .andExpect(status: 403);
      await mvc
          .get('/api/reports/q1', headers: basic('root', 'root-pw'))
          .andExpect(status: 200, body: 'report q1');
    }),
  );

  test(
    'the user in controllers: Principal, @AuthenticationPrincipal, '
    'the context',
    () => app((mvc) async {
      final ada = basic('ada', 'ada-pw');
      await mvc.get('/api/principal', headers: ada).andExpect(body: 'ada');
      await mvc.get('/api/user', headers: ada).andExpect(body: 'ada');
      await mvc.get('/api/context', headers: ada).andExpect(body: 'ada');
    }),
  );

  test(
    'MockMvc post-processors: user(), jwt()',
    () => app((mvc) async {
      await mvc
          .perform(
            request(
              HttpMethod.get,
              '/api/admin',
              processors: [
                user('root').roles(['ADMIN']),
              ],
            ),
          )
          .andExpect(status: 200);
      await mvc
          .perform(
            request(
              HttpMethod.get,
              '/api/me',
              processors: [
                jwt().subject('svc').authorities(['SCOPE_read']),
              ],
            ),
          )
          .andExpect(
            json: {
              'name': 'svc',
              'authorities': ['SCOPE_read'],
            },
          );
    }),
  );
}
