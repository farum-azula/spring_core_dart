import 'dart:convert';

import 'package:spring_boot_starter_oauth2_client/src/core/tokens.dart';
import 'package:spring_boot_starter_oauth2_client/src/oidc/oidc_id_token.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration_repository.dart';
import 'package:spring_boot_starter_oauth2_client/src/token_store.dart';
import 'package:spring_security_core/spring_security_core.dart';

const _log = SpringLog('spring.security.oauth2.client');

/// The tokens one principal holds for one registration: the access token,
/// the refresh token and, after an OpenID Connect login, the ID token.
///
/// A login creates it; the authorized client manager refreshes it; an
/// [OAuth2AuthorizedClientService] keeps it between calls (and, through
/// the `TokenStore`, between runs of an app). Ask the manager for it to
/// get a token that is still valid:
///
/// ```dart
/// final client = await manager.authorize(
///   OAuth2AuthorizeRequest.withClientRegistrationId('keycloak')
///       .principal(authentication)
///       .build(),
/// );
/// final token = client?.accessToken.tokenValue;
/// ```
///
/// Spring (Java): `OAuth2AuthorizedClient`. [idToken] is this package's:
/// an app needs it after a restart for the logout's `id_token_hint`,
/// where Spring keeps it in the `OidcUser` of the session.
final class OAuth2AuthorizedClient {
  /// The tokens of [principalName] for [clientRegistration].
  OAuth2AuthorizedClient(
    this.clientRegistration,
    this.principalName,
    this.accessToken, {
    this.refreshToken,
    this.idToken,
  }) {
    if (principalName.isEmpty) {
      throw ArgumentError('principalName cannot be empty');
    }
  }

  /// The registration the tokens are for.
  final ClientRegistration clientRegistration;

  /// Who the tokens belong to: the user's name, or `anonymousUser` for
  /// client credentials.
  final String principalName;

  /// The access token.
  final OAuth2AccessToken accessToken;

  /// The refresh token, or `null`.
  final OAuth2RefreshToken? refreshToken;

  /// The ID token of the login (OpenID Connect), or `null`.
  final OidcIdToken? idToken;

  @override
  String toString() =>
      'OAuth2AuthorizedClient [registrationId='
      '${clientRegistration.registrationId}, principalName=$principalName, '
      'accessToken=[PROTECTED], expiresAt=${accessToken.expiresAt}]';
}

/// Keeps the [OAuth2AuthorizedClient]s, by registration and principal.
///
/// The login saves the client it created, the manager saves refreshed
/// ones, the logout removes them. The starter declares a
/// [TokenStoreOAuth2AuthorizedClientService] on the `TokenStore` bean, so
/// an app's tokens survive a restart in the platform's secure storage.
/// Declare your own to keep them elsewhere (a database on a server).
///
/// Spring (Java): `OAuth2AuthorizedClientService`; the methods return
/// `Future`s here.
abstract interface class OAuth2AuthorizedClientService {
  /// The client of [principalName] for [clientRegistrationId], or `null`.
  Future<OAuth2AuthorizedClient?> loadAuthorizedClient(
    String clientRegistrationId,
    String principalName,
  );

  /// Keeps [authorizedClient] for [principal] (by its name), replacing
  /// the one before.
  Future<void> saveAuthorizedClient(
    OAuth2AuthorizedClient authorizedClient,
    Authentication principal,
  );

  /// Forgets the client of [principalName] for [clientRegistrationId];
  /// nothing happens when there is none.
  Future<void> removeAuthorizedClient(
    String clientRegistrationId,
    String principalName,
  );
}

/// An [OAuth2AuthorizedClientService] in memory: the tokens are lost when
/// the program stops.
///
/// Right for a server's client-credentials tokens and for tests.
///
/// Spring (Java): `InMemoryOAuth2AuthorizedClientService`.
final class InMemoryOAuth2AuthorizedClientService
    implements OAuth2AuthorizedClientService {
  /// A service for the registrations of [clientRegistrationRepository].
  InMemoryOAuth2AuthorizedClientService(this.clientRegistrationRepository);

  /// The registrations; a client of an unknown registration is not kept.
  final ClientRegistrationRepository clientRegistrationRepository;

  final Map<(String, String), OAuth2AuthorizedClient> _clients = {};

  @override
  Future<OAuth2AuthorizedClient?> loadAuthorizedClient(
    String clientRegistrationId,
    String principalName,
  ) async {
    if (await clientRegistrationRepository.findByRegistrationId(
          clientRegistrationId,
        ) ==
        null) {
      return null;
    }
    return _clients[(clientRegistrationId, principalName)];
  }

  @override
  Future<void> saveAuthorizedClient(
    OAuth2AuthorizedClient authorizedClient,
    Authentication principal,
  ) async {
    _clients[(
          authorizedClient.clientRegistration.registrationId,
          principal.name,
        )] =
        authorizedClient;
  }

  @override
  Future<void> removeAuthorizedClient(
    String clientRegistrationId,
    String principalName,
  ) async {
    _clients.remove((clientRegistrationId, principalName));
  }
}

/// An [OAuth2AuthorizedClientService] that keeps each client as JSON in a
/// [TokenStore]: the default of the starter.
///
/// With the Flutter starter's store, the tokens of a login are in the
/// Keychain or the Android Keystore and survive a restart, so
/// `OAuth2LoginService.restore()` logs the user back in. The key is
/// `oauth2.authorized-client.<registration>.<principal>` (both
/// URI-encoded). A stored value that cannot be read (written by another
/// version, damaged) is removed and counts as none: the user logs in
/// again.
///
/// ```dart
/// @Bean()
/// OAuth2AuthorizedClientService clients(
///   TokenStore store,
///   ClientRegistrationRepository registrations,
/// ) => TokenStoreOAuth2AuthorizedClientService(store, registrations);
/// ```
///
/// Spring has no such service (its servers keep clients in memory or in a
/// database: `JdbcOAuth2AuthorizedClientService`).
final class TokenStoreOAuth2AuthorizedClientService
    implements OAuth2AuthorizedClientService {
  /// A service writing to [tokenStore], for the registrations of
  /// [clientRegistrationRepository].
  TokenStoreOAuth2AuthorizedClientService(
    this.tokenStore,
    this.clientRegistrationRepository,
  );

  /// Where the clients are written.
  final TokenStore tokenStore;

  /// The registrations; a client of an unknown registration is not
  /// loaded.
  final ClientRegistrationRepository clientRegistrationRepository;

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
    final stored = await tokenStore.read(key);
    if (stored == null) {
      return null;
    }
    final registration = await clientRegistrationRepository
        .findByRegistrationId(clientRegistrationId);
    if (registration == null) {
      return null;
    }
    try {
      return _decode(stored, registration, principalName);
    } on Object {
      // Never log the value: it holds tokens.
      _log.warning(
        'Removing the unreadable authorized client of registration '
        "'$clientRegistrationId'",
      );
      await tokenStore.delete(key);
      return null;
    }
  }

  @override
  Future<void> saveAuthorizedClient(
    OAuth2AuthorizedClient authorizedClient,
    Authentication principal,
  ) => tokenStore.write(
    keyOf(authorizedClient.clientRegistration.registrationId, principal.name),
    jsonEncode(_encode(authorizedClient, principal.name)),
  );

  @override
  Future<void> removeAuthorizedClient(
    String clientRegistrationId,
    String principalName,
  ) => tokenStore.delete(keyOf(clientRegistrationId, principalName));

  static int? _millis(DateTime? time) => time?.millisecondsSinceEpoch;

  static DateTime? _time(Object? millis) => switch (millis) {
    null => null,
    final int value => DateTime.fromMillisecondsSinceEpoch(value, isUtc: true),
    _ => throw const FormatException('bad time'),
  };

  static Map<String, Object?> _encode(
    OAuth2AuthorizedClient client,
    String principalName,
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
    },
    if (client.refreshToken case final refresh?)
      'refreshToken': {
        'value': refresh.tokenValue,
        'issuedAt': _millis(refresh.issuedAt),
        'expiresAt': _millis(refresh.expiresAt),
      },
    if (client.idToken case final idToken?) 'idToken': idToken.tokenValue,
  };

  static OAuth2AuthorizedClient _decode(
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
    if (access['tokenType'] != TokenType.bearer.value) {
      throw const FormatException('not a bearer token');
    }
    final refresh = json['refreshToken'] as Map<String, Object?>?;
    final idToken = json['idToken'] as String?;
    return OAuth2AuthorizedClient(
      registration,
      principalName,
      OAuth2AccessToken(
        TokenType.bearer,
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
  }
}
