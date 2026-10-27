// The parts that fetch over HTTP, against a JWK Set served on the
// loopback interface: the default fetcher (statuses, the size limit) and the
// decoder the auto-configuration builds from `jwk-set-uri` (audiences,
// issuer, expiry, algorithms of the properties).
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:test/test.dart';

import 'app/jwt/keys.dart';
import 'support.dart';

const _jwt = 'spring.security.oauth2.resourceserver.jwt';

void main() {
  group('the HTTP fetcher', () {
    late HttpServer server;
    late Uri base;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = Uri.parse('http://localhost:${server.port}');
      unawaited(
        server.forEach((request) {
          final path = request.uri.path;
          final response = request.response;
          switch (path) {
            case '/jwks':
              response.write('{"keys": []}');
            case '/exact':
              response.write('a' * (1 << 20));
            case '/big':
              response.write('a' * ((1 << 20) + 1));
            default:
              response
                ..statusCode = HttpStatus.notFound
                ..write('{"keys": []}');
          }
          unawaited(response.close());
        }),
      );
    });

    tearDown(() => server.close(force: true));

    test('returns the body of a 200', () async {
      expect(await defaultJwkFetcher(base.resolve('/jwks')), '{"keys": []}');
    });

    test('any other status is an error', () async {
      await expectLater(
        defaultJwkFetcher(base.resolve('/missing')),
        throwsA(
          isA<JwtException>().having(
            (e) => e.message,
            'message',
            contains('404'),
          ),
        ),
      );
    });

    test('accepts 1 MiB, not a byte more', () async {
      expect(
        await defaultJwkFetcher(base.resolve('/exact')),
        hasLength(1 << 20),
      );
      await expectLater(
        defaultJwkFetcher(base.resolve('/big')),
        throwsA(isA<JwtException>()),
      );
    });
  });

  group('the decoder of the properties', () {
    late HttpServer server;
    late String jwks;
    final factory = testKeys;

    setUp(() async {
      jwks = jsonEncode({
        'keys': [factory.rsa.jwk, factory.ec.jwk],
      });
      server = (await HttpServer.bind(InternetAddress.loopbackIPv4, 0))
        ..listen((request) {
          final response = request.response
            ..headers.contentType = ContentType.json
            ..write(jwks);
          unawaited(response.close());
        });
    });

    tearDown(() => server.close(force: true));

    Future<JwtDecoder> decoder([List<String> properties = const []]) async {
      JwtDecoder? built;
      await securityRunner(null, [
        '$_jwt.jwk-set-uri=http://127.0.0.1:${server.port}/jwks',
        ...properties,
      ]).runAsync((started) async {
        built = started.context.getBean<JwtDecoder>();
      });
      return built!;
    }

    final refused = throwsA(isA<JwtException>());

    test('audiences are checked when set', () async {
      final strict = await decoder(['$_jwt.audiences=api,web']);
      await strict.decode(factory.token(claims: {'aud': 'api'}));
      await strict.decode(
        factory.token(
          claims: {
            'aud': ['other', 'web'],
          },
        ),
      );
      await expectLater(
        strict.decode(factory.token(claims: {'aud': 'other'})),
        refused,
      );
      await expectLater(strict.decode(factory.token()), refused);
    });

    test('without audiences any audience is accepted', () async {
      final open = await decoder();
      await open.decode(factory.token());
      await open.decode(factory.token(claims: {'aud': 'whoever'}));
    });

    test('the issuer is checked when set', () async {
      final strict = await decoder(['$_jwt.issuer-uri=https://issuer.example']);
      await strict.decode(
        factory.token(claims: {'iss': 'https://issuer.example'}),
      );
      await expectLater(
        strict.decode(factory.token(claims: {'iss': 'https://evil.example'})),
        refused,
      );
      await expectLater(strict.decode(factory.token()), refused);
      await (await decoder()).decode(factory.token());
    });

    test('expired tokens are refused', () async {
      final now = TokenFactory.now();
      await expectLater(
        (await decoder()).decode(
          factory.token(claims: {'iat': now - 7200, 'exp': now - 3600}),
        ),
        refused,
      );
    });

    test('only the algorithms of the properties', () async {
      final rsaOnly = await decoder();
      await rsaOnly.decode(factory.token());
      await expectLater(rsaOnly.decode(factory.token(alg: 'ES256')), refused);
      final ecOnly = await decoder(['$_jwt.jws-algorithms=ES256']);
      await ecOnly.decode(factory.token(alg: 'ES256'));
      await expectLater(ecOnly.decode(factory.token()), refused);
    });
  });
}
