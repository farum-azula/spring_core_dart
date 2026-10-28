import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// Keeps the [OAuth2AuthorizedClient]s (the tokens) of the users of a web
/// application, by registration and request.
///
/// `oauth2Login()` saves the tokens of each login here; code that calls
/// an API with the user's token loads them back:
///
/// ```dart
/// @GetMapping('/orders')
/// Future<String> orders(ServerHttpRequest request) async {
///   final user = SecurityContextHolder.getContext().authentication!;
///   final client = await repository.loadAuthorizedClient(
///     'keycloak',
///     user,
///     request,
///   );
///   return await shop.orders(client!.accessToken.tokenValue);
/// }
/// ```
///
/// The starter declares an
/// [AuthenticatedPrincipalOAuth2AuthorizedClientRepository] on the
/// `OAuth2AuthorizedClientService` bean.
///
/// Spring (Java): `OAuth2AuthorizedClientRepository`; the methods return
/// `Future`s here.
abstract interface class OAuth2AuthorizedClientRepository {
  /// The client of [principal] for [clientRegistrationId], or `null`.
  Future<OAuth2AuthorizedClient?> loadAuthorizedClient(
    String clientRegistrationId,
    Authentication? principal,
    ServerHttpRequest request,
  );

  /// Keeps [authorizedClient] for [principal], replacing the one before.
  Future<void> saveAuthorizedClient(
    OAuth2AuthorizedClient authorizedClient,
    Authentication? principal,
    ServerHttpRequest request,
    ServerHttpResponse response,
  );

  /// Forgets the client of [principal] for [clientRegistrationId].
  Future<void> removeAuthorizedClient(
    String clientRegistrationId,
    Authentication? principal,
    ServerHttpRequest request,
    ServerHttpResponse response,
  );
}

/// An [OAuth2AuthorizedClientRepository] that keeps the clients in the
/// HTTP session, by registration id: they end with the session (at
/// logout).
///
/// Spring (Java): `HttpSessionOAuth2AuthorizedClientRepository`.
final class HttpSessionOAuth2AuthorizedClientRepository
    implements OAuth2AuthorizedClientRepository {
  /// The repository; it has no state of its own.
  const HttpSessionOAuth2AuthorizedClientRepository();

  /// The session attribute holding the clients by registration id.
  static const authorizedClientsAttributeName =
      'HttpSessionOAuth2AuthorizedClientRepository.AUTHORIZED_CLIENTS';

  static Map<String, OAuth2AuthorizedClient> _clients(HttpSession? session) =>
      switch (session?.getAttribute(authorizedClientsAttributeName)) {
        final Map<String, OAuth2AuthorizedClient> clients => clients,
        _ => const {},
      };

  @override
  Future<OAuth2AuthorizedClient?> loadAuthorizedClient(
    String clientRegistrationId,
    Authentication? principal,
    ServerHttpRequest request,
  ) async => _clients(request.getSession(create: false))[clientRegistrationId];

  @override
  Future<void> saveAuthorizedClient(
    OAuth2AuthorizedClient authorizedClient,
    Authentication? principal,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    final session = (await request.getSessionAsync())!;
    session.setAttribute(
      authorizedClientsAttributeName,
      Map<String, OAuth2AuthorizedClient>.unmodifiable({
        ..._clients(session),
        authorizedClient.clientRegistration.registrationId: authorizedClient,
      }),
    );
  }

  @override
  Future<void> removeAuthorizedClient(
    String clientRegistrationId,
    Authentication? principal,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    final session = request.getSession(create: false);
    final clients = _clients(session);
    if (!clients.containsKey(clientRegistrationId)) {
      return;
    }
    final rest = {...clients}..remove(clientRegistrationId);
    if (rest.isEmpty) {
      session!.removeAttribute(authorizedClientsAttributeName);
    } else {
      session!.setAttribute(
        authorizedClientsAttributeName,
        Map<String, OAuth2AuthorizedClient>.unmodifiable(rest),
      );
    }
  }
}

/// The default [OAuth2AuthorizedClientRepository]: the clients of logged
/// in users go to an [OAuth2AuthorizedClientService] (by user name), those
/// of anonymous users to the session.
///
/// Through the service, code without a request (a scheduled job, the
/// Feign interceptor) finds the tokens of a user too.
///
/// Spring (Java): `AuthenticatedPrincipalOAuth2AuthorizedClientRepository`.
final class AuthenticatedPrincipalOAuth2AuthorizedClientRepository
    implements OAuth2AuthorizedClientRepository {
  /// A repository keeping the clients of logged-in users in
  /// [authorizedClientService], and the others in
  /// [anonymousAuthorizedClientRepository].
  const AuthenticatedPrincipalOAuth2AuthorizedClientRepository(
    this.authorizedClientService, {
    this.anonymousAuthorizedClientRepository =
        const HttpSessionOAuth2AuthorizedClientRepository(),
    this.trustResolver = const AuthenticationTrustResolverImpl(),
  });

  /// Where the clients of logged-in users are kept.
  final OAuth2AuthorizedClientService authorizedClientService;

  /// Where the clients of anonymous users are kept.
  final OAuth2AuthorizedClientRepository anonymousAuthorizedClientRepository;

  /// Tells anonymous users from logged-in ones.
  final AuthenticationTrustResolver trustResolver;

  bool _authenticated(Authentication? principal) =>
      principal != null &&
      !trustResolver.isAnonymous(principal) &&
      principal.isAuthenticated;

  @override
  Future<OAuth2AuthorizedClient?> loadAuthorizedClient(
    String clientRegistrationId,
    Authentication? principal,
    ServerHttpRequest request,
  ) => _authenticated(principal)
      ? authorizedClientService.loadAuthorizedClient(
          clientRegistrationId,
          principal!.name,
        )
      : anonymousAuthorizedClientRepository.loadAuthorizedClient(
          clientRegistrationId,
          principal,
          request,
        );

  @override
  Future<void> saveAuthorizedClient(
    OAuth2AuthorizedClient authorizedClient,
    Authentication? principal,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) => _authenticated(principal)
      ? authorizedClientService.saveAuthorizedClient(
          authorizedClient,
          principal!,
        )
      : anonymousAuthorizedClientRepository.saveAuthorizedClient(
          authorizedClient,
          principal,
          request,
          response,
        );

  @override
  Future<void> removeAuthorizedClient(
    String clientRegistrationId,
    Authentication? principal,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) => _authenticated(principal)
      ? authorizedClientService.removeAuthorizedClient(
          clientRegistrationId,
          principal!.name,
        )
      : anonymousAuthorizedClientRepository.removeAuthorizedClient(
          clientRegistrationId,
          principal,
          request,
          response,
        );
}
