@Tags(['supabase'])
library;

import 'dart:convert';

import 'package:test/test.dart';

import 'server_support.dart';

const _secret = 'tW9fQ2xvL0p1c3RBTGVnYWN5SldUU2VjcmV0OTk4MTIz';

// A server of a project that signs with its legacy secret
// (spring.supabase.auth.jwt-secret): a user's HS256 token signed with it
// passes, and nothing else does. The anon and the service role key of
// such a project are signed with the same secret.
void main() {
  final project = TokenFactory(testKeys.rsa, testKeys.ec, utf8.encode(_secret));

  late KeyServer host;
  late TestServer server;

  setUpAll(() async {
    host = await KeyServer.project(testKeys);
    server = await TestServer.start(
      projectUrl: host.url,
      properties: ['spring.supabase.auth.jwt-secret=$_secret'],
    );
  });

  tearDownAll(() async {
    await server.close();
    await host.close();
  });

  Map<String, Object?> claims({
    Map<String, Object?> changes = const {},
    List<String> without = const [],
  }) => userClaims(host.issuer, changes: changes, without: without);

  String hs256(Map<String, Object?> claims) =>
      sign(project, claims, alg: 'HS256');

  Future<void> refused(
    String token, {
    String? because,
    String? reason,
  }) async =>
      expectRefused(await server.me(token), because: because, reason: reason);

  test("a user's HS256 token signed with the secret passes, with the "
      "token's sub as the principal", () async {
    final answer = await server.me(hs256(claims()));
    expect(answer.status, 200, reason: answer.text);
    expect(answer.json, {'name': userId, 'authorities': <Object?>[]});
  });

  test(
    "a user's HS256 token with a kid in its header passes",
    () async {
      final answer = await server.me(
        sign(project, claims(), alg: 'HS256', header: {'kid': 'c2VjcmV0LTE'}),
      );
      expect(answer.status, 200, reason: answer.text);
    },
  );

  test('app_metadata.roles gives the roles here too', () async {
    final admin = hs256(
      claims(
        changes: {
          'app_metadata': {
            'roles': ['ADMIN'],
          },
        },
      ),
    );
    expect((await server.get('/api/admin', bearer: admin)).status, 200);
    expect(
      (await server.get('/api/admin', bearer: hs256(claims()))).status,
      403,
    );
  });

  group('refused with 401', () {
    test('a request without a token', () async {
      final answer = await server.me(null);
      expect(answer.status, 401);
      expect(answer.headers['www-authenticate'], 'Bearer');
    });

    test('a token signed with another secret', () async {
      final others = <String, List<int>>{
        'another secret': utf8.encode(
          'another-secret-of-44-characters-0123456789ab',
        ),
        'the secret in upper case': utf8.encode(_secret.toUpperCase()),
        'the secret decoded as base64': base64.decode(_secret),
        'the secret and a line break': utf8.encode('$_secret\n'),
        'the first 32 bytes of the secret': utf8.encode(
          _secret.substring(0, 32),
        ),
        'the anon key': utf8.encode(anonKey),
        'the service role key': utf8.encode(serviceRoleKey),
        'no secret': const [],
      };
      for (final MapEntry(key: name, value: secret) in others.entries) {
        await refused(
          sign(
            TokenFactory(testKeys.rsa, testKeys.ec, secret),
            claims(),
            alg: 'HS256',
          ),
          because: Because.signature,
          reason: name,
        );
      }
    });

    for (final alg in ['HS384', 'HS512']) {
      test('an $alg token signed with the secret', () async {
        await refused(
          sign(project, claims(), alg: alg),
          because: Because.algorithmOrKey,
        );
        // Its MAC under the name HS256.
        final mac = sign(project, claims(), alg: alg).split('.')[2];
        await refused(
          unsigned({'alg': 'HS256', 'typ': 'JWT'}, claims(), mac),
          because: Because.signature,
          reason: 'named HS256',
        );
      });
    }

    for (final alg in ['ES256', 'RS256']) {
      test("an $alg token, signed with the project's own key or carrying "
          'the MAC of the secret', () async {
        await refused(
          sign(testKeys, claims(), alg: alg),
          because: Because.algorithmOrKey,
        );
        final mac = hs256(claims()).split('.')[2];
        await refused(
          unsigned({'alg': alg, 'typ': 'JWT'}, claims(), mac),
          because: Because.algorithmOrKey,
          reason: 'the MAC',
        );
        // Signed with a private key, named HS256.
        await refused(
          sign(
            testKeys,
            claims(),
            alg: alg,
            header: {'alg': 'HS256', 'kid': null},
          ),
          because: Because.signature,
          reason: 'named HS256',
        );
      });
    }

    test('alg none, with and without a signature', () async {
      final mac = hs256(claims()).split('.')[2];
      for (final alg in ['none', 'None', 'NONE', 'nOnE', '']) {
        final header = {'alg': alg, 'typ': 'JWT'};
        await refused(unsigned(header, claims()), reason: alg);
        await refused(unsigned(header, claims(), mac), reason: '$alg signed');
      }
      await refused(unsigned({'typ': 'JWT'}, claims()), reason: 'no alg');
    });

    test('a token whose payload was changed after it was signed', () async {
      final parts = hs256(claims()).split('.');
      final forged = claims(changes: {'sub': 'another-user'});
      await refused(
        '${parts[0]}.${b64Json(forged)}.${parts[2]}',
        because: Because.signature,
      );
    });

    final now = TokenFactory.now();
    final invalid =
        <String, (Map<String, Object?> Function() claims, String because)>{
          'an expired token': (
            () => claims(changes: {'iat': now - 7200, 'exp': now - 3600}),
            Because.expired,
          ),
          'a token not valid yet (nbf in the future)': (
            () => claims(changes: {'nbf': now + 3600}),
            Because.notYetValid,
          ),
          'a token whose iss is another project': (
            () => claims(changes: {'iss': 'https://other.supabase.co/auth/v1'}),
            Because.issuer,
          ),
          'a token whose iss is the project with a trailing slash': (
            () => claims(changes: {'iss': '${host.issuer}/'}),
            Because.issuer,
          ),
          'a token whose iss is another path of the project': (
            () => claims(changes: {'iss': '${host.url}/auth/v2'}),
            Because.issuer,
          ),
          'a token without iss': (
            () => claims(without: ['iss']),
            Because.issuer,
          ),
          'a token of another audience': (
            () => claims(changes: {'aud': 'anon'}),
            Because.audience,
          ),
          'a token without aud': (
            () => claims(without: ['aud']),
            Because.audience,
          ),
          'the anon key as bearer': (() => apiKeyClaims('anon'), Because.role),
          'the anon key as bearer, were it of the issuer and the audience of '
              'a user': (
            () => claims(changes: {'role': 'anon'}),
            Because.role,
          ),
          'the service role key as bearer': (
            () => apiKeyClaims('service_role'),
            Because.role,
          ),
          'the service role key as bearer, were it of the issuer and the '
              'audience of a user': (
            () => claims(changes: {'role': 'service_role'}),
            Because.role,
          ),
          'a token without role': (
            () => claims(without: ['role']),
            Because.role,
          ),
        };
    for (final MapEntry(key: name, value: (claims, because))
        in invalid.entries) {
      test(name, () async {
        await refused(hs256(claims()), because: because);
      });
    }

    test(
      'a token without exp',
      () async {
        await refused(hs256(claims(without: ['exp'])));
      },
    );
  });

  test('no key set is asked of a project with a secret, and the server '
      'calls nobody', () async {
    await server.me(hs256(claims()));
    await server.me(sign(testKeys, claims()));
    expect(host.requests, isEmpty);
    expect(server.transport.requests, isEmpty);
  });

  group('the start fails', () {
    Future<(String failure, String log)> start(String secret) async {
      Object? failure;
      final log = await logged(
        () =>
            serverRunner(
              MockHttpTransport(),
              projectUrl: host.url,
              properties: ['spring.supabase.auth.jwt-secret=$secret'],
            ).runAsync((started) async {
              failure = started.startupFailure;
            }),
      );
      expect(failure, isNotNull, reason: 'the application started');
      return ('$failure', log);
    }

    test('with a secret shorter than 32 bytes, and the secret is in '
        'neither the error nor the log', () async {
      const short = 'kQ7-a-legacy-secret-of-31-bytes';
      expect(utf8.encode(short), hasLength(31));
      final (failure, log) = await start(short);
      expect(failure, contains('31 bytes'));
      expect(failure, contains('HS256'));
      for (final text in [failure, log]) {
        expect(text, isNot(contains(short)));
        expect(text, isNot(contains(short.substring(0, 12))));
        expect(text, isNot(contains(base64.encode(utf8.encode(short)))));
      }
    });
  });
}
