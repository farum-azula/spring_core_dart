// The API without a project: who is let in, and what the server asks of
// the project's database, Edge Functions and Storage for the caller. The
// project is a MockHttpTransport and a FakeDatabase; what a real project
// answers is in test/stack_test.dart.
@TestOn('vm')
library;

import 'dart:convert';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support/app.dart';

void main() {
  final http = MockHttpTransport();
  final database = FakeDatabase();
  final app = exampleServer(http, database);

  setUp(() {
    http.reset();
    database.reset();
  });

  MockRequestBuilder get(String path) =>
      MockRequestBuilder(HttpMethod.get, path);

  group('who is let in', () {
    test('no token: 401, and nothing is asked of the project', () async {
      for (final path in ['/api/me', '/api/todos?list=home', '/api/stats']) {
        await app.mockMvc.get(path).andExpect(status: 401);
      }
      expect(http.requests, isEmpty);
    });

    test('outside /api/ nothing is served', () async {
      await app.mockMvc
          .perform(get('/actuator/health')..with_(projectUser()))
          .andExpect(status: 403);
    });

    test('/api/me: the id of the user, the roles of app_metadata', () async {
      await app.mockMvc
          .perform(
            get('/api/me')..with_(projectUser(userToken(roles: ['ADMIN']))),
          )
          .andExpect(
            status: 200,
            json: {
              'id': userId,
              'roles': ['ADMIN'],
              'email': 'ada@example.com',
            },
          );
    });

    test("@PreAuthorize(\"hasRole('ADMIN')\"): 403 for a user "
        'without the role', () async {
      await app.mockMvc
          .perform(get('/api/admin/report')..with_(projectUser()))
          .andExpect(status: 403);
      await app.mockMvc
          .perform(
            get('/api/admin/report')
              ..with_(projectUser(userToken(roles: ['EDITOR']))),
          )
          .andExpect(status: 403);
    });

    test('a body that is not valid: 400 before any statement', () async {
      await app.mockMvc
          .perform(
            MockRequestBuilder(HttpMethod.post, '/api/todos')
              ..with_(projectUser())
              ..json({'title': ' ', 'listId': 'home'}),
          )
          .andExpect(status: 400);
    });
  });

  group('an Edge Function, as the caller', () {
    test("the function gets the caller's token and the anon key", () async {
      final token = userToken();
      http
          .when(HttpMethod.get, '$projectUrl/functions/v1/api/stats')
          .respond(
            200,
            json: {'from': 'server', 'user': userId, 'role': 'authenticated'},
          );

      await app.mockMvc
          .perform(get('/api/stats')..with_(projectUser(token)))
          .andExpect(
            status: 200,
            json: {'from': 'server', 'user': userId, 'role': 'authenticated'},
          );

      final request = http.requests.single;
      expect(request.url.queryParameters, {'from': 'server'});
      expect(request.headers['apikey'], anonKey);
      expect(request.headers['Authorization'], 'Bearer $token');
    });

    test('a token of another issuer never leaves the server: the function '
        'is called as nobody', () async {
      http
          .when(HttpMethod.get, '$projectUrl/functions/v1/api/stats')
          .respond(200, json: {'from': 'x', 'user': null, 'role': 'anon'});

      await app.mockMvc
          .perform(
            get('/api/stats?from=x')..with_(
              projectUser(userToken(issuer: 'https://login.example.com')),
            ),
          )
          .andExpect(status: 200);

      expect(http.requests.single.headers['Authorization'], 'Bearer $anonKey');
    });

    test('a function that fails is a 502', () async {
      http
          .when(HttpMethod.get, '$projectUrl/functions/v1/api/stats')
          .respond(422, json: {'error': 'no stats from fail'});

      await app.mockMvc
          .perform(get('/api/stats?from=fail')..with_(projectUser()))
          .andExpect(
            status: 502,
            contentType: 'application/problem+json',
            body: isNot(contains('no stats from fail')),
          );
    });
  });

  group('Storage, as the caller', () {
    const path = '/storage/v1/object/sign/avatars/$userId/avatar.png';

    test("a signed URL of the caller's own avatar, for five "
        'minutes', () async {
      http
          .when(HttpMethod.post, '$projectUrl$path')
          .respond(
            200,
            json: {
              'signedURL': '/object/sign/avatars/$userId/avatar.png?token=t1',
            },
          );

      await app.mockMvc
          .perform(get('/api/avatar')..with_(projectUser()))
          .andExpect(status: 200, json: {'url': '$projectUrl$path?token=t1'});

      final request = http.requests.single;
      expect(jsonDecode(utf8.decode(request.body!)), {'expiresIn': 300});
      expect(request.headers['Authorization'], startsWith('Bearer ey'));
    });

    test('no avatar yet: 404', () async {
      http
          .when(HttpMethod.post, '$projectUrl$path')
          .respond(
            400,
            json: {
              'statusCode': '404',
              'error': 'not_found',
              'message': 'Object not found',
            },
          );

      await app.mockMvc
          .perform(get('/api/avatar')..with_(projectUser()))
          .andExpect(status: 404, contentType: 'application/problem+json');
    });
  });

  group('the todos, over SQL as the caller', () {
    MockRequestBuilder post(String path, [Object? body]) {
      final request = MockRequestBuilder(HttpMethod.post, path)
        ..with_(projectUser());
      if (body != null) {
        request.json(body);
      }
      return request;
    }

    test('the repositories use SQL, every statement as the caller', () {
      expect(app.getBean<SupabaseStartup>().dataPath, startsWith('SQL'));
      expect(app.getBean<SupabaseProperties>().db.rls, SupabaseRls.user);
    });

    test('a read: the role and the claims of the token on the connection, '
        'taken off again afterwards', () async {
      await app.mockMvc
          .perform(get('/api/todos?list=home')..with_(projectUser()))
          .andExpect(status: 200, json: isEmpty);

      expect(database.statements, [
        'set role authenticated',
        contains("set_config('request.jwt.claims'"),
        allOf(contains('from "todos"'), contains('"list_id" = ?')),
        'reset role',
        contains("set_config('request.jwt.claims'"),
      ]);
      // What auth.uid() and auth.jwt() of the project read.
      final [claims, subject, role] = database.parameters[1];
      expect(jsonDecode(claims! as String), containsPair('sub', userId));
      expect(subject, userId);
      expect(role, 'authenticated');
      expect(database.parameters[2], ['home']);
      expect(database.parameters.last, ['', '', '']);
    });

    test('@Transactional: two writes and one commit, as the caller for '
        'that transaction only', () async {
      await app.mockMvc
          .perform(
            post('/api/todos/pair', {
              'listId': 'home',
              'first': 'Buy milk',
              'second': 'Bake bread',
            }),
          )
          .andExpect(
            status: 201,
            json: [
              containsPair('title', 'Buy milk'),
              containsPair('title', 'Bake bread'),
            ],
          );

      expect(database.statements, [
        'begin',
        'set local role authenticated',
        contains("set_config('request.jwt.claims'"),
        startsWith('insert into "todos"'),
        startsWith('insert into "todos"'),
        'commit',
      ]);
      // The owner is not sent: the database sets it (default auth.uid()).
      expect(database.containing('owner'), isEmpty);
    });

    test('@Transactional: the second write refused, the first is taken '
        'back', () async {
      await app.mockMvc
          .perform(
            post('/api/todos/pair', {
              'listId': 'home',
              'first': 'Buy milk',
              'second': ' ',
            }),
          )
          .andExpect(status: 400, contentType: 'application/problem+json');

      expect(database.containing('insert into "todos"'), hasLength(1));
      expect(database.statements.last, 'rollback');
      expect(database.statements, isNot(contains('commit')));
    });

    test("@Procedure('close_all'): the database function, with the "
        'parameter by its name', () async {
      database.answer = (sql, _) => sql.contains('close_all')
          ? JdbcResult(
              const ['close_all'],
              const [
                [3],
              ],
            )
          : null;

      await app.mockMvc
          .perform(post('/api/todos/close?list=home'))
          .andExpect(status: 200, json: {'closed': 3});

      expect(
        database.containing('close_all').single,
        'select * from "close_all"("list_id" => ?)',
      );
    });

    test('a todo the caller cannot see is not there: 404', () async {
      await app.mockMvc
          .perform(
            MockRequestBuilder(HttpMethod.put, '/api/todos/5/done')
              ..with_(projectUser()),
          )
          .andExpect(status: 404);
      expect(database.containing('update'), isEmpty);
    });

    test('an admin counts the todos of everyone: inside asServiceRole the '
        'statement runs as the user of the address', () async {
      database.answer = (sql, _) => sql.contains('count(*)')
          ? JdbcResult(
              const ['count'],
              const [
                [7],
              ],
            )
          : null;

      await app.mockMvc
          .perform(
            get('/api/admin/report')
              ..with_(projectUser(userToken(roles: ['ADMIN']))),
          )
          .andExpect(status: 200, json: {'todos': 7});

      expect(database.statements.first, 'select count(*) from "todos"');
      expect(database.statements, isNot(contains('set role authenticated')));
    });
  });
}
