// The server against the whole of Supabase: the Supabase CLI's stack of
// ../supabase (or a hosted project with the same migration and
// functions), given by SUPABASE_URL, SUPABASE_ANON_KEY,
// SUPABASE_SERVICE_ROLE_KEY and SUPABASE_DB_URL; skipped without them
// (../README.md says how to start one).
//
// The server runs on a free port and is called over HTTP with the access
// tokens of two users the test makes: one signs up as the app does
// (SupabaseAuth), the other is created with the role ADMIN through the
// admin API (SupabaseAuthAdmin).
@TestOn('vm')
@Tags(['supabase-stack'])
library;

import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../bin/spring_gen/main.spring.dart';

/// The value of the variable [name], without the quotes
/// `supabase status -o env` puts around it; `null` when not set.
String? env(String name) {
  var value = io.Platform.environment[name]?.trim();
  if (value == null) {
    return null;
  }
  if (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'")))) {
    value = value.substring(1, value.length - 1);
  }
  return value.isEmpty ? null : value;
}

const _variables = [
  'SUPABASE_URL',
  'SUPABASE_ANON_KEY',
  'SUPABASE_SERVICE_ROLE_KEY',
  'SUPABASE_DB_URL',
];

final _random = Random.secure();

/// [prefix] with twelve random hexadecimal digits: a name no other run
/// uses.
String unique(String prefix) => [
  prefix,
  for (var i = 0; i < 12; i++) _random.nextInt(16).toRadixString(16),
].join();

/// A user of the project as the app is one: a login of its own
/// (`SupabaseAuth`) and Storage as that user.
final class Client {
  Client(SupabaseProperties properties) {
    final credentials = DefaultSupabaseCredentials(
      properties: properties,
      session: () => auth,
      authentication: () => null,
    );
    final http = SupabaseHttp(
      properties: properties,
      transport: platformHttpTransport(),
      credentials: credentials,
    );
    auth = SupabaseAuth(http: http);
    storage = StorageTemplate(http: http, mapper: ObjectMapper());
  }

  late final SupabaseAuth auth;
  late final StorageTemplate storage;

  final String email = '${unique('example-')}@example.com';
  final String password = unique('Pw-');

  /// The user's id in the project.
  String get id => auth.user!.id;

  /// The access token the app would send to the server.
  Future<String> token() async => (await auth.accessToken())!;

  /// Runs [body] with a security context of its own: a login puts its
  /// user into the current one, and two users share this process.
  Future<T> run<T>(Future<T> Function() body) =>
      SecurityContextHolder.runWithContext(body);
}

/// What the server answered.
typedef Answer = ({int status, Object? body});

void main() {
  final url = env('SUPABASE_URL');
  final skip = url == null
      ? 'SUPABASE_URL is not set: this test needs the whole of Supabase '
            '(example/supabase/README.md)'
      : null;

  group('the server against a project', skip: skip, () {
    final local = const {
      '127.0.0.1',
      'localhost',
      '::1',
    }.contains(Uri.tryParse(url ?? '')?.host);
    final server = springBootTest(
      springApplication,
      systemEnvironment: {
        for (final name in _variables) name: env(name) ?? '',
        'SUPABASE_DB_SSLMODE':
            env('SUPABASE_DB_SSLMODE') ?? (local ? 'disable' : 'require'),
      },
      webEnvironment: WebEnvironment.randomPort,
    );

    final http = io.HttpClient();
    final listId = unique('list-');
    late SupabaseAuthAdmin admin;
    late Client ada;
    late Client root;
    late String adaToken;
    late String rootToken;

    Future<Answer> call(
      String method,
      String path, {
      String? token,
      Object? json,
    }) async {
      final request = await http.openUrl(
        method,
        Uri.parse('http://127.0.0.1:${server.localServerPort}$path'),
      );
      request.headers.set('accept', 'application/json');
      if (token != null) {
        request.headers.set('authorization', 'Bearer $token');
      }
      if (json != null) {
        request.headers.contentType = io.ContentType.json;
        request.write(jsonEncode(json));
      }
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      return (
        status: response.statusCode,
        body: text.isEmpty ? null : jsonDecode(text),
      );
    }

    Future<List<Map<String, Object?>>> todos(String token) async {
      final answer = await call('GET', '/api/todos?list=$listId', token: token);
      expect(answer.status, 200);
      return (answer.body! as List).cast();
    }

    setUpAll(() async {
      for (final name in _variables) {
        if (env(name) == null) {
          fail('SUPABASE_URL is set but $name is not');
        }
      }
      final properties = server.getBean<SupabaseProperties>();
      admin = server.getBean<SupabaseAuthAdmin>();

      // Ada signs up, as in the app. (A project that confirms addresses
      // signs nobody in here: the stack of ../supabase does not.)
      ada = Client(properties);
      await ada.run(
        () => ada.auth.signUp(email: ada.email, password: ada.password),
      );
      expect(
        ada.auth.isLoggedIn,
        isTrue,
        reason: 'the project confirms addresses: nobody is signed in',
      );
      adaToken = await ada.token();

      // Root is made by the admin API, the only way to a role: a user
      // cannot write app_metadata.
      root = Client(properties);
      await admin.createUser(
        email: root.email,
        password: root.password,
        emailConfirm: true,
        appMetadata: {
          'roles': ['ADMIN'],
        },
      );
      await root.run(
        () => root.auth.signInWithPassword(
          email: root.email,
          password: root.password,
        ),
      );
      rootToken = await root.token();
    });

    tearDownAll(() async {
      http.close(force: true);
      for (final client in [ada, root]) {
        final id = client.auth.user?.id;
        if (id == null) {
          continue;
        }
        // The rows of a user do not go with the user: as the service
        // role, past the policies.
        await server.getBean<SupabaseCredentials>().asServiceRole(
          () => server
              .getBean<JdbcClient>()
              .sql('delete from todos where owner::text = ?')
              .param(id)
              .update(),
        );
        await client.run(
          () => client.storage.delete('avatars', '$id/avatar.png'),
        );
        await admin.deleteUser(id);
        await client.auth.destroy();
      }
    });

    test('the tokens of the project are signed with a key the starter '
        'accepts by default', () {
      final header = jsonDecode(
        utf8.decode(
          base64Url.decode(
            base64Url.normalize(adaToken.split('.').first),
          ),
        ),
      ) as Map<String, Object?>;
      expect(
        header['alg'],
        anyOf('ES256', 'RS256'),
        reason:
            'a project that signs with HS256 needs '
            'spring.supabase.auth.jwt-secret',
      );
    });

    test('no token, a wrong token, the anon key: 401', () async {
      expect((await call('GET', '/api/me')).status, 401);
      expect((await call('GET', '/api/me', token: 'nothing')).status, 401);
      expect(
        (await call('GET', '/api/me', token: env('SUPABASE_ANON_KEY'))).status,
        401,
      );
      final forged = adaToken.replaceRange(adaToken.length - 6, null, 'AAAAAA');
      expect((await call('GET', '/api/me', token: forged)).status, 401);
    });

    test('/api/me: the user of the token, the roles of '
        'app_metadata', () async {
      final her = await call('GET', '/api/me', token: adaToken);
      expect(her.status, 200);
      expect(her.body, {
        'id': ada.id,
        'email': ada.email,
        'roles': isEmpty,
      });

      final his = await call('GET', '/api/me', token: rootToken);
      expect(his.body, {
        'id': root.id,
        'email': root.email,
        'roles': ['ADMIN'],
      });
    });

    test("a todo is its owner's: the database sets the owner and shows "
        'the row to nobody else', () async {
      final added = await call(
        'POST',
        '/api/todos',
        token: adaToken,
        json: {'title': 'Buy milk', 'listId': listId},
      );
      expect(added.status, 201);
      final todo = added.body! as Map<String, Object?>;
      expect(todo, containsPair('title', 'Buy milk'));
      expect(todo['id'], isA<int>());

      expect(await todos(adaToken), [containsPair('id', todo['id'])]);
      // The same list, asked by another user.
      expect(await todos(rootToken), isEmpty);
      final his = await call(
        'PUT',
        '/api/todos/${todo['id']}/done',
        token: rootToken,
      );
      expect(his.status, 404);

      final owner = await server.getBean<SupabaseCredentials>().asServiceRole(
        () => server
            .getBean<JdbcClient>()
            .sql('select owner::text from todos where id = ?')
            .param(todo['id'])
            .query<String>()
            .single(),
      );
      expect(owner, ada.id);
    });

    test('done and back: an update as the caller, the version '
        'counted', () async {
      final first = (await todos(adaToken)).first;
      final done = await call(
        'PUT',
        '/api/todos/${first['id']}/done',
        token: adaToken,
      );
      expect(done.status, 200);
      expect(done.body, containsPair('done', true));
      expect(
        (done.body! as Map)['version'],
        greaterThan(first['version']! as int),
      );

      final open = await call(
        'PUT',
        '/api/todos/${first['id']}/done?value=false',
        token: adaToken,
      );
      expect(open.body, containsPair('done', false));
    });

    test('@Transactional: both todos of a pair, or neither', () async {
      final before = (await todos(adaToken)).length;

      final refused = await call(
        'POST',
        '/api/todos/pair',
        token: adaToken,
        json: {'listId': listId, 'first': 'Lost', 'second': ''},
      );
      expect(refused.status, 400);
      // The first row was written, and taken back with the transaction.
      expect(await todos(adaToken), hasLength(before));

      final added = await call(
        'POST',
        '/api/todos/pair',
        token: adaToken,
        json: {'listId': listId, 'first': 'Flour', 'second': 'Yeast'},
      );
      expect(added.status, 201);
      expect(
        [for (final todo in await todos(adaToken)) todo['title']],
        containsAll(['Flour', 'Yeast']),
      );
      expect(await todos(adaToken), hasLength(before + 2));
    });

    test("@Procedure('close_all'): the database function closes the "
        "caller's open todos", () async {
      final open = (await todos(adaToken)).where((t) => t['done'] == false);
      expect(open, isNotEmpty);

      // Another user closes nothing of hers.
      final his = await call(
        'POST',
        '/api/todos/close?list=$listId',
        token: rootToken,
      );
      expect(his.body, {'closed': 0});

      final hers = await call(
        'POST',
        '/api/todos/close?list=$listId',
        token: adaToken,
      );
      expect(hers.status, 200);
      expect(hers.body, {'closed': open.length});
      expect(await todos(adaToken), everyElement(containsPair('done', true)));
    });

    test("@PreAuthorize(\"hasRole('ADMIN')\"): 403 for a user, the todos "
        'of everyone for an admin', () async {
      final refused = await call('GET', '/api/admin/report', token: adaToken);
      expect(refused.status, 403);

      final report = await call('GET', '/api/admin/report', token: rootToken);
      expect(report.status, 200);
      // Root has no todo: what is counted are the rows of the others.
      expect(
        (report.body! as Map)['todos'],
        greaterThanOrEqualTo((await todos(adaToken)).length),
      );
    });

    test('an Edge Function is called as the caller: the function and Auth '
        'see the same user', () async {
      final stats = await call('GET', '/api/stats?from=test', token: adaToken);
      expect(stats.status, 200);
      expect(
        stats.body,
        allOf(
          containsPair('from', 'test'),
          containsPair('user', ada.id),
          containsPair('role', 'authenticated'),
          containsPair('verified', ada.id),
        ),
      );

      final failed = await call(
        'GET',
        '/api/stats?from=fail',
        token: adaToken,
      );
      expect(failed.status, 502);
    });

    test("a signed URL of the caller's avatar opens without a "
        'token', () async {
      final none = await call('GET', '/api/avatar', token: adaToken);
      expect(none.status, 404);

      // The app uploads it, as the user (the policies of the bucket let
      // her write under her own id only).
      final bytes = Uint8List.fromList([for (var i = 0; i < 64; i++) i]);
      await ada.run(
        () => ada.storage.upload(
          'avatars',
          '${ada.id}/avatar.png',
          bytes,
          contentType: 'image/png',
          upsert: true,
        ),
      );

      final link = await call('GET', '/api/avatar', token: adaToken);
      expect(link.status, 200);
      final signed = Uri.parse((link.body! as Map)['url']! as String);
      expect(signed.path, contains('/object/sign/avatars/${ada.id}/'));

      final request = await http.getUrl(signed);
      final response = await request.close();
      expect(response.statusCode, 200);
      final received = await response.fold(
        <int>[],
        (all, chunk) => all..addAll(chunk),
      );
      expect(received, bytes);

      // Root has none, and no way to hers.
      expect((await call('GET', '/api/avatar', token: rootToken)).status, 404);
    });
  });
}
