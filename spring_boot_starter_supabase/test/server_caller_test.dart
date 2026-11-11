@Tags(['supabase'])
library;

import 'dart:convert';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:test/test.dart';

import 'server_app/basic/basic.dart';
import 'server_support.dart';

// Whom the server calls the project as: `/api/todos` reads the Todos
// repository (the store over the project's REST API). A user's token of
// the project is passed on, so the database applies their row-level
// security; any other login of the application reaches the project as
// nobody (the anon key), and its credential never leaves the server.
void main() {
  final keys = testKeys;
  // Another identity provider the application trusts by itself.
  final other = TokenFactory(keys.rsa, EcTestKey.generate(kid: 'other-1'), []);

  late KeyServer project;
  TestServer? server;

  setUp(() async => project = await KeyServer.project(keys));

  tearDown(() async {
    await server?.close();
    server = null;
    await project.close();
  });

  Future<TestServer> start({
    List<BeanModule> configurations = const [],
    JwtDecoder Function()? decoder,
  }) async {
    final app = server = await TestServer.start(
      projectUrl: project.url,
      configurations: configurations,
      decoder: decoder,
    );
    app.transport
        .when(HttpMethod.get, '/rest/v1/todos')
        .respond(
          200,
          json: [
            {
              'id': 1,
              'title': 'Buy milk',
              'list_id': 'l1',
              'done': false,
              'priority': 'low',
              'created_at': '2026-11-10T08:00:00Z',
              'version': 1,
            },
          ],
        );
    return app;
  }

  String userToken({Map<String, Object?> changes = const {}}) =>
      sign(keys, userClaims(project.issuer, changes: changes));

  // Every header of every call to the project, as text.
  String sent(TestServer app) => [
    for (final request in app.transport.requests)
      [
        request.method,
        request.url,
        request.headers,
        utf8.decode(request.body ?? const [], allowMalformed: true),
      ].join(' '),
  ].join('\n');

  void expectOnlyTheProject(TestServer app) {
    expect(
      [for (final request in app.transport.requests) request.url.origin],
      everyElement(project.url),
    );
    expect(project.requests, everyElement('/auth/v1/.well-known/jwks.json'));
  }

  test("a user's token is passed on as Authorization, with the anon key "
      'as apikey', () async {
    final app = await start();
    final token = userToken();
    final answer = await app.get('/api/todos', bearer: token);
    expect(answer.status, 200, reason: answer.text);
    expect(answer.json, ['Buy milk']);
    final call = app.transport.requests.single;
    expect(call.url.origin, project.url);
    expect(call.url.path, '/rest/v1/todos');
    expect(call.headers['Authorization'], 'Bearer $token');
    expect(call.headers['apikey'], anonKey);
    expect(sent(app), isNot(contains(serviceRoleKey)));
    expectOnlyTheProject(app);
  });

  test("an admin's token is passed on as it is: a role of the application "
      'is no service role', () async {
    final app = await start();
    final token = userToken(
      changes: {
        'app_metadata': {
          'roles': ['ADMIN'],
        },
      },
    );
    expect((await app.get('/api/todos', bearer: token)).status, 200);
    final call = app.transport.requests.single;
    expect(call.headers['Authorization'], 'Bearer $token');
    expect(call.headers['apikey'], anonKey);
    expect(sent(app), isNot(contains(serviceRoleKey)));
  });

  test('each of two users at once reaches the project with their own '
      'token', () async {
    final app = await start();
    // The project answers each caller with a row named after their sub.
    app.transport.reset();
    app.transport.when(HttpMethod.get, '/rest/v1/todos').respondWith((call) {
      final token = call.headers['Authorization']!.substring(7);
      final claims = jsonDecode(
        utf8.decode(
          base64Url.decode(base64Url.normalize(token.split('.')[1])),
        ),
      ) as Map<String, Object?>;
      return HttpResponse(
        200,
        headers: HttpHeaders()..set('content-type', 'application/json'),
        body: utf8.encode(
          jsonEncode([
            {
              'id': 1,
              'title': claims['sub'],
              'list_id': 'l1',
              'done': false,
              'priority': 'low',
              'created_at': '2026-11-10T08:00:00Z',
              'version': 1,
            },
          ]),
        ),
      );
    });
    const bob = 'b0b00000-0000-4000-8000-000000000b0b';
    final tokens = {
      userId: userToken(),
      bob: userToken(changes: {'sub': bob}),
    };
    final answers = await Future.wait([
      for (var i = 0; i < 10; i++)
        for (final MapEntry(key: user, value: token) in tokens.entries)
          app.get('/api/todos', bearer: token).then((answer) => (user, answer)),
    ]);
    for (final (user, answer) in answers) {
      expect(answer.status, 200, reason: answer.text);
      expect(answer.json, [user]);
    }
    expect(app.transport.requests, hasLength(20));
  });

  test('a refused token reaches neither the endpoint nor the '
      'project', () async {
    final app = await start();
    for (final token in [
      userToken(changes: {'role': 'service_role'}),
      userToken(changes: {'iss': 'https://other.supabase.co/auth/v1'}),
      sign(other, userClaims(project.issuer), header: {'kid': keys.ec.kid}),
    ]) {
      expectRefused(await app.get('/api/todos', bearer: token));
    }
    expect((await app.get('/api/todos')).status, 401);
    expect(app.transport.requests, isEmpty);
    expectOnlyTheProject(app);
  });

  group('with HTTP Basic beside the tokens of the project', () {
    const password = 'ada-pw-51c9';
    final basic = 'Basic ${base64.encode(utf8.encode('ada:$password'))}';

    test('a Basic login reaches the project with the anon key, never with '
        'the password', () async {
      final app = await start(configurations: [basicLoginBeans]);
      final me = await app.get('/api/me', headers: {'authorization': basic});
      expect(me.status, 200, reason: me.text);
      expect((me.json! as Map<String, Object?>)['name'], 'ada');
      final answer = await app.get(
        '/api/todos',
        headers: {'authorization': basic},
      );
      expect(answer.status, 200, reason: answer.text);
      final call = app.transport.requests.single;
      expect(call.headers['Authorization'], 'Bearer $anonKey');
      expect(call.headers['apikey'], anonKey);
      final all = sent(app);
      expect(all, isNot(contains('Basic')));
      expect(all, isNot(contains(password)));
      expect(all, isNot(contains(basic.substring(6))));
      expect(all, isNot(contains(serviceRoleKey)));
      expectOnlyTheProject(app);
    });

    test("a user's token of the project is still passed on", () async {
      final app = await start(configurations: [basicLoginBeans]);
      final token = userToken();
      expect((await app.get('/api/todos', bearer: token)).status, 200);
      expect(
        app.transport.requests.single.headers['Authorization'],
        'Bearer $token',
      );
    });

    test('a wrong password reaches nothing', () async {
      final app = await start(configurations: [basicLoginBeans]);
      final wrong = 'Basic ${base64.encode(utf8.encode('ada:wrong'))}';
      final answer = await app.get(
        '/api/todos',
        headers: {'authorization': wrong},
      );
      expect(answer.status, 401);
      expect(app.transport.requests, isEmpty);
    });
  });

  group("with the application's own decoder for another issuer", () {
    const issuer = 'https://login.example.com/realms/shop';

    JwtDecoder decoder() => NimbusJwtDecoder.withJwkSource(
      StaticJwkSource([other.ec.verificationKey]),
      jwsAlgorithms: {JwsAlgorithm.es256},
    );

    // Everything else as in a token of the project.
    String otherToken({Map<String, Object?> changes = const {}}) => sign(
      other,
      userClaims(issuer, changes: {'sub': 'shop-user-7', ...changes}),
    );

    test('a token of that issuer reaches the project with the anon key, '
        'never with the token', () async {
      final app = await start(decoder: decoder);
      final token = otherToken();
      final me = await app.me(token);
      expect(me.status, 200, reason: me.text);
      expect((me.json! as Map<String, Object?>)['name'], 'shop-user-7');
      final answer = await app.get('/api/todos', bearer: token);
      expect(answer.status, 200, reason: answer.text);
      final call = app.transport.requests.single;
      expect(call.headers['Authorization'], 'Bearer $anonKey');
      expect(call.headers['apikey'], anonKey);
      final all = sent(app);
      for (final part in token.split('.')) {
        expect(all, isNot(contains(part)));
      }
      expect(all, isNot(contains(serviceRoleKey)));
      expectOnlyTheProject(app);
      // The project's keys were never needed.
      expect(project.requests, isEmpty);
    });

    test('a token of that issuer with the path of the project in its iss, '
        'or with a trailing slash, is not passed on', () async {
      final app = await start(decoder: decoder);
      for (final iss in [
        '${project.issuer}/',
        '${project.url}/auth/v1/../v1',
        project.issuer.toUpperCase(),
        'https://login.example.com/auth/v1',
      ]) {
        final token = otherToken(changes: {'iss': iss});
        expect((await app.get('/api/todos', bearer: token)).status, 200);
        expect(
          app.transport.requests.last.headers['Authorization'],
          'Bearer $anonKey',
          reason: iss,
        );
      }
    });

    test("a token of the project's issuer with another role is not passed "
        'on', () async {
      final app = await start(decoder: decoder);
      for (final role in ['service_role', 'anon', null]) {
        final token = otherToken(
          changes: {'iss': project.issuer, 'role': role},
        );
        expect((await app.get('/api/todos', bearer: token)).status, 200);
        expect(
          app.transport.requests.last.headers['Authorization'],
          'Bearer $anonKey',
          reason: '$role',
        );
      }
    });

    // The starter passes on what the application's decoder accepted when
    // its claims are those of a user of the project: whose signatures are
    // trusted is the decoder's decision. The project then checks the
    // token itself.
    test("a token the application's decoder accepted that names the "
        'project as its issuer is passed on', () async {
      final app = await start(decoder: decoder);
      final token = otherToken(changes: {'iss': project.issuer});
      expect((await app.get('/api/todos', bearer: token)).status, 200);
      final call = app.transport.requests.single;
      expect(call.headers['Authorization'], 'Bearer $token');
      expect(call.headers['apikey'], anonKey);
      expect(call.url.origin, project.url);
    });
  });
}
