@Tags(['supabase'])
library;

import 'dart:convert';

import 'package:test/test.dart';

import 'server_support.dart';

const _secret = 'tW9fQ2xvL0p1c3RBTGVnYWN5SldUU2VjcmV0OTk4MTIz';
const _garbage = 'garbage-TOKEN-4c1d7e02.not-a-jwt';

// Nothing a client or a reader of the log may learn: with everything
// logged at the default level captured from the start of the server on,
// accepted and refused tokens are sent, and no token, key or secret may be
// in an answer that refuses or in the log.
void main() {
  final keys = testKeys;
  final legacy = TokenFactory(keys.rsa, keys.ec, utf8.encode(_secret));
  final attacker = TokenFactory(
    keys.rsa,
    EcTestKey.generate(kid: keys.ec.kid),
    utf8.encode('another-secret-of-44-characters-0123456789ab'),
  );

  late KeyServer project;

  setUp(() async => project = await KeyServer.project(keys));
  tearDown(() => project.close());

  // The tokens of a run by name: [accepted] pass, the others are refused.
  Future<void> run({
    required List<String> properties,
    required TokenFactory signer,
    required TokenFactory forger,
    required String alg,
    required Map<String, String> secrets,
  }) async {
    Map<String, Object?> claims([Map<String, Object?> changes = const {}]) =>
        userClaims(project.issuer, changes: changes);
    final now = TokenFactory.now();
    final accepted = sign(signer, claims(), alg: alg);
    final admin = sign(
      signer,
      claims({
        'app_metadata': {
          'roles': ['ADMIN'],
        },
      }),
      alg: alg,
    );
    final parts = accepted.split('.');
    final refusedTokens = <String, String>{
      'expired': sign(signer, claims({'exp': now - 3600}), alg: alg),
      'of another issuer': sign(signer, claims({'iss': 'supabase'}), alg: alg),
      'of another audience': sign(signer, claims({'aud': 'x'}), alg: alg),
      'the anon key': sign(signer, apiKeyClaims('anon'), alg: alg),
      'the service role key': sign(
        signer,
        apiKeyClaims('service_role'),
        alg: alg,
      ),
      'of another key': sign(forger, claims(), alg: alg),
      'unsigned': unsigned({'alg': 'none', 'typ': 'JWT'}, claims()),
      'changed':
          '${parts[0]}.${b64Json(claims({'sub': 'another'}))}.${parts[2]}',
      'encrypted':
          '${b64Json({'alg': 'dir', 'enc': 'A256GCM'})}.e30.e30.'
          '${b64Json(claims())}.e30',
      'no token': _garbage,
    };
    final refusals = <String>[];
    final answers = <String>[];
    final log = await logged(() async {
      final server = await TestServer.start(
        projectUrl: project.url,
        properties: properties,
      );
      try {
        server.transport
            .when(HttpMethod.get, '/rest/v1/todos')
            .respond(200, json: <Object?>[]);
        for (final token in [accepted, admin]) {
          for (final path in ['/api/me', '/api/admin', '/api/todos']) {
            final answer = await server.get(path, bearer: token);
            expect(answer.status, anyOf(200, 403), reason: answer.text);
            answers.add(answer.text);
          }
        }
        refusals.add((await server.me(null)).text);
        for (final MapEntry(key: name, value: token) in refusedTokens.entries) {
          final answer = await server.me(token);
          expect(answer.status, 401, reason: name);
          refusals.add(answer.text);
        }
      } finally {
        await server.close();
      }
    });
    expect(log, contains('Web server started'));
    final hidden = <String, String>{
      'the anon key': anonKey,
      'the service role key': serviceRoleKey,
      ...secrets,
      for (final MapEntry(key: name, value: token) in {
        'accepted': accepted,
        'admin': admin,
        ...refusedTokens,
      }.entries)
        for (final (index, part) in token.split('.').indexed)
          if (part.length >= 12) 'part $index of the token $name': part,
    };
    final texts = {
      'the log': log,
      'the answers that refuse': refusals.join('\n'),
      'the answers to a user': answers.join('\n'),
    };
    for (final MapEntry(key: where, value: text) in texts.entries) {
      for (final MapEntry(key: name, value: secret) in hidden.entries) {
        expect(text, isNot(contains(secret)), reason: '$name in $where');
        expect(
          text,
          isNot(contains(base64.encode(utf8.encode(secret)))),
          reason: '$name, as base64, in $where',
        );
      }
    }
  }

  test('a project with signing keys: no token and no key in a 401 or in '
      'the log', () async {
    await run(
      properties: const [],
      signer: keys,
      forger: attacker,
      alg: 'ES256',
      secrets: const {},
    );
  });

  test('a project with a legacy secret: no token, no key and no secret in '
      'a 401 or in the log', () async {
    await run(
      properties: ['spring.supabase.auth.jwt-secret=$_secret'],
      signer: legacy,
      forger: attacker,
      alg: 'HS256',
      secrets: {
        'the secret': _secret,
        'the start of the secret': _secret.substring(0, 12),
        'the end of the secret': _secret.substring(_secret.length - 12),
      },
    );
  });

  test('a 401 says why in words of the server, never in words of the '
      'token', () async {
    final server = await TestServer.start(projectUrl: project.url);
    addTearDown(server.close);
    const marker = 'MARKER-b71e';
    for (final token in [
      sign(keys, userClaims(project.issuer, changes: {'iss': marker})),
      sign(keys, userClaims(project.issuer, changes: {'aud': marker})),
      sign(keys, userClaims(project.issuer, changes: {'role': marker})),
      sign(keys, userClaims(project.issuer), header: {'kid': marker}),
      sign(keys, userClaims(project.issuer), header: {'typ': marker}),
      unsigned({'alg': marker, 'typ': 'JWT'}, userClaims(project.issuer)),
      sign(
        keys,
        userClaims(
          project.issuer,
          changes: {'exp': TokenFactory.now() - 3600, 'sub': marker},
        ),
      ),
    ]) {
      final answer = await server.me(token);
      expect(answer.status, 401);
      expect(answer.text, isNot(contains(marker)));
    }
  });
}
