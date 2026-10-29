// DPoP on the client's side (RFC 9449): the software ES256 key (RFC 6979
// vectors, JWK round trip), DER to raw R || S, the proofs (structure as in
// RFC 9449 §4, signatures checked with pointycastle directly), the token
// response clients (proofs, nonce retry, token types, auto / true / false
// per registration), the user services, the Feign interceptor and error
// decoder, the auto-configured key, and no key, proof or token in logs or
// toString.
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart'
    show
        ECCurve_secp256r1,
        ECDSASigner,
        ECPublicKey,
        ECSignature,
        PublicKeyParameter,
        SHA256Digest;
import 'package:spring_boot_starter_oauth2_client/spring_auto_configuration.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

const _tokenUri = 'https://sso.test/token';

Uint8List _hex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

String _b64(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');

List<int> _unb64(String text) => base64Url.decode(base64Url.normalize(text));

BigInt _int(List<int> bytes) =>
    bytes.fold(BigInt.zero, (value, b) => (value << 8) | BigInt.from(b));

Map<String, Object?> _json(String part) =>
    jsonDecode(utf8.decode(_unb64(part))) as Map<String, Object?>;

/// Whether [signature] (raw R || S) is the ES256 signature of [input] by
/// the public [jwk], checked with pointycastle, not with the code tested.
bool _verifies(Map<String, Object?> jwk, List<int> input, List<int> signature) {
  if (signature.length != 64) {
    return false;
  }
  final domain = ECCurve_secp256r1();
  final point = domain.curve.createPoint(
    _int(_unb64(jwk['x']! as String)),
    _int(_unb64(jwk['y']! as String)),
  );
  final verifier = ECDSASigner(SHA256Digest())
    ..init(false, PublicKeyParameter<ECPublicKey>(ECPublicKey(point, domain)));
  return verifier.verifySignature(
    Uint8List.fromList(input),
    ECSignature(_int(signature.sublist(0, 32)), _int(signature.sublist(32))),
  );
}

/// The header and claims of [proof], after checking its signature by the
/// key in its own header.
(Map<String, Object?>, Map<String, Object?>) _open(String proof) {
  final parts = proof.split('.');
  expect(parts, hasLength(3));
  final header = _json(parts[0]);
  final jwk = header['jwk']! as Map<String, Object?>;
  expect(
    _verifies(jwk, ascii.encode('${parts[0]}.${parts[1]}'), _unb64(parts[2])),
    isTrue,
    reason: 'the proof is signed by the key in its header',
  );
  return (header, _json(parts[1]));
}

ClientRegistration _registration({
  DPoPMode dpop = DPoPMode.auto,
  Map<String, Object?> metadata = const {},
}) =>
    ClientRegistration.withRegistrationId('partner')
        .clientId('shop')
        .clientSecret('s3cret')
        .authorizationGrantType(AuthorizationGrantType.clientCredentials)
        .tokenUri(_tokenUri)
        .userInfoUri('https://sso.test/userinfo')
        .userNameAttributeName('sub')
        .providerConfigurationMetadata(metadata)
        .dpop(dpop)
        .build();

HttpResponse _jsonResponse(
  HttpRequest request,
  int status,
  Object body, {
  Map<String, String> headers = const {},
}) => HttpResponse(
  status,
  headers: HttpHeaders({'Content-Type': 'application/json', ...headers}),
  body: utf8.encode(jsonEncode(body)),
  request: request,
);

// RFC 6979 A.2.5: the P-256 key and its public point.
const _rfc6979D =
    'C9AFA9D845BA75166B5C215767B1D6934E50C3DB36E89B127B8A622B120F6721';
const _rfc6979X =
    '60FED4BA255A9D31C961EB74C6356D68C049B8923B61FA6CE669622E60F29FB6';
const _rfc6979Y =
    '7903FE1008B8BC99A41AE9E95628BC64F2F1B20C2D7E9F5177A3C294D4462299';

Map<String, Object?> _rfc6979Jwk() => {
  'kty': 'EC',
  'crv': 'P-256',
  'x': _b64(_hex(_rfc6979X)),
  'y': _b64(_hex(_rfc6979Y)),
  'd': _b64(_hex(_rfc6979D)),
};

/// A key that signs in DER, as a platform key would, without converting.
final class _DerKey implements DPoPKey {
  _DerKey(this.inner);
  final SoftwareDPoPKey inner;

  @override
  bool get persistent => true;

  @override
  String get algorithm => 'ES256';

  @override
  Map<String, Object?> get publicJwk => inner.publicJwk;

  @override
  Future<Uint8List> sign(Uint8List input) async =>
      _der(await inner.sign(input));
}

/// A key whose "public" JWK leaks its private member.
final class _LeakyKey implements DPoPKey {
  _LeakyKey(this.inner);
  final SoftwareDPoPKey inner;

  @override
  bool get persistent => true;

  @override
  String get algorithm => 'ES256';

  @override
  Map<String, Object?> get publicJwk => inner.toJwk();

  @override
  Future<Uint8List> sign(Uint8List input) => inner.sign(input);
}

/// The DER encoding of a raw 64-byte R || S.
Uint8List _der(List<int> raw) {
  List<int> integer(List<int> bytes) {
    var value = bytes.skipWhile((b) => b == 0).toList();
    if (value.isEmpty) {
      value = [0];
    }
    if (value[0] & 0x80 != 0) {
      value = [0, ...value];
    }
    return [0x02, value.length, ...value];
  }

  final body = [...integer(raw.sublist(0, 32)), ...integer(raw.sublist(32))];
  return Uint8List.fromList([0x30, body.length, ...body]);
}

final class _FixedManager implements OAuth2AuthorizedClientManager {
  _FixedManager(this.client);
  OAuth2AuthorizedClient client;

  @override
  Future<OAuth2AuthorizedClient?> authorize(
    OAuth2AuthorizeRequest authorizeRequest,
  ) async => client;
}

void main() {
  group('SoftwareDPoPKey', () {
    test('RFC 6979 A.2.5: deterministic ES256 signatures', () async {
      final key = SoftwareDPoPKey.fromJwk(_rfc6979Jwk());
      for (final (message, r, s) in [
        (
          'sample',
          'EFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716',
          'F7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8',
        ),
        (
          'test',
          'F1ABB023518351CD71D881567B1EA663ED3EFCF6C5132B354F28D3B0B7D38367',
          '019F4113742A2B14BD25926B49C649155F267E60D3814B4C0CC84250E46F0083',
        ),
      ]) {
        final signature = await key.sign(ascii.encode(message));
        expect(signature, _hex('$r$s'), reason: message);
        expect(
          _verifies(key.publicJwk, ascii.encode(message), signature),
          isTrue,
        );
      }
    });

    test('a generated key: P-256, verifiable, never the same twice', () async {
      final a = SoftwareDPoPKey.generate();
      final b = SoftwareDPoPKey.generate();
      expect(a.algorithm, 'ES256');
      expect(a.publicJwk.keys, unorderedEquals(['kty', 'crv', 'x', 'y']));
      expect(a.publicJwk['kty'], 'EC');
      expect(a.publicJwk['crv'], 'P-256');
      expect(_unb64(a.publicJwk['x']! as String), hasLength(32));
      expect(a.publicJwk, isNot(equals(b.publicJwk)));
      expect(() => a.publicJwk['d'] = 'x', throwsUnsupportedError);
      final input = Uint8List.fromList(ascii.encode('header.payload'));
      final first = await a.sign(input);
      expect(first, hasLength(64));
      expect(_verifies(a.publicJwk, input, first), isTrue);
      expect(_verifies(b.publicJwk, input, first), isFalse);
      // RFC 6979: the same message, the same k; another message, another
      // k (r is the x of k × G).
      expect(await a.sign(input), first);
      final other = await a.sign(Uint8List.fromList(ascii.encode('other')));
      expect(other.sublist(0, 32), isNot(first.sublist(0, 32)));
    });

    test('toJwk and fromJwk: the same key back', () async {
      final key = SoftwareDPoPKey.generate();
      final jwk = key.toJwk();
      expect(jwk.keys, unorderedEquals(['kty', 'crv', 'x', 'y', 'd']));
      final restored = SoftwareDPoPKey.fromJwk(
        jsonDecode(jsonEncode(jwk)) as Map<String, Object?>,
      );
      expect(restored.publicJwk, key.publicJwk);
      expect(restored.thumbprint, key.thumbprint);
      final input = Uint8List.fromList([1, 2, 3]);
      expect(await restored.sign(input), await key.sign(input));
    });

    test('fromJwk refuses what is not a P-256 key pair', () {
      final good = _rfc6979Jwk();
      final other = SoftwareDPoPKey.generate().toJwk();
      final n = ECCurve_secp256r1().n;
      for (final (why, jwk) in [
        ('RSA', {...good, 'kty': 'RSA'}),
        ('P-384', {...good, 'crv': 'P-384'}),
        ('no d', {...good}..remove('d')),
        ('d not base64url', {...good, 'd': '***'}),
        ('short d', {...good, 'd': _b64(List.filled(31, 1))}),
        ('d = 0', {...good, 'd': _b64(List.filled(32, 0))}),
        ('d = n', {...good, 'd': _b64(_hex(n.toRadixString(16)))}),
        ('another x', {...good, 'x': other['x']}),
        ('another d', {...good, 'd': other['d']}),
        ('number x', {...good, 'x': 1}),
      ]) {
        expect(
          () => SoftwareDPoPKey.fromJwk(jwk),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              isNot(contains(good['d']! as String)),
            ),
          ),
          reason: why,
        );
      }
    });

    test('toString shows the thumbprint, never the private key', () {
      final key = SoftwareDPoPKey.generate();
      final text = '$key';
      expect(text, contains(key.thumbprint));
      expect(text, isNot(contains(key.toJwk()['d']! as String)));
    });
  });

  group('ECDSA.transcodeSignatureToConcat', () {
    test('DER to R || S: leading zeros, high bits, long form', () {
      final raw = _hex(
        '${'00' * 2}${'7f' * 30}' // r: two leading zero bytes, short
        '${'ff' * 32}', // s: the high bit set, needs 0x00 in DER
      );
      final der = _der(raw);
      expect(der[3], 30); // r in 30 bytes
      expect(der[3 + 30 + 1 + 1], 33); // s in 33 bytes (0x00 + 32)
      expect(ECDSA.transcodeSignatureToConcat(der, 64), raw);

      // ES512 lengths need the long form (0x81).
      final r = [0x01, ...List.filled(65, 0xab)];
      final s = [0x00, 0x80, ...List.filled(64, 0x11)];
      final body = [0x02, 66, ...r, 0x02, 66, ...s];
      final long = [0x30, 0x81, body.length, ...body];
      expect(ECDSA.transcodeSignatureToConcat(long, 132), [...r, ...s]);
    });

    test('a real signature converts back to the raw one', () async {
      final key = SoftwareDPoPKey.generate();
      final input = Uint8List.fromList(ascii.encode('x'));
      final raw = await key.sign(input);
      expect(ECDSA.transcodeSignatureToConcat(_der(raw), 64), raw);
    });

    test('anything but strict DER is refused', () {
      final good = _der(_hex('11' * 64));
      for (final (why, der) in [
        ('empty', <int>[]),
        ('not a SEQUENCE', [0x31, ...good.sublist(1)]),
        ('length too long', [0x30, good[1] + 1, ...good.sublist(2)]),
        ('trailing byte', [...good, 0]),
        ('truncated', good.sublist(0, good.length - 1)),
        ('negative r', [0x30, 6, 0x02, 1, 0x80, 0x02, 1, 0x01]),
        ('non-minimal r', [0x30, 7, 0x02, 2, 0x00, 0x01, 0x02, 1, 0x01]),
        ('zero r', [0x30, 6, 0x02, 1, 0x00, 0x02, 1, 0x01]),
        (
          'r too large',
          [0x30, 38, 0x02, 33, 0x01, ...List.filled(32, 1), 0x02, 1, 1],
        ),
        ('BOOLEAN instead', [0x30, 6, 0x01, 1, 0x01, 0x02, 1, 0x01]),
        ('non-minimal length', [0x30, 0x81, 6, 0x02, 1, 1, 0x02, 1, 1]),
        ('raw R || S', _hex('30${'11' * 63}')),
      ]) {
        expect(
          () => ECDSA.transcodeSignatureToConcat(der, 64),
          throwsFormatException,
          reason: why,
        );
      }
      expect(
        () => ECDSA.transcodeSignatureToConcat(good, 63),
        throwsArgumentError,
      );
    });
  });

  group('DPoPProofBuilder', () {
    final key = SoftwareDPoPKey.generate();
    final now = DateTime.utc(2026, 10, 29, 12, 0, 0, 750);

    test('RFC 9449 §4.2: header, claims, signature', () async {
      final proof = await DPoPProofBuilder(key, clock: () => now).build(
        method: 'POST',
        url: Uri.parse('https://server.example.com/token?x=1#frag'),
      );
      final (header, claims) = _open(proof);
      expect(header, {'typ': 'dpop+jwt', 'alg': 'ES256', 'jwk': key.publicJwk});
      expect(claims.keys, unorderedEquals(['jti', 'htm', 'htu', 'iat']));
      expect(claims['htm'], 'POST');
      expect(claims['htu'], 'https://server.example.com/token');
      expect(claims['iat'], now.millisecondsSinceEpoch ~/ 1000);
      final jti = claims['jti']! as String;
      expect(jti, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(_unb64(jti).length, greaterThanOrEqualTo(16));
      // The server reads it strictly.
      expect(DPoPProofClaims.fromJson(claims).htm, 'POST');
    });

    test('RFC 9449 §7.1: ath of the access token, and the nonce', () async {
      final proof = await DPoPProofBuilder(key).build(
        method: 'GET',
        url: Uri.parse('https://resource.example.org/protectedresource'),
        accessToken: 'Kz~8mXK1EalYznwH-LC-1fBAo.4Ljp~zsPE_NeO.gxU',
        nonce: 'eyJ7S_zG.eyJH0-Z.HX4w-7v',
      );
      final (_, claims) = _open(proof);
      expect(claims['ath'], 'fUHyO2r2Z3DZ53EsNrWBb0xWXoaNy59IiKCAqksmQEo');
      expect(claims['nonce'], 'eyJ7S_zG.eyJH0-Z.HX4w-7v');
      expect(claims['htm'], 'GET');
    });

    test('a new jti for every proof', () async {
      final builder = DPoPProofBuilder(key);
      final ids = <Object?>{};
      for (var i = 0; i < 50; i++) {
        final proof = await builder.build(
          method: 'GET',
          url: Uri.parse('https://api.test/x'),
        );
        ids.add(_json(proof.split('.')[1])['jti']);
      }
      expect(ids, hasLength(50));
    });

    test('a private member in the jwk, or a DER signature: refused', () {
      final url = Uri.parse('https://api.test/x');
      expect(
        DPoPProofBuilder(_LeakyKey(key)).build(method: 'GET', url: url),
        throwsStateError,
      );
      expect(
        DPoPProofBuilder(_DerKey(key)).build(method: 'GET', url: url),
        throwsStateError,
      );
      expect(
        DPoPProofBuilder(key).build(method: 'GET', url: Uri.parse('/x')),
        throwsArgumentError,
      );
      expect(
        DPoPProofBuilder(
          key,
        ).build(method: 'GET', url: Uri.parse('ftp://api.test/x')),
        throwsArgumentError,
      );
    });

    test('a WebSocket URL: htu is its http(s) form (RFC 9449 §4.2)', () async {
      for (final (url, htu) in [
        ('wss://api.test/ws/support?t=1', 'https://api.test/ws/support'),
        ('ws://localhost:8080/ws/support', 'http://localhost:8080/ws/support'),
        ('WSS://API.test:443/ws', 'https://api.test/ws'),
      ]) {
        final proof = await DPoPProofBuilder(
          key,
        ).build(method: 'GET', url: Uri.parse(url));
        expect(_open(proof).$2['htu'], htu);
      }
    });

    test('a LoadableDPoPKey is loaded before its public key is read', () async {
      final lazy = _LazyKey(key);
      final proofs = await Future.wait([
        for (var i = 0; i < 3; i++)
          DPoPProofBuilder(
            lazy,
          ).build(method: 'GET', url: Uri.parse('https://api.test/$i')),
      ]);
      for (final proof in proofs) {
        expect(_open(proof).$1['jwk'], key.publicJwk);
      }
      expect(lazy.loads, 3, reason: 'awaited before every proof');
    });
  });

  group('OAuth2AccessTokenHeaders', () {
    final key = SoftwareDPoPKey.generate();
    final url = Uri.parse('wss://api.test/ws/support');

    test('Bearer: the Authorization header only', () async {
      final headers = await OAuth2AccessTokenHeaders(dPoPKey: key).of(
        OAuth2AccessToken(TokenType.bearer, 'token-1'),
        method: 'GET',
        url: url,
      );
      expect(headers, {'Authorization': 'Bearer token-1'});
    });

    test('DPoP: the token and a proof for this request', () async {
      final headers = await OAuth2AccessTokenHeaders(dPoPKey: key).of(
        OAuth2AccessToken(TokenType.dpop, 'token-1'),
        method: 'GET',
        url: url,
        nonce: 'n-1',
      );
      expect(headers['Authorization'], 'DPoP token-1');
      final (header, claims) = _open(headers['DPoP']!);
      expect(header['jwk'], key.publicJwk);
      expect(claims['htm'], 'GET');
      expect(claims['htu'], 'https://api.test/ws/support');
      expect(claims['ath'], sha256Base64Url('token-1'));
      expect(claims['nonce'], 'n-1');
    });

    test('DPoP without a key fails; toString shows no token', () async {
      await expectLater(
        OAuth2AccessTokenHeaders().of(
          OAuth2AccessToken(TokenType.dpop, 'token-1'),
          method: 'GET',
          url: url,
        ),
        throwsStateError,
      );
      expect('${OAuth2AccessTokenHeaders(dPoPKey: key)}', contains('ES256'));
    });
  });

  group('DPoPMode and the registration', () {
    test('parse: auto, true, false', () {
      expect(DPoPMode.parse('auto'), DPoPMode.auto);
      expect(DPoPMode.parse(' TRUE '), DPoPMode.enabled);
      expect(DPoPMode.parse('false'), DPoPMode.disabled);
      expect(() => DPoPMode.parse('yes'), throwsArgumentError);
    });

    test('auto keeps Bearer with a key made for one run (servers)', () {
      final metadata = {
        'dpop_signing_alg_values_supported': ['ES256'],
      };
      expect(
        _registration(metadata: metadata).usesDPoP(SoftwareDPoPKey.generate()),
        isFalse,
      );
      expect(
        _registration(
          dpop: DPoPMode.enabled,
          metadata: metadata,
        ).usesDPoP(SoftwareDPoPKey.generate()),
        isTrue,
      );
    });

    test('auto follows dpop_signing_alg_values_supported', () {
      // A key that outlives the program (an app's).
      final key = SoftwareDPoPKey.generate(persistent: true);
      expect(_registration().dpop, DPoPMode.auto);
      expect(_registration().usesDPoP(key), isFalse);
      expect(
        _registration(
          metadata: {
            'dpop_signing_alg_values_supported': ['RS256', 'ES256'],
          },
        ).usesDPoP(key),
        isTrue,
      );
      expect(
        _registration(
          metadata: {
            'dpop_signing_alg_values_supported': ['RS256'],
          },
        ).usesDPoP(key),
        isFalse,
      );
      expect(
        _registration(
          metadata: {'dpop_signing_alg_values_supported': 'ES256'},
        ).usesDPoP(key),
        isFalse,
      );
      expect(_registration(dpop: DPoPMode.enabled).usesDPoP(key), isTrue);
      expect(
        _registration(
          dpop: DPoPMode.disabled,
          metadata: {
            'dpop_signing_alg_values_supported': ['ES256'],
          },
        ).usesDPoP(key),
        isFalse,
      );
      final copy = ClientRegistration.withClientRegistration(
        _registration(dpop: DPoPMode.enabled),
      ).build();
      expect(copy.dpop, DPoPMode.enabled);
      expect('$copy', contains('dpop=enabled'));
    });

    test('the dpop property, per registration', () async {
      const p = 'spring.security.oauth2.client.registration';
      final environment = StandardEnvironment()
        ..propertySources.addFirst(
          const MapPropertySource('test', {
            '$p.a.client-id': 'a',
            '$p.a.authorization-grant-type': 'client_credentials',
            '$p.a.provider': 'p',
            '$p.a.dpop': 'true',
            '$p.b.client-id': 'b',
            '$p.b.authorization-grant-type': 'client_credentials',
            '$p.b.provider': 'p',
            '$p.b.dpop': 'false',
            '$p.c.client-id': 'c',
            '$p.c.authorization-grant-type': 'client_credentials',
            '$p.c.provider': 'p',
            'spring.security.oauth2.client.provider.p.token-uri': _tokenUri,
          }),
        );
      ConfigurationPropertySources.attach(environment);
      final suppliers = OAuth2ClientPropertiesMapper(
        OAuth2ClientProperties.of(environment),
      ).asClientRegistrations();
      expect((await suppliers['a']!()).dpop, DPoPMode.enabled);
      expect((await suppliers['b']!()).dpop, DPoPMode.disabled);
      // Not set: auto, on when the provider announces DPoP.
      expect((await suppliers['c']!()).dpop, DPoPMode.auto);

      environment.propertySources.addFirst(
        const MapPropertySource('bad', {'$p.a.dpop': 'sometimes'}),
      );
      expect(
        () => OAuth2ClientPropertiesMapper(
          OAuth2ClientProperties.of(environment),
        ).asClientRegistrations(),
        throwsArgumentError,
      );
    });
  });

  group('the token response clients', () {
    // An app's key (kept outside the program), so `auto` applies.
    final key = SoftwareDPoPKey.generate(persistent: true);

    DefaultClientCredentialsTokenResponseClient client(
      MockHttpTransport transport, {
      DPoPKey? dPoPKey,
    }) => DefaultClientCredentialsTokenResponseClient(
      transport,
      dPoPKey: dPoPKey ?? key,
    );

    MockHttpTransport issuing(String tokenType) =>
        MockHttpTransport()
          ..when(HttpMethod.post, _tokenUri).respondWith(
            (request) => _jsonResponse(request, 200, {
              'access_token': 'at',
              'token_type': tokenType,
              'expires_in': 300,
            }),
          );

    test(
      'DPoP on: a proof for POST to the token endpoint, a DPoP token',
      () async {
        final transport = issuing('DPoP');
        final response = await client(transport).getTokenResponse(
          OAuth2ClientCredentialsGrantRequest(
            _registration(dpop: DPoPMode.enabled),
          ),
        );
        expect(response.accessToken.tokenType, TokenType.dpop);
        final request = transport.lastRequest;
        final (header, claims) = _open(request.headers['DPoP']!);
        expect(header['jwk'], key.publicJwk);
        expect(claims['htm'], 'POST');
        expect(claims['htu'], _tokenUri);
        expect(claims, isNot(contains('ath')));
        expect(claims, isNot(contains('nonce')));
        expect(request.headers['Authorization'], startsWith('Basic '));
      },
    );

    test('token_type is read in any case', () async {
      for (final type in ['dpop', 'DPOP', 'DPoP']) {
        final response = await client(issuing(type)).getTokenResponse(
          OAuth2ClientCredentialsGrantRequest(
            _registration(dpop: DPoPMode.enabled),
          ),
        );
        expect(response.accessToken.tokenType, TokenType.dpop, reason: type);
      }
      expect(
        () => OAuth2AccessTokenResponse.fromJson(const {
          'access_token': 'a',
          'token_type': 'mac',
        }),
        throwsA(isA<OAuth2AuthorizationException>()),
      );
    });

    test('DPoP asked, Bearer issued: kept as Bearer (RFC 9449 §5)', () async {
      final response = await client(issuing('Bearer')).getTokenResponse(
        OAuth2ClientCredentialsGrantRequest(
          _registration(dpop: DPoPMode.enabled),
        ),
      );
      expect(response.accessToken.tokenType, TokenType.bearer);
    });

    test('DPoP off: no proof; a DPoP token is refused', () async {
      final transport = issuing('Bearer');
      await client(transport).getTokenResponse(
        OAuth2ClientCredentialsGrantRequest(
          _registration(dpop: DPoPMode.disabled),
        ),
      );
      expect(transport.lastRequest.headers['DPoP'], isNull);
      await expectLater(
        client(issuing('DPoP')).getTokenResponse(
          OAuth2ClientCredentialsGrantRequest(
            _registration(dpop: DPoPMode.disabled),
          ),
        ),
        throwsA(
          isA<OAuth2AuthorizationException>().having(
            (e) => e.error.errorCode,
            'error',
            OAuth2ErrorCodes.invalidTokenResponse,
          ),
        ),
      );
    });

    test('auto: on with ES256 in the metadata, off otherwise', () async {
      for (final (metadata, expected) in [
        (
          {
            'dpop_signing_alg_values_supported': ['ES256', 'PS256'],
          },
          true,
        ),
        (
          {
            'dpop_signing_alg_values_supported': ['RS256'],
          },
          false,
        ),
        (const <String, Object?>{}, false),
      ]) {
        final transport = issuing(expected ? 'DPoP' : 'Bearer');
        await client(transport).getTokenResponse(
          OAuth2ClientCredentialsGrantRequest(
            _registration(metadata: metadata),
          ),
        );
        expect(
          transport.lastRequest.headers['DPoP'] != null,
          expected,
          reason: '$metadata',
        );
      }
    });

    test('without a key: never a proof', () async {
      final transport = issuing('Bearer');
      await DefaultClientCredentialsTokenResponseClient(transport)
          .getTokenResponse(
            OAuth2ClientCredentialsGrantRequest(
              _registration(dpop: DPoPMode.enabled),
            ),
          );
      expect(transport.lastRequest.headers['DPoP'], isNull);
    });

    test(
      'use_dpop_nonce: sent once more with the nonce, which is kept',
      () async {
        final transport = MockHttpTransport()
          ..when(HttpMethod.post, _tokenUri).respondWith(
            (request) => _jsonResponse(
              request,
              400,
              {'error': 'use_dpop_nonce', 'error_description': 'nonce'},
              headers: {'DPoP-Nonce': 'n-1'},
            ),
          )
          ..when(HttpMethod.post, _tokenUri).respondWith(
            (request) => _jsonResponse(request, 200, {
              'access_token': 'at',
              'token_type': 'DPoP',
            }),
          );
        final tokens = client(transport);
        final grant = OAuth2ClientCredentialsGrantRequest(
          _registration(dpop: DPoPMode.enabled),
        );
        await tokens.getTokenResponse(grant);
        expect(transport.requests, hasLength(2));
        final (_, first) = _open(transport.requests[0].headers['DPoP']!);
        final (_, second) = _open(transport.requests[1].headers['DPoP']!);
        expect(first, isNot(contains('nonce')));
        expect(second['nonce'], 'n-1');
        expect(second['jti'], isNot(first['jti']));
        // The body is the same request again.
        expect(transport.requests[1].body, transport.requests[0].body);

        // The next request carries the nonce from the start.
        await tokens.getTokenResponse(grant);
        expect(transport.requests, hasLength(3));
        expect(
          _open(transport.requests[2].headers['DPoP']!).$2['nonce'],
          'n-1',
        );
      },
    );

    test('use_dpop_nonce again, or without a nonce: no loop', () async {
      final again = MockHttpTransport()
        ..when(HttpMethod.post, _tokenUri).respondWith(
          (request) => _jsonResponse(
            request,
            400,
            {'error': 'use_dpop_nonce'},
            headers: {'DPoP-Nonce': 'n-${DateTime.now().microsecond}'},
          ),
        );
      await expectLater(
        client(again).getTokenResponse(
          OAuth2ClientCredentialsGrantRequest(
            _registration(dpop: DPoPMode.enabled),
          ),
        ),
        throwsA(
          isA<OAuth2AuthorizationException>().having(
            (e) => e.error.errorCode,
            'error',
            OAuth2ErrorCodes.useDPoPNonce,
          ),
        ),
      );
      expect(again.requests, hasLength(2));

      final withoutNonce = MockHttpTransport()
        ..when(HttpMethod.post, _tokenUri).respondWith(
          (request) => _jsonResponse(request, 400, {'error': 'use_dpop_nonce'}),
        );
      await expectLater(
        client(withoutNonce).getTokenResponse(
          OAuth2ClientCredentialsGrantRequest(
            _registration(dpop: DPoPMode.enabled),
          ),
        ),
        throwsA(isA<OAuth2AuthorizationException>()),
      );
      expect(withoutNonce.requests, hasLength(1));

      // A nonce is not answered when DPoP is off.
      final off = MockHttpTransport()
        ..when(HttpMethod.post, _tokenUri).respondWith(
          (request) => _jsonResponse(
            request,
            400,
            {'error': 'use_dpop_nonce'},
            headers: {'DPoP-Nonce': 'n'},
          ),
        );
      await expectLater(
        client(off).getTokenResponse(
          OAuth2ClientCredentialsGrantRequest(
            _registration(dpop: DPoPMode.disabled),
          ),
        ),
        throwsA(isA<OAuth2AuthorizationException>()),
      );
      expect(off.requests, hasLength(1));
    });

    test('the refresh of a DPoP token carries a proof', () async {
      final transport = issuing('DPoP');
      // DPoP off for the registration: the DPoP token decides.
      final registration = _registration(dpop: DPoPMode.disabled);
      await DefaultRefreshTokenTokenResponseClient(
        transport,
        dPoPKey: key,
      ).getTokenResponse(
        OAuth2RefreshTokenGrantRequest(
          registration,
          OAuth2AccessToken(TokenType.dpop, 'old'),
          OAuth2RefreshToken('rt'),
        ),
      );
      final (_, claims) = _open(transport.lastRequest.headers['DPoP']!);
      expect(claims['htu'], _tokenUri);
    });

    test('the authorization code exchange carries a proof', () async {
      final transport = issuing('DPoP');
      final registration = ClientRegistration.withRegistrationId('kc')
          .clientId('app')
          .authorizationGrantType(AuthorizationGrantType.authorizationCode)
          .redirectUri('http://127.0.0.1/callback')
          .authorizationUri('https://sso.test/auth')
          .tokenUri(_tokenUri)
          .dpop(DPoPMode.enabled)
          .build();
      final request = OAuth2AuthorizationRequest.forRegistration(
        registration,
        redirectUri: 'http://127.0.0.1:5000/callback',
      );
      final response =
          await DefaultAuthorizationCodeTokenResponseClient(
            transport,
            dPoPKey: key,
          ).getTokenResponse(
            OAuth2AuthorizationCodeGrantRequest(
              registration,
              OAuth2AuthorizationExchange(
                request,
                OAuth2AuthorizationResponse(
                  redirectUri: 'http://127.0.0.1:5000/callback',
                  code: 'c',
                  state: request.state,
                ),
              ),
            ),
          );
      expect(response.accessToken.tokenType, TokenType.dpop);
      expect(transport.lastRequest.headers['DPoP'], isNotNull);
    });
  });

  group('the user services', () {
    final key = SoftwareDPoPKey.generate();
    const userInfo = 'https://sso.test/userinfo';

    OAuth2UserRequest request(TokenType type) => OAuth2UserRequest(
      _registration(),
      OAuth2AccessToken(type, 'the-token'),
    );

    test('a DPoP token: Authorization DPoP and a proof with ath', () async {
      final transport = MockHttpTransport()
        ..when(HttpMethod.get, userInfo).respondWith(
          (r) => _jsonResponse(r, 200, {'sub': 'ada'}),
        );
      final user = await DefaultOAuth2UserService(
        transport,
        dPoPKey: key,
      ).loadUser(request(TokenType.dpop));
      expect(user.name, 'ada');
      final sent = transport.lastRequest;
      expect(sent.headers['Authorization'], 'DPoP the-token');
      final (_, claims) = _open(sent.headers['DPoP']!);
      expect(claims['htm'], 'GET');
      expect(claims['htu'], userInfo);
      expect(claims['ath'], sha256Base64Url('the-token'));
    });

    test('a nonce asked for with 401: retried once with it', () async {
      final transport = MockHttpTransport()
        ..when(HttpMethod.get, userInfo).respondWith(
          (r) => HttpResponse(
            401,
            headers: HttpHeaders({
              'WWW-Authenticate': 'DPoP error="use_dpop_nonce"',
              'DPoP-Nonce': 'rs-nonce',
            }),
            request: r,
          ),
        )
        ..when(HttpMethod.get, userInfo).respondWith(
          (r) => _jsonResponse(r, 200, {'sub': 'ada'}),
        );
      await DefaultOAuth2UserService(
        transport,
        dPoPKey: key,
      ).loadUser(request(TokenType.dpop));
      expect(transport.requests, hasLength(2));
      expect(
        _open(transport.lastRequest.headers['DPoP']!).$2['nonce'],
        'rs-nonce',
      );
    });

    test('a Bearer token stays Bearer; a DPoP token needs the key', () async {
      final transport = MockHttpTransport()
        ..when(HttpMethod.get, userInfo).respondWith(
          (r) => _jsonResponse(r, 200, {'sub': 'ada'}),
        );
      await DefaultOAuth2UserService(
        transport,
        dPoPKey: key,
      ).loadUser(request(TokenType.bearer));
      expect(
        transport.lastRequest.headers['Authorization'],
        'Bearer the-token',
      );
      expect(transport.lastRequest.headers['DPoP'], isNull);
      await expectLater(
        DefaultOAuth2UserService(transport).loadUser(request(TokenType.dpop)),
        throwsA(isA<OAuth2AuthenticationException>()),
      );
    });
  });

  group('the Feign interceptor', () {
    final key = SoftwareDPoPKey.generate();
    final registration = _registration(dpop: DPoPMode.enabled);

    OAuth2AuthorizedClient authorized(TokenType type, String value) =>
        OAuth2AuthorizedClient(
          registration,
          'anonymousUser',
          OAuth2AccessToken(type, value),
        );

    RequestTemplate template({String url = 'https://api.test/orders?page=2'}) =>
        RequestTemplate(
          method: HttpMethod.delete,
          url: Uri.parse(url),
          methodKey: 'Orders#delete()',
          clientName: 'partner',
          headers: HttpHeaders({'DPoP': 'stale', 'Authorization': 'old'}),
        );

    test(
      'a DPoP token: DPoP <token> and a fresh proof for this call',
      () async {
        final interceptor = OAuth2AccessTokenInterceptor(
          _FixedManager(authorized(TokenType.dpop, 'dpop-token')),
          dPoPKey: key,
        );
        final call = template();
        await interceptor.apply(call);
        expect(call.headers.getAll('Authorization'), ['DPoP dpop-token']);
        final proofs = call.headers.getAll('DPoP');
        expect(proofs, hasLength(1));
        final (header, claims) = _open(proofs.single);
        expect(header['jwk'], key.publicJwk);
        expect(claims['htm'], 'DELETE');
        expect(claims['htu'], 'https://api.test/orders');
        expect(claims['ath'], sha256Base64Url('dpop-token'));
        expect(claims, isNot(contains('nonce')));

        final again = template();
        await interceptor.apply(again);
        expect(
          _open(again.headers['DPoP']!).$2['jti'],
          isNot(claims['jti']),
        );
      },
    );

    test('a Bearer token: Bearer and no proof', () async {
      final interceptor = OAuth2AccessTokenInterceptor(
        _FixedManager(authorized(TokenType.bearer, 'bearer-token')),
        dPoPKey: key,
      );
      final call = template();
      await interceptor.apply(call);
      expect(call.headers.getAll('Authorization'), ['Bearer bearer-token']);
      expect(call.headers['DPoP'], isNull);
    });

    test('a DPoP token without a key fails the call', () {
      final interceptor = OAuth2AccessTokenInterceptor(
        _FixedManager(authorized(TokenType.dpop, 'dpop-token')),
      );
      expect(interceptor.apply(template()), throwsStateError);
    });

    test('a DPoP-Nonce of an error answer goes into the next proof, per '
        'server', () async {
      final interceptor = OAuth2AccessTokenInterceptor(
        _FixedManager(authorized(TokenType.dpop, 'dpop-token')),
        dPoPKey: key,
        authorizedClientService: InMemoryOAuth2AuthorizedClientService(
          InMemoryClientRegistrationRepository([registration]),
        ),
      );
      final decoder = OAuth2AccessTokenErrorDecoder(
        const DefaultErrorDecoder(),
        interceptor,
      );
      final first = template();
      await interceptor.apply(first);
      final response = HttpResponse(
        401,
        headers: HttpHeaders({
          'WWW-Authenticate':
              'DPoP error="use_dpop_nonce", '
              'error_description="Resource server requires nonce"',
          'DPoP-Nonce': 'api-nonce',
        }),
        request: HttpRequest(
          method: first.method,
          url: first.url,
          headers: first.headers,
        ),
      );
      expect(
        decoder.decode('Orders#delete()', response),
        isA<FeignUnauthorized>(),
      );

      final second = template(url: 'https://api.test/other');
      await interceptor.apply(second);
      expect(_open(second.headers['DPoP']!).$2['nonce'], 'api-nonce');
      final elsewhere = template(url: 'https://other.test/orders');
      await interceptor.apply(elsewhere);
      expect(_open(elsewhere.headers['DPoP']!).$2, isNot(contains('nonce')));
    });

    test('a 401 that only asks for a nonce keeps the token', () async {
      final repository = InMemoryClientRegistrationRepository([registration]);
      final service = InMemoryOAuth2AuthorizedClientService(repository);
      final stored = authorized(TokenType.dpop, 'dpop-token');
      await service.saveAuthorizedClient(stored, anonymousAuthentication);
      final interceptor = OAuth2AccessTokenInterceptor(
        _FixedManager(stored),
        dPoPKey: key,
        authorizedClientService: service,
      );
      final decoder = OAuth2AccessTokenErrorDecoder(
        const DefaultErrorDecoder(),
        interceptor,
      );
      final call = template();
      await interceptor.apply(call);
      HttpResponse refused(String challenge) => HttpResponse(
        401,
        headers: HttpHeaders({'WWW-Authenticate': challenge}),
        request: HttpRequest(
          method: call.method,
          url: call.url,
          headers: call.headers,
        ),
      );
      decoder.decode('k', refused('DPoP error="use_dpop_nonce"'));
      await interceptor.apply(template()); // waits for pending work
      expect(
        (await service.loadAuthorizedClient(
          'partner',
          'anonymousUser',
        ))!.accessToken.expiresAt,
        isNull,
      );
      decoder.decode('k', refused('DPoP error="invalid_token"'));
      await interceptor.apply(template());
      expect(
        (await service.loadAuthorizedClient(
          'partner',
          'anonymousUser',
        ))!.accessToken.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });
  });

  group('auto-configuration', () {
    final runner = const ApplicationContextRunner()
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
        .withAutoConfiguration(springSecurityCoreAutoConfiguration)
        .withAutoConfiguration(springBootStarterOauth2ClientAutoConfiguration)
        .withBean<HttpTransport>(MockHttpTransport.new);
    const r = 'spring.security.oauth2.client.registration';
    const partner = [
      '$r.partner.client-id=shop',
      '$r.partner.client-secret=s',
      '$r.partner.authorization-grant-type=client_credentials',
      '$r.partner.dpop=true',
      'spring.security.oauth2.client.provider.partner.token-uri=$_tokenUri',
    ];

    test('a SoftwareDPoPKey for the run, used by the token clients', () async {
      await runner.withPropertyValues(partner).runAsync((context) async {
        expect(context.startupFailure, isNull);
        final key = context.getBean<DPoPKey>();
        expect(key, isA<SoftwareDPoPKey>());
        final transport = context.getBean<HttpTransport>() as MockHttpTransport;
        transport
            .when(HttpMethod.post, _tokenUri)
            .respond(
              200,
              json: {'access_token': 'cc', 'token_type': 'DPoP'},
            );
        final client = await context
            .getBean<OAuth2AuthorizedClientManager>()
            .authorize(
              OAuth2AuthorizeRequest.withClientRegistrationId(
                'partner',
              ).principal(anonymousAuthentication).build(),
            );
        expect(client!.accessToken.tokenType, TokenType.dpop);
        final (header, _) = _open(transport.lastRequest.headers['DPoP']!);
        expect(header['jwk'], key.publicJwk);
      });
    });

    test("no key without registrations; the application's key wins", () {
      runner.run((context) {
        expect(context, doesNotHaveBean<DPoPKey>());
      });
      final own = SoftwareDPoPKey.generate();
      runner.withPropertyValues(partner).withBean<DPoPKey>(() => own).run((
        context,
      ) {
        expect(context, hasSingleBean<DPoPKey>());
        expect(context.getBean<DPoPKey>(), same(own));
      });
    });

    test('a bad dpop value fails the start', () {
      runner.withPropertyValues([...partner, '$r.partner.dpop=maybe']).run((
        context,
      ) {
        expect(context.startupFailure, isNotNull);
      });
    });
  });

  test('no key, proof or token in logs or toString', () async {
    final logs = <String>[];
    final cancel = SpringLog.listen(
      (record) => logs.add('${record.message} ${record.error ?? ''}'),
    );
    final saved = SpringLog.level;
    SpringLog.level = SpringLogLevel.trace;
    addTearDown(() {
      cancel();
      SpringLog.level = saved;
    });
    final key = SoftwareDPoPKey.generate();
    final transport = MockHttpTransport()
      ..when(HttpMethod.post, _tokenUri).respondWith(
        (request) => _jsonResponse(
          request,
          400,
          {'error': 'use_dpop_nonce'},
          headers: {'DPoP-Nonce': 'n'},
        ),
      )
      ..when(HttpMethod.post, _tokenUri).respondWith(
        (request) => _jsonResponse(request, 200, {
          'access_token': 'secret-access-token',
          'token_type': 'DPoP',
          'refresh_token': 'secret-refresh-token',
        }),
      );
    final response =
        await DefaultClientCredentialsTokenResponseClient(
          transport,
          dPoPKey: key,
        ).getTokenResponse(
          OAuth2ClientCredentialsGrantRequest(
            _registration(dpop: DPoPMode.enabled),
          ),
        );
    final proofs = [for (final r in transport.requests) r.headers['DPoP']!];
    final texts = [
      ...logs,
      '$response',
      '${response.accessToken}',
      '$key',
      '${DPoPProofBuilder(key)}',
      '${DPoPProofClaims.fromJson(_json(proofs.first.split('.')[1]))}',
    ].join('\n');
    expect(logs, isNotEmpty); // the nonce retry is logged
    for (final secret in [
      'secret-access-token',
      'secret-refresh-token',
      key.toJwk()['d']! as String,
      ...proofs,
      for (final proof in proofs) proof.split('.')[2],
    ]) {
      expect(texts, isNot(contains(secret)));
    }
  });
}

// A key whose public part is known only after load(), as the platform
// keys of the Flutter security package.
final class _LazyKey implements LoadableDPoPKey {
  _LazyKey(this._key);
  final SoftwareDPoPKey _key;

  @override
  bool get persistent => true;
  bool _loaded = false;
  int loads = 0;

  @override
  Future<void> load() async {
    loads++;
    await Future<void>.delayed(Duration.zero);
    _loaded = true;
  }

  @override
  String get algorithm => 'ES256';

  @override
  Map<String, Object?> get publicJwk =>
      _loaded ? _key.publicJwk : throw StateError('not loaded');

  @override
  Future<Uint8List> sign(Uint8List input) => _key.sign(input);
}
