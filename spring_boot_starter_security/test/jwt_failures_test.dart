// How the JWT machinery fails: an unreadable or unreachable JWK Set, wrong
// decoder settings, issuer metadata that cannot be used, a decoder that
// cannot work (a 401 without details, not an invalid_token), the Bearer
// challenge with and without realm and error, a bearer token that never
// shows itself, and the scope claims that become authorities.
import 'dart:convert';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'app/jwt/keys.dart';

final class _FailingDecoder implements JwtDecoder {
  _FailingDecoder(this.error);

  final JwtException error;

  @override
  Future<Jwt> decode(String token) async => throw error;
}

Jwt _jwt(Map<String, Object?> claims) =>
    Jwt('t.o.k', headers: const {'alg': 'RS256'}, claims: claims);

List<String?> _names(List<GrantedAuthority> authorities) => [
  for (final a in authorities) a.authority,
];

Matcher _jwtException(String text) => throwsA(
  isA<JwtException>().having((e) => e.message, 'message', contains(text)),
);

void main() {
  final keys = testKeys;

  group('JWK Set documents', () {
    test('text that is not JSON is a JwtException, not a crash', () {
      expect(() => parseJwkSet('<html>'), _jwtException('not valid JSON'));
      expect(() => parseJwkSet(''), _jwtException('not valid JSON'));
    });

    test('keeps the parse error as the cause', () {
      try {
        parseJwkSet('{');
        fail('should throw');
      } on JwtException catch (e) {
        expect(e.cause, isA<FormatException>());
      }
    });

    test('JSON that is no set is refused', () {
      for (final text in ['[]', '"keys"', '{"keys": "x"}', '{}', 'null']) {
        expect(
          () => parseJwkSet(text),
          _jwtException('no "keys"'),
          reason: text,
        );
      }
    });

    test('a key that cannot be read does not spoil the others', () {
      final good = keys.rsa.jwk;
      final set = parseJwkSet(
        jsonEncode({
          'keys': [
            'not a key',
            {'kty': 'RSA', 'n': 1},
            {'kty': 'RSA'},
            {'kty': 'oct', 'k': 'AAAA'},
            {'kty': 'RSA', 'use': 'enc', 'n': good['n'], 'e': good['e']},
            good,
          ],
        }),
      );
      expect(set, hasLength(1));
      expect(set.single.keyId, keys.rsa.kid);
    });
  });

  group('a JWK Set that cannot be fetched', () {
    test('is a JwtException naming the cause', () async {
      final source = RemoteJwkSource(
        Uri.parse('https://issuer.example/jwks'),
        fetcher: (_) async => throw StateError('connection refused'),
      );
      await expectLater(
        source.keys(),
        _jwtException("Couldn't retrieve remote JWK set"),
      );
      await expectLater(source.keys(), _jwtException('connection refused'));
    });

    test('is not a BadJwtException: the token is not to blame', () async {
      final decoder = NimbusJwtDecoder.withJwkSetUri(
        Uri.parse('https://issuer.example/jwks'),
        fetcher: (_) async => throw StateError('down'),
      );
      await expectLater(
        decoder.decode(keys.token()),
        throwsA(
          isA<JwtException>().having(
            (e) => e,
            'is a bad token',
            isNot(isA<BadJwtException>()),
          ),
        ),
      );
    });

    // Before: every token made a new request while the endpoint was down.
    test('is fetched again 30 seconds later at the earliest, not with '
        'every token', () async {
      var now = DateTime(2026);
      var requests = 0;
      var down = true;
      final source = RemoteJwkSource(
        Uri.parse('https://issuer.example/jwks'),
        clock: () => now,
        fetcher: (_) async {
          requests++;
          if (down) {
            throw StateError('connection refused');
          }
          return jsonEncode({
            'keys': [keys.rsa.jwk],
          });
        },
      );
      final decoder = NimbusJwtDecoder.withJwkSource(source);
      for (var i = 0; i < 50; i++) {
        await expectLater(
          decoder.decode(keys.token(kid: 'made-up-$i')),
          _jwtException('connection refused'),
        );
      }
      expect(requests, 1);
      down = false;
      now = now.add(const Duration(seconds: 29));
      await expectLater(source.keys(), _jwtException('connection refused'));
      expect(requests, 1);
      now = now.add(const Duration(seconds: 1));
      await decoder.decode(keys.token());
      expect(requests, 2);
      // Keys known, then the endpoint down and the keys old: one attempt
      // per interval, the old keys meanwhile.
      down = true;
      now = now.add(const Duration(minutes: 10));
      for (var i = 0; i < 50; i++) {
        await decoder.decode(keys.token());
        await expectLater(
          decoder.decode(keys.token(kid: 'made-up-$i')),
          throwsA(isA<BadJwtException>()),
        );
      }
      expect(requests, 3);
      now = now.add(const Duration(seconds: 30));
      await decoder.decode(keys.token());
      expect(requests, 4);
    });

    test('a document that is not JSON fails the same way', () async {
      final source = RemoteJwkSource(
        Uri.parse('https://issuer.example/jwks'),
        fetcher: (_) async => '<html>captive portal</html>',
      );
      await expectLater(source.keys(), _jwtException('not valid JSON'));
    });
  });

  group('NimbusJwtDecoder.withSecretKey', () {
    final secret = List<int>.filled(32, 7);

    test('a signature algorithm of another family is refused', () {
      for (final algorithm in [
        JwsAlgorithm.rs256,
        JwsAlgorithm.ps384,
        JwsAlgorithm.es512,
      ]) {
        expect(
          () => NimbusJwtDecoder.withSecretKey(secret, macAlgorithm: algorithm),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('not an HMAC algorithm'),
            ),
          ),
          reason: algorithm.name,
        );
      }
    });

    test('a secret shorter than the hash is refused', () {
      expect(
        () => NimbusJwtDecoder.withSecretKey(List.filled(31, 1)),
        throwsArgumentError,
      );
      expect(
        () => NimbusJwtDecoder.withSecretKey(
          secret,
          macAlgorithm: JwsAlgorithm.hs512,
        ),
        throwsArgumentError,
      );
    });

    test('a secret of the size of the hash is accepted', () {
      expect(NimbusJwtDecoder.withSecretKey(secret), isA<JwtDecoder>());
    });
  });

  group('JwsAlgorithm', () {
    test('keyType is the JWK kty of its keys', () {
      expect(
        {
          for (final a in JwsAlgorithm.values)
            if (!a.name.startsWith('P')) a.name: a.keyType,
        },
        {
          'RS256': 'RSA',
          'RS384': 'RSA',
          'RS512': 'RSA',
          'ES256': 'EC',
          'ES384': 'EC',
          'ES512': 'EC',
          'HS256': 'oct',
          'HS384': 'oct',
          'HS512': 'oct',
        },
      );
      expect(JwsAlgorithm.ps256.keyType, 'RSA');
      expect(JwsAlgorithm.ps512.keyType, 'RSA');
    });
  });

  group('issuer metadata that cannot be used', () {
    Future<Object> failure(JwkFetcher fetcher) async {
      final decoder = JwtDecoders.fromIssuerLocation(
        'https://issuer.example',
        fetcher: fetcher,
      );
      try {
        await decoder.decode(keys.token());
      } on Object catch (e) {
        return e;
      }
      fail('should not decode');
    }

    test('without jwks_uri: refused, and not a bad token', () async {
      final error = await failure(
        (_) async => jsonEncode({'issuer': 'https://issuer.example'}),
      );
      expect(error, isA<JwtException>());
      expect(error, isNot(isA<BadJwtException>()));
      expect(
        (error as JwtException).message,
        allOf(
          contains('Unable to resolve the issuer'),
          contains('no jwks_uri'),
        ),
      );
    });

    test('a jwks_uri that is no text: refused', () async {
      final error = await failure(
        (_) async => jsonEncode({
          'issuer': 'https://issuer.example',
          'jwks_uri': ['https://evil.example/jwks'],
        }),
      );
      expect((error as JwtException).message, contains('no jwks_uri'));
    });

    test('an issuer of another name: refused, naming both', () async {
      final error = await failure(
        (_) async => jsonEncode({
          'issuer': 'https://evil.example',
          'jwks_uri': 'https://issuer.example/jwks',
        }),
      );
      expect(
        (error as JwtException).message,
        allOf(contains('https://evil.example'), contains('did not match')),
      );
    });

    test(
      'a document that is not an object is skipped; none left: refused',
      () async {
        var fetched = 0;
        final error = await failure((_) async {
          fetched++;
          return '[1, 2]';
        });
        expect(fetched, 3, reason: 'the three standard places');
        expect(
          (error as JwtException).message,
          contains('No metadata for issuer https://issuer.example'),
        );
      },
    );

    test('is tried again 30 seconds later, not with every token', () async {
      var up = false;
      var requests = 0;
      var now = DateTime(2026);
      final decoder = JwtDecoders.fromIssuerLocation(
        'https://issuer.example',
        clock: () => now,
        fetcher: (uri) async {
          requests++;
          if (!up) {
            throw StateError('down');
          }
          return uri.path.endsWith('jwks')
              ? jsonEncode({
                  'keys': [keys.rsa.jwk],
                })
              : jsonEncode({
                  'issuer': 'https://issuer.example',
                  'jwks_uri': 'https://issuer.example/jwks',
                });
        },
      );
      final token = keys.token(claims: {'iss': 'https://issuer.example'});
      await expectLater(decoder.decode(token), throwsA(isA<JwtException>()));
      final lookup = requests; // the metadata locations tried
      expect(lookup, greaterThan(0));
      up = true;
      // Many tokens while the provider was down a moment ago: no request.
      for (var i = 0; i < 50; i++) {
        await expectLater(
          decoder.decode(token),
          throwsA(
            isA<JwtException>().having(
              (e) => e.message,
              'message',
              contains('down'),
            ),
          ),
        );
      }
      expect(requests, lookup);
      now = now.add(const Duration(seconds: 30));
      expect((await decoder.decode(token)).subject, isNotNull);
      expect(requests, lookup + 2); // the metadata, then the keys
    });

    test('audiences set: a token for another audience is refused', () async {
      JwtDecoder decoder(List<String> audiences) =>
          JwtDecoders.fromIssuerLocation(
            'https://issuer.example',
            audiences: audiences,
            fetcher: (uri) async => uri.path.endsWith('jwks')
                ? jsonEncode({
                    'keys': [keys.rsa.jwk],
                  })
                : jsonEncode({
                    'issuer': 'https://issuer.example',
                    'jwks_uri': 'https://issuer.example/jwks',
                  }),
          );
      final token = keys.token(
        claims: {'iss': 'https://issuer.example', 'aud': 'web'},
      );
      await expectLater(
        decoder(['api']).decode(token),
        throwsA(isA<JwtValidationException>()),
      );
      expect((await decoder(['api', 'web']).decode(token)).audience, ['web']);
      expect((await decoder(const []).decode(token)).audience, ['web']);
    });
  });

  group('JwtAuthenticationProvider', () {
    BearerTokenAuthenticationToken bearer() =>
        BearerTokenAuthenticationToken('a.b.c');

    test('a bad token is an invalid_token with the decoder reason', () async {
      final provider = JwtAuthenticationProvider(
        _FailingDecoder(BadJwtException('Jwt expired')),
      );
      await expectLater(
        provider.authenticate(bearer()),
        throwsA(
          isA<InvalidBearerTokenException>()
              .having((e) => e.error.errorCode, 'code', 'invalid_token')
              .having((e) => e.message, 'message', 'Jwt expired'),
        ),
      );
    });

    test('a decoder that cannot work is a service failure, not a bad '
        'token', () async {
      final provider = JwtAuthenticationProvider(
        _FailingDecoder(JwtException('issuer down')),
      );
      await expectLater(
        provider.authenticate(bearer()),
        throwsA(
          isA<AuthenticationServiceException>().having(
            (e) => e,
            'is an OAuth2 error',
            isNot(isA<OAuth2AuthenticationException>()),
          ),
        ),
      );
    });

    test('supports bearer tokens only', () {
      final provider = JwtAuthenticationProvider(
        _FailingDecoder(JwtException('x')),
      );
      expect(provider.supports(bearer()), isTrue);
      expect(
        provider.supports(
          UsernamePasswordAuthenticationToken.unauthenticated('a', 'b'),
        ),
        isFalse,
      );
    });

    test('the request details go to the result', () async {
      final provider = JwtAuthenticationProvider(
        NimbusJwtDecoder.withPublicKey(keys.rsa.verificationKey),
      );
      final details = WebAuthenticationDetails.of(
        MockServerHttpRequest(HttpMethod.get, '/'),
      );
      final result = await provider.authenticate(
        BearerTokenAuthenticationToken(keys.token())..details = details,
      );
      expect(result, isA<JwtAuthenticationToken>());
      expect((result! as JwtAuthenticationToken).details, details);
      expect(result.isAuthenticated, isTrue);
    });
  });

  group('the bearer token', () {
    test('is not authenticated, has no name, and is its own credentials', () {
      final token = BearerTokenAuthenticationToken('a.b.c');
      expect(token.isAuthenticated, isFalse);
      expect(token.name, isEmpty);
      expect(token.principal, 'a.b.c');
      expect(token.credentials, 'a.b.c');
      expect(token.authorities, isEmpty);
    });

    test('two Authorization headers are refused', () {
      final request = MockServerHttpRequest(HttpMethod.get, '/');
      request.headers
        ..add(HttpHeaders.authorizationHeader, 'Bearer a')
        ..add(HttpHeaders.authorizationHeader, 'Bearer b');
      expect(
        () => const DefaultBearerTokenResolver().resolve(request),
        throwsA(isA<InvalidBearerTokenException>()),
      );
    });
  });

  group('the Bearer challenge', () {
    Future<String?> challenge(
      AuthenticationEntryPoint entryPoint,
      AuthenticationException exception,
    ) async {
      final response = MockServerHttpResponse();
      await entryPoint.commence(
        MockServerHttpRequest(HttpMethod.get, '/api/me'),
        response,
        exception,
      );
      expect(response.statusCode, 401);
      return response.headers['www-authenticate'];
    }

    test('without a token: just "Bearer"', () async {
      expect(
        await challenge(
          const BearerTokenAuthenticationEntryPoint(),
          InsufficientAuthenticationException('x'),
        ),
        'Bearer',
      );
    });

    test('with a realm', () async {
      expect(
        await challenge(
          const BearerTokenAuthenticationEntryPoint(realmName: 'api'),
          InsufficientAuthenticationException('x'),
        ),
        'Bearer realm="api"',
      );
    });

    test('with a bad token: the error, its description and uri', () async {
      expect(
        await challenge(
          const BearerTokenAuthenticationEntryPoint(realmName: 'api'),
          InvalidBearerTokenException('Jwt expired'),
        ),
        'Bearer realm="api", error="invalid_token", '
        'error_description="Jwt expired", '
        'error_uri="https://tools.ietf.org/html/rfc6750#section-3.1"',
      );
    });

    test('a quote in the description cannot break the header', () async {
      final header = await challenge(
        const BearerTokenAuthenticationEntryPoint(),
        InvalidBearerTokenException('bad "x", error="none"'),
      );
      expect(header, contains('''error_description="bad 'x', error='none'"'''));
    });

    test('an error without description or uri has only the code', () async {
      expect(
        await challenge(
          const BearerTokenAuthenticationEntryPoint(),
          OAuth2AuthenticationException(const OAuth2Error('server_error')),
        ),
        'Bearer error="server_error"',
      );
    });

    test('the body does not repeat the error', () async {
      final response = MockServerHttpResponse();
      await const BearerTokenAuthenticationEntryPoint().commence(
        MockServerHttpRequest(HttpMethod.get, '/api/me'),
        response,
        InvalidBearerTokenException('secret detail'),
      );
      expect(response.bodyText, isNot(contains('secret detail')));
    });
  });

  group('the access denied answer of a resource server', () {
    Future<String?> denied(Authentication? authentication, {String? realm}) =>
        SecurityContextHolder.runWithContext(() async {
          SecurityContextHolder.getContext().authentication = authentication;
          final response = MockServerHttpResponse();
          await BearerTokenAccessDeniedHandler(realmName: realm).handle(
            MockServerHttpRequest(HttpMethod.get, '/api/admin'),
            response,
            AccessDeniedException('no'),
          );
          expect(response.statusCode, 403);
          return response.headers['www-authenticate'];
        });

    test('a JWT user lacks scope: insufficient_scope', () async {
      final header = await denied(
        JwtAuthenticationToken(_jwt({'sub': 'ada'}), const []),
        realm: 'api',
      );
      expect(header, startsWith('Bearer realm="api", '));
      expect(header, contains('error="insufficient_scope"'));
      expect(header, contains('error_uri='));
    });

    test('another user gets a bare challenge', () async {
      expect(
        await denied(
          UsernamePasswordAuthenticationToken.authenticated('ada', null, []),
        ),
        'Bearer',
      );
      expect(await denied(null, realm: 'api'), 'Bearer realm="api"');
    });
  });

  group('the authorities of a JWT', () {
    const converter = JwtGrantedAuthoritiesConverter();

    test('scope is split at spaces, blanks dropped', () {
      expect(_names(converter.convert(_jwt({'scope': ' read  write '}))), [
        'SCOPE_read',
        'SCOPE_write',
      ]);
    });

    test('scp is read when there is no scope', () {
      expect(
        _names(
          converter.convert(
            _jwt({
              'scp': ['a', 'b'],
            }),
          ),
        ),
        ['SCOPE_a', 'SCOPE_b'],
      );
      expect(_names(converter.convert(_jwt({'scp': 'a b'}))), [
        'SCOPE_a',
        'SCOPE_b',
      ]);
    });

    test('scope wins over scp', () {
      expect(
        _names(
          converter.convert(
            _jwt({
              'scope': 'x',
              'scp': ['y'],
            }),
          ),
        ),
        ['SCOPE_x'],
      );
    });

    test('elements that are no text are ignored', () {
      expect(
        _names(
          converter.convert(
            _jwt({
              'scp': ['a', 1, null, <Object?, Object?>{}, ' '],
            }),
          ),
        ),
        ['SCOPE_a'],
      );
    });

    test('no scope claim, or one of another type, grants nothing', () {
      expect(converter.convert(_jwt({})), isEmpty);
      expect(converter.convert(_jwt({'scope': 5})), isEmpty);
      expect(
        converter.convert(
          _jwt({
            'scope': {'a': 1},
          }),
        ),
        isEmpty,
      );
    });

    test('another claim, prefix and delimiter', () {
      const custom = JwtGrantedAuthoritiesConverter(
        authorityPrefix: 'ROLE_',
        authoritiesClaimName: 'roles',
        authoritiesClaimDelimiter: ',',
      );
      expect(
        _names(custom.convert(_jwt({'roles': 'A,B', 'scope': 'ignored'}))),
        ['ROLE_A', 'ROLE_B'],
      );
      expect(custom.convert(_jwt({'scope': 'ignored'})), isEmpty);
    });

    test('the converter names the user by the principal claim', () {
      const converter = JwtAuthenticationConverter(principalClaimName: 'email');
      final result = converter.convert(
        _jwt({'sub': 'id-1', 'email': 'ada@example.com', 'scope': 'a'}),
      );
      expect(result.name, 'ada@example.com');
      expect(_names(result.authorities.toList()), ['SCOPE_a']);
      expect(
        const JwtAuthenticationConverter().convert(_jwt({'sub': 'id-1'})).name,
        'id-1',
      );
    });
  });
}
