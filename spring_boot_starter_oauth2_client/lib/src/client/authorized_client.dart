import 'package:spring_boot_starter_oauth2_client/src/core/tokens.dart';
import 'package:spring_boot_starter_oauth2_client/src/oidc/oidc_id_token.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration_repository.dart';
import 'package:spring_security_core/spring_security_core.dart';

/// The tokens one principal holds for one registration: the access token,
/// the refresh token and, after an OpenID Connect login, the ID token.
///
/// A login or a client-credentials grant creates it; the authorized
/// client manager refreshes it; an [OAuth2AuthorizedClientService] keeps
/// it between calls. Ask the manager for it to get a token that is still
/// valid:
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
/// the refresh checks a new ID token against it (OpenID Connect Core
/// §12.2), and a logout needs it as `id_token_hint` when no session holds
/// the `OidcUser` (Spring keeps it there).
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
/// ones, the logout removes them. The starter declares an
/// [InMemoryOAuth2AuthorizedClientService]; declare your own to keep them
/// elsewhere (a database).
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
/// The starter's default (`authorizedClientService`), as in Spring Boot:
/// right for client-credentials tokens and for tests.
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
