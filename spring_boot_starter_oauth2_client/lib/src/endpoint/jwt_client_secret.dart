// The documentation has properties lines, which cannot be wrapped.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/crypto_primitives.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/oauth2_error.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration.dart';

const _log = SpringLog('spring.security.oauth2.client.endpoint');

/// Where the client secret of a token request comes from when it is not
/// the registration's fixed `client-secret`.
///
/// Some providers want a secret that changes: Sign in with Apple takes as
/// `client_secret` a short-lived JWT the server signs with the key of its
/// Apple developer account ([JwtClientSecret]). The token response
/// clients ask the resolver for the secret of each request sent with
/// `client_secret_basic` or `client_secret_post`; `null` keeps the
/// registration's own.
///
/// The starter declares a [JwtClientSecretResolver] as the
/// `clientSecretResolver` bean when a registration has
/// `client-secret-jwt.*` properties; declare your own bean of this type
/// for a secret from a vault.
///
/// Spring (Java): no such type. A Spring application sets the parameters
/// of the token request itself, with a parameters converter of its
/// `RestClientAuthorizationCodeTokenResponseClient`
/// (`NimbusJwtClientAuthenticationParametersConverter` covers
/// `private_key_jwt` and `client_secret_jwt`, which put the JWT in
/// `client_assertion`, not in `client_secret` as Apple does).
abstract interface class OAuth2ClientSecretResolver {
  /// The secret [registration] sends now, or `null` for its
  /// [ClientRegistration.clientSecret].
  ///
  /// A credential: never log it.
  FutureOr<String?> resolve(ClientRegistration registration);
}

/// A client secret that is a JWT signed with ES256 by the client's own
/// private key, made again before it expires: the `client_secret` Sign
/// in with Apple asks for.
///
/// Apple gives a developer account a P-256 key (a `.p8` file, PKCS #8)
/// and wants each token request to carry, as `client_secret`, a JWT with
/// the header `{"alg":"ES256","kid":<key id>}` and the claims `iss` (the
/// team id), `iat`, `exp` (at most six months later), `aud`
/// (`https://appleid.apple.com`) and `sub` (the client id: the Services
/// ID of a web login, the bundle id of an app's code). Only a server can
/// hold that key, so only a server can exchange Apple's codes.
///
/// The JWT is cached and made again when less than a tenth of its
/// [lifetime] (one hour by default) is left, so a request never sends one
/// about to expire. The key never leaves this object: [toString] and the
/// errors never show it.
///
/// ```properties
/// spring.security.oauth2.client.registration.apple.client-id=books.neon.web
/// spring.security.oauth2.client.registration.apple.client-authentication-method=client_secret_post
/// spring.security.oauth2.client.registration.apple.client-secret-jwt.issuer=DEF123GHIJ
/// spring.security.oauth2.client.registration.apple.client-secret-jwt.key-id=ABC123DEFG
/// spring.security.oauth2.client.registration.apple.client-secret-jwt.private-key-location=file:/run/secrets/apple-key.p8
/// ```
///
/// ```dart
/// // The same in code, with the key from a vault.
/// final secret = JwtClientSecret.fromPem(
///   issuer: 'DEF123GHIJ', // the team id
///   keyId: 'ABC123DEFG',
///   pem: await vault.read('apple-key'),
/// );
/// final value = secret.clientSecret(appleRegistration);
/// ```
///
/// Spring (Java): no such class (see [OAuth2ClientSecretResolver]); the
/// JWT is what Spring applications build with Nimbus for Apple.
final class JwtClientSecret {
  /// A secret signed by the P-256 private number [privateKey], named
  /// [keyId], issued by [issuer]; for [audience] (by default the
  /// registration's issuer URI), valid for [lifetime].
  ///
  /// Throws an [ArgumentError] for an empty [issuer] or [keyId], a key
  /// out of range, or a [lifetime] not within one minute and 180 days
  /// (Apple refuses more than 15 777 000 seconds).
  JwtClientSecret({
    required this.issuer,
    required this.keyId,
    required BigInt privateKey,
    this.audience,
    this.lifetime = const Duration(hours: 1),
    DateTime Function()? clock,
  }) : _privateKey = privateKey,
       _clock = clock ?? DateTime.now {
    if (issuer.trim().isEmpty) {
      throw ArgumentError.value(issuer, 'issuer', 'cannot be empty');
    }
    if (keyId.trim().isEmpty) {
      throw ArgumentError.value(keyId, 'keyId', 'cannot be empty');
    }
    if (privateKey <= BigInt.zero || privateKey >= p256Order) {
      throw ArgumentError('The private key is not a P-256 key');
    }
    if (lifetime < const Duration(minutes: 1) ||
        lifetime > const Duration(days: 180)) {
      throw ArgumentError.value(
        lifetime,
        'lifetime',
        'must be between one minute and 180 days',
      );
    }
  }

  /// A secret whose key is the PKCS #8 PEM [pem]
  /// (`-----BEGIN PRIVATE KEY-----`, the content of Apple's `.p8` file;
  /// `\n` escapes instead of line breaks are fine).
  ///
  /// Throws a [FormatException] when [pem] is no P-256 key in PKCS #8
  /// (the message names no key material), and an [ArgumentError] as the
  /// main constructor.
  factory JwtClientSecret.fromPem({
    required String issuer,
    required String keyId,
    required String pem,
    String? audience,
    Duration lifetime = const Duration(hours: 1),
    DateTime Function()? clock,
  }) => JwtClientSecret(
    issuer: issuer,
    keyId: keyId,
    privateKey: p256PrivateKeyFromPkcs8(_pemBody(pem)),
    audience: audience,
    lifetime: lifetime,
    clock: clock,
  );

  /// The `iss` claim: who issues the secret (Apple: the team id).
  final String issuer;

  /// The `kid` header: the id of the key.
  final String keyId;

  /// The `aud` claim, or `null` for the registration's issuer URI.
  final String? audience;

  /// How long each JWT is valid.
  final Duration lifetime;

  final BigInt _privateKey;
  final DateTime Function() _clock;
  final Map<String, (String, DateTime)> _cache = {};

  /// The JWT [registration] sends as its `client_secret` now: `sub` is
  /// its client id, `aud` the [audience] or its issuer URI.
  ///
  /// Throws an [ArgumentError] when there is no audience (neither
  /// [audience] nor an issuer URI).
  String clientSecret(ClientRegistration registration) {
    final aud =
        audience ??
        registration.providerDetails.issuerUri ??
        (throw ArgumentError(
          'No audience for the client secret JWT of registration '
          '${registration.registrationId}: set client-secret-jwt.audience '
          'or the provider issuer-uri',
        ));
    final cacheKey = '${registration.clientId} $aud';
    final now = _clock().toUtc();
    final cached = _cache[cacheKey];
    if (cached != null && cached.$2.difference(now) > lifetime ~/ 10) {
      return cached.$1;
    }
    final iat = now.millisecondsSinceEpoch ~/ 1000;
    final exp = iat + lifetime.inSeconds;
    String part(Map<String, Object> json) =>
        _base64Url(utf8.encode(jsonEncode(json)));
    final input =
        '${part({'alg': 'ES256', 'kid': keyId})}.'
        '${part({'iss': issuer, 'iat': iat, 'exp': exp, 'aud': aud, 'sub': registration.clientId})}';
    final signature = p256Sign(_privateKey, utf8.encode(input));
    final jwt =
        '$input.${_base64Url([...unsignedBytes(signature.r, 32), ...unsignedBytes(signature.s, 32)])}';
    _cache[cacheKey] = (
      jwt,
      DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true),
    );
    return jwt;
  }

  @override
  String toString() =>
      'JwtClientSecret [issuer=$issuer, keyId=$keyId, '
      'audience=$audience, lifetime=$lifetime, privateKey=[PROTECTED]]';

  static String _base64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static Uint8List _pemBody(String pem) {
    // An environment variable often holds the PEM on one line with `\n`
    // escapes instead of line breaks.
    final match = RegExp(
      r'-----BEGIN PRIVATE KEY-----([A-Za-z0-9+/=\s]+)-----END PRIVATE KEY-----',
    ).firstMatch(pem.replaceAll(r'\n', '\n'));
    if (match == null) {
      throw const FormatException(
        'Not a PKCS #8 PEM: expected -----BEGIN PRIVATE KEY-----',
      );
    }
    try {
      return base64.decode(match[1]!.replaceAll(RegExp(r'\s'), ''));
    } on FormatException {
      throw const FormatException('Not a PKCS #8 PEM: the body is no base64');
    }
  }
}

/// The [OAuth2ClientSecretResolver] of the `client-secret-jwt.*`
/// properties: a [JwtClientSecret] per registration that has them, the
/// fixed `client-secret` for the others.
///
/// The keys are read at the first token request of their registration,
/// not at startup, from `private-key` (the PEM itself, from an
/// environment variable) or `private-key-location` (`file:`,
/// `classpath:`). A key that cannot be read or is no P-256 key fails
/// that request (`invalid_client`), never with the key in the message.
///
/// | Property (`spring.security.oauth2.client.registration.<id>.client-secret-jwt.`) | Meaning |
/// |---|---|
/// | `issuer` | the `iss` claim (Apple: the team id), required |
/// | `key-id` | the `kid` header (Apple: the key id), required |
/// | `private-key` | the PKCS #8 PEM itself |
/// | `private-key-location` | where the PEM is (`file:/run/secrets/apple.p8`) |
/// | `audience` | the `aud` claim; the provider's issuer URI by default |
/// | `lifetime` | how long each JWT is valid, `1h` by default (at most `180d`) |
///
/// Not in Spring Boot (see [OAuth2ClientSecretResolver]).
final class JwtClientSecretResolver implements OAuth2ClientSecretResolver {
  /// A resolver with the [secrets] given, by registration id.
  JwtClientSecretResolver(Map<String, JwtClientSecret> secrets)
    : _sources = {
        for (final MapEntry(:key, :value) in secrets.entries)
          key: () async => value,
      };

  /// A resolver of the `client-secret-jwt.*` properties of
  /// [environment]; [resourceLoader] reads `private-key-location`.
  ///
  /// Throws an [ArgumentError] at once when a registration with these
  /// properties lacks `issuer`, `key-id` or a key, or has a malformed
  /// `lifetime`.
  factory JwtClientSecretResolver.fromEnvironment(
    Environment environment, {
    ResourceLoader? resourceLoader,
  }) {
    final loader = resourceLoader ?? DefaultResourceLoader();
    final resolver = JwtClientSecretResolver(const {});
    for (final id in registrationIds(environment)) {
      String? text(String name) {
        final value = environment
            .getProperty('$_prefix.$id.client-secret-jwt.$name')
            ?.trim();
        return value == null || value.isEmpty ? null : value;
      }

      String required(String name) =>
          text(name) ??
          (throw ArgumentError(
            '$_prefix.$id.client-secret-jwt.$name must be set',
          ));
      final issuer = required('issuer');
      final keyId = required('key-id');
      final pem = text('private-key');
      final location = text('private-key-location');
      if (pem == null && location == null) {
        throw ArgumentError(
          '$_prefix.$id.client-secret-jwt.private-key or '
          '.private-key-location must be set',
        );
      }
      final lifetime = switch (text('lifetime')) {
        final value? => DurationStyle.parse(value),
        null => const Duration(hours: 1),
      };
      if (lifetime < const Duration(minutes: 1) ||
          lifetime > const Duration(days: 180)) {
        throw ArgumentError(
          '$_prefix.$id.client-secret-jwt.lifetime must be between one '
          'minute and 180 days',
        );
      }
      final audience = text('audience');
      JwtClientSecret? made;
      resolver._sources[id] = () async => made ??= JwtClientSecret.fromPem(
        issuer: issuer,
        keyId: keyId,
        pem: pem ?? await loader.getResource(location!).readAsString(),
        audience: audience,
        lifetime: lifetime,
      );
    }
    return resolver;
  }

  static const _prefix = 'spring.security.oauth2.client.registration';

  /// The ids of the registrations of [environment] that have
  /// `client-secret-jwt.*` properties: the condition of the starter's
  /// `clientSecretResolver` bean.
  static Set<String> registrationIds(Environment environment) {
    if (environment is! ConfigurableEnvironment) {
      return const {};
    }
    final entries = Binder.get(environment)
        .bind(
          _prefix,
          const MapType<String, String>(
            ClassType<String>(),
            ClassType<String>(),
          ),
        )
        .orElse(const {});
    // The keys as the sources hold them: `apple.client-secret-jwt.issuer`
    // from a file, `apple.clientsecretjwt.issuer` or
    // `apple.client.secret.jwt.issuer` from environment variables
    // (`..._APPLE_CLIENTSECRETJWT_ISSUER`, `..._APPLE_CLIENT_SECRET_JWT_ISSUER`):
    // compared without dashes, dots and case, as relaxed binding does.
    return {
      for (final key in entries.keys)
        if (key.split('.') case [final id, ...final rest]
            when rest
                .join()
                .replaceAll('-', '')
                .toLowerCase()
                .startsWith('clientsecretjwt'))
          id,
    };
  }

  final Map<String, Future<JwtClientSecret> Function()> _sources;

  /// Whether [registrationId] has a JWT secret here.
  bool handles(String registrationId) => _sources.containsKey(registrationId);

  @override
  Future<String?> resolve(ClientRegistration registration) async {
    final source = _sources[registration.registrationId];
    if (source == null) {
      return null;
    }
    try {
      return (await source()).clientSecret(registration);
    } on Object catch (e) {
      // The type only: a message could quote part of the key file.
      _log.error(
        "The client secret JWT of registration '"
        "${registration.registrationId}' could not be made (${e.runtimeType})",
      );
      throw OAuth2AuthorizationException(
        OAuth2Error(
          OAuth2ErrorCodes.invalidClient,
          'The client secret JWT of registration '
          '${registration.registrationId} could not be made '
          '(${e.runtimeType})',
        ),
      );
    }
  }
}
