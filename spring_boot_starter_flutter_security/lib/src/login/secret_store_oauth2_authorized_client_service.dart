import 'dart:convert';

import 'package:spring_boot_starter_flutter_security/src/secret_store/secret_store.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

const _log = SpringLog('spring.security.oauth2.client');

/// An [OAuth2AuthorizedClientService] that keeps each client as JSON in a
/// [SecretStore]: the app's `authorizedClientService` bean.
///
/// On the `PlatformSecretStore`, the tokens of a login are in the
/// Keychain, the Android Keystore, DPAPI or the Secret Service and
/// survive a restart, so `OAuth2LoginService.restore()` logs the user
/// back in. The key is
/// `oauth2.authorized-client.<registration>.<principal>` (both
/// URI-encoded). A stored value that cannot be read (written by another
/// version, damaged) is removed and counts as none: the user logs in
/// again.
///
/// The access token's type is kept: `Bearer`, or `DPoP` for a token bound
/// to the app's DPoP key (a record without a type, written before DPoP,
/// reads as `Bearer`). With [dPoPKey], a DPoP token is stored with the
/// thumbprint of that key (RFC 7638, the token's `cnf.jkt`), and a stored
/// token bound to another key (the key was lost, deleted at logout or
/// replaced) is removed when loaded: it could no longer be used, and the
/// refresh token neither, so the user logs in again at once instead of
/// failing at the first call.
///
/// ```dart
/// @Bean()
/// OAuth2AuthorizedClientService clients(
///   SecretStore store,
///   ClientRegistrationRepository registrations,
/// ) => SecretStoreOAuth2AuthorizedClientService(store, registrations);
/// ```
///
/// The package declares it in place of the OAuth2 client's
/// `InMemoryOAuth2AuthorizedClientService` (its module comes before the
/// client's). Spring has no such service (its servers keep clients in
/// memory or in a database: `JdbcOAuth2AuthorizedClientService`).
final class SecretStoreOAuth2AuthorizedClientService
    implements OAuth2AuthorizedClientService {
  /// A service writing to [secretStore], for the registrations of
  /// [clientRegistrationRepository].
  /// [dPoPKey] (the app's `DPoPKey` bean) lets it drop DPoP tokens bound
  /// to another key.
  SecretStoreOAuth2AuthorizedClientService(
    this.secretStore,
    this.clientRegistrationRepository, {
    this.dPoPKey,
  });

  /// Where the clients are written.
  final SecretStore secretStore;

  /// The registrations; a client of an unknown registration is not
  /// loaded.
  final ClientRegistrationRepository clientRegistrationRepository;

  /// The key DPoP tokens are bound to, or `null` to keep them whatever
  /// key they are bound to.
  final DPoPKey? dPoPKey;

  /// The key of the client of [principalName] for [clientRegistrationId].
  static String keyOf(String clientRegistrationId, String principalName) =>
      'oauth2.authorized-client.${Uri.encodeComponent(clientRegistrationId)}'
      '.${Uri.encodeComponent(principalName)}';

  @override
  Future<OAuth2AuthorizedClient?> loadAuthorizedClient(
    String clientRegistrationId,
    String principalName,
  ) async {
    final key = keyOf(clientRegistrationId, principalName);
    final stored = await secretStore.read(key);
    if (stored == null) {
      return null;
    }
    final registration = await clientRegistrationRepository
        .findByRegistrationId(clientRegistrationId);
    if (registration == null) {
      return null;
    }
    final (OAuth2AuthorizedClient, String?) decoded;
    try {
      decoded = _decode(stored, registration, principalName);
    } on Object {
      // Never log the value: it holds tokens.
      _log.warning(
        'Removing the unreadable authorized client of registration '
        "'$clientRegistrationId'",
      );
      await secretStore.delete(key);
      return null;
    }
    final (client, jkt) = decoded;
    if (jkt != null && await _boundElsewhere(jkt)) {
      _log.info(
        "The tokens of registration '$clientRegistrationId' are bound to "
        'another DPoP key (lost, deleted or replaced); removing them, the '
        'user logs in again',
      );
      await secretStore.delete(key);
      return null;
    }
    return client;
  }

  // Whether the current key is not the one of the thumbprint [jkt]. A key
  // that cannot be loaded now does not judge: the tokens stay, and the
  // request that needs a proof fails on its own.
  Future<bool> _boundElsewhere(String jkt) async {
    final key = dPoPKey;
    if (key == null) {
      return false;
    }
    try {
      return await _thumbprint(key) != jkt;
    } on Object catch (e) {
      _log.debug('The DPoP key could not be loaded (${e.runtimeType})');
      return false;
    }
  }

  static Future<String> _thumbprint(DPoPKey key) async {
    if (key is LoadableDPoPKey) {
      await key.load();
    }
    return JwkThumbprint.of(key.publicJwk);
  }

  @override
  Future<void> saveAuthorizedClient(
    OAuth2AuthorizedClient authorizedClient,
    Authentication principal,
  ) async {
    String? jkt;
    final key = dPoPKey;
    if (key != null &&
        authorizedClient.accessToken.tokenType == TokenType.dpop) {
      try {
        jkt = await _thumbprint(key);
      } on Object catch (e) {
        _log.debug('The DPoP key could not be loaded (${e.runtimeType})');
      }
    }
    await secretStore.write(
      keyOf(authorizedClient.clientRegistration.registrationId, principal.name),
      jsonEncode(_encode(authorizedClient, principal.name, jkt)),
    );
  }

  @override
  Future<void> removeAuthorizedClient(
    String clientRegistrationId,
    String principalName,
  ) => secretStore.delete(keyOf(clientRegistrationId, principalName));

  static int? _millis(DateTime? time) => time?.millisecondsSinceEpoch;

  static DateTime? _time(Object? millis) => switch (millis) {
    null => null,
    final int value => DateTime.fromMillisecondsSinceEpoch(value, isUtc: true),
    _ => throw const FormatException('bad time'),
  };

  static Map<String, Object?> _encode(
    OAuth2AuthorizedClient client,
    String principalName,
    String? jkt,
  ) => {
    'version': 1,
    'registrationId': client.clientRegistration.registrationId,
    'principalName': principalName,
    'accessToken': {
      'tokenType': client.accessToken.tokenType.value,
      'value': client.accessToken.tokenValue,
      'issuedAt': _millis(client.accessToken.issuedAt),
      'expiresAt': _millis(client.accessToken.expiresAt),
      'scopes': client.accessToken.scopes.toList(),
      'jkt': ?jkt,
    },
    if (client.refreshToken case final refresh?)
      'refreshToken': {
        'value': refresh.tokenValue,
        'issuedAt': _millis(refresh.issuedAt),
        'expiresAt': _millis(refresh.expiresAt),
      },
    if (client.idToken case final idToken?) 'idToken': idToken.tokenValue,
  };

  // The client, and the thumbprint of the key its DPoP token is bound to
  // (when known).
  static (OAuth2AuthorizedClient, String?) _decode(
    String stored,
    ClientRegistration registration,
    String principalName,
  ) {
    final json = jsonDecode(stored);
    if (json is! Map<String, Object?> ||
        json['version'] != 1 ||
        json['registrationId'] != registration.registrationId ||
        json['principalName'] != principalName) {
      throw const FormatException('not an authorized client of this key');
    }
    final access = json['accessToken']! as Map<String, Object?>;
    final tokenType = switch (access['tokenType']) {
      // Written before DPoP, or by hand: a Bearer token.
      null => TokenType.bearer,
      final String type when type == TokenType.bearer.value => TokenType.bearer,
      final String type when type == TokenType.dpop.value => TokenType.dpop,
      _ => throw const FormatException('unknown token type'),
    };
    final jkt = access['jkt'] as String?;
    if (jkt != null && tokenType != TokenType.dpop) {
      throw const FormatException('a key thumbprint on a bearer token');
    }
    final refresh = json['refreshToken'] as Map<String, Object?>?;
    final idToken = json['idToken'] as String?;
    final client = OAuth2AuthorizedClient(
      registration,
      principalName,
      OAuth2AccessToken(
        tokenType,
        access['value']! as String,
        issuedAt: _time(access['issuedAt']),
        expiresAt: _time(access['expiresAt']),
        scopes: {...(access['scopes']! as List<Object?>).cast<String>()},
      ),
      refreshToken: refresh == null
          ? null
          : OAuth2RefreshToken(
              refresh['value']! as String,
              issuedAt: _time(refresh['issuedAt']),
              expiresAt: _time(refresh['expiresAt']),
            ),
      idToken: idToken == null ? null : OidcIdToken.parse(idToken),
    );
    return (client, jkt);
  }
}
