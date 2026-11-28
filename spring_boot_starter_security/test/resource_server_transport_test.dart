// The resource server's keys on the RestClient starter's transport: the
// auto-configured decoder fetches through the httpTransport bean, the host
// of jwk-set-uri (or issuer-uri) joins its allow list, and the jwks_uri
// the issuer's metadata names joins it once discovered (by host name).
import 'dart:convert';

import 'package:spring_boot_starter_security/spring_auto_configuration.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app/jwt/keys.dart';
import 'support.dart';

const _jwt = 'spring.security.oauth2.resourceserver.jwt';

void main() {
  final keys = testKeys;
  final jwks = jsonEncode({
    'keys': [keys.rsa.jwk],
  });

  Future<void> withDecoder(
    MockHttpTransport transport,
    List<String> properties,
    Future<void> Function(JwtDecoder decoder, AllowedAddresses allowed) body,
  ) => securityRunner(null, properties)
      .withAutoConfiguration(springBootStarterRestclientAutoConfiguration)
      .withBean<HttpTransport>(() => transport)
      .runAsync((started) async {
        expect(started.startupFailure, isNull);
        await body(
          started.context.getBean<JwtDecoder>(),
          started.context.getBean<AllowedAddresses>(),
        );
      });

  test('jwk-set-uri: the keys come through the transport bean, its host '
      'is allowed', () async {
    final transport = MockHttpTransport()
      ..when(
        HttpMethod.get,
        'https://keys.test/jwks',
      ).respond(200, body: jwks);
    await withDecoder(transport, ['$_jwt.jwk-set-uri=https://keys.test/jwks'], (
      decoder,
      allowed,
    ) async {
      await decoder.decode(keys.token());
      expect(transport.requests.single.url.host, 'keys.test');
      allowed.checkUrl(Uri.parse('https://keys.test/jwks'));
      expect(
        () => allowed.checkUrl(Uri.parse('https://other.test/')),
        throwsA(isA<FilteredHostException>()),
      );
    });
  });

  test(
    "issuer-uri: the issuer's host, then the discovered jwks_uri's",
    () async {
      const issuer = 'https://issuer.test/realms/shop';
      final transport = MockHttpTransport()
        ..when(
          HttpMethod.get,
          '$issuer/.well-known/openid-configuration',
        ).respond(
          200,
          body: jsonEncode({
            'issuer': issuer,
            'jwks_uri': 'https://keys.cdn.test/certs',
          }),
        )
        ..when(
          HttpMethod.get,
          'https://keys.cdn.test/certs',
        ).respond(200, body: jwks);
      await withDecoder(transport, ['$_jwt.issuer-uri=$issuer'], (
        decoder,
        allowed,
      ) async {
        allowed.checkUrl(Uri.parse(issuer));
        expect(
          () => allowed.checkUrl(Uri.parse('https://keys.cdn.test/certs')),
          throwsA(isA<FilteredHostException>()),
        );
        await decoder.decode(keys.token(claims: {'iss': issuer}));
        allowed.checkUrl(Uri.parse('https://keys.cdn.test/certs'));
        expect(transport.requests, hasLength(2));
      });
    },
  );
}
