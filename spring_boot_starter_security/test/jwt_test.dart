// JWT verification: the RFC 7515 examples, every algorithm, the known
// attacks on JWT libraries (alg none, algorithm confusion, embedded keys,
// kid tricks, oversized and malformed tokens), the claims checks, key
// rotation, issuer discovery, and the resource server end to end.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_security/src/jwt/jose.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app/jwt/jwt.dart';
import 'app/jwt/keys.dart';
import 'support.dart';

/// [path] in this package (the tests also run from the workspace root).
File _packageFile(String path) => File.fromUri(
  Isolate.resolvePackageUriSync(
    Uri.parse('package:spring_boot_starter_security/'),
  )!.resolve('../$path'),
);

final _noValidation = DelegatingOAuth2TokenValidator<Jwt>(const []);

Map<String, Object?> _vector(String name) =>
    (jsonDecode(_packageFile('test/vectors/rfc7515.json').readAsStringSync())
            as Map<String, Object?>)[name]!
        as Map<String, Object?>;

final Matcher _rejected = throwsA(isA<BadJwtException>());

String _tamper(String token, int part) {
  final parts = token.split('.');
  final chars = parts[part].split('');
  final i = chars.length ~/ 2;
  chars[i] = chars[i] == 'A' ? 'B' : 'A';
  parts[part] = chars.join();
  return parts.join('.');
}

void main() {
  final keys = testKeys;
  JwtDecoder decoder({Set<JwsAlgorithm>? algorithms}) =>
      NimbusJwtDecoder.withJwkSource(
        StaticJwkSource([keys.rsa.verificationKey, keys.ec.verificationKey]),
        jwsAlgorithms: algorithms,
      );

  group('RFC 7515 examples', () {
    test('A.1 HS256', () async {
      final vector = _vector('A.1');
      final jwk = vector['jwk']! as Map<String, Object?>;
      final hs = NimbusJwtDecoder.withSecretKey(
        base64UrlToBytes(jwk['k']! as String),
        validator: _noValidation,
      );
      final jwt = await hs.decode(vector['jws']! as String);
      expect(jwt.claims['iss'], 'joe');
      expect(jwt.claims['http://example.com/is_root'], isTrue);
      await expectLater(
        hs.decode(_tamper(vector['jws']! as String, 1)),
        _rejected,
      );
    });

    test('A.4 ES512 (a payload that is not JSON: only the signature)', () {
      final vector = _vector('A.4');
      final key = parseJwk(vector['jwk']! as Map<String, Object?>)!;
      final token = vector['jws']! as String;
      expect(verifyCompactJws(token, key), isTrue);
      expect(verifyCompactJws(_tamper(token, 1), key), isFalse);
      expect(verifyCompactJws(_tamper(token, 2), key), isFalse);
    });

    for (final name in ['A.2', 'A.3']) {
      test('$name ${name == 'A.2' ? 'RS256' : 'ES256'}', () async {
        final vector = _vector(name);
        final key = parseJwk(vector['jwk']! as Map<String, Object?>)!;
        final decoder = NimbusJwtDecoder.withJwkSource(
          StaticJwkSource([key]),
          validator: _noValidation,
        );
        final token = vector['jws']! as String;
        expect((await decoder.decode(token)).claims['iss'], 'joe');
        await expectLater(decoder.decode(_tamper(token, 1)), _rejected);
        await expectLater(decoder.decode(_tamper(token, 2)), _rejected);
      });
    }
  });

  group('algorithms', () {
    for (final alg in [
      'RS256',
      'RS384',
      'RS512',
      'PS256',
      'PS384',
      'PS512',
      'ES256',
    ]) {
      test('$alg verifies, a changed payload does not', () async {
        final token = keys.token(alg: alg);
        expect((await decoder().decode(token)).subject, 'ada');
        await expectLater(decoder().decode(_tamper(token, 1)), _rejected);
      });
    }

    test('HS256 with a secret', () async {
      final hs = NimbusJwtDecoder.withSecretKey(keys.secret);
      expect((await hs.decode(keys.token(alg: 'HS256'))).subject, 'ada');
      expect(
        () => NimbusJwtDecoder.withSecretKey(List.filled(16, 1)),
        throwsArgumentError,
        reason: 'a 128-bit secret is too short for HS256',
      );
    });

    test('only the configured algorithms', () async {
      final rs256Only = decoder(algorithms: {JwsAlgorithm.rs256});
      await rs256Only.decode(keys.token());
      await expectLater(rs256Only.decode(keys.token(alg: 'PS256')), _rejected);
      await expectLater(rs256Only.decode(keys.token(alg: 'ES256')), _rejected);
    });
  });

  group('attacks', () {
    test('alg none, in every spelling, is never accepted', () async {
      for (final alg in ['none', 'None', 'NONE', 'nOnE']) {
        final header = b64Json({'alg': alg, 'typ': 'JWT'});
        final payload = b64Json({
          'sub': 'admin',
          'exp': TokenFactory.now() + 60,
        });
        for (final token in ['$header.$payload.', '$header.$payload']) {
          await expectLater(decoder().decode(token), _rejected, reason: alg);
        }
      }
    });

    test('algorithm confusion: HS256 signed with the RSA public key', () async {
      final publicKeyBytes = utf8.encode(jsonEncode(keys.rsa.jwk));
      final forged = TokenFactory(
        keys.rsa,
        keys.ec,
        publicKeyBytes,
      ).token(alg: 'HS256', kid: keys.rsa.kid, claims: {'sub': 'admin'});
      // Even with HS256 allowed, an RSA key never verifies HMAC.
      await expectLater(
        decoder(algorithms: {JwsAlgorithm.rs256, JwsAlgorithm.hs256})
            .decode(forged),
        _rejected,
      );
      await expectLater(decoder().decode(forged), _rejected);
    });

    test('a key embedded in the token (jwk, jku, x5u) is ignored', () async {
      final attacker = RsaTestKey.generate(kid: 'evil');
      final factory = TokenFactory(attacker, keys.ec, keys.secret);
      for (final header in [
        {'jwk': attacker.jwk},
        {'jku': 'https://evil.example/jwks.json'},
        {'x5u': 'https://evil.example/cert.pem'},
      ]) {
        final token = factory.token(kid: 'evil', header: header);
        await expectLater(
          decoder().decode(token),
          _rejected,
          reason: '$header',
        );
      }
    });

    test('an unknown or odd kid finds no key', () async {
      for (final kid in ['unknown', '../../etc/passwd', "' OR 1=1 --", '']) {
        await expectLater(
          decoder().decode(keys.token(kid: kid)),
          _rejected,
          reason: kid,
        );
      }
    });

    test('a token signed by another key', () async {
      final other = TokenFactory(
        RsaTestKey.generate(kid: keys.rsa.kid),
        keys.ec,
        keys.secret,
      );
      await expectLater(decoder().decode(other.token()), _rejected);
    });

    test('malformed tokens', () async {
      final valid = keys.token();
      final [header, payload, signature] = valid.split('.');
      for (final token in [
        '',
        'abc',
        '$header.$payload',
        '$header.$payload.$signature.extra',
        '$header.$payload.$signature.a.b', // JWE shape
        '$header=.$payload.$signature',
        '$header.$payload.$signature=',
        '$header.$payload.${signature.substring(1)}',
        '$header.@@@.$signature',
        '${b64Json([1, 2])}.$payload.$signature',
        '${b64(utf8.encode('not json'))}.$payload.$signature',
        '${b64Json({'typ': 'JWT'})}.$payload.$signature',
        '${b64Json({'alg': 7})}.$payload.$signature',
      ]) {
        await expectLater(decoder().decode(token), _rejected, reason: token);
      }
    });

    test('crit headers and nested tokens are refused', () async {
      await expectLater(
        decoder().decode(
          keys.token(
            header: {
              'crit': ['exp'],
            },
          ),
        ),
        _rejected,
      );
      await expectLater(
        decoder().decode(keys.token(header: {'cty': 'JWT'})),
        _rejected,
      );
    });

    test('an ECDSA signature in DER instead of R||S is refused', () async {
      final token = keys.token(alg: 'ES256');
      final parts = token.split('.');
      final raw = base64Url.decode(base64Url.normalize(parts[2]));
      final der = [
        0x30,
        raw.length + 4,
        0x02,
        32,
        ...raw.sublist(0, 32),
        0x02,
        32,
        ...raw.sublist(32),
      ];
      await expectLater(
        decoder().decode('${parts[0]}.${parts[1]}.${b64(der)}'),
        _rejected,
      );
    });

    test('an oversized token is refused before any work', () async {
      final huge = keys.token(claims: {'pad': 'x' * (70 * 1024)});
      final watch = Stopwatch()..start();
      await expectLater(decoder().decode(huge), _rejected);
      expect(watch.elapsedMilliseconds, lessThan(200));
    });

    test('weak keys are not used: RSA under 2048 bits, EC off the curve', () {
      final small = RsaTestKey.generate(bits: 1024);
      expect(small.verificationKey.fits(JwsAlgorithm.rs256), isFalse);
      final ec = keys.ec.jwk;
      expect(parseJwk({...ec, 'y': ec['x']}), isNull);
    });
  });

  group('claims', () {
    final now = TokenFactory.now();

    test('expired: refused after 60 s of skew, accepted within', () async {
      await expectLater(
        decoder().decode(keys.token(claims: {'exp': now - 120})),
        throwsA(
          isA<JwtValidationException>().having(
            (e) => e.message,
            'message',
            contains('Jwt expired at'),
          ),
        ),
      );
      await decoder().decode(keys.token(claims: {'exp': now - 30}));
    });

    test('not yet valid', () async {
      await expectLater(
        decoder().decode(keys.token(claims: {'nbf': now + 120})),
        throwsA(isA<JwtValidationException>()),
      );
      await decoder().decode(keys.token(claims: {'nbf': now + 30}));
    });

    test('a non-numeric exp is refused', () async {
      await expectLater(
        decoder().decode(keys.token(claims: {'exp': 'tomorrow'})),
        throwsA(isA<JwtValidationException>()),
      );
    });

    test('issuer and audience', () async {
      final strict = NimbusJwtDecoder.withJwkSource(
        StaticJwkSource([keys.rsa.verificationKey]),
        validator: DelegatingOAuth2TokenValidator([
          JwtTimestampValidator(),
          const JwtIssuerValidator('https://issuer.example'),
          JwtAudienceValidator(['api']),
        ]),
      );
      final good = {
        'iss': 'https://issuer.example',
        'aud': ['other', 'api'],
      };
      await strict.decode(keys.token(claims: good));
      await strict.decode(keys.token(claims: {...good, 'aud': 'api'}));
      for (final bad in [
        {...good, 'iss': 'https://evil.example'},
        {...good, 'aud': 'other'},
        {'iss': 'https://issuer.example'},
      ]) {
        await expectLater(
          strict.decode(keys.token(claims: bad)),
          throwsA(isA<JwtValidationException>()),
          reason: '$bad',
        );
      }
    });
  });

  group('JWK sets', () {
    test('parsing skips encryption keys, symmetric keys and broken ones', () {
      final keys = parseJwkSet(
        jsonEncode({
          'keys': [
            testKeys.rsa.jwk,
            {...testKeys.rsa.jwk, 'use': 'enc', 'kid': 'enc'},
            {'kty': 'oct', 'k': 'c2VjcmV0'},
            {'kty': 'RSA', 'n': '!!!'},
            testKeys.ec.jwk,
          ],
        }),
      );
      expect(
        [for (final k in keys) k.keyId],
        [testKeys.rsa.kid, testKeys.ec.kid],
      );
      expect(() => parseJwkSet('[]'), throwsA(isA<JwtException>()));
    });

    test(
      'rotation: an unknown kid fetches again, at most every 30 s',
      () async {
        var now = DateTime(2026);
        var fetches = 0;
        var current = [keys.rsa.jwk];
        final source = RemoteJwkSource(
          Uri.parse('https://issuer.example/jwks'),
          fetcher: (_) async {
            fetches++;
            return jsonEncode({'keys': current});
          },
          clock: () => now,
        );
        final decoder = NimbusJwtDecoder.withJwkSource(source);
        await decoder.decode(keys.token());
        expect(fetches, 1);
        final rotated = RsaTestKey.generate(kid: 'rsa-2');
        final next = TokenFactory(rotated, keys.ec, keys.secret);
        current = [keys.rsa.jwk, rotated.jwk];
        // Within 30 s of the last fetch: no new fetch, the token fails.
        await expectLater(decoder.decode(next.token()), _rejected);
        expect(fetches, 1);
        now = now.add(const Duration(seconds: 31));
        await decoder.decode(next.token());
        expect(fetches, 2);
        // Made-up kids cannot make it fetch on every token.
        for (var i = 0; i < 5; i++) {
          await expectLater(
            decoder.decode(keys.token(kid: 'made-up-$i')),
            _rejected,
          );
        }
        expect(fetches, 2);
      },
    );

    test('the issuer being down keeps the keys fetched before', () async {
      var now = DateTime(2026);
      var down = false;
      final source = RemoteJwkSource(
        Uri.parse('https://issuer.example/jwks'),
        fetcher: (_) async {
          if (down) {
            throw const SocketException('down');
          }
          return jsonEncode({
            'keys': [keys.rsa.jwk],
          });
        },
        clock: () => now,
      );
      final decoder = NimbusJwtDecoder.withJwkSource(source);
      await decoder.decode(keys.token());
      down = true;
      now = now.add(const Duration(minutes: 10));
      await decoder.decode(keys.token());
    });

    test(
      'discovery: the jwks_uri of the issuer; a wrong issuer is refused',
      () async {
        String metadata(String issuer) => jsonEncode({
          'issuer': issuer,
          'jwks_uri': 'https://issuer.example/jwks',
        });
        final fetched = <Uri>[];
        final decoder = JwtDecoders.fromIssuerLocation(
          'https://issuer.example',
          fetcher: (uri) async {
            fetched.add(uri);
            return uri.path.endsWith('jwks')
                ? jsonEncode({
                    'keys': [keys.rsa.jwk],
                  })
                : metadata('https://issuer.example');
          },
        );
        expect(fetched, isEmpty, reason: 'nothing fetched at startup');
        await decoder.decode(
          keys.token(claims: {'iss': 'https://issuer.example'}),
        );
        expect(fetched.first.path, '/.well-known/openid-configuration');
        await expectLater(
          decoder.decode(keys.token(claims: {'iss': 'https://evil.example'})),
          throwsA(isA<JwtValidationException>()),
        );
        final lying = JwtDecoders.fromIssuerLocation(
          'https://issuer.example',
          fetcher: (uri) async => metadata('https://evil.example'),
        );
        await expectLater(
          lying.decode(keys.token()),
          throwsA(isA<JwtException>()),
        );
      },
    );
  });

  group('the resource server', () {
    Future<void> app(Future<void> Function(MockMvc mvc) body) =>
        withApp(jwtSecurityBeans, (mvc, _) => body(mvc));

    Map<String, String> bearer(String token) => {
      'authorization': 'Bearer $token',
    };

    test(
      'no token: 401 with a bare Bearer challenge',
      () => app((mvc) async {
        await mvc
            .get('/api/me')
            .andExpect(status: 401, headers: {'www-authenticate': 'Bearer'});
      }),
    );

    test(
      'a valid token: the subject and its scopes',
      () => app((mvc) async {
        await mvc
            .get('/api/me', headers: bearer(keys.token()))
            .andExpect(
              status: 200,
              json: {
                'name': 'ada',
                'authorities': ['SCOPE_read'],
              },
            );
      }),
    );

    test(
      'a bad token: 401 invalid_token, as RFC 6750',
      () => app((mvc) async {
        final result = await mvc.get(
          '/api/me',
          headers: bearer(
            keys.token(claims: {'exp': TokenFactory.now() - 600}),
          ),
        );
        expect(result.status, 401);
        final challenge = result.header('www-authenticate')!;
        expect(challenge, startsWith('Bearer error="invalid_token"'));
        expect(challenge, contains('Jwt expired at'));
        expect(
          challenge,
          contains(
            'error_uri="https://tools.ietf.org/html/rfc6750#section-3.1"',
          ),
        );
      }),
    );

    test(
      'a malformed or doubled header: 401 invalid_token',
      () => app((mvc) async {
        for (final header in ['Bearer a b', 'Bearer ', 'Bearer a"b']) {
          final result = await mvc.get(
            '/api/me',
            headers: {'authorization': header},
          );
          expect(result.status, 401, reason: header);
          expect(result.header('www-authenticate'), contains('invalid_token'));
        }
      }),
    );

    test(
      'too few scopes: 403 insufficient_scope',
      () => app((mvc) async {
        final result = await mvc.get(
          '/api/admin',
          headers: bearer(keys.token()),
        );
        expect(result.status, 403);
        expect(
          result.header('www-authenticate'),
          startsWith('Bearer error="insufficient_scope"'),
        );
        await mvc
            .get(
              '/api/admin',
              headers: bearer(keys.token(claims: {'scope': 'read admin'})),
            )
            .andExpect(status: 200);
      }),
    );

    test(
      'stateless: no session cookie, no CSRF needed',
      () => app((mvc) async {
        final result = await mvc.post(
          '/api/data',
          body: 'x',
          headers: bearer(keys.token()),
        );
        expect(result.status, 200);
        expect(result.response.cookies, isEmpty);
      }),
    );
  });
}
