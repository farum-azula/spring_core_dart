// The function built for Supabase and run by the Edge Runtime of a real
// stack, called through its gateway as the project's users call it.
@TestOn('vm')
@Tags(['supabase-stack'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:spring_boot_starter_edge/build.dart';
import 'package:test/test.dart';

String? _env(String name) {
  var value = Platform.environment[name]?.trim();
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

final _random = Random.secure();

String _unique(String prefix) => [
  prefix,
  for (var i = 0; i < 12; i++) _random.nextInt(16).toRadixString(16),
].join();

final class _Answer {
  _Answer(this.status, this.headers, this.text);

  final int status;
  final HttpHeaders headers;
  final String text;

  Object? get json => jsonDecode(text);
}

// The directory of this package, wherever the tests are run from.
final _package = Directory.fromUri(
  Isolate.resolvePackageUriSync(
    Uri.parse('package:supabase_example_function/src/app.dart'),
  )!.resolve('../..'),
);

void main() {
  final url = _env('SUPABASE_URL');
  final anonKey = _env('SUPABASE_ANON_KEY');
  final functions =
      _env('SUPABASE_FUNCTIONS') ??
      '${_package.path}../../../spring_boot_starter_supabase/test/stack/'
          'supabase/functions';
  final skip = url == null || anonKey == null
      ? 'no Supabase stack (SUPABASE_URL, SUPABASE_ANON_KEY)'
      : null;
  final client = HttpClient();

  Future<_Answer> send(
    String method,
    String address, {
    String? token,
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    final request = await client.openUrl(method, Uri.parse(address));
    headers.forEach(request.headers.set);
    if (token != null) {
      request.headers.set('authorization', 'Bearer $token');
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close();
    return _Answer(
      response.statusCode,
      response.headers,
      await utf8.decoder.bind(response).join(),
    );
  }

  Future<_Answer> api(
    String method,
    String path, {
    String? token,
    Object? body,
  }) => send(
    method,
    '$url/functions/v1/api$path',
    token: token,
    body: body,
    headers: {'apikey': anonKey!},
  );

  // A new user of the project: its id and an access token.
  Future<(String, String)> signUp() async {
    final answer = await send(
      'POST',
      '$url/auth/v1/signup',
      headers: {'apikey': anonKey!},
      body: {
        'email': '${_unique('edge-')}@example.com',
        'password': 'pw-123456',
      },
    );
    final json = answer.json! as Map<String, Object?>;
    return (
      (json['user']! as Map)['id']! as String,
      json['access_token']! as String,
    );
  }

  setUpAll(() async {
    if (skip != null) {
      return;
    }
    await EdgeBuild(
      platform: EdgePlatform.supabase,
      application: _package,
      output: Directory('$functions/api').absolute.path,
    ).run();
    // The first call loads the function.
    for (var i = 0; i < 60; i++) {
      if ((await api('GET', '/health')).status == 200) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    fail('The function does not answer');
  });

  tearDownAll(() => client.close(force: true));

  group('the Edge Function written in Dart', skip: skip, () {
    test('open to everyone, with the anon key or without', () async {
      final plain = await api('GET', '/health');
      expect(plain.json, {'status': 'UP', 'runtime': 'supabase'});
      expect((await api('GET', '/health', token: anonKey)).status, 200);
    });

    test('everything else needs a token of the project', () async {
      expect((await api('GET', '/todos?list=a')).status, 401);
      expect((await api('GET', '/todos?list=a', token: anonKey)).status, 401);
      expect(
        (await api(
          'GET',
          '/me',
          token: _env('SUPABASE_SERVICE_ROLE_KEY') ?? 'x',
        )).status,
        401,
      );
      expect((await api('GET', '/me', token: 'a.b.c')).status, 401);
    });

    test("a user's token is the user", () async {
      final (id, token) = await signUp();
      final me = await api('GET', '/me', token: token);
      expect(me.json, {'id': id, 'roles': <Object?>[]});
      // A role the user does not have.
      expect((await api('GET', '/admin', token: token)).status, 403);
    });

    test('a changed token is not the user', () async {
      final (_, token) = await signUp();
      final parts = token.split('.');
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, Object?>;
      claims['app_metadata'] = {
        'roles': ['ADMIN'],
      };
      final forged = [
        parts[0],
        base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', ''),
        parts[2],
      ].join('.');
      expect((await api('GET', '/admin', token: forged)).status, 401);
    });

    test('the todos are read and written as the caller', () async {
      final (_, ada) = await signUp();
      final (_, bob) = await signUp();
      final list = _unique('list-');
      final added = await api(
        'POST',
        '/todos',
        token: ada,
        body: {'title': 'written in Dart', 'listId': list},
      );
      expect(added.status, 201);
      expect((added.json! as Map)['title'], 'written in Dart');
      final hers = await api('GET', '/todos?list=$list', token: ada);
      expect(hers.json, hasLength(1));
      // The policy of the project, not the function, hides it from Bob.
      final his = await api('GET', '/todos?list=$list', token: bob);
      expect(his.json, isEmpty);
      // The database function, as the caller.
      expect(
        (await api('POST', '/todos/close-all?list=$list', token: bob)).json,
        {'closed': 0},
      );
      expect(
        (await api('POST', '/todos/close-all?list=$list', token: ada)).json,
        {'closed': 1},
      );
    });

    test(
      'what the server of the example calls: who the function sees',
      () async {
        final (id, token) = await signUp();
        final stats = await api('GET', '/stats?from=test', token: token);
        expect(stats.json, {
          'from': 'test',
          'method': 'GET',
          'user': id,
          'role': 'authenticated',
          'verified': id,
          'apikey': true,
        });
        expect(
          (await api('GET', '/stats?from=fail', token: token)).status,
          422,
        );
        expect((await api('GET', '/stats?from=test')).status, 401);
      },
    );

    test('what the app of the example calls, also from a browser', () async {
      final (id, token) = await signUp();
      // The pre-flight of a page on another origin, without a token.
      final preflight = await send(
        'OPTIONS',
        '$url/functions/v1/api/send-invite',
        headers: {
          'origin': 'http://localhost:3000',
          'access-control-request-method': 'POST',
          'access-control-request-headers':
              'authorization, apikey, content-type',
        },
      );
      expect(preflight.status, lessThan(300));
      expect(preflight.headers.value('access-control-allow-origin'), '*');
      final invited = await send(
        'POST',
        '$url/functions/v1/api/send-invite',
        token: token,
        headers: {'apikey': anonKey!, 'origin': 'http://localhost:3000'},
        body: {'email': 'friend@example.com'},
      );
      expect(invited.json, {'id': '$id|friend@example.com'});
      expect(invited.headers.value('access-control-allow-origin'), '*');
      expect(
        (await api(
          'POST',
          '/send-invite',
          body: {'email': 'x@example.com'},
        )).status,
        401,
      );
    });

    test('a body that is not valid: 400', () async {
      final (_, token) = await signUp();
      final answer = await api(
        'POST',
        '/todos',
        token: token,
        body: {'title': ' ', 'listId': 'x'},
      );
      expect(answer.status, 400);
    });

    test('ten todos a minute for each user, counted in the project', () async {
      final (_, ada) = await signUp();
      final (_, bob) = await signUp();
      final list = _unique('limit-');
      final statuses = <int>[];
      for (var i = 0; i < 11; i++) {
        statuses.add(
          (await api(
            'POST',
            '/todos',
            token: ada,
            body: {'title': 'todo $i', 'listId': list},
          )).status,
        );
      }
      expect(statuses, [...List.filled(10, 201), 429]);
      final refused = await api(
        'POST',
        '/todos',
        token: ada,
        body: {'title': 'one more', 'listId': list},
      );
      expect(refused.status, 429);
      expect(int.parse(refused.headers.value('retry-after')!), greaterThan(0));
      // Bob has his own count.
      expect(
        (await api(
          'POST',
          '/todos',
          token: bob,
          body: {'title': 'his', 'listId': list},
        )).status,
        201,
      );
    });
  });
}
