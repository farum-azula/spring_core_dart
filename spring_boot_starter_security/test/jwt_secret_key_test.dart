// The decoder the auto-configuration builds from `secret-key`: tokens
// signed with the shared secret pass, tokens of any other algorithm or key
// do not (algorithm confusion, `alg: none`), the claims are checked as on
// the other decoders, and a wrong combination of properties fails the
// start.
import 'dart:convert';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app/jwt/keys.dart';
import 'app/validators/validators.dart';
import 'support.dart';

const _jwt = 'spring.security.oauth2.resourceserver.jwt';
const _secret = 'a-shared-secret-of-32-characters';

// Signs HS* tokens with [secret] as its UTF-8 bytes, RS* and ES* tokens
// with the test keys.
TokenFactory _tokens([String secret = _secret]) =>
    TokenFactory(testKeys.rsa, testKeys.ec, utf8.encode(secret));

Future<JwtDecoder> _decoder(
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

// What the start failed with, as text.
Future<String> _startupFailure(List<String> properties) async {
  Object? failure;
  await securityRunner(null, properties).runAsync((started) async {
    failure = started.startupFailure;
  });
  expect(failure, isNotNull, reason: 'the application started');
  return '$failure';
}

final Matcher _refused = throwsA(isA<BadJwtException>());

Matcher _invalid(String text) => throwsA(
  isA<JwtValidationException>().having(
    (e) => e.message,
    'message',
    contains(text),
  ),
);

Map<String, String> _bearer(String token) => {'authorization': 'Bearer $token'};

void main() {
  final tokens = _tokens();

  group('a token signed with the shared secret', () {
    test('HS256 by default', () async {
      final decoder = await _decoder(['$_jwt.secret-key=$_secret']);
      final jwt = await decoder.decode(tokens.token(alg: 'HS256'));
      expect(jwt.subject, 'ada');
      expect(decoder, isA<NimbusJwtDecoder>());
      expect((decoder as NimbusJwtDecoder).jwsAlgorithms, {JwsAlgorithm.hs256});
    });

    test('logs the user in through the default chain', () async {
      await withApp(null, properties: ['$_jwt.secret-key=$_secret'], (
        mvc,
        context,
      ) async {
        await mvc
            .perform(request(HttpMethod.get, '/api/me'))
            .andExpect(status: 401);
        final ok = await mvc.perform(
          request(
            HttpMethod.get,
            '/api/me',
            headers: _bearer(tokens.token(alg: 'HS256')),
          ),
        );
        expect(ok.status, 200);
        final refused = await mvc.perform(
          request(
            HttpMethod.get,
            '/api/me',
            headers: _bearer(_tokens('b' * 32).token(alg: 'HS256')),
          ),
        );
        expect(refused.status, 401);
        expect(refused.header('www-authenticate'), contains('invalid_token'));
      });
    });

    test('the algorithm of the properties, and only that one', () async {
      final long = 'k' * 64;
      final hs512 = await _decoder([
        '$_jwt.secret-key=$long',
        '$_jwt.jws-algorithms=HS512',
      ]);
      await hs512.decode(_tokens(long).token(alg: 'HS512'));
      await expectLater(
        hs512.decode(_tokens(long).token(alg: 'HS256')),
        _refused,
      );
      await expectLater(
        hs512.decode(_tokens(long).token(alg: 'HS384')),
        _refused,
      );
      final hs384 = await _decoder([
        '$_jwt.secret-key=$long',
        '$_jwt.jws-algorithms=HS384',
      ]);
      await hs384.decode(_tokens(long).token(alg: 'HS384'));
      await expectLater(
        hs384.decode(_tokens(long).token(alg: 'HS512')),
        _refused,
      );
      // The default stays HS256 with a longer secret.
      final hs256 = await _decoder(['$_jwt.secret-key=$long']);
      await hs256.decode(_tokens(long).token(alg: 'HS256'));
      await expectLater(
        hs256.decode(_tokens(long).token(alg: 'HS512')),
        _refused,
      );
    });

    test('another secret is refused', () async {
      final decoder = await _decoder(['$_jwt.secret-key=$_secret']);
      await expectLater(
        decoder.decode(
          _tokens('another-secret-of-32-characters!').token(
            alg: 'HS256',
          ),
        ),
        _refused,
      );
      // The secret is the text as written: not its trimmed or lower-case
      // form.
      await expectLater(
        decoder.decode(_tokens(_secret.toUpperCase()).token(alg: 'HS256')),
        _refused,
      );
    });

    test('a changed payload is refused', () async {
      final decoder = await _decoder(['$_jwt.secret-key=$_secret']);
      final parts = tokens.token(alg: 'HS256').split('.');
      final forged = b64Json({
        'sub': 'root',
        'exp': TokenFactory.now() + 3600,
      });
      await expectLater(
        decoder.decode('${parts[0]}.$forged.${parts[2]}'),
        _refused,
      );
    });
  });

  test('the secret is in no log record, at trace, from the start on', () async {
    final records = <String>[];
    final handler = SpringLog.handler;
    SpringLog.handler = (_) {};
    SpringLog.level = SpringLogLevel.trace;
    final stop = SpringLog.listen(
      (r) => records.add(
        '${r.message} | ${r.error} | ${r.stackTrace} | ${r.fields}',
      ),
    );
    try {
      await withApp(
        null,
        properties: ['$_jwt.secret-key=$_secret'],
        (mvc, context) async {
          for (final (signer, status) in [
            (tokens, 200),
            (_tokens('b' * 32), 401),
          ]) {
            final result = await mvc.perform(
              request(
                HttpMethod.get,
                '/api/me',
                headers: _bearer(signer.token(alg: 'HS256')),
              ),
            );
            expect(result.status, status);
          }
        },
      );
      // A start that fails because of the secret does not show it either.
      await _startupFailure([
        '$_jwt.secret-key=$_secret',
        '$_jwt.jws-algorithms=HS512',
      ]);
    } finally {
      stop();
      SpringLog.handler = handler;
      SpringLog.level = SpringLogLevel.info;
      SpringLog.resetLevels();
    }
    final text = records.join('\n');
    // The start and both requests were logged.
    expect(text, contains('jwtDecoder'));
    expect(text, contains('Found a bearer token in the request'));
    expect(text, contains('Failed to process authentication request'));
    expect(text, isNot(contains(_secret)));
    expect(text, isNot(contains(base64.encode(utf8.encode(_secret)))));
  });

  group('algorithm confusion', () {
    test('RS256 and ES256 tokens are refused', () async {
      final decoder = await _decoder(['$_jwt.secret-key=$_secret']);
      for (final alg in ['RS256', 'PS256', 'ES256']) {
        await expectLater(
          decoder.decode(tokens.token(alg: alg)),
          _refused,
          reason: alg,
        );
      }
    });

    test('a secret that is a public key verifies no RS256 or ES256 '
        'token of that key', () async {
      // The secret is the text of the public key: an attacker who knows
      // it (it is public) still cannot pass a token off as RS256 or ES256,
      // and the key's own tokens are not accepted either.
      final rsaPublic = testKeys.rsa.jwk['n']! as String;
      final ecPublic = '${testKeys.ec.jwk['x']}${testKeys.ec.jwk['y']}';
      for (final public in [rsaPublic, ecPublic]) {
        final decoder = await _decoder(['$_jwt.secret-key=$public']);
        final signer = _tokens(public);
        for (final alg in ['RS256', 'ES256']) {
          // Signed with the private half.
          await expectLater(
            decoder.decode(signer.token(alg: alg)),
            _refused,
            reason: alg,
          );
          // Named RS256 or ES256, with the MAC of the secret as signature.
          final mac = signer.token(alg: 'HS256', header: {'alg': alg});
          await expectLater(decoder.decode(mac), _refused, reason: '$alg mac');
        }
        // What the decoder was told: these bytes are the HMAC secret.
        await decoder.decode(signer.token(alg: 'HS256'));
      }
    });

    test(
      'a token named HS256 but signed with a private key is refused',
      () async {
        final decoder = await _decoder(['$_jwt.secret-key=$_secret']);
        for (final alg in ['RS256', 'ES256']) {
          await expectLater(
            decoder.decode(tokens.token(alg: alg, header: {'alg': 'HS256'})),
            _refused,
            reason: alg,
          );
        }
      },
    );

    test('alg none is refused, with or without a signature', () async {
      final decoder = await _decoder(['$_jwt.secret-key=$_secret']);
      final claims = b64Json({'sub': 'ada', 'exp': TokenFactory.now() + 3600});
      final signed = tokens.token(alg: 'HS256').split('.')[2];
      for (final alg in ['none', 'None', 'NONE', 'nOnE', '']) {
        final header = b64Json({'alg': alg, 'typ': 'JWT'});
        await expectLater(
          decoder.decode('$header.$claims.'),
          _refused,
          reason: alg,
        );
        await expectLater(
          decoder.decode('$header.$claims.$signed'),
          _refused,
          reason: '$alg signed',
        );
      }
      await expectLater(
        decoder.decode('${b64Json({'typ': 'JWT'})}.$claims.'),
        _refused,
      );
      await withApp(null, properties: ['$_jwt.secret-key=$_secret'], (
        mvc,
        context,
      ) async {
        final header = b64Json({'alg': 'none', 'typ': 'JWT'});
        final result = await mvc.perform(
          request(
            HttpMethod.get,
            '/api/me',
            headers: _bearer('$header.$claims.'),
          ),
        );
        expect(result.status, 401);
      });
    });
  });

  group('the claims of a token signed with the shared secret', () {
    test('type and lifetime', () async {
      final decoder = await _decoder(['$_jwt.secret-key=$_secret']);
      final now = TokenFactory.now();
      await expectLater(
        decoder.decode(
          tokens.token(
            alg: 'HS256',
            claims: {'iat': now - 7200, 'exp': now - 3600},
          ),
        ),
        _invalid('expired'),
      );
      await expectLater(
        decoder.decode(
          tokens.token(alg: 'HS256', header: {'typ': 'logout+jwt'}),
        ),
        _invalid('typ'),
      );
    });

    test('issuer-uri is compared with iss, not asked for keys', () async {
      // Nothing listens there: a discovery would fail every token.
      final decoder = await _decoder([
        '$_jwt.secret-key=$_secret',
        '$_jwt.issuer-uri=http://127.0.0.1:9/issuer',
      ]);
      expect(decoder, isA<NimbusJwtDecoder>());
      await decoder.decode(
        tokens.token(
          alg: 'HS256',
          claims: {'iss': 'http://127.0.0.1:9/issuer'},
        ),
      );
      await expectLater(
        decoder.decode(
          tokens.token(alg: 'HS256', claims: {'iss': 'https://evil.example'}),
        ),
        _invalid('iss'),
      );
      await expectLater(
        decoder.decode(tokens.token(alg: 'HS256')),
        _invalid('iss'),
      );
    });

    test('audiences', () async {
      final decoder = await _decoder([
        '$_jwt.secret-key=$_secret',
        '$_jwt.audiences=api',
      ]);
      await decoder.decode(tokens.token(alg: 'HS256', claims: {'aud': 'api'}));
      await expectLater(
        decoder.decode(tokens.token(alg: 'HS256', claims: {'aud': 'other'})),
        _invalid('aud'),
      );
      await expectLater(
        decoder.decode(tokens.token(alg: 'HS256')),
        _invalid('aud'),
      );
    });

    test('required claims: equal, different, absent', () async {
      final decoder = await _decoder([
        '$_jwt.secret-key=$_secret',
        '$_jwt.required-claims.role=authenticated',
      ]);
      await decoder.decode(
        tokens.token(alg: 'HS256', claims: {'role': 'authenticated'}),
      );
      for (final role in ['anon', 'service_role', 'Authenticated', '']) {
        await expectLater(
          decoder.decode(tokens.token(alg: 'HS256', claims: {'role': role})),
          _invalid('The role claim is not valid'),
          reason: role,
        );
      }
      await expectLater(
        decoder.decode(tokens.token(alg: 'HS256')),
        _invalid('The role claim is not valid'),
      );
    });

    test('a required claim refused is a 401 invalid_token', () async {
      await withApp(
        null,
        properties: [
          '$_jwt.secret-key=$_secret',
          '$_jwt.required-claims.role=authenticated',
        ],
        (mvc, context) async {
          Future<MvcResult> get(Map<String, Object?> claims) => mvc.perform(
            request(
              HttpMethod.get,
              '/api/me',
              headers: _bearer(tokens.token(alg: 'HS256', claims: claims)),
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

    test('the validator beans of the application', () async {
      final decoder = await _decoder([
        '$_jwt.secret-key=$_secret',
      ], configuration: jwtValidatorBeans);
      await decoder.decode(
        tokens.token(
          alg: 'HS256',
          claims: {'tenant': 'shop', 'email_verified': true},
        ),
      );
      await expectLater(
        decoder.decode(
          tokens.token(
            alg: 'HS256',
            claims: {'tenant': 'other', 'email_verified': true},
          ),
        ),
        _invalid('The tenant is not shop'),
      );
      await expectLater(
        decoder.decode(tokens.token(alg: 'HS256', claims: {'tenant': 'shop'})),
        _invalid('The email_verified claim is not valid'),
      );
      // They are added: the checks of the properties stay.
      final now = TokenFactory.now();
      await expectLater(
        decoder.decode(
          tokens.token(
            alg: 'HS256',
            claims: {
              'tenant': 'shop',
              'email_verified': true,
              'iat': now - 7200,
              'exp': now - 3600,
            },
          ),
        ),
        _invalid('expired'),
      );
    });
  });

  group('the start fails', () {
    test('with a shared secret and jwk-set-uri', () async {
      final failure = await _startupFailure([
        '$_jwt.secret-key=$_secret',
        '$_jwt.jwk-set-uri=https://issuer.example/jwks',
      ]);
      expect(failure, contains('$_jwt.secret-key'));
      expect(failure, contains('$_jwt.jwk-set-uri'));
      expect(failure, isNot(contains(_secret)));
    });

    test('with an algorithm that is not HS256, HS384 or HS512', () async {
      for (final names in ['RS256', 'ES256', 'PS512', 'HS256,RS256', 'none']) {
        final failure = await _startupFailure([
          '$_jwt.secret-key=$_secret',
          '$_jwt.jws-algorithms=$names',
        ]);
        expect(failure, contains('$_jwt.jws-algorithms'), reason: names);
        expect(failure, isNot(contains(_secret)), reason: names);
      }
    });

    test('with more than one algorithm', () async {
      final failure = await _startupFailure([
        '$_jwt.secret-key=${'k' * 64}',
        '$_jwt.jws-algorithms=HS256,HS512',
      ]);
      expect(failure, contains('$_jwt.jws-algorithms'));
      expect(failure, contains('one algorithm'));
    });

    test('with a secret shorter than the hash', () async {
      for (final (length, algorithm) in [
        (31, 'HS256'),
        (47, 'HS384'),
        (63, 'HS512'),
      ]) {
        final secret = 'k' * length;
        final failure = await _startupFailure([
          '$_jwt.secret-key=$secret',
          '$_jwt.jws-algorithms=$algorithm',
        ]);
        expect(failure, contains('$_jwt.secret-key'), reason: algorithm);
        expect(failure, contains('$length bytes'), reason: algorithm);
        expect(failure, isNot(contains(secret)), reason: algorithm);
      }
      final byDefault = await _startupFailure(['$_jwt.secret-key=short']);
      expect(byDefault, contains('$_jwt.secret-key'));
      expect(byDefault, contains('HS256'));
    });

    test(
      'not with a blank secret: it is not set, no resource server',
      () async {
        await securityRunner(null, [
          '$_jwt.secret-key= ',
          'spring.security.user.password=pw',
        ]).runAsync((started) async {
          expect(started.startupFailure, isNull);
          expect(started.context.containsBean('jwtDecoder'), isFalse);
          expect(
            started.context.containsBean('inMemoryUserDetailsManager'),
            isTrue,
          );
        });
      },
    );
  });
}
