import 'dart:async';

import 'package:spring_boot_starter_oauth2_client/src/client/authorized_client.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/oauth2_error.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/tokens.dart';
import 'package:spring_boot_starter_oauth2_client/src/endpoint/token_response_clients.dart';
import 'package:spring_boot_starter_oauth2_client/src/oidc/oidc_id_token.dart';
import 'package:spring_boot_starter_oauth2_client/src/oidc/oidc_id_token_decoder.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration_repository.dart';
import 'package:spring_security_core/spring_security_core.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.security.oauth2.client');

/// The principal of client-credentials tokens, which belong to no user.
///
/// Spring (Java): the `anonymousUser` principal of
/// `OAuth2AccessTokenInterceptor` and the `ServletOAuth2AuthorizedClient*`
/// classes.
final Authentication anonymousAuthentication = AnonymousAuthenticationToken(
  'anonymous',
  'anonymousUser',
  AuthorityUtils.createAuthorityList(['ROLE_ANONYMOUS']),
);

/// A request for the authorized client of one registration and one
/// principal: "give me a valid token of `keycloak` for this user".
///
/// ```dart
/// final request = OAuth2AuthorizeRequest.withClientRegistrationId('keycloak')
///     .principal(SecurityContextHolder.getContext().authentication!)
///     .build();
/// final client = await manager.authorize(request);
/// ```
///
/// Spring (Java): `OAuth2AuthorizeRequest`, with the same builder.
final class OAuth2AuthorizeRequest {
  OAuth2AuthorizeRequest._(
    this.clientRegistrationId,
    this.authorizedClient,
    this.principal,
    Map<String, Object?> attributes,
  ) : attributes = Map.unmodifiable(attributes);

  /// A builder for a request of the registration [clientRegistrationId].
  static OAuth2AuthorizeRequestBuilder withClientRegistrationId(
    String clientRegistrationId,
  ) => OAuth2AuthorizeRequestBuilder._(clientRegistrationId, null);

  /// A builder for a request that re-authorizes (refreshes)
  /// [authorizedClient].
  static OAuth2AuthorizeRequestBuilder withAuthorizedClient(
    OAuth2AuthorizedClient authorizedClient,
  ) => OAuth2AuthorizeRequestBuilder._(
    authorizedClient.clientRegistration.registrationId,
    authorizedClient,
  );

  /// The registration, such as `keycloak`.
  final String clientRegistrationId;

  /// The client to re-authorize, or `null` to load it from the service.
  final OAuth2AuthorizedClient? authorizedClient;

  /// Who the tokens are for.
  final Authentication principal;

  /// More information for the providers, such as
  /// [OAuth2AuthorizationContext.requestScopeAttributeName].
  final Map<String, Object?> attributes;
}

/// Builds an [OAuth2AuthorizeRequest].
///
/// Spring (Java): `OAuth2AuthorizeRequest.Builder`.
final class OAuth2AuthorizeRequestBuilder {
  OAuth2AuthorizeRequestBuilder._(this._registrationId, this._client);

  final String _registrationId;
  final OAuth2AuthorizedClient? _client;
  Authentication? _principal;
  final Map<String, Object?> _attributes = {};

  /// Sets the principal.
  OAuth2AuthorizeRequestBuilder principal(Authentication principal) {
    _principal = principal;
    return this;
  }

  /// Sets the principal by its name only.
  OAuth2AuthorizeRequestBuilder principalName(String name) {
    _principal = _NamedPrincipal(name);
    return this;
  }

  /// Adds [attributes].
  OAuth2AuthorizeRequestBuilder attributes(Map<String, Object?> attributes) {
    _attributes.addAll(attributes);
    return this;
  }

  /// The request.
  ///
  /// Throws an [ArgumentError] when no principal was set.
  OAuth2AuthorizeRequest build() {
    final principal =
        _principal ?? (throw ArgumentError('principal cannot be null'));
    return OAuth2AuthorizeRequest._(
      _registrationId,
      _client,
      principal,
      _attributes,
    );
  }
}

final class _NamedPrincipal extends AbstractAuthenticationToken {
  _NamedPrincipal(this._name) {
    if (_name.isEmpty) {
      throw ArgumentError('principalName cannot be empty');
    }
  }

  final String _name;

  @override
  String get name => _name;

  @override
  Object? get principal => _name;

  @override
  Object? get credentials => '';
}

/// What an [OAuth2AuthorizedClientProvider] gets: the registration, the
/// current authorized client (if any), the principal and the attributes.
///
/// Spring (Java): `OAuth2AuthorizationContext`.
final class OAuth2AuthorizationContext {
  /// A context for [clientRegistration], with the current
  /// [authorizedClient] when there is one.
  OAuth2AuthorizationContext({
    required this.clientRegistration,
    required this.principal,
    this.authorizedClient,
    Map<String, Object?> attributes = const {},
  }) : attributes = Map.unmodifiable(attributes);

  /// The attribute holding the scopes (a `Set<String>`) a refresh asks
  /// for.
  static const requestScopeAttributeName =
      'OAuth2AuthorizationContext.REQUEST_SCOPE';

  /// The registration.
  final ClientRegistration clientRegistration;

  /// The current client, or `null` when none was authorized yet.
  final OAuth2AuthorizedClient? authorizedClient;

  /// Who the tokens are for.
  final Authentication principal;

  /// More information, such as [requestScopeAttributeName].
  final Map<String, Object?> attributes;
}

/// One way of getting or renewing tokens: from a code, a refresh token or
/// the client's credentials.
///
/// The manager asks its provider (usually a
/// [DelegatingOAuth2AuthorizedClientProvider] of several) and keeps what
/// it returns. Write one for another grant, such as the JWT bearer grant.
///
/// Spring (Java): `OAuth2AuthorizedClientProvider`.
abstract interface class OAuth2AuthorizedClientProvider {
  /// A new or renewed client, or `null` when this provider has nothing
  /// to do (the token is still valid, or the grant is not its own).
  ///
  /// Throws an [OAuth2AuthorizationException] when the provider refused.
  Future<OAuth2AuthorizedClient?> authorize(OAuth2AuthorizationContext context);
}

/// Whether [token] expires within [clockSkew] of [now] (a token without
/// expiry never does).
bool _expiresSoon(AbstractOAuth2Token token, DateTime now, Duration clockSkew) {
  final expiresAt = token.expiresAt;
  return expiresAt != null &&
      now.toUtc().isAfter(expiresAt.subtract(clockSkew));
}

/// The provider of `authorization_code` registrations: it cannot log a
/// user in by itself (that needs the browser), so without an authorized
/// client it throws a [ClientAuthorizationRequiredException].
///
/// Spring (Java): `AuthorizationCodeOAuth2AuthorizedClientProvider`.
final class AuthorizationCodeOAuth2AuthorizedClientProvider
    implements OAuth2AuthorizedClientProvider {
  /// The provider; it has no state.
  const AuthorizationCodeOAuth2AuthorizedClientProvider();

  @override
  Future<OAuth2AuthorizedClient?> authorize(
    OAuth2AuthorizationContext context,
  ) async {
    if (context.clientRegistration.authorizationGrantType ==
            AuthorizationGrantType.authorizationCode &&
        context.authorizedClient == null) {
      throw ClientAuthorizationRequiredException(
        context.clientRegistration.registrationId,
      );
    }
    return null;
  }
}

/// Renews an access token that expires within [clockSkew] (60 seconds)
/// with the refresh token.
///
/// When the answer carries a new ID token, it is decoded with
/// [idTokenDecoder] and must be about the same user from the same issuer
/// as the old one (OpenID Connect Core §12.2), or the refresh fails with
/// `invalid_id_token`.
///
/// Spring (Java): `RefreshTokenOAuth2AuthorizedClientProvider`, and the
/// ID token checks of Spring Security 6.3's
/// `OidcAuthorizedClientRefreshedEventListener`.
final class RefreshTokenOAuth2AuthorizedClientProvider
    implements OAuth2AuthorizedClientProvider {
  /// A provider calling [accessTokenResponseClient].
  RefreshTokenOAuth2AuthorizedClientProvider(
    this.accessTokenResponseClient, {
    this.clockSkew = const Duration(seconds: 60),
    DateTime Function()? clock,
    OidcIdTokenDecoder? idTokenDecoder,
  }) : _clock = clock ?? DateTime.now,
       idTokenDecoder =
           idTokenDecoder ?? TokenEndpointOidcIdTokenDecoder(clock: clock);

  /// The client of the refresh grant.
  final OAuth2AccessTokenResponseClient<OAuth2RefreshTokenGrantRequest>
  accessTokenResponseClient;

  /// How long before its expiry a token is renewed.
  final Duration clockSkew;

  /// Decodes a new ID token of the answer.
  final OidcIdTokenDecoder idTokenDecoder;

  final DateTime Function() _clock;

  @override
  Future<OAuth2AuthorizedClient?> authorize(
    OAuth2AuthorizationContext context,
  ) async {
    final client = context.authorizedClient;
    final refreshToken = client?.refreshToken;
    if (client == null ||
        refreshToken == null ||
        !_expiresSoon(client.accessToken, _clock(), clockSkew)) {
      return null;
    }
    final scopes = switch (context.attributes[OAuth2AuthorizationContext
        .requestScopeAttributeName]) {
      final Set<String> scopes => scopes,
      final Iterable<String> scopes => scopes.toSet(),
      _ => const <String>{},
    };
    final registration = context.clientRegistration;
    final response = await accessTokenResponseClient
        .getTokenResponse(
          OAuth2RefreshTokenGrantRequest(
            registration,
            client.accessToken,
            refreshToken,
            scopes: scopes,
          ),
        )
        .onError<OAuth2AuthorizationException>(
          (e, stackTrace) => Error.throwWithStackTrace(
            ClientAuthorizationException(
              e.error,
              registration.registrationId,
              e.message,
              e,
            ),
            stackTrace,
          ),
        );
    var idToken = client.idToken;
    if (response.additionalParameters['id_token'] case final String raw) {
      idToken = await _refreshedIdToken(registration, client.idToken, raw);
    }
    return OAuth2AuthorizedClient(
      registration,
      client.principalName,
      response.accessToken,
      refreshToken: response.refreshToken,
      idToken: idToken,
    );
  }

  Future<OidcIdToken> _refreshedIdToken(
    ClientRegistration registration,
    OidcIdToken? old,
    String raw,
  ) async {
    Never fail(String why) => throw ClientAuthorizationException(
      OAuth2Error(OAuth2ErrorCodes.invalidIdToken, why),
      registration.registrationId,
    );
    final OidcIdToken fresh;
    try {
      fresh = await idTokenDecoder.decode(registration, raw);
    } on OAuth2AuthenticationException catch (e) {
      fail(e.message);
    }
    if (old != null) {
      if (fresh.issuer != old.issuer) {
        fail('The refreshed ID token has another issuer');
      }
      if (fresh.subject != old.subject) {
        fail('The refreshed ID token is about another user');
      }
      final oldAuthTime = old.authenticatedAt;
      final freshAuthTime = fresh.authenticatedAt;
      if (oldAuthTime != null &&
          freshAuthTime != null &&
          oldAuthTime != freshAuthTime) {
        fail('The refreshed ID token has another auth_time');
      }
      if (fresh.nonce != null && fresh.nonce != old.nonce) {
        fail('The refreshed ID token has another nonce');
      }
    }
    return fresh;
  }
}

/// Gets a client-credentials token when there is none or it expires
/// within [clockSkew] (60 seconds).
///
/// Spring (Java): `ClientCredentialsOAuth2AuthorizedClientProvider`.
final class ClientCredentialsOAuth2AuthorizedClientProvider
    implements OAuth2AuthorizedClientProvider {
  /// A provider calling [accessTokenResponseClient].
  ClientCredentialsOAuth2AuthorizedClientProvider(
    this.accessTokenResponseClient, {
    this.clockSkew = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The client of the client-credentials grant.
  final OAuth2AccessTokenResponseClient<OAuth2ClientCredentialsGrantRequest>
  accessTokenResponseClient;

  /// How long before its expiry a token is replaced.
  final Duration clockSkew;

  final DateTime Function() _clock;

  @override
  Future<OAuth2AuthorizedClient?> authorize(
    OAuth2AuthorizationContext context,
  ) async {
    final registration = context.clientRegistration;
    if (registration.authorizationGrantType !=
        AuthorizationGrantType.clientCredentials) {
      return null;
    }
    final client = context.authorizedClient;
    if (client != null &&
        !_expiresSoon(client.accessToken, _clock(), clockSkew)) {
      return null;
    }
    final response = await accessTokenResponseClient
        .getTokenResponse(OAuth2ClientCredentialsGrantRequest(registration))
        .onError<OAuth2AuthorizationException>(
          (e, stackTrace) => Error.throwWithStackTrace(
            ClientAuthorizationException(
              e.error,
              registration.registrationId,
              e.message,
              e,
            ),
            stackTrace,
          ),
        );
    return OAuth2AuthorizedClient(
      registration,
      context.principal.name,
      response.accessToken,
    );
  }
}

/// Several [OAuth2AuthorizedClientProvider]s: the first that returns a
/// client wins.
///
/// Spring (Java): `DelegatingOAuth2AuthorizedClientProvider`.
final class DelegatingOAuth2AuthorizedClientProvider
    implements OAuth2AuthorizedClientProvider {
  /// The providers [providers], asked in order.
  DelegatingOAuth2AuthorizedClientProvider(
    List<OAuth2AuthorizedClientProvider> providers,
  ) : providers = List.unmodifiable(providers);

  /// The providers.
  final List<OAuth2AuthorizedClientProvider> providers;

  @override
  Future<OAuth2AuthorizedClient?> authorize(
    OAuth2AuthorizationContext context,
  ) async {
    for (final provider in providers) {
      final client = await provider.authorize(context);
      if (client != null) {
        return client;
      }
    }
    return null;
  }
}

/// Builds the provider of a manager from the grants it supports.
///
/// ```dart
/// final provider = OAuth2AuthorizedClientProviderBuilder.builder(
///   transport: transport,
/// ).authorizationCode().refreshToken().clientCredentials().build();
/// ```
///
/// Spring (Java): `OAuth2AuthorizedClientProviderBuilder`. The default
/// token clients need a [HttpTransport], given to [builder].
final class OAuth2AuthorizedClientProviderBuilder {
  OAuth2AuthorizedClientProviderBuilder._(this._transport);

  /// A builder; [transport] sends the requests of the default token
  /// clients (needed unless every grant gets its own client).
  static OAuth2AuthorizedClientProviderBuilder builder({
    HttpTransport? transport,
  }) => OAuth2AuthorizedClientProviderBuilder._(transport);

  final HttpTransport? _transport;
  final List<OAuth2AuthorizedClientProvider> _providers = [];

  HttpTransport get _requiredTransport =>
      _transport ??
      (throw ArgumentError(
        'A transport is needed for the default token response client',
      ));

  /// Adds the `authorization_code` provider.
  OAuth2AuthorizedClientProviderBuilder authorizationCode() {
    _providers.add(const AuthorizationCodeOAuth2AuthorizedClientProvider());
    return this;
  }

  /// Adds the refresh provider, with [accessTokenResponseClient] (a
  /// [DefaultRefreshTokenTokenResponseClient] by default).
  OAuth2AuthorizedClientProviderBuilder refreshToken({
    OAuth2AccessTokenResponseClient<OAuth2RefreshTokenGrantRequest>?
    accessTokenResponseClient,
    Duration clockSkew = const Duration(seconds: 60),
    DateTime Function()? clock,
    OidcIdTokenDecoder? idTokenDecoder,
  }) {
    _providers.add(
      RefreshTokenOAuth2AuthorizedClientProvider(
        accessTokenResponseClient ??
            DefaultRefreshTokenTokenResponseClient(
              _requiredTransport,
              clock: clock,
            ),
        clockSkew: clockSkew,
        clock: clock,
        idTokenDecoder: idTokenDecoder,
      ),
    );
    return this;
  }

  /// Adds the client-credentials provider, with
  /// [accessTokenResponseClient] (a
  /// [DefaultClientCredentialsTokenResponseClient] by default).
  OAuth2AuthorizedClientProviderBuilder clientCredentials({
    OAuth2AccessTokenResponseClient<OAuth2ClientCredentialsGrantRequest>?
    accessTokenResponseClient,
    Duration clockSkew = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) {
    _providers.add(
      ClientCredentialsOAuth2AuthorizedClientProvider(
        accessTokenResponseClient ??
            DefaultClientCredentialsTokenResponseClient(
              _requiredTransport,
              clock: clock,
            ),
        clockSkew: clockSkew,
        clock: clock,
      ),
    );
    return this;
  }

  /// Adds [provider].
  OAuth2AuthorizedClientProviderBuilder provider(
    OAuth2AuthorizedClientProvider provider,
  ) {
    _providers.add(provider);
    return this;
  }

  /// The provider: the one added, or a
  /// [DelegatingOAuth2AuthorizedClientProvider] of all.
  OAuth2AuthorizedClientProvider build() => _providers.length == 1
      ? _providers.single
      : DelegatingOAuth2AuthorizedClientProvider(_providers);
}

/// Hands out valid tokens: it loads the stored client, renews it when it
/// expires soon, gets client-credentials tokens, and saves the result.
///
/// Everything that calls an API with a token goes through it (the Feign
/// interceptor does), so a token is refreshed in one place. Two callers
/// asking for the same registration and principal at the same time share
/// one call to the provider: a refresh token is never sent twice (many
/// providers rotate it, and the second use would log the user out).
///
/// Spring (Java): `OAuth2AuthorizedClientManager`.
abstract interface class OAuth2AuthorizedClientManager {
  /// A client with a valid token for [authorizeRequest], or `null` when
  /// there is none and none can be obtained.
  ///
  /// Throws a [ClientAuthorizationRequiredException] when the user must
  /// log in, an [OAuth2AuthorizationException] when the provider refused.
  Future<OAuth2AuthorizedClient?> authorize(
    OAuth2AuthorizeRequest authorizeRequest,
  );
}

/// The [OAuth2AuthorizedClientManager] of the starter: clients kept in an
/// [OAuth2AuthorizedClientService], renewed by an
/// [OAuth2AuthorizedClientProvider].
///
/// On success the client is saved; when the provider answers
/// `invalid_grant` or `invalid_token` (a revoked refresh token, a removed
/// user), the stored client is removed, as the user must log in again.
/// Concurrent calls for one registration and principal share one
/// authorization.
///
/// ```dart
/// final manager = AuthorizedClientServiceOAuth2AuthorizedClientManager(
///   registrations,
///   clients,
///   authorizedClientProvider: OAuth2AuthorizedClientProviderBuilder.builder(
///     transport: transport,
///   ).authorizationCode().refreshToken().clientCredentials().build(),
/// );
/// ```
///
/// Spring (Java): `AuthorizedClientServiceOAuth2AuthorizedClientManager`
/// (the manager for code outside an HTTP request), with
/// `RemoveAuthorizedClientOAuth2AuthorizationFailureHandler`. The provider
/// is required here (Spring defaults to client credentials alone).
final class AuthorizedClientServiceOAuth2AuthorizedClientManager
    implements OAuth2AuthorizedClientManager {
  /// A manager of the clients of [clientRegistrationRepository] kept in
  /// [authorizedClientService].
  AuthorizedClientServiceOAuth2AuthorizedClientManager(
    this.clientRegistrationRepository,
    this.authorizedClientService, {
    required this.authorizedClientProvider,
  });

  /// The registrations.
  final ClientRegistrationRepository clientRegistrationRepository;

  /// Where the clients are kept.
  final OAuth2AuthorizedClientService authorizedClientService;

  /// What gets and renews tokens.
  final OAuth2AuthorizedClientProvider authorizedClientProvider;

  final Map<(String, String), Future<OAuth2AuthorizedClient?>> _inFlight = {};

  /// The errors after which the stored client is removed.
  static const Set<String> _removing = {
    OAuth2ErrorCodes.invalidGrant,
    OAuth2ErrorCodes.invalidToken,
  };

  @override
  Future<OAuth2AuthorizedClient?> authorize(
    OAuth2AuthorizeRequest authorizeRequest,
  ) {
    final key = (
      authorizeRequest.clientRegistrationId,
      authorizeRequest.principal.name,
    );
    final pending = _inFlight[key];
    if (pending != null) {
      return pending;
    }
    final started = _authorize(authorizeRequest);
    _inFlight[key] = started;
    unawaited(_settle(key, started));
    return started;
  }

  // Forgets [started] once it settled; its errors reach the callers
  // through `started` itself.
  Future<void> _settle(
    (String, String) key,
    Future<OAuth2AuthorizedClient?> started,
  ) async {
    try {
      await started;
    } on Object {
      // Reported to the callers.
    } finally {
      if (identical(_inFlight[key], started)) {
        unawaited(_inFlight.remove(key));
      }
    }
  }

  Future<OAuth2AuthorizedClient?> _authorize(
    OAuth2AuthorizeRequest request,
  ) async {
    final id = request.clientRegistrationId;
    final principal = request.principal;
    var current = request.authorizedClient;
    final ClientRegistration registration;
    if (current != null) {
      registration = current.clientRegistration;
    } else {
      registration =
          await clientRegistrationRepository.findByRegistrationId(id) ??
          (throw ArgumentError(
            "Could not find ClientRegistration with id '$id'",
          ));
      current = await authorizedClientService.loadAuthorizedClient(
        id,
        principal.name,
      );
    }
    final context = OAuth2AuthorizationContext(
      clientRegistration: registration,
      principal: principal,
      authorizedClient: current,
      attributes: request.attributes,
    );
    final OAuth2AuthorizedClient? authorized;
    try {
      authorized = await authorizedClientProvider.authorize(context);
    } on OAuth2AuthorizationException catch (e) {
      if (_removing.contains(e.error.errorCode)) {
        _log.debug(
          "Removing the authorized client of registration '$id' after "
          '${e.error.errorCode}',
        );
        await authorizedClientService.removeAuthorizedClient(
          id,
          principal.name,
        );
      }
      rethrow;
    }
    if (authorized != null) {
      await authorizedClientService.saveAuthorizedClient(authorized, principal);
      return authorized;
    }
    return current;
  }
}
