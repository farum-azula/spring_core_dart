import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

const _log = SpringLog('spring.security.oauth2.client.login');

/// The tokens of a Flutter web app that logs in by itself
/// (`spring.flutter.security.web.mode=spa`), in the tab's memory only:
/// gone with a reload or the tab, never written to `localStorage`,
/// `sessionStorage` or IndexedDB, where any script of the origin (and
/// anyone with the disk) would find them later.
///
/// It also watches the refresh tokens: a browser keeps its refresh token
/// where an injected script can read it, so the provider must rotate it
/// (a new refresh token with every refresh, the old one revoked; reusing
/// an old one ends the login), which makes a stolen copy short-lived and
/// its use noticed. When a refresh comes back with the same refresh
/// token, a warning is logged once per registration: turn rotation on at
/// the provider (Keycloak: "Revoke Refresh Token" in the realm's
/// settings; Auth0, Okta: "Refresh Token Rotation").
///
/// The package declares it as the `OAuth2AuthorizedClientService` bean in
/// spa mode.
///
/// Spring (Java): Spring Security's `InMemoryOAuth2AuthorizedClientService`
/// keeps tokens the same way; the rotation warning is not in Spring.
final class TabOAuth2AuthorizedClientService
    implements OAuth2AuthorizedClientService {
  /// The tokens of the registrations of [clientRegistrationRepository].
  TabOAuth2AuthorizedClientService(ClientRegistrationRepository repository)
    : _delegate = InMemoryOAuth2AuthorizedClientService(repository);

  final InMemoryOAuth2AuthorizedClientService _delegate;
  final Set<String> _warned = {};

  @override
  Future<OAuth2AuthorizedClient?> loadAuthorizedClient(
    String clientRegistrationId,
    String principalName,
  ) => _delegate.loadAuthorizedClient(clientRegistrationId, principalName);

  @override
  Future<void> saveAuthorizedClient(
    OAuth2AuthorizedClient authorizedClient,
    Authentication principal,
  ) async {
    final registrationId = authorizedClient.clientRegistration.registrationId;
    final previous = await _delegate.loadAuthorizedClient(
      registrationId,
      principal.name,
    );
    final refresh = authorizedClient.refreshToken?.tokenValue;
    if (previous != null &&
        refresh != null &&
        previous.accessToken.tokenValue !=
            authorizedClient.accessToken.tokenValue &&
        previous.refreshToken?.tokenValue == refresh &&
        _warned.add(registrationId)) {
      _log.warning(
        "The provider of registration '$registrationId' did not rotate the "
        'refresh token: a browser keeps it where scripts of the page can '
        'read it, so the provider must issue a new one with every refresh '
        '(refresh token rotation)',
      );
    }
    await _delegate.saveAuthorizedClient(authorizedClient, principal);
  }

  @override
  Future<void> removeAuthorizedClient(
    String clientRegistrationId,
    String principalName,
  ) => _delegate.removeAuthorizedClient(clientRegistrationId, principalName);
}
