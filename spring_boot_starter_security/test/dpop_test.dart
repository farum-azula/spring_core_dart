// DPoP-bound access tokens (RFC 9449) on the resource server: the proofs
// checked through the real filter chain of the JWT test application, and
// the attacks of docs/security.md as tests (a replayed proof, another key,
// a wrong htm or htu, a stale or future iat, a missing or wrong ath, a
// bound token sent as Bearer, alg none and HS256 proofs, a private key in
// the proof, oversized and doubled proofs).
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app/jwt/jwt.dart';
import 'app/jwt/keys.dart';
import 'chain_support.dart';
import 'dpop_support.dart';
import 'support.dart';

const _url = 'http://localhost/api/me';

Future<void> _app(Future<void> Function(MockMvc mvc) body) =>
    withApp(jwtSecurityBeans, (mvc, _) => body(mvc));

/// Expects a 401 whose DPoP challenge names [error].
Future<void> _refused(
  ResultActions sent,
  String error, {
  String? reason,
  String? description,
}) async {
  final result = await sent;
  expect(result.status, 401, reason: reason);
  final challenge = result.header('www-authenticate') ?? '';
  expect(challenge, startsWith('DPoP error="$error"'), reason: reason);
  // The DPoP errors have no URI, and none is made up (a bad token may
  // link RFC 6750's, as Spring's).
  if (error != 'invalid_token') {
    expect(challenge, isNot(contains('error_uri')), reason: reason);
  }
  expect(
    challenge,
    endsWith('algs="RS256 RS384 RS512 PS256 PS384 PS512 ES256 ES384 ES512"'),
    reason: reason,
  );
  if (description != null) {
    expect(challenge, contains(description), reason: reason);
  }
}

final class _Beans implements BeanFactory {
  _Beans(this.beans);

  final List<Object> beans;

  @override
  ObjectProvider<T> getBeanProvider<T extends Object>({String? qualifier}) =>
      _Provider<T>([
        for (final bean in beans)
          if (bean is T) bean,
      ]);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Provider<T extends Object> implements ObjectProvider<T> {
  _Provider(this.found);

  final List<T> found;

  @override
  T? getIfUnique([T Function()? defaultSupplier]) =>
      found.length == 1 ? found.single : defaultSupplier?.call();

  @override
  List<T> orderedList() => found;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _BrokenCache implements DPoPProofJtiCache {
  @override
  Future<bool> markUsed(
    String jti,
    DateTime expiresAt, {
    required String jwkThumbprint,
  }) => Future.error(StateError('the store is down'));
}

void main() {
  final client = ProofSigner.ec();

  group('through the filter chain', () {
    test(
      'a valid DPoP request: logged in as for Bearer',
      () => _app((mvc) async {
        final token = boundToken(client);
        await mvc
            .get(
              '/api/me',
              headers: dPoPHeaders(
                token,
                client.proof(accessToken: token),
              ),
            )
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
      'every key type and algorithm of a client',
      () => _app((mvc) async {
        final rsa = ProofSigner.rsa(RsaTestKey.generate(kid: 'client'));
        for (final (signer, alg) in [
          (ProofSigner.ec(crv: 'P-384'), 'ES384'),
          (ProofSigner.ec(crv: 'P-521'), 'ES512'),
          (rsa, 'RS256'),
          (rsa, 'PS256'),
          (rsa, 'RS512'),
        ]) {
          final token = boundToken(signer);
          await mvc
              .get(
                '/api/me',
                headers: dPoPHeaders(
                  token,
                  signer.proof(accessToken: token, alg: alg),
                ),
              )
              .andExpect(status: 200);
        }
      }),
    );

    test(
      'the scheme is case-insensitive; a POST needs a POST proof',
      () => _app((mvc) async {
        final token = boundToken(client);
        await mvc
            .post(
              '/api/data',
              body: 'x',
              headers: {
                'authorization': 'dpop $token',
                'dpop': client.proof(
                  method: 'POST',
                  url: 'http://localhost/api/data',
                  accessToken: token,
                ),
              },
            )
            .andExpect(status: 200);
      }),
    );

    test(
      'too few scopes is a 403, as for Bearer',
      () => _app((mvc) async {
        final token = boundToken(client);
        final result = await mvc.get(
          '/api/admin',
          headers: dPoPHeaders(
            token,
            client.proof(
              url: 'http://localhost/api/admin',
              accessToken: token,
            ),
          ),
        );
        expect(result.status, 403);
      }),
    );
  });

  group('attacks', () {
    test(
      'a replayed proof is refused (jti)',
      () => _app((mvc) async {
        final token = boundToken(client);
        final proof = client.proof(accessToken: token);
        await mvc
            .get('/api/me', headers: dPoPHeaders(token, proof))
            .andExpect(status: 200);
        await _refused(
          mvc.get('/api/me', headers: dPoPHeaders(token, proof)),
          'invalid_dpop_proof',
          description: 'jti',
        );
        // A new proof with the same jti: still a replay.
        final jti = randomJti();
        await mvc
            .get(
              '/api/me',
              headers: dPoPHeaders(
                token,
                client.proof(accessToken: token, jti: jti),
              ),
            )
            .andExpect(status: 200);
        await _refused(
          mvc.get(
            '/api/me',
            headers: dPoPHeaders(
              token,
              client.proof(accessToken: token, jti: jti),
            ),
          ),
          'invalid_dpop_proof',
        );
      }),
    );

    test(
      'a stolen token with a proof of another key is refused (cnf.jkt)',
      () => _app((mvc) async {
        final token = boundToken(client);
        final thief = ProofSigner.ec();
        await _refused(
          mvc.get(
            '/api/me',
            headers: dPoPHeaders(token, thief.proof(accessToken: token)),
          ),
          'invalid_dpop_proof',
          description: 'jkt',
        );
      }),
    );

    test(
      "the client's jwk with another key's signature is refused",
      () => _app((mvc) async {
        final token = boundToken(client);
        await _refused(
          mvc.get(
            '/api/me',
            headers: dPoPHeaders(
              token,
              client.proof(accessToken: token, signWith: ProofSigner.ec()),
            ),
          ),
          'invalid_dpop_proof',
          description: 'signature',
        );
      }),
    );

    test(
      'a proof of another method is refused (htm)',
      () => _app((mvc) async {
        final token = boundToken(client);
        for (final method in ['POST', 'get', 'GET ', 'HEAD']) {
          await _refused(
            mvc.get(
              '/api/me',
              headers: dPoPHeaders(
                token,
                client.proof(method: method, accessToken: token),
              ),
            ),
            'invalid_dpop_proof',
            reason: method,
            description: 'htm',
          );
        }
      }),
    );

    test(
      'htu: compared after normalization, query and fragment ignored',
      () => _app((mvc) async {
        final token = boundToken(client);
        for (final url in [
          'HTTP://LOCALHOST/api/me',
          'http://localhost:80/api/me',
          'http://localhost/api/me?page=2',
          'http://localhost/api/me#top',
          'http://localhost/api/%6De',
          'http://localhost/api/./x/../me',
        ]) {
          await mvc
              .get(
                '/api/me',
                headers: dPoPHeaders(
                  token,
                  client.proof(url: url, accessToken: token),
                ),
              )
              .andExpect(status: 200);
        }
      }),
    );

    test(
      'a proof for another URL is refused (htu)',
      () => _app((mvc) async {
        final token = boundToken(client);
        for (final url in [
          'https://localhost/api/me',
          'http://localhost:8080/api/me',
          'http://evil.example/api/me',
          'http://localhost/api/me/',
          'http://localhost/API/me',
          'http://localhost/api/admin',
          'http://localhost/api%2Fme',
          'http://user@localhost/api/me',
          '/api/me',
          'localhost/api/me',
        ]) {
          await _refused(
            mvc.get(
              '/api/me',
              headers: dPoPHeaders(
                token,
                client.proof(url: url, accessToken: token),
              ),
            ),
            'invalid_dpop_proof',
            reason: url,
          );
        }
      }),
    );

    test(
      'a stale or future proof is refused (iat), within 30 s accepted',
      () => _app((mvc) async {
        final token = boundToken(client);
        final now = TokenFactory.now();
        for (final iat in [now - 120, now + 120, now - 3600, 0]) {
          await _refused(
            mvc.get(
              '/api/me',
              headers: dPoPHeaders(
                token,
                client.proof(accessToken: token, iat: iat),
              ),
            ),
            'invalid_dpop_proof',
            reason: '$iat',
            description: 'iat',
          );
        }
        for (final iat in [now - 20, now + 20]) {
          await mvc
              .get(
                '/api/me',
                headers: dPoPHeaders(
                  token,
                  client.proof(accessToken: token, iat: iat),
                ),
              )
              .andExpect(status: 200);
        }
      }),
    );

    test(
      'a proof without ath, or for another token, is refused',
      () => _app((mvc) async {
        final token = boundToken(client);
        await _refused(
          mvc.get('/api/me', headers: dPoPHeaders(token, client.proof())),
          'invalid_dpop_proof',
          description: 'ath claim is required',
        );
        final other = boundToken(client, claims: {'jti': 'other'});
        await _refused(
          mvc.get(
            '/api/me',
            headers: dPoPHeaders(token, client.proof(accessToken: other)),
          ),
          'invalid_dpop_proof',
          description: 'ath claim is not valid',
        );
        await _refused(
          mvc.get(
            '/api/me',
            headers: dPoPHeaders(
              token,
              client.proof(claims: {'ath': 123}),
            ),
          ),
          'invalid_dpop_proof',
        );
      }),
    );

    test(
      'a bound token sent as Bearer is refused, with or without a proof',
      () => _app((mvc) async {
        final token = boundToken(client);
        for (final headers in [
          {'authorization': 'Bearer $token'},
          {
            'authorization': 'Bearer $token',
            'dpop': client.proof(accessToken: token),
          },
        ]) {
          final result = await mvc.get('/api/me', headers: headers);
          expect(result.status, 401);
          expect(
            result.header('www-authenticate'),
            startsWith('Bearer error="invalid_token"'),
          );
        }
      }),
    );

    test(
      'a bound token with an unreadable cnf.jkt is still refused as Bearer',
      () => _app((mvc) async {
        final token = testKeys.token(
          claims: {
            'cnf': {'jkt': 42},
          },
        );
        final result = await mvc.get(
          '/api/me',
          headers: {'authorization': 'Bearer $token'},
        );
        expect(result.status, 401);
      }),
    );

    test(
      'an unbound token: Bearer works (a DPoP header ignored, as in '
      'Spring), the DPoP scheme is refused',
      () => _app((mvc) async {
        final token = testKeys.token();
        await mvc
            .get(
              '/api/me',
              headers: {
                'authorization': 'Bearer $token',
                'dpop': client.proof(accessToken: token),
              },
            )
            .andExpect(status: 200);
        await _refused(
          mvc.get(
            '/api/me',
            headers: dPoPHeaders(token, client.proof(accessToken: token)),
          ),
          'invalid_dpop_proof',
          description: 'jkt claim is required',
        );
      }),
    );

    test(
      'alg none and HS256 proofs are refused',
      () => _app((mvc) async {
        final token = boundToken(client);
        await _refused(
          mvc.get(
            '/api/me',
            headers: dPoPHeaders(
              token,
              client.proof(accessToken: token, alg: 'none'),
            ),
          ),
          'invalid_dpop_proof',
        );
        // HS256 with the shared secret in the jwk header, and HS256 with
        // the client's public key as the secret: neither verifies.
        for (final jwk in [
          {'kty': 'oct', 'k': b64(testKeys.secret)},
          client.publicJwk,
        ]) {
          await _refused(
            mvc.get(
              '/api/me',
              headers: dPoPHeaders(
                token,
                client.proof(
                  accessToken: token,
                  alg: 'HS256',
                  header: {'jwk': jwk},
                ),
              ),
            ),
            'invalid_dpop_proof',
            description: 'alg',
          );
        }
      }),
    );

    test(
      'a private key in the jwk header is refused',
      () => _app((mvc) async {
        final token = boundToken(client);
        for (final member in ['d', 'p', 'q', 'dp', 'dq', 'qi', 'oth', 'k']) {
          await _refused(
            mvc.get(
              '/api/me',
              headers: dPoPHeaders(
                token,
                client.proof(
                  accessToken: token,
                  header: {
                    'jwk': {...client.publicJwk, member: client.privateD},
                  },
                ),
              ),
            ),
            'invalid_dpop_proof',
            reason: member,
            description: 'not a public key',
          );
        }
      }),
    );

    test(
      'a wrong, missing or unusable jwk is refused',
      () => _app((mvc) async {
        final token = boundToken(client);
        final small = ProofSigner.rsa(
          RsaTestKey.generate(bits: 1024, kid: 'small'),
        );
        final jwk = client.publicJwk;
        for (final (name, proof) in [
          ('no jwk', client.proof(accessToken: token, header: {'jwk': null})),
          (
            'jwk as text',
            client.proof(accessToken: token, header: {'jwk': 'x'}),
          ),
          (
            'the issuer key by kid instead',
            client.proof(
              accessToken: token,
              header: {'jwk': null, 'kid': testKeys.ec.kid},
            ),
          ),
          (
            'point off the curve',
            client.proof(
              accessToken: token,
              header: {
                'jwk': {...jwk, 'y': jwk['x']},
              },
            ),
          ),
          (
            'a curve of another algorithm',
            client.proof(
              accessToken: token,
              alg: 'ES384',
              header: {'jwk': jwk},
            ),
          ),
          (
            'RSA under 2048 bits',
            small.proof(accessToken: boundToken(small)),
          ),
          (
            'jwk for encryption',
            client.proof(
              accessToken: token,
              header: {
                'jwk': {...jwk, 'use': 'enc'},
              },
            ),
          ),
          (
            'jwk restricted to another alg',
            client.proof(
              accessToken: token,
              header: {
                'jwk': {...jwk, 'alg': 'ES512'},
              },
            ),
          ),
        ]) {
          await _refused(
            mvc.get('/api/me', headers: dPoPHeaders(token, proof)),
            'invalid_dpop_proof',
            reason: name,
          );
        }
      }),
    );

    test(
      'a proof of another type, or not a proof at all, is refused',
      () => _app((mvc) async {
        final token = boundToken(client);
        for (final (name, proof) in [
          (
            'typ JWT',
            client.proof(accessToken: token, header: {'typ': 'JWT'}),
          ),
          ('no typ', client.proof(accessToken: token, header: {'typ': null})),
          (
            'typ in upper case',
            client.proof(accessToken: token, header: {'typ': 'DPOP+JWT'}),
          ),
          ('the access token itself', token),
          ('garbage', 'a.b.c'),
          (
            'a crit header',
            client.proof(
              accessToken: token,
              header: {
                'crit': ['exp'],
              },
            ),
          ),
        ]) {
          await _refused(
            mvc.get('/api/me', headers: dPoPHeaders(token, proof)),
            'invalid_dpop_proof',
            reason: name,
          );
        }
      }),
    );

    test(
      'mistyped or missing claims are refused',
      () => _app((mvc) async {
        final token = boundToken(client);
        for (final claims in <Map<String, Object?>>[
          {'jti': null},
          {'jti': 7},
          {'htm': null},
          {'htu': null},
          {
            'htu': ['http://localhost/api/me'],
          },
          {'iat': null},
          {'iat': '${TokenFactory.now()}'},
        ]) {
          await _refused(
            mvc.get(
              '/api/me',
              headers: dPoPHeaders(
                token,
                client.proof(accessToken: token, claims: claims),
              ),
            ),
            'invalid_dpop_proof',
            reason: '$claims',
          );
        }
      }),
    );

    test(
      'an oversized proof is refused before decoding',
      () => _app((mvc) async {
        final token = boundToken(client);
        await _refused(
          mvc.get(
            '/api/me',
            headers: dPoPHeaders(
              token,
              client.proof(
                accessToken: token,
                claims: {'pad': 'x' * maxDPoPProofLength},
              ),
            ),
          ),
          'invalid_request',
        );
      }),
    );

    test(
      'a proof of exactly the largest length reaches the checks',
      () => _app((mvc) async {
        final token = boundToken(client);
        await _refused(
          mvc.get(
            '/api/me',
            headers: dPoPHeaders(token, 'x' * maxDPoPProofLength),
          ),
          'invalid_dpop_proof',
        );
        await _refused(
          mvc.get(
            '/api/me',
            headers: dPoPHeaders(token, 'x' * (maxDPoPProofLength + 1)),
          ),
          'invalid_request',
        );
      }),
    );

    test(
      'no DPoP header, an empty one, or two: invalid_request',
      () => _app((mvc) async {
        final token = boundToken(client);
        await _refused(
          mvc.get('/api/me', headers: {'authorization': 'DPoP $token'}),
          'invalid_request',
        );
        await _refused(
          mvc.get(
            '/api/me',
            headers: {'authorization': 'DPoP $token', 'dpop': ''},
          ),
          'invalid_request',
        );
        final second = client.proof(accessToken: token);
        await _refused(
          mvc.perform(
            request(
              HttpMethod.get,
              '/api/me',
              headers: dPoPHeaders(token, client.proof(accessToken: token)),
              processors: [
                FunctionRequestPostProcessor(
                  (r) => r..headers.add('DPoP', second),
                ),
              ],
            ),
          ),
          'invalid_request',
        );
      }),
    );

    test(
      'a malformed DPoP authorization header: invalid_token',
      () => _app((mvc) async {
        for (final header in ['DPoP', 'DPoP ', 'DPoP a b', 'DPoP a"b']) {
          await _refused(
            mvc.get(
              '/api/me',
              headers: {'authorization': header, 'dpop': client.proof()},
            ),
            'invalid_token',
            reason: header,
          );
        }
      }),
    );

    test(
      'two Authorization headers (DPoP and Bearer): refused',
      () => _app((mvc) async {
        final token = boundToken(client);
        final result = await mvc.perform(
          request(
            HttpMethod.get,
            '/api/me',
            headers: dPoPHeaders(token, client.proof(accessToken: token)),
            processors: [
              FunctionRequestPostProcessor(
                (r) => r..headers.add('Authorization', 'Bearer $token'),
              ),
            ],
          ),
        );
        expect(result.status, 401);
      }),
    );

    test(
      'an invalid access token with a valid proof: invalid_token',
      () => _app((mvc) async {
        for (final token in [
          boundToken(client, claims: {'exp': TokenFactory.now() - 600}),
          '${boundToken(client)}x',
          boundToken(ProofSigner.ec()).replaceRange(0, 1, 'x'),
        ]) {
          await _refused(
            mvc.get(
              '/api/me',
              headers: dPoPHeaders(token, client.proof(accessToken: token)),
            ),
            'invalid_token',
          );
        }
      }),
    );

    test(
      'the refusal names no token, proof or key',
      () => _app((mvc) async {
        final token = boundToken(client);
        final proof = client.proof(accessToken: token, url: 'http://x/y');
        final result = await mvc.get(
          '/api/me',
          headers: dPoPHeaders(token, proof),
        );
        final everything =
            '${result.header('www-authenticate')} ${result.response.bodyText}';
        for (final secret in [
          token,
          proof,
          client.thumbprint,
          client.publicJwk['x']! as String,
        ]) {
          expect(everything, isNot(contains(secret)));
        }
      }),
    );
  });

  group('DPoPProofJwtDecoderFactory', () {
    final now = DateTime.utc(2026, 10, 30, 12);
    final token = boundToken(client);
    DPoPProofContext context(String proof, {String? accessToken}) =>
        DPoPProofContext(
          proof,
          method: 'GET',
          targetUri: Uri.parse(_url),
          accessToken: accessToken,
        );
    int seconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

    test('the clock skew is configurable', () async {
      final factory = DPoPProofJwtDecoderFactory(
        clockSkew: const Duration(seconds: 5),
        clock: () => now,
      );
      final late = client.proof(accessToken: token, iat: seconds(now) - 10);
      await expectLater(
        factory.createDecoder(context(late, accessToken: token)).decode(late),
        throwsA(isA<BadJwtException>()),
      );
      final fresh = client.proof(accessToken: token, iat: seconds(now) - 4);
      final jwt = await factory
          .createDecoder(context(fresh, accessToken: token))
          .decode(fresh);
      expect(jwt.headers['jwk'], client.publicJwk);
    });

    test(
      'without an access token (a token endpoint) ath is not needed',
      () async {
        final factory = DPoPProofJwtDecoderFactory(clock: () => now);
        final proof = client.proof(iat: seconds(now));
        await factory.createDecoder(context(proof)).decode(proof);
      },
    );

    test('HMAC among the algorithms is refused, even beside RS256', () {
      expect(
        () => DPoPProofJwtDecoderFactory(
          jwsAlgorithms: {JwsAlgorithm.rs256, JwsAlgorithm.hs256},
        ),
        throwsArgumentError,
      );
      expect(
        () => DPoPProofJwtDecoderFactory(jwsAlgorithms: const {}),
        throwsArgumentError,
      );
    });

    // A proof whose signature is junk: the message tells whether its key
    // was accepted (the signature fails) or refused before.
    Future<String> failure(String proof) async {
      try {
        await DPoPProofJwtDecoderFactory(
          clock: () => now,
        ).createDecoder(context(proof)).decode(proof);
      } on BadJwtException catch (e) {
        return e.message;
      }
      fail('accepted');
    }

    test('a proof of exactly the largest length is read', () async {
      expect(
        await failure('x' * maxDPoPProofLength),
        isNot(contains('too long')),
      );
      expect(
        await failure('x' * (maxDPoPProofLength + 1)),
        contains('too long'),
      );
    });

    test('the RSA keys of proofs: 2048 to 8192 bits, an odd exponent '
        'of at most 64 bits', () async {
      String b64Int(BigInt value) {
        var hex = value.toRadixString(16);
        if (hex.length.isOdd) {
          hex = '0$hex';
        }
        return b64([
          for (var i = 0; i < hex.length; i += 2)
            int.parse(hex.substring(i, i + 2), radix: 16),
        ]);
      }

      String proofWith(int bits, BigInt exponent) => [
        b64Json({
          'typ': 'dpop+jwt',
          'alg': 'RS256',
          'jwk': {
            'kty': 'RSA',
            // The top bit set: exactly [bits] bits; odd.
            'n': b64Int((BigInt.one << (bits - 1)) | BigInt.one),
            'e': b64Int(exponent),
          },
        }),
        b64Json({
          'jti': randomJti(),
          'htm': 'GET',
          'htu': _url,
          'iat': seconds(now),
        }),
        b64([1, 2, 3]),
      ].join('.');

      const accepted = 'signature is not valid';
      const refused = 'not a supported public key';
      final f4 = BigInt.from(65537);
      expect(await failure(proofWith(2048, f4)), contains(accepted));
      expect(await failure(proofWith(8192, f4)), contains(accepted));
      expect(await failure(proofWith(2047, f4)), contains(refused));
      expect(await failure(proofWith(8193, f4)), contains(refused));
      expect(
        await failure(proofWith(2048, BigInt.from(65536))),
        contains(refused),
      );
      expect(await failure(proofWith(2048, BigInt.one)), contains(refused));
      expect(
        await failure(proofWith(2048, (BigInt.one << 64) + BigInt.one)),
        contains(refused),
      );
      expect(
        await failure(proofWith(2048, (BigInt.one << 63) + BigInt.one)),
        contains(accepted),
      );
    });

    test('a store that fails refuses the proof (fail closed)', () async {
      final factory = DPoPProofJwtDecoderFactory(
        clock: () => now,
        jtiCache: _BrokenCache(),
      );
      final proof = client.proof(accessToken: token, iat: seconds(now));
      await expectLater(
        factory.createDecoder(context(proof, accessToken: token)).decode(proof),
        throwsA(isA<JwtException>()),
      );
    });

    test('a jti is recorded only for a proof that passed the rest', () async {
      final cache = InMemoryDPoPProofJtiCache(clock: () => now);
      final factory = DPoPProofJwtDecoderFactory(
        clock: () => now,
        jtiCache: cache,
      );
      final bad = client.proof(
        accessToken: token,
        iat: seconds(now),
        jti: 'j',
        method: 'POST',
      );
      await expectLater(
        factory.createDecoder(context(bad, accessToken: token)).decode(bad),
        throwsA(isA<BadJwtException>()),
      );
      expect(cache.size, 0);
      final good = client.proof(
        accessToken: token,
        iat: seconds(now),
        jti: 'j',
      );
      await factory
          .createDecoder(context(good, accessToken: token))
          .decode(good);
      expect(cache.size, 1);
    });

    test('custom validators replace the claim checks', () async {
      final factory = DPoPProofJwtDecoderFactory(
        clock: () => now,
        jwtValidatorFactory: (context) => DelegatingOAuth2TokenValidator([
          DPoPProofJwtDecoderFactory.defaultValidator(
            context,
            clock: () => now,
          ),
          JwtClaimValidator('nonce', (value) => value == 'n-1'),
        ]),
      );
      final without = client.proof(accessToken: token, iat: seconds(now));
      await expectLater(
        factory
            .createDecoder(context(without, accessToken: token))
            .decode(without),
        throwsA(isA<JwtValidationException>()),
      );
      final withNonce = client.proof(
        accessToken: token,
        iat: seconds(now),
        claims: {'nonce': 'n-1'},
      );
      await factory
          .createDecoder(context(withNonce, accessToken: token))
          .decode(withNonce);
    });

    test('HMAC or no algorithms cannot be configured', () {
      expect(
        () => DPoPProofJwtDecoderFactory(jwsAlgorithms: {JwsAlgorithm.hs256}),
        throwsArgumentError,
      );
      expect(
        () => DPoPProofJwtDecoderFactory(jwsAlgorithms: const {}),
        throwsArgumentError,
      );
    });

    test(
      'a bean replaces the default, its algorithms in the challenge',
      () async {
        final chain =
            HttpSecurity(
                  _Beans([
                    DPoPProofJwtDecoderFactory(
                      jwsAlgorithms: {JwsAlgorithm.es256},
                    ),
                    NimbusJwtDecoder.withJwkSource(
                      StaticJwkSource([testKeys.rsa.verificationKey]),
                    ),
                  ]),
                )
                .authorizeHttpRequests((a) => a.anyRequest().authenticated())
                .oauth2ResourceServer((s) => s.jwt())
                .build();
        final rsa = ProofSigner.rsa(RsaTestKey.generate(kid: 'client'));
        final rsaToken = boundToken(rsa);
        final refused = await ChainClient(chain).get(
          '/api/me',
          headers: dPoPHeaders(
            rsaToken,
            rsa.proof(accessToken: rsaToken),
          ),
        );
        expect(refused.status, 401);
        expect(
          refused.header('www-authenticate'),
          allOf(contains('invalid_dpop_proof'), endsWith('algs="ES256"')),
        );
        final ecToken = boundToken(client);
        final accepted = await ChainClient(chain).get(
          '/api/me',
          headers: dPoPHeaders(ecToken, client.proof(accessToken: ecToken)),
        );
        expect(accepted.reached, isTrue);
        expect(accepted.authentication, isA<JwtAuthenticationToken>());
      },
    );
  });

  group('InMemoryDPoPProofJtiCache', () {
    var now = DateTime.utc(2026);
    setUp(() => now = DateTime.utc(2026));

    test('an id is refused until it expires', () {
      final cache = InMemoryDPoPProofJtiCache(clock: () => now);
      final expiry = now.add(const Duration(minutes: 1));
      expect(cache.markUsed('a', expiry, jwkThumbprint: 'k'), isTrue);
      expect(cache.markUsed('a', expiry, jwkThumbprint: 'k'), isFalse);
      expect(cache.markUsed('b', expiry, jwkThumbprint: 'k'), isTrue);
      now = now.add(const Duration(minutes: 2));
      expect(
        cache.markUsed(
          'a',
          now.add(const Duration(minutes: 1)),
          jwkThumbprint: 'k',
        ),
        isTrue,
      );
    });

    test('full: new ids are refused until old ones expire', () {
      final cache = InMemoryDPoPProofJtiCache(maximumSize: 2, clock: () => now);
      final expiry = now.add(const Duration(minutes: 1));
      expect(cache.markUsed('a', expiry, jwkThumbprint: 'k'), isTrue);
      expect(cache.markUsed('b', expiry, jwkThumbprint: 'k'), isTrue);
      expect(cache.markUsed('c', expiry, jwkThumbprint: 'k'), isFalse);
      expect(cache.markUsed('a', expiry, jwkThumbprint: 'k'), isFalse);
      now = now.add(const Duration(minutes: 2));
      expect(
        cache.markUsed(
          'c',
          now.add(const Duration(minutes: 1)),
          jwkThumbprint: 'k',
        ),
        isTrue,
      );
      expect(cache.size, 1);
    });

    test('one key cannot fill the cache for the others', () {
      final cache = InMemoryDPoPProofJtiCache(
        maximumPerKey: 2,
        clock: () => now,
      );
      final expiry = now.add(const Duration(seconds: 30));
      expect(cache.markUsed('a', expiry, jwkThumbprint: 'k1'), isTrue);
      expect(cache.markUsed('b', expiry, jwkThumbprint: 'k1'), isTrue);
      expect(cache.markUsed('c', expiry, jwkThumbprint: 'k1'), isFalse);
      expect(cache.markUsed('c', expiry, jwkThumbprint: 'k2'), isTrue);
      now = now.add(const Duration(minutes: 1));
      final later = now.add(const Duration(seconds: 30));
      expect(cache.markUsed('d', later, jwkThumbprint: 'k1'), isTrue);
    });

    test('sizes of 1 are allowed', () {
      final cache = InMemoryDPoPProofJtiCache(
        maximumSize: 1,
        maximumPerKey: 1,
        clock: () => now,
      );
      final expiry = now.add(const Duration(minutes: 1));
      expect(cache.markUsed('a', expiry, jwkThumbprint: 'k1'), isTrue);
      expect(cache.markUsed('b', expiry, jwkThumbprint: 'k2'), isFalse);
    });

    test('expired ids are dropped every 10 seconds, not before', () {
      final cache = InMemoryDPoPProofJtiCache(clock: () => now);
      final later = now.add(const Duration(minutes: 1));
      // The first call drops nothing but starts the 10 seconds.
      cache.markUsed(
        'a',
        now.add(const Duration(seconds: 1)),
        jwkThumbprint: 'k',
      );
      now = now.add(const Duration(seconds: 5));
      cache.markUsed('b', later, jwkThumbprint: 'k');
      expect(cache.size, 2, reason: "'a' expired, but kept until the purge");
      now = now.add(const Duration(seconds: 5)); // 10 seconds exactly
      cache.markUsed('c', later, jwkThumbprint: 'k');
      expect(cache.size, 2, reason: "'a' dropped");
    });

    test('full: expired ids are dropped at once, 50 ms after the last '
        'purge', () {
      final cache = InMemoryDPoPProofJtiCache(maximumSize: 2, clock: () => now);
      final soon = now.add(const Duration(milliseconds: 10));
      expect(cache.markUsed('a', soon, jwkThumbprint: 'k1'), isTrue);
      expect(cache.markUsed('b', soon, jwkThumbprint: 'k2'), isTrue);
      now = now.add(const Duration(milliseconds: 50));
      final later = now.add(const Duration(minutes: 1));
      expect(cache.markUsed('c', later, jwkThumbprint: 'k3'), isTrue);
      expect(cache.size, 1);
    });

    test('a key at its limit: its expired ids are dropped at once', () {
      final cache = InMemoryDPoPProofJtiCache(
        maximumPerKey: 2,
        clock: () => now,
      );
      final soon = now.add(const Duration(milliseconds: 10));
      expect(cache.markUsed('a', soon, jwkThumbprint: 'k'), isTrue);
      expect(cache.markUsed('b', soon, jwkThumbprint: 'k'), isTrue);
      now = now.add(const Duration(milliseconds: 50));
      final later = now.add(const Duration(minutes: 1));
      expect(cache.markUsed('c', later, jwkThumbprint: 'k'), isTrue);
    });

    test('a size under 1 is refused', () {
      expect(
        () => InMemoryDPoPProofJtiCache(maximumSize: 0),
        throwsArgumentError,
      );
      expect(
        () => InMemoryDPoPProofJtiCache(maximumPerKey: 0),
        throwsArgumentError,
      );
    });
  });

  group('normalizedDPoPTarget', () {
    test('RFC 3986 normalization, query and fragment dropped', () {
      for (final (url, expected) in [
        ('HTTPS://API.Example.COM:443/a?b#c', 'https://api.example.com/a'),
        ('http://x', 'http://x/'),
        ('http://x:8080/%7e/%2f', 'http://x:8080/~/%2F'),
        ('https://x:80/', 'https://x:80/'),
      ]) {
        expect(normalizedDPoPTarget(Uri.parse(url)), expected, reason: url);
      }
    });

    test('not http(s), no host or user information: no target', () {
      for (final url in ['ftp://x/', '/a', 'https://u:p@x/', 'urn:a']) {
        expect(normalizedDPoPTarget(Uri.parse(url)), isNull, reason: url);
      }
    });
  });

  group('Jwt.confirmation and jwkThumbprint', () {
    Jwt jwt(Map<String, Object?> claims) =>
        Jwt('t', headers: const {'alg': 'RS256'}, claims: claims);

    test('cnf.jkt of a bound token', () {
      final bound = jwt({
        'cnf': {'jkt': 'abc'},
      });
      expect(bound.confirmation, {'jkt': 'abc'});
      expect(bound.jwkThumbprint, 'abc');
    });

    test('not bound: no cnf, or cnf without jkt', () {
      expect(jwt(const {}).jwkThumbprint, isNull);
      expect(jwt(const {'cnf': 'x'}).confirmation, isNull);
      expect(
        jwt(const {
          'cnf': {'x5t#S256': 'y'},
        }).jwkThumbprint,
        isNull,
      );
    });

    test('a jkt that is not text matches no key but counts as bound', () {
      expect(
        jwt(const {
          'cnf': {'jkt': 1},
        }).jwkThumbprint,
        '',
      );
    });
  });

  test('DPoPAuthenticationToken never shows token or proof', () {
    final token = DPoPAuthenticationToken(
      'secret-token',
      'secret-proof',
      method: 'GET',
      resourceUri: Uri.parse(_url),
    );
    expect(token.name, '');
    expect('$token', isNot(contains('secret')));
  });
}
