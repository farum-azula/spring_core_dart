// `required-claims` and the application's validator beans on the decoders
// the auto-configuration builds from `jwk-set-uri` and from `issuer-uri`
// alone, against a provider served on the loopback interface: a token
// passes only with every required claim, and no other check is lost.
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app/jwt/keys.dart';
import 'app/validators/validators.dart';
import 'support.dart';

const _jwt = 'spring.security.oauth2.resourceserver.jwt';

Matcher _invalid(String text) => throwsA(
  isA<JwtValidationException>().having(
    (e) => e.message,
    'message',
    contains(text),
  ),
);

void main() {
  late HttpServer server;
  late String issuer;
  final factory = testKeys;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    issuer = 'http://127.0.0.1:${server.port}';
    server.listen((request) {
      final response = request.response..headers.contentType = ContentType.json;
      switch (request.uri.path) {
        case '/jwks':
          response.write(
            jsonEncode({
              'keys': [factory.rsa.jwk, factory.ec.jwk],
            }),
          );
        case '/.well-known/openid-configuration':
          response.write(
            jsonEncode({'issuer': issuer, 'jwks_uri': '$issuer/jwks'}),
          );
        default:
          response.statusCode = HttpStatus.notFound;
      }
      unawaited(response.close());
    });
  });

  tearDown(() => server.close(force: true));

  Future<JwtDecoder> decoder(
    List<String> properties, {
    BeanModule? configuration,
  }) async {
    JwtDecoder? built;
    await securityRunner(configuration, properties).runAsync((started) async {
      final failure = started.startupFailure;
      if (failure != null) {
        fail('The application failed to start: $failure');
      }
      built = started.context.getBean<JwtDecoder>();
    });
    return built!;
  }

  // The two decoders of the properties: the keys by their address, and the
  // issuer alone (its metadata names the keys).
  final branches = <String, List<String> Function()>{
    'jwk-set-uri': () => ['$_jwt.jwk-set-uri=$issuer/jwks'],
    'issuer-uri alone': () => ['$_jwt.issuer-uri=$issuer'],
  };

  for (final MapEntry(key: branch, value: keys) in branches.entries) {
    group('with $branch', () {
      // Every token names the issuer, which `issuer-uri` checks.
      String token(Map<String, Object?> claims) =>
          factory.token(claims: {'iss': issuer, ...claims});

      test('a required claim: equal, different, absent', () async {
        final strict = await decoder([
          ...keys(),
          '$_jwt.required-claims.role=authenticated',
        ]);
        final jwt = await strict.decode(token({'role': 'authenticated'}));
        expect(jwt.claims['role'], 'authenticated');
        for (final role in ['anon', 'service_role', 'AUTHENTICATED', '', ' ']) {
          await expectLater(
            strict.decode(token({'role': role})),
            _invalid('The role claim is not valid'),
            reason: '"$role"',
          );
        }
        await expectLater(
          strict.decode(token({})),
          _invalid('The role claim is not valid'),
        );
      });

      test('without the property no claim is required', () async {
        final open = await decoder(keys());
        await open.decode(token({}));
        await open.decode(token({'role': 'anon'}));
      });

      test('the claim itself, never one inside an object or a list', () async {
        final strict = await decoder([
          ...keys(),
          '$_jwt.required-claims.role=authenticated',
        ]);
        for (final role in <Object?>[
          null,
          ['authenticated'],
          {'role': 'authenticated'},
          <String>[],
        ]) {
          await expectLater(
            strict.decode(token({'role': role})),
            _invalid('The role claim is not valid'),
            reason: '$role',
          );
        }
        await expectLater(
          strict.decode(
            token({
              'app_metadata': {'role': 'authenticated'},
              'user_metadata': {'role': 'authenticated'},
            }),
          ),
          _invalid('The role claim is not valid'),
        );
      });

      test('a number or a boolean claim is compared as its text', () async {
        final strict = await decoder([
          ...keys(),
          '$_jwt.required-claims.email_verified=true',
          '$_jwt.required-claims.level=2',
        ]);
        await strict.decode(token({'email_verified': true, 'level': 2}));
        await strict.decode(token({'email_verified': 'true', 'level': '2'}));
        await expectLater(
          strict.decode(token({'email_verified': false, 'level': 2})),
          _invalid('The email_verified claim is not valid'),
        );
        await expectLater(
          strict.decode(token({'email_verified': true, 'level': 3})),
          _invalid('The level claim is not valid'),
        );
      });

      test('every required claim must hold', () async {
        final strict = await decoder([
          ...keys(),
          '$_jwt.required-claims.role=authenticated',
          '$_jwt.required-claims.tenant=shop',
        ]);
        await strict.decode(token({'role': 'authenticated', 'tenant': 'shop'}));
        await expectLater(
          strict.decode(token({'role': 'authenticated'})),
          _invalid('The tenant claim is not valid'),
        );
        await expectLater(
          strict.decode(token({'tenant': 'shop'})),
          _invalid('The role claim is not valid'),
        );
        await expectLater(
          strict.decode(token({'role': 'authenticated', 'tenant': 'other'})),
          _invalid('The tenant claim is not valid'),
        );
      });

      test('the other checks stay: signature, lifetime, type, audience, '
          'issuer', () async {
        final strict = await decoder([
          ...keys(),
          '$_jwt.issuer-uri=$issuer',
          '$_jwt.audiences=api',
          '$_jwt.required-claims.role=authenticated',
        ]);
        const role = {'role': 'authenticated', 'aud': 'api'};
        await strict.decode(token(role));
        final now = TokenFactory.now();
        await expectLater(
          strict.decode(token({...role, 'iat': now - 7200, 'exp': now - 3600})),
          _invalid('expired'),
        );
        await expectLater(
          strict.decode(token({...role, 'aud': 'other'})),
          _invalid('aud'),
        );
        await expectLater(
          strict.decode(token({...role, 'iss': 'https://evil.example'})),
          _invalid('iss'),
        );
        await expectLater(
          strict.decode(
            factory.token(
              claims: {'iss': issuer, ...role},
              header: {'typ': 'logout+jwt'},
            ),
          ),
          _invalid('typ'),
        );
        final other = RsaTestKey.generate(kid: factory.rsa.kid);
        await expectLater(
          strict.decode(
            TokenFactory(
              other,
              factory.ec,
              factory.secret,
            ).token(claims: {'iss': issuer, ...role}),
          ),
          throwsA(isA<BadJwtException>()),
        );
      });

      test('the validator beans of the application are added', () async {
        final strict = await decoder([
          ...keys(),
          '$_jwt.required-claims.role=authenticated',
        ], configuration: jwtValidatorBeans);
        const valid = {
          'role': 'authenticated',
          'tenant': 'shop',
          'email_verified': true,
        };
        await strict.decode(token(valid));
        await expectLater(
          strict.decode(token({...valid, 'tenant': 'other'})),
          _invalid('The tenant is not shop'),
        );
        await expectLater(
          strict.decode(token({...valid, 'email_verified': false})),
          _invalid('The email_verified claim is not valid'),
        );
        await expectLater(
          strict.decode(token({...valid, 'role': 'anon'})),
          _invalid('The role claim is not valid'),
        );
        final now = TokenFactory.now();
        await expectLater(
          strict.decode(
            token({...valid, 'iat': now - 7200, 'exp': now - 3600}),
          ),
          _invalid('expired'),
        );
      });

      test('a refused claim is a 401 invalid_token', () async {
        await withApp(
          null,
          properties: [
            ...keys(),
            '$_jwt.required-claims.role=authenticated',
          ],
          (mvc, context) async {
            Future<MvcResult> get(Map<String, Object?> claims) => mvc.perform(
              request(
                HttpMethod.get,
                '/api/me',
                headers: {'authorization': 'Bearer ${token(claims)}'},
              ),
            );
            expect((await get({'role': 'authenticated'})).status, 200);
            for (final claims in [
              {'role': 'anon'},
              <String, Object?>{},
            ]) {
              final refused = await get(claims);
              expect(refused.status, 401, reason: '$claims');
              expect(
                refused.header('www-authenticate'),
                allOf(contains('invalid_token'), contains('role claim')),
              );
            }
          },
        );
      });
    });
  }

  test('a blank claim name fails the start', () async {
    Object? failure;
    await securityRunner(null, [
      '$_jwt.jwk-set-uri=$issuer/jwks',
      '$_jwt.required-claims[ ]=x',
    ]).runAsync((started) async {
      failure = started.startupFailure;
    });
    expect('$failure', contains('$_jwt.required-claims'));
  });
}
