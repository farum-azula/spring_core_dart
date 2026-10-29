// The JWT decoder around the signature check: which keys a token's `kid`
// and `alg` select, when the key source is asked again, the timing of the
// remote JWK Set cache and its refetch limit, the algorithms a public-key
// decoder accepts, issuer discovery, and the claim times being UTC. The
// HTTP fetcher: jwk_http_test.dart.
import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'app/jwt/keys.dart';

final Matcher _rejected = throwsA(isA<BadJwtException>());

Matcher _rejectedWith(String text) => throwsA(
  isA<BadJwtException>().having((e) => e.message, 'message', contains(text)),
);

String _tokenWithoutKid(RsaTestKey key) {
  final input =
      '${b64Json({'alg': 'RS256'})}.'
      '${b64Json({'sub': 'ada', 'exp': TokenFactory.now() + 3600})}';
  return '$input.${b64(key.sign('RS256', ascii.encode(input)))}';
}

final class _RecordingSource implements JwkSource {
  _RecordingSource(this._keys);

  final List<VerificationKey> _keys;
  final calls = <({String? keyId, bool refresh})>[];

  @override
  Future<List<VerificationKey>> keys({
    String? keyId,
    bool refresh = false,
  }) async {
    calls.add((keyId: keyId, refresh: refresh));
    return _keys;
  }
}

final class _Issuer {
  DateTime now = DateTime.utc(2026);
  int fetches = 0;
  List<String> keyIds = ['first'];

  late final source = RemoteJwkSource(
    Uri.parse('https://issuer.example/jwks'),
    fetcher: (_) async {
      fetches++;
      return jsonEncode({
        'keys': [
          for (final id in keyIds) {...testKeys.rsa.jwk, 'kid': id},
        ],
      });
    },
    clock: () => now,
  );

  void advance(Duration time) => now = now.add(time);

  Future<List<String?>> ids({bool refresh = false}) async => [
    for (final key in await source.keys(refresh: refresh)) key.keyId,
  ];
}

void main() {
  final keys = testKeys;

  group('which keys verify a token', () {
    test(
      'a token with a kid asks the source once when the key is there',
      () async {
        final source = _RecordingSource([keys.rsa.verificationKey]);
        await NimbusJwtDecoder.withJwkSource(source).decode(keys.token());
        expect(source.calls, [(keyId: keys.rsa.kid, refresh: false)]);
      },
    );

    test('an unknown kid asks again for fresh keys, once', () async {
      final source = _RecordingSource([keys.rsa.verificationKey]);
      await expectLater(
        NimbusJwtDecoder.withJwkSource(source).decode(keys.token(kid: 'new')),
        _rejectedWith('no matching key'),
      );
      expect(source.calls, [
        (keyId: 'new', refresh: false),
        (keyId: 'new', refresh: true),
      ]);
    });

    test('a token without a kid never asks for fresh keys', () async {
      final source = _RecordingSource([]);
      await expectLater(
        NimbusJwtDecoder.withJwkSource(source)
            .decode(_tokenWithoutKid(keys.rsa)),
        _rejectedWith('no matching key'),
      );
      expect(source.calls, [(keyId: null, refresh: false)]);
    });

    test('without a kid, one key out of several may verify', () async {
      final other = RsaTestKey.generate(kid: 'other');
      for (final order in [
        [other.verificationKey, keys.rsa.verificationKey],
        [keys.rsa.verificationKey, other.verificationKey],
      ]) {
        final decoder = NimbusJwtDecoder.withJwkSource(StaticJwkSource(order));
        expect(
          (await decoder.decode(_tokenWithoutKid(keys.rsa))).subject,
          'ada',
        );
      }
    });

    test(
      'with one kid on several keys, the one that signed verifies',
      () async {
        final other = RsaTestKey.generate(kid: keys.rsa.kid);
        for (final order in [
          [other.verificationKey, keys.rsa.verificationKey],
          [keys.rsa.verificationKey, other.verificationKey],
        ]) {
          final decoder = NimbusJwtDecoder.withJwkSource(
            StaticJwkSource(order),
          );
          expect((await decoder.decode(keys.token())).subject, 'ada');
        }
        final onlyOther = NimbusJwtDecoder.withJwkSource(
          StaticJwkSource([other.verificationKey]),
        );
        await expectLater(
          onlyOther.decode(keys.token()),
          _rejectedWith('Invalid signature'),
        );
      },
    );

    test('a key restricted to another alg is not a candidate', () async {
      RsaVerificationKey restricted(String algorithm) => RsaVerificationKey(
        keys.rsa.publicKey.modulus!,
        keys.rsa.publicKey.exponent!,
        keyId: keys.rsa.kid,
        algorithm: algorithm,
      );
      final other = _RecordingSource([restricted('RS384')]);
      await expectLater(
        NimbusJwtDecoder.withJwkSource(
          other,
          jwsAlgorithms: {JwsAlgorithm.rs256},
        ).decode(keys.token()),
        _rejectedWith('no matching key'),
      );
      expect(other.calls.map((c) => c.refresh), [false, true]);

      final same = NimbusJwtDecoder.withJwkSource(
        StaticJwkSource([restricted('RS256')]),
      );
      expect((await same.decode(keys.token())).subject, 'ada');
      await expectLater(same.decode(keys.token(alg: 'PS256')), _rejected);
    });
  });

  group('a public-key decoder accepts asymmetric algorithms only', () {
    final key = keys.rsa.verificationKey;
    final uri = Uri.parse('https://issuer.example/jwks');

    test('HMAC, none and a mix are refused', () {
      for (final algorithms in [
        <JwsAlgorithm>{},
        {JwsAlgorithm.hs256},
        {JwsAlgorithm.rs256, JwsAlgorithm.hs512},
        {JwsAlgorithm.hs384, JwsAlgorithm.ps256},
      ]) {
        expect(
          () => NimbusJwtDecoder.withPublicKey(key, jwsAlgorithms: algorithms),
          throwsArgumentError,
          reason: '$algorithms',
        );
        expect(
          () => NimbusJwtDecoder.withJwkSetUri(uri, jwsAlgorithms: algorithms),
          throwsArgumentError,
          reason: '$algorithms',
        );
      }
    });

    test('RSA and EC algorithms are accepted', () async {
      final decoder = NimbusJwtDecoder.withPublicKey(
        key,
        jwsAlgorithms: {JwsAlgorithm.rs256, JwsAlgorithm.ps256},
      );
      expect((await decoder.decode(keys.token(alg: 'PS256'))).subject, 'ada');
      expect(
        NimbusJwtDecoder.withJwkSetUri(
          uri,
          jwsAlgorithms: {JwsAlgorithm.es256, JwsAlgorithm.ps512},
        ).jwsAlgorithms,
        {JwsAlgorithm.es256, JwsAlgorithm.ps512},
      );
    });
  });

  group('the remote JWK Set cache', () {
    test('serves keys from the cache until the lifespan has passed', () async {
      final issuer = _Issuer();
      expect(await issuer.ids(), ['first']);
      issuer
        ..keyIds = ['second']
        ..advance(const Duration(minutes: 1));
      expect(await issuer.ids(), ['first']);
      issuer.advance(
        const Duration(minutes: 4) - const Duration(milliseconds: 1),
      );
      expect(await issuer.ids(), ['first']);
      expect(issuer.fetches, 1);
      issuer.advance(const Duration(milliseconds: 1));
      expect(await issuer.ids(), ['second'], reason: 'exactly 5 minutes');
      expect(issuer.fetches, 2);
    });

    test('keys fetched long ago are fetched again', () async {
      final issuer = _Issuer();
      await issuer.ids();
      issuer
        ..keyIds = ['second']
        ..advance(const Duration(minutes: 6));
      expect(await issuer.ids(), ['second']);
      expect(issuer.fetches, 2);
    });

    test(
      'asking again for fresh keys is limited to every 30 seconds',
      () async {
        final issuer = _Issuer();
        await issuer.ids();
        issuer
          ..keyIds = ['second']
          ..advance(
            const Duration(seconds: 30) - const Duration(milliseconds: 1),
          );
        expect(await issuer.ids(refresh: true), ['first']);
        expect(issuer.fetches, 1);
        issuer.advance(const Duration(milliseconds: 1));
        expect(await issuer.ids(refresh: true), [
          'second',
        ], reason: 'exactly 30 s');
        expect(issuer.fetches, 2);
        expect(await issuer.ids(refresh: true), ['second']);
        expect(issuer.fetches, 2);
      },
    );

    test('a fresh cache is not fetched again unless asked to', () async {
      final issuer = _Issuer();
      await issuer.ids();
      issuer
        ..keyIds = ['second']
        ..advance(const Duration(minutes: 2));
      expect(await issuer.ids(), ['first']);
      expect(await issuer.source.keys(keyId: 'x'), hasLength(1));
      expect(issuer.fetches, 1);
      expect(await issuer.ids(refresh: true), ['second']);
      expect(issuer.fetches, 2);
    });
  });

  group('issuer discovery', () {
    test('an issuer with a trailing slash', () async {
      const issuer = 'https://issuer.example/tenant/';
      final fetched = <Uri>[];
      final decoder = JwtDecoders.fromIssuerLocation(
        issuer,
        fetcher: (uri) async {
          fetched.add(uri);
          return uri.path.endsWith('jwks')
              ? jsonEncode({
                  'keys': [keys.rsa.jwk],
                })
              : jsonEncode({
                  'issuer': issuer,
                  'jwks_uri': 'https://issuer.example/tenant/jwks',
                });
        },
      );
      expect(
        (await decoder.decode(keys.token(claims: {'iss': issuer}))).issuer,
        issuer,
      );
      expect(
        fetched.first.toString(),
        'https://issuer.example/tenant/.well-known/openid-configuration',
      );
    });

    test('the metadata is looked up in the three standard places', () async {
      for (final issuer in [
        'https://issuer.example/tenant',
        'https://issuer.example/tenant/',
      ]) {
        final fetched = <Uri>[];
        final decoder = JwtDecoders.fromIssuerLocation(
          issuer,
          fetcher: (uri) async {
            fetched.add(uri);
            throw const FormatException('not here');
          },
        );
        await expectLater(
          decoder.decode(keys.token()),
          throwsA(isA<JwtException>()),
        );
        expect(fetched.map((u) => u.path), [
          '/tenant/.well-known/openid-configuration',
          '/.well-known/openid-configuration/tenant',
          '/.well-known/oauth-authorization-server/tenant',
        ], reason: issuer);
      }
    });

    test('404s lead to the OAuth 2.0 metadata (the transport fetcher, as '
        "the client's discovery)", () async {
      const issuer = 'https://issuer.example/tenant';
      final transport = MockHttpTransport()
        ..when(
          HttpMethod.get,
          '$issuer/.well-known/openid-configuration',
        ).respond(404)
        ..when(
          HttpMethod.get,
          'https://issuer.example/.well-known/openid-configuration/tenant',
        ).respond(404)
        ..when(
          HttpMethod.get,
          'https://issuer.example/.well-known/oauth-authorization-server/tenant',
        ).respond(
          200,
          body: jsonEncode({
            'issuer': issuer,
            'jwks_uri': 'https://issuer.example/jwks',
          }),
        )
        ..when(HttpMethod.get, 'https://issuer.example/jwks').respond(
          200,
          body: jsonEncode({
            'keys': [keys.rsa.jwk],
          }),
        );
      final decoder = JwtDecoders.fromIssuerLocation(
        issuer,
        fetcher: transportJwkFetcher(transport),
      );
      expect(
        (await decoder.decode(keys.token(claims: {'iss': issuer}))).issuer,
        issuer,
      );
      expect(transport.requests.map((r) => r.url.path), [
        '/tenant/.well-known/openid-configuration',
        '/.well-known/openid-configuration/tenant',
        '/.well-known/oauth-authorization-server/tenant',
        '/jwks',
      ]);
    });
  });

  group('claim times', () {
    test('are UTC', () {
      final jwt = Jwt(
        'token',
        headers: const {},
        claims: const {'exp': 1700000000, 'nbf': 1699999999.5, 'iat': 0},
      );
      expect(jwt.expiresAt, DateTime.utc(2023, 11, 14, 22, 13, 20));
      for (final time in [jwt.expiresAt, jwt.notBefore, jwt.issuedAt]) {
        expect(time!.isUtc, isTrue);
      }
    });
  });
}
