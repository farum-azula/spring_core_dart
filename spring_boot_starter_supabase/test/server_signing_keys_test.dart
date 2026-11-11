@Tags(['supabase'])
library;

import 'dart:convert';

import 'package:test/test.dart';

import 'server_support.dart';

// A server of a project with signing keys: its JWKS is served on the
// loopback interface, and the server accepts a user's ES256 or RS256
// token of that project and nothing else.
void main() {
  final keys = testKeys;
  final attackerEc = EcTestKey.generate(kid: keys.ec.kid);
  final attackerRsa = RsaTestKey.generate(kid: keys.rsa.kid);
  final attacker = TokenFactory(attackerRsa, attackerEc, const []);

  late KeyServer project;
  late KeyServer attackerHost;
  late TestServer server;

  setUpAll(() async {
    project = await KeyServer.project(keys);
    attackerHost = await KeyServer.attacker([attackerEc.jwk, attackerRsa.jwk]);
    server = await TestServer.start(projectUrl: project.url);
  });

  tearDownAll(() async {
    await server.close();
    await attackerHost.close();
    await project.close();
  });

  Map<String, Object?> claims({
    Map<String, Object?> changes = const {},
    List<String> without = const [],
  }) => userClaims(project.issuer, changes: changes, without: without);

  Future<void> refused(
    String token, {
    String? because,
    String? reason,
  }) async =>
      expectRefused(await server.me(token), because: because, reason: reason);

  group('accepted', () {
    for (final alg in ['ES256', 'RS256']) {
      test("a user's $alg token, with the token's sub as the "
          'principal', () async {
        final answer = await server.me(sign(keys, claims(), alg: alg));
        expect(answer.status, 200, reason: answer.text);
        expect(answer.json, {'name': userId, 'authorities': <Object?>[]});
      });
    }

    test('the keys were asked of the project, at its JWKS address '
        'only', () async {
      await server.me(sign(keys, claims()));
      expect(project.requests, isNotEmpty);
      expect(
        project.requests,
        everyElement('/auth/v1/.well-known/jwks.json'),
      );
      expect(server.transport.requests, isEmpty);
    });
  });

  group('refused with 401', () {
    test('a request without a token', () async {
      final answer = await server.me(null);
      expect(answer.status, 401);
      expect(answer.headers['www-authenticate'], 'Bearer');
    });

    test('an expired token', () async {
      final now = TokenFactory.now();
      await refused(
        sign(keys, claims(changes: {'iat': now - 7200, 'exp': now - 3600})),
        because: Because.expired,
      );
      await refused(
        sign(keys, claims(changes: {'iat': now - 7200, 'exp': now - 120})),
        because: Because.expired,
        reason: 'two minutes ago',
      );
    });

    test(
      'a token without exp',
      () async {
        await refused(sign(keys, claims(without: ['exp'])));
      },
    );

    test('a token not valid yet (nbf in the future)', () async {
      await refused(
        sign(keys, claims(changes: {'nbf': TokenFactory.now() + 3600})),
        because: Because.notYetValid,
      );
    });

    final issuers = <String, String Function()>{
      'another project': () => 'https://other.supabase.co/auth/v1',
      'the project with a trailing slash': () => '${project.issuer}/',
      'another path of the project': () => '${project.url}/auth/v2',
      'the project itself, without the path': () => project.url,
      'the project in upper case': () => project.issuer.toUpperCase(),
      'the project by another name of its host': () =>
          project.issuer.replaceFirst('127.0.0.1', 'localhost'),
      'the name of the API keys': () => 'supabase',
    };
    for (final MapEntry(key: name, value: issuer) in issuers.entries) {
      test('a token whose iss is $name', () async {
        await refused(
          sign(keys, claims(changes: {'iss': issuer()})),
          because: Because.issuer,
        );
      });
    }

    test('a token without iss', () async {
      await refused(
        sign(keys, claims(without: ['iss'])),
        because: Because.issuer,
      );
    });

    test('a token of another audience', () async {
      for (final aud in <Object?>[
        'anon',
        'service_role',
        'Authenticated',
        'authenticated ',
        ['other'],
        <String>[],
        '',
        null,
      ]) {
        await refused(
          sign(keys, claims(changes: {'aud': aud})),
          because: Because.audience,
          reason: jsonEncode(aud),
        );
      }
    });

    test('a token without aud', () async {
      await refused(
        sign(keys, claims(without: ['aud'])),
        because: Because.audience,
      );
    });

    for (final role in ['anon', 'service_role']) {
      test('the $role key as bearer', () async {
        await refused(
          sign(keys, apiKeyClaims(role)),
          because: Because.role,
          reason: 'as issued',
        );
        // Were it of the issuer and the audience of a user: the role alone.
        await refused(
          sign(keys, claims(changes: {'role': role})),
          because: Because.role,
          reason: 'with the iss and aud of a user',
        );
        await refused(
          sign(keys, claims(changes: {'role': role}, without: ['sub'])),
          because: Because.role,
          reason: 'without sub',
        );
      });
    }

    test('a token without role', () async {
      await refused(
        sign(keys, claims(without: ['role'])),
        because: Because.role,
      );
    });

    test('a token whose role is not the text authenticated', () async {
      for (final role in <Object?>[
        'AUTHENTICATED',
        ' authenticated',
        ['authenticated'],
        {'role': 'authenticated'},
        true,
        null,
      ]) {
        await refused(
          sign(keys, claims(changes: {'role': role})),
          because: Because.role,
          reason: jsonEncode(role),
        );
      }
    });

    test('alg none, with and without a signature', () async {
      final signature = sign(keys, claims()).split('.')[2];
      for (final alg in ['none', 'None', 'NONE', 'nOnE', '']) {
        final header = {'alg': alg, 'typ': 'JWT', 'kid': keys.ec.kid};
        await refused(unsigned(header, claims()), reason: alg);
        await refused(
          unsigned(header, claims(), signature),
          reason: '$alg signed',
        );
      }
      await refused(unsigned({'typ': 'JWT'}, claims()), reason: 'no alg');
    });

    test('an HS256, HS384 or HS512 token signed with a public key as the '
        'secret', () async {
      final ec = keys.ec.jwk;
      final rsa = keys.rsa.jwk;
      List<int> raw(Object? text) =>
          base64Url.decode(base64Url.normalize(text! as String));
      final secrets = <String, List<int>>{
        'the key set as served': utf8.encode(project.body),
        'the EC JWK': utf8.encode(jsonEncode(ec)),
        'the RSA JWK': utf8.encode(jsonEncode(rsa)),
        'the EC point': [4, ...raw(ec['x']), ...raw(ec['y'])],
        'the EC coordinates': [...raw(ec['x']), ...raw(ec['y'])],
        'the EC coordinates as text': utf8.encode('${ec['x']}${ec['y']}'),
        'the RSA modulus': raw(rsa['n']),
        'the RSA modulus as text': utf8.encode(rsa['n']! as String),
        'the anon key': utf8.encode(anonKey),
      };
      for (final MapEntry(key: name, value: secret) in secrets.entries) {
        final forger = TokenFactory(keys.rsa, keys.ec, secret);
        for (final alg in ['HS256', 'HS384', 'HS512']) {
          for (final kid in [keys.ec.kid, keys.rsa.kid, null]) {
            await refused(
              sign(forger, claims(), alg: alg, header: {'kid': ?kid}),
              because: Because.algorithmOrKey,
              reason: '$alg with $name, kid $kid',
            );
          }
        }
        // The MAC of the public key under the name of the key's algorithm.
        final mac = sign(forger, claims(), alg: 'HS256').split('.')[2];
        for (final (alg, kid) in [
          ('ES256', keys.ec.kid),
          ('RS256', keys.rsa.kid),
        ]) {
          await refused(
            unsigned({'alg': alg, 'typ': 'JWT', 'kid': kid}, claims(), mac),
            because: Because.signature,
            reason: 'a MAC with $name named $alg',
          );
        }
      }
    });

    test('a token signed by another key with the kid of a key of the '
        'project', () async {
      for (final alg in ['ES256', 'RS256']) {
        await refused(
          sign(attacker, claims(), alg: alg),
          because: Because.signature,
          reason: alg,
        );
      }
    });

    test('a token of a key the project does not have (an unknown '
        'kid)', () async {
      for (final alg in ['ES256', 'RS256']) {
        await refused(
          sign(attacker, claims(), alg: alg, header: {'kid': 'attacker-1'}),
          because: Because.algorithmOrKey,
          reason: alg,
        );
        // Signed by the project, under a name it does not know.
        await refused(
          sign(keys, claims(), alg: alg, header: {'kid': 'unknown'}),
          because: Because.algorithmOrKey,
          reason: '$alg, the project',
        );
        // Without a name every key of the project is tried.
        await refused(
          sign(attacker, claims(), alg: alg, header: {'kid': null}),
          because: Because.signature,
          reason: '$alg, no kid',
        );
      }
    });

    test('a token of one key of the project under the kid of the '
        'other', () async {
      await refused(
        sign(keys, claims(), header: {'kid': keys.rsa.kid}),
        because: Because.algorithmOrKey,
      );
      await refused(
        sign(keys, claims(), alg: 'RS256', header: {'kid': keys.ec.kid}),
        because: Because.algorithmOrKey,
      );
    });

    final ownKeys = <String, Map<String, Object?> Function(String alg)>{
      'jku': (_) => {'jku': '${attackerHost.url}/jwks.json'},
      'jwk': (alg) => {
        'jwk': alg == 'ES256' ? attackerEc.jwk : attackerRsa.jwk,
      },
      'x5u': (_) => {'x5u': '${attackerHost.url}/cert.pem'},
    };
    for (final MapEntry(key: name, value: header) in ownKeys.entries) {
      test("a token that brings the attacker's key in $name", () async {
        for (final alg in ['ES256', 'RS256']) {
          for (final kid in [keys.ec.kid, keys.rsa.kid, 'attacker-1', null]) {
            await refused(
              sign(
                attacker,
                claims(),
                alg: alg,
                header: {...header(alg), 'kid': kid},
              ),
              reason: '$alg, kid $kid',
            );
          }
        }
        expect(attackerHost.requests, isEmpty);
      });
    }

    test('a token whose payload was changed after it was signed', () async {
      final parts = sign(keys, claims()).split('.');
      for (final forged in [
        claims(changes: {'sub': 'another-user'}),
        claims(
          changes: {
            'app_metadata': {
              'roles': ['ADMIN'],
            },
          },
        ),
      ]) {
        await refused(
          '${parts[0]}.${b64Json(forged)}.${parts[2]}',
          because: Because.signature,
        );
      }
    });

    test('a token of an algorithm the project does not sign with', () async {
      for (final alg in ['RS384', 'RS512', 'PS256', 'PS384', 'PS512']) {
        await refused(
          sign(keys, claims(), alg: alg),
          because: Because.algorithmOrKey,
          reason: alg,
        );
      }
      // The header alone changed: the project's key, another algorithm.
      final parts = sign(keys, claims()).split('.');
      final header = b64Json({
        'alg': 'ES384',
        'typ': 'JWT',
        'kid': keys.ec.kid,
      });
      await refused(
        '$header.${parts[1]}.${parts[2]}',
        because: Because.algorithmOrKey,
        reason: 'ES384',
      );
    });

    test('an encrypted token (a JWE of five parts)', () async {
      final header = b64Json({'alg': 'RSA-OAEP', 'enc': 'A256GCM'});
      await refused(
        '$header.${b64([1, 2, 3])}.${b64([4, 5])}.'
        '${b64Json(claims())}.${b64([6, 7])}',
        because: Because.encrypted,
      );
      await refused('$header.e30.e30.e30.e30', because: Because.encrypted);
    });

    test('a token of another type (typ)', () async {
      for (final type in ['at+jwt', 'logout+jwt', 'dpop+jwt']) {
        await refused(
          sign(keys, claims(), header: {'typ': type}),
          because: Because.type,
          reason: type,
        );
      }
    });

    test('text that is no token', () async {
      final valid = sign(keys, claims());
      final parts = valid.split('.');
      for (final text in [
        'garbage',
        'a.b.c',
        '..',
        '.',
        'e30.e30.e30',
        '${parts[0]}.${parts[1]}',
        '${parts[0]}.${parts[1]}.',
        '${parts[0]}..${parts[2]}',
        '.${parts[1]}.${parts[2]}',
        '$valid.',
        '$valid.${parts[2]}',
        '${valid.substring(0, valid.length - 4)}AAAA',
        anonKey,
        'sb_publishable_9f3a71c2d0e8a514b7e9c330d5a4be7f',
        'sb_secret_5be04d17d0e8a514b7e9c330d5a4be7f',
        'null',
        'undefined',
      ]) {
        final answer = await server.me(text);
        expect(answer.status, 401, reason: text);
      }
    });

    test('a valid token under another scheme, in the query or as '
        'apikey', () async {
      final valid = sign(keys, claims());
      for (final scheme in ['Basic', 'Token', 'JWT']) {
        final answer = await server.get(
          '/api/me',
          headers: {'authorization': '$scheme $valid'},
        );
        expect(answer.status, 401, reason: scheme);
      }
      final query = await server.get('/api/me?access_token=$valid');
      expect(query.status, 401);
      final apikey = await server.get('/api/me', headers: {'apikey': valid});
      expect(apikey.status, 401);
    });
  });

  test('nothing but the key set was ever asked of the project, and nothing '
      "of the attacker's host", () async {
    expect(
      project.requests,
      everyElement('/auth/v1/.well-known/jwks.json'),
    );
    expect(attackerHost.requests, isEmpty);
    expect(server.transport.requests, isEmpty);
  });
}
