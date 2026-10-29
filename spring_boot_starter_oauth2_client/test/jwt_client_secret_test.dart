// The client secret that is a JWT (Sign in with Apple's): the PKCS #8 key,
// the header and claims Apple asks for, the ES256 signature checked with
// pointycastle (not with the code tested), the cache, the properties and
// the bean, the token request carrying it, and no key in any message.
// Also the response mode (form_post) of registrations, the authorization
// response read from a posted form, and the `apple` common provider.
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

// A P-256 test key in PKCS #8 (made with `openssl ecparam -name
// prime256v1 -genkey | openssl pkcs8 -topk8 -nocrypt`), and its public
// point (`openssl ec -pubout -text`).
const _pem = '''
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg8AKcLRNkUBl8oFs5
0Ghza1oULwQqaBQ2SX04I4iCNQihRANCAATVdYNqAd2owA7sqhNT39lMsIltaiQq
2cQMbHMCbVIe+tokO/8ivpFPBy9RU3FQ4+0AOa6GorvtZ8veVGvyxAGO
-----END PRIVATE KEY-----
''';
const _privateHex =
    'f0029c2d136450197ca05b39d068736b5a142f042a681436497d382388823508';
const _publicHex =
    'd575836a01dda8c00eecaa1353dfd94cb0896d6a242ad9c40c6c73026d521efa'
    'da243bff22be914f072f51537150e3ed0039ae86a2bbed67cbde546bf2c4018e';

// A P-384 key: not a key for ES256.
const _p384Pem = '''
-----BEGIN PRIVATE KEY-----
MIG2AgEAMBAGByqGSM49AgEGBSuBBAAiBIGeMIGbAgEBBDAUZ5HPp5wkvbxlj1KG
U30pyAeEOduHy0dLOfsyGXmcYquMHa5Hh/JYcOVKbhudE1qhZANiAAR9flAhAKkW
zR/tDU2cUtQrgmBf7bNNfm/zHfZ61XwTlMZEKJNYR7aKu9YB5F5TTQd1zfe7YB6h
BZZ5cocvV9owOj4dg7G8OY02ZpMt9C6UJbXsBMMIdxOXDIul7mYYxLo=
-----END PRIVATE KEY-----
''';

BigInt _hexInt(String hex) => BigInt.parse(hex, radix: 16);

List<int> _unb64(String text) => base64Url.decode(base64Url.normalize(text));

BigInt _int(List<int> bytes) =>
    bytes.fold(BigInt.zero, (value, b) => (value << 8) | BigInt.from(b));

Map<String, Object?> _json(String part) =>
    jsonDecode(utf8.decode(_unb64(part))) as Map<String, Object?>;

bool _verifiesWithTestKey(String jwt) {
  final parts = jwt.split('.');
  final signature = _unb64(parts[2]);
  if (signature.length != 64) {
    return false;
  }
  final domain = ECCurve_secp256r1();
  final point = domain.curve.createPoint(
    _hexInt(_publicHex.substring(0, 64)),
    _hexInt(_publicHex.substring(64)),
  );
  final verifier = ECDSASigner(SHA256Digest())
    ..init(false, PublicKeyParameter<ECPublicKey>(ECPublicKey(point, domain)));
  return verifier.verifySignature(
    Uint8List.fromList(ascii.encode('${parts[0]}.${parts[1]}')),
    ECSignature(_int(signature.sublist(0, 32)), _int(signature.sublist(32))),
  );
}

const _jwt =
    'spring.security.oauth2.client.registration.apple.client-secret-jwt';

Environment _environment(Map<String, Object> values) {
  final environment = StandardEnvironment()
    ..propertySources.addFirst(MapPropertySource('test', values));
  ConfigurationPropertySources.attach(environment);
  return environment;
}

ClientRegistration _apple({
  ClientAuthenticationMethod? method,
  String clientId = 'books.neon.web',
}) => CommonOAuth2Provider.apple
    .getBuilder('apple')
    .clientId(clientId)
    .clientAuthenticationMethod(
      method ?? ClientAuthenticationMethod.clientSecretPost,
    )
    .build();

void main() {
  group('JwtClientSecret', () {
    test('reads the PKCS #8 key and signs the JWT Apple asks for', () {
      final now = DateTime.utc(2026, 10, 29, 12);
      final secret = JwtClientSecret.fromPem(
        issuer: 'DEF123GHIJ',
        keyId: 'ABC123DEFG',
        pem: _pem,
        clock: () => now,
      );
      final jwt = secret.clientSecret(_apple());
      final parts = jwt.split('.');
      expect(parts, hasLength(3));
      expect(_json(parts[0]), {'alg': 'ES256', 'kid': 'ABC123DEFG'});
      final iat = now.millisecondsSinceEpoch ~/ 1000;
      expect(_json(parts[1]), {
        'iss': 'DEF123GHIJ',
        'iat': iat,
        'exp': iat + 3600,
        'aud': 'https://appleid.apple.com',
        'sub': 'books.neon.web',
      });
      expect(_verifiesWithTestKey(jwt), isTrue);
    });

    test('the key read from the PEM is the key of the file', () {
      final fromPem = JwtClientSecret.fromPem(
        issuer: 'T',
        keyId: 'K',
        pem: _pem,
        clock: () => DateTime.utc(2026),
      ).clientSecret(_apple());
      final fromNumber = JwtClientSecret(
        issuer: 'T',
        keyId: 'K',
        privateKey: _hexInt(_privateHex),
        clock: () => DateTime.utc(2026),
      ).clientSecret(_apple());
      // RFC 6979: the same key and message give the same signature.
      expect(fromPem, fromNumber);
    });

    test('is cached and made again before it expires', () {
      var now = DateTime.utc(2026, 10, 29, 12);
      final secret = JwtClientSecret.fromPem(
        issuer: 'T',
        keyId: 'K',
        pem: _pem,
        clock: () => now,
      );
      final first = secret.clientSecret(_apple());
      now = now.add(const Duration(minutes: 50));
      expect(secret.clientSecret(_apple()), first);
      now = now.add(const Duration(minutes: 5)); // 5 minutes left: < 10 %
      final second = secret.clientSecret(_apple());
      expect(second, isNot(first));
      expect(_verifiesWithTestKey(second), isTrue);
      // Another client id gets its own JWT.
      final other = secret.clientSecret(_apple(clientId: 'books.neon.app'));
      expect(_json(other.split('.')[1])['sub'], 'books.neon.app');
    });

    test('an explicit audience wins over the issuer', () {
      final jwt = JwtClientSecret.fromPem(
        issuer: 'T',
        keyId: 'K',
        pem: _pem,
        audience: 'https://other.test',
      ).clientSecret(_apple());
      expect(_json(jwt.split('.')[1])['aud'], 'https://other.test');
    });

    test('refuses keys that are not P-256 PKCS #8, without key material', () {
      for (final pem in [
        _p384Pem,
        'no pem at all',
        '-----BEGIN PRIVATE KEY-----\n!!!\n-----END PRIVATE KEY-----',
        '-----BEGIN PRIVATE KEY-----\nMAA=\n-----END PRIVATE KEY-----',
        _pem.replaceAll('PRIVATE KEY', 'EC PRIVATE KEY'),
      ]) {
        expect(
          () => JwtClientSecret.fromPem(issuer: 'T', keyId: 'K', pem: pem),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              isNot(contains('MIG')),
            ),
          ),
          reason: pem,
        );
      }
    });

    test('refuses lifetimes Apple refuses, empty ids, and keys out of '
        'range', () {
      expect(
        () => JwtClientSecret.fromPem(
          issuer: 'T',
          keyId: 'K',
          pem: _pem,
          lifetime: const Duration(days: 181),
        ),
        throwsArgumentError,
      );
      expect(
        () => JwtClientSecret.fromPem(issuer: ' ', keyId: 'K', pem: _pem),
        throwsArgumentError,
      );
      expect(
        () => JwtClientSecret.fromPem(issuer: 'T', keyId: '', pem: _pem),
        throwsArgumentError,
      );
      expect(
        () => JwtClientSecret(issuer: 'T', keyId: 'K', privateKey: BigInt.zero),
        throwsArgumentError,
      );
    });

    test('never shows the key', () {
      final secret = JwtClientSecret.fromPem(
        issuer: 'T',
        keyId: 'K',
        pem: _pem,
      );
      expect('$secret', contains('[PROTECTED]'));
      expect('$secret', isNot(contains(_hexInt(_privateHex).toString())));
    });
  });

  group('the token request with a JWT client secret', () {
    MockHttpTransport transport() {
      final mock = MockHttpTransport();
      mock
          .when(HttpMethod.post, 'https://appleid.apple.com/auth/token')
          .respondWith(
            (_) => HttpResponse(
              200,
              headers: HttpHeaders({
                HttpHeaders.contentTypeHeader: 'application/json',
              }),
              body: utf8.encode(
                jsonEncode({
                  'access_token': 'at',
                  'token_type': 'Bearer',
                  'expires_in': 3600,
                }),
              ),
            ),
          );
      return mock;
    }

    OAuth2AuthorizationCodeGrantRequest grant(ClientRegistration r) =>
        OAuth2AuthorizationCodeGrantRequest(
          r,
          OAuth2AuthorizationExchange(
            OAuth2AuthorizationRequest.forRegistration(
              r,
              redirectUri: 'https://books.neon.test/login/oauth2/code/apple',
            ),
            const OAuth2AuthorizationResponse(
              redirectUri: 'https://books.neon.test/login/oauth2/code/apple',
              code: 'c',
              state: 's',
            ),
          ),
        );

    test('sends the JWT as client_secret (client_secret_post)', () async {
      final mock = transport();
      final client = DefaultAuthorizationCodeTokenResponseClient(
        mock,
        clientSecretResolver: JwtClientSecretResolver({
          'apple': JwtClientSecret.fromPem(
            issuer: 'T',
            keyId: 'K',
            pem: _pem,
          ),
        }),
      );
      await client.getTokenResponse(grant(_apple()));
      final form = Uri.splitQueryString(
        utf8.decode(mock.requests.single.body!),
      );
      expect(form['client_id'], 'books.neon.web');
      expect(_verifiesWithTestKey(form['client_secret']!), isTrue);
    });

    test('a registration that sends no secret is refused, not sent without '
        'it', () async {
      final mock = transport();
      final client = DefaultAuthorizationCodeTokenResponseClient(
        mock,
        clientSecretResolver: JwtClientSecretResolver({
          'apple': JwtClientSecret.fromPem(
            issuer: 'T',
            keyId: 'K',
            pem: _pem,
          ),
        }),
      );
      await expectLater(
        client.getTokenResponse(
          grant(_apple(method: ClientAuthenticationMethod.none)),
        ),
        throwsA(
          isA<OAuth2AuthorizationException>().having(
            (e) => e.error.errorCode,
            'errorCode',
            OAuth2ErrorCodes.invalidClient,
          ),
        ),
      );
      expect(mock.requests, isEmpty);
    });

    test('the bean of the properties signs with the key file', () async {
      const r = 'spring.security.oauth2.client.registration.apple';
      await const ApplicationContextRunner()
          .withAutoConfiguration(springBootAutoConfiguration)
          .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
          .withAutoConfiguration(springSecurityCoreAutoConfiguration)
          .withAutoConfiguration(
            springBootStarterOauth2ClientAutoConfiguration,
          )
          .withBean<HttpTransport>(transport)
          .withPropertyValues([
            '$r.client-id=books.neon.web',
            '$r.client-authentication-method=client_secret_post',
            '$r.client-secret-jwt.issuer=DEF123GHIJ',
            '$r.client-secret-jwt.key-id=ABC123DEFG',
            '$r.client-secret-jwt.private-key=${_pem.replaceAll('\n', r'\n')}',
            '$r.client-secret-jwt.lifetime=10m',
          ])
          .runAsync((context) async {
            expect(context.startupFailure, isNull);
            expect(
              context.getBean<OAuth2ClientSecretResolver>(),
              isA<JwtClientSecretResolver>(),
            );
            final mock = context.getBean<HttpTransport>() as MockHttpTransport;
            final registration = (await context
                .getBean<ClientRegistrationRepository>()
                .findByRegistrationId('apple'))!;
            expect(registration.responseMode, ResponseMode.formPost);
            await context
                .getBean<
                  OAuth2AccessTokenResponseClient<
                    OAuth2AuthorizationCodeGrantRequest
                  >
                >()
                .getTokenResponse(grant(registration));
            final form = Uri.splitQueryString(
              utf8.decode(mock.requests.single.body!),
            );
            final claims = _json(form['client_secret']!.split('.')[1]);
            expect(claims['iss'], 'DEF123GHIJ');
            expect((claims['exp']! as int) - (claims['iat']! as int), 600);
            expect(_verifiesWithTestKey(form['client_secret']!), isTrue);
          });
    });

    test('without client-secret-jwt properties: no resolver', () async {
      await const ApplicationContextRunner()
          .withAutoConfiguration(springBootAutoConfiguration)
          .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
          .withAutoConfiguration(springSecurityCoreAutoConfiguration)
          .withAutoConfiguration(
            springBootStarterOauth2ClientAutoConfiguration,
          )
          .withBean<HttpTransport>(transport)
          .withPropertyValues([
            'spring.security.oauth2.client.registration.apple.client-id=x',
          ])
          .runAsync((context) async {
            expect(context.startupFailure, isNull);
            expect(context, doesNotHaveBean<OAuth2ClientSecretResolver>());
          });
    });

    test('a key that cannot be read fails the request as invalid_client, '
        'without the key in the message or the log', () async {
      final resolver = JwtClientSecretResolver.fromEnvironment(
        _environment({
          '$_jwt.issuer': 'T',
          '$_jwt.key-id': 'K',
          '$_jwt.private-key': _p384Pem,
        }),
      );
      await expectLater(
        resolver.resolve(_apple()),
        throwsA(
          isA<OAuth2AuthorizationException>()
              .having(
                (e) => e.error.errorCode,
                'errorCode',
                OAuth2ErrorCodes.invalidClient,
              )
              .having((e) => '$e', 'text', isNot(contains('MIG'))),
        ),
      );
    });

    test('incomplete properties fail at once', () {
      expect(
        () => JwtClientSecretResolver.fromEnvironment(
          _environment({
            '$_jwt.issuer': 'T',
            '$_jwt.private-key': _pem,
          }),
        ),
        throwsArgumentError,
      );
    });
  });

  group('response mode', () {
    test('form_post is sent with the authorization request', () {
      final request = OAuth2AuthorizationRequest.forRegistration(
        _apple(),
        redirectUri: 'https://books.neon.test/login/oauth2/code/apple',
      );
      expect(
        request.authorizationRequestUri.queryParameters['response_mode'],
        'form_post',
      );
      expect(request.responseMode, ResponseMode.formPost);
    });

    test('query sends no response_mode', () {
      final registration = ClientRegistration.withRegistrationId('kc')
          .clientId('app')
          .authorizationGrantType(AuthorizationGrantType.authorizationCode)
          .redirectUri('app:/cb')
          .authorizationUri('https://sso.test/auth')
          .tokenUri('https://sso.test/token')
          .build();
      final request = OAuth2AuthorizationRequest.forRegistration(
        registration,
        redirectUri: 'app:/cb',
      );
      expect(
        request.authorizationRequestUri.queryParameters,
        isNot(contains('response_mode')),
      );
      expect(request.responseMode, ResponseMode.query);
    });

    test('the property sets it; fragment and unknown values fail at '
        'startup', () {
      ClientRegistrationSupplier supplier(String mode) =>
          OAuth2ClientPropertiesMapper(
            const OAuth2ClientProperties(
              registration: {
                'apple': OAuth2ClientRegistrationProperties(
                  clientId: 'books.neon.app',
                  responseMode: 'query',
                ),
              },
            ),
          ).asClientRegistrations()['apple']!;
      expect(supplier, isNotNull);
      expect(ResponseMode.parse('FORM-POST'), ResponseMode.formPost);
      expect(() => ResponseMode.parse('fragment'), throwsArgumentError);
      expect(
        () => OAuth2ClientPropertiesMapper(
          const OAuth2ClientProperties(
            registration: {
              'apple': OAuth2ClientRegistrationProperties(
                clientId: 'x',
                responseMode: 'fragment',
              ),
            },
          ),
        ).asClientRegistrations(),
        throwsArgumentError,
      );
    });

    test('an app sets query on the apple preset', () async {
      final registrations = OAuth2ClientPropertiesMapper(
        const OAuth2ClientProperties(
          registration: {
            'apple': OAuth2ClientRegistrationProperties(
              clientId: 'books.neon.app',
              responseMode: 'query',
              redirectUri: 'https://books.neon.test/oauth2/callback',
            ),
          },
        ),
      ).asClientRegistrations();
      final apple = await registrations['apple']!();
      expect(apple.responseMode, ResponseMode.query);
      // No secret, no method: a public client.
      expect(apple.clientAuthenticationMethod, ClientAuthenticationMethod.none);
    });

    test('the apple preset', () {
      final apple = _apple();
      expect(apple.scopes, {'openid', 'name', 'email'});
      expect(apple.providerDetails.issuerUri, 'https://appleid.apple.com');
      expect(
        apple.providerDetails.jwkSetUri,
        'https://appleid.apple.com/auth/keys',
      );
      expect(apple.providerDetails.userInfoEndpoint.uri, isNull);
      expect(apple.responseMode, ResponseMode.formPost);
      expect(CommonOAuth2Provider.of('Apple'), CommonOAuth2Provider.apple);
      expect('$apple', contains('responseMode=form_post'));
    });

    test('a posted response is read like a redirect; other parameters are '
        'kept apart', () {
      final response = OAuth2AuthorizationResponse.fromParameters(
        {
          'code': ['c'],
          'state': ['s'],
          'user': ['{"name":{"firstName":"Ada"}}'],
          'twice': ['a', 'b'],
        },
        redirectUri: 'https://books.neon.test/login/oauth2/code/apple',
      );
      expect(response.code, 'c');
      expect(response.state, 's');
      expect(response.additionalParameters, {
        'user': '{"name":{"firstName":"Ada"}}',
      });
      final duplicated = OAuth2AuthorizationResponse.fromParameters({
        'code': ['c', 'd'],
        'state': ['s'],
      }, redirectUri: 'x');
      expect(duplicated.code, isNull);
      expect('$response', isNot(contains('c,')));
    });
  });
}
