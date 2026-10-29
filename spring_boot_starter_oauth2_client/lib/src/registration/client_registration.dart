// The documentation has properties lines, which cannot be wrapped.
// ignore_for_file: lines_longer_than_80_chars

import 'package:spring_boot_starter_oauth2_client/src/dpop/dpop_key.dart';

/// How the client proves who it is to the provider's token endpoint.
///
/// A server (a confidential client) has a secret and sends it either in
/// the `Authorization` header ([clientSecretBasic], the default) or in the
/// form ([clientSecretPost]). An app (a public client) has no secret,
/// since anyone could extract it: it uses [none], and PKCE protects its
/// codes instead. The registration's `client-authentication-method`
/// property picks one; without it, a registration with no secret gets
/// [none].
///
/// ```properties
/// spring.security.oauth2.client.registration.keycloak.client-authentication-method=client_secret_post
/// ```
///
/// Spring (Java): `ClientAuthenticationMethod`. `client_secret_jwt`,
/// `private_key_jwt` and `tls_client_auth` exist as values but the token
/// clients refuse them.
final class ClientAuthenticationMethod {
  /// A method named [value], as in the properties and the provider's
  /// metadata.
  const ClientAuthenticationMethod(this.value);

  /// `client_secret_basic`: the id and secret in HTTP Basic (RFC 6749
  /// §2.3.1).
  static const clientSecretBasic = ClientAuthenticationMethod(
    'client_secret_basic',
  );

  /// `client_secret_post`: the id and secret as form parameters.
  static const clientSecretPost = ClientAuthenticationMethod(
    'client_secret_post',
  );

  /// `client_secret_jwt` (not supported by the token clients).
  static const clientSecretJwt = ClientAuthenticationMethod(
    'client_secret_jwt',
  );

  /// `private_key_jwt` (not supported by the token clients).
  static const privateKeyJwt = ClientAuthenticationMethod('private_key_jwt');

  /// `none`: a public client, only its `client_id` is sent.
  static const none = ClientAuthenticationMethod('none');

  /// The name, such as `client_secret_basic`.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is ClientAuthenticationMethod && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// How a client gets its tokens: the OAuth 2.0 grant.
///
/// [authorizationCode] logs a user in through the browser (apps and
/// server pages); [clientCredentials] gets a token for the client itself
/// (server to server); [refreshToken] renews tokens. Set by the
/// registration's `authorization-grant-type` property; the common
/// providers and issuer discovery choose [authorizationCode].
///
/// Spring (Java): `AuthorizationGrantType`.
final class AuthorizationGrantType {
  /// A grant named [value].
  const AuthorizationGrantType(this.value);

  /// `authorization_code`: a user logs in in the browser.
  static const authorizationCode = AuthorizationGrantType(
    'authorization_code',
  );

  /// `refresh_token`: new tokens for a refresh token.
  static const refreshToken = AuthorizationGrantType('refresh_token');

  /// `client_credentials`: the client's own token, no user.
  static const clientCredentials = AuthorizationGrantType(
    'client_credentials',
  );

  /// The name, such as `authorization_code`.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is AuthorizationGrantType && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// How the access token is sent to the user-info endpoint.
///
/// Spring (Java): `AuthenticationMethod`.
final class AuthenticationMethod {
  /// A method named [value].
  const AuthenticationMethod(this.value);

  /// `header`: `Authorization: Bearer <token>` (the default).
  static const header = AuthenticationMethod('header');

  /// `form`: a POST with `access_token` in the form.
  static const form = AuthenticationMethod('form');

  /// `query`: `?access_token=` (supported for compatibility; avoid it, the
  /// token ends up in logs).
  static const query = AuthenticationMethod('query');

  /// The name, such as `header`.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is AuthenticationMethod && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// The provider's user-info endpoint: where to ask about the user, how to
/// send the token, and which attribute names the user.
///
/// Spring (Java): `ClientRegistration.ProviderDetails.UserInfoEndpoint`.
final class UserInfoEndpoint {
  /// An endpoint at [uri] (none when `null`).
  const UserInfoEndpoint({
    this.uri,
    this.authenticationMethod = AuthenticationMethod.header,
    this.userNameAttributeName,
  });

  /// The URL, or `null` when the provider has none.
  final String? uri;

  /// How the access token is sent; [AuthenticationMethod.header] by
  /// default.
  final AuthenticationMethod authenticationMethod;

  /// The attribute of the user info (or of the ID token) that is the
  /// user's name in the application, such as `sub`, `login` or `email`.
  final String? userNameAttributeName;
}

/// Where a provider's endpoints are and what it says about itself.
///
/// Built from the common providers (Google, GitHub, ...), from the
/// provider's metadata (issuer discovery) or from the
/// `spring.security.oauth2.client.provider.<id>.*` properties.
///
/// Spring (Java): `ClientRegistration.ProviderDetails`.
final class ProviderDetails {
  /// The details of one provider.
  ProviderDetails({
    this.authorizationUri,
    this.tokenUri,
    this.userInfoEndpoint = const UserInfoEndpoint(),
    this.jwkSetUri,
    this.issuerUri,
    Map<String, Object?> configurationMetadata = const {},
  }) : configurationMetadata = Map.unmodifiable(configurationMetadata);

  /// The page that logs the user in (`authorization_endpoint`).
  final String? authorizationUri;

  /// The endpoint that issues tokens (`token_endpoint`).
  final String? tokenUri;

  /// The user-info endpoint.
  final UserInfoEndpoint userInfoEndpoint;

  /// The provider's public keys (`jwks_uri`), for servers checking
  /// signatures.
  final String? jwkSetUri;

  /// The provider's issuer identifier: the `iss` of its ID tokens and of
  /// its redirects (RFC 9207).
  final String? issuerUri;

  /// The provider's metadata as discovered (empty otherwise), such as
  /// `end_session_endpoint`, `revocation_endpoint` and
  /// `authorization_response_iss_parameter_supported`.
  final Map<String, Object?> configurationMetadata;

  /// `end_session_endpoint` of the metadata: where the provider's own
  /// session is ended (OpenID Connect RP-initiated logout), or `null`.
  String? get endSessionEndpoint =>
      _text(configurationMetadata['end_session_endpoint']);

  /// `revocation_endpoint` of the metadata: where tokens are revoked (RFC
  /// 7009), or `null`.
  String? get revocationEndpoint =>
      _text(configurationMetadata['revocation_endpoint']);

  static String? _text(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}

/// Whether a registration's tokens are bound to the app's key with DPoP
/// (RFC 9449), set by the registration's `dpop` property.
///
/// With DPoP the token requests carry a proof signed by the app's
/// `DPoPKey`, the provider binds the tokens to that key, and every API
/// call sends `Authorization: DPoP <token>` with a fresh proof: a stolen
/// token is useless without the key. [auto], the default, uses it when
/// the provider says it can (its discovered metadata lists the key's
/// algorithm in `dpop_signing_alg_values_supported`); [enabled] always,
/// for a provider configured by hand; [disabled] never.
///
/// DPoP needs a key that lives as long as the tokens: an app with
/// `spring_boot_starter_flutter_security` keeps it in the Secure Enclave,
/// the Android Keystore or its `SecretStore`; elsewhere the starter's key
/// lives as long as the process (the tokens die with it). A server with
/// several instances sharing sessions declares a shared `DPoPKey` bean,
/// or sets `dpop=false`.
///
/// ```properties
/// spring.security.oauth2.client.registration.keycloak.dpop=true
/// ```
///
/// Spring (Java): no such setting; Spring Security has no DPoP on the
/// client's side yet (spring-security#18228 proposes
/// `ClientSettings.requireDpop`). An addition of this port.
enum DPoPMode {
  /// On when the key outlives the program (the apps' keys:
  /// [DPoPKey.persistent]) and the provider's metadata lists its
  /// algorithm in `dpop_signing_alg_values_supported`; off otherwise, so
  /// a server with a key made in memory keeps `Bearer` (`dpop=auto`, the
  /// default).
  auto,

  /// Always on (`dpop=true`).
  enabled,

  /// Always off: `Bearer` tokens (`dpop=false`).
  disabled;

  /// The mode of the property value [value]: `auto`, `true` or `false`
  /// (any case).
  ///
  /// Throws an [ArgumentError] for anything else.
  static DPoPMode parse(String value) => switch (value.trim().toLowerCase()) {
    'auto' => auto,
    'true' => enabled,
    'false' => disabled,
    _ => throw ArgumentError.value(
      value,
      'dpop',
      'must be auto, true or false',
    ),
  };
}

/// How the provider sends the authorization response (the `code` and
/// `state`, or an `error`) back to the redirect URI: OAuth 2.0's
/// `response_mode` parameter.
///
/// [query], the default of the code flow, redirects the browser with the
/// parameters in the URI. [formPost] (OAuth 2.0 Form Post Response Mode)
/// makes the browser post them as a form to the redirect URI, so they
/// never appear in a URI, a log or the history. Sign in with Apple
/// requires it when the login asks for the user's name or e-mail. Only a
/// server can receive a form post: `oauth2Login()` of the security
/// starter accepts the callback as a `POST` for these registrations (and
/// only for them); an app's login window refuses it.
///
/// ```properties
/// spring.security.oauth2.client.registration.apple.response-mode=form_post
/// ```
///
/// Spring (Java): no such setting; Spring Security sends no
/// `response_mode` and its callback reads the parameters of any method,
/// so a Spring application adds the parameter with an authorization
/// request customizer.
enum ResponseMode {
  /// The parameters in the redirect URI's query (`response_mode` not
  /// sent): the default.
  query('query'),

  /// The parameters posted as an `application/x-www-form-urlencoded`
  /// form to the redirect URI (`response_mode=form_post`).
  formPost('form_post');

  ResponseMode(this.value);

  /// The value of `response_mode` and of the `response-mode` property.
  final String value;

  /// The mode named [value] (`query`, `form_post`), ignoring case and
  /// `-` / `_`.
  ///
  /// Throws an [ArgumentError] for another value (`fragment` included:
  /// a server never sees a URI's fragment).
  static ResponseMode parse(String value) =>
      switch (value.trim().toLowerCase().replaceAll('-', '_')) {
        'query' => query,
        'form_post' => formPost,
        _ => throw ArgumentError.value(
          value,
          'response-mode',
          'must be query or form_post',
        ),
      };
}

/// One client of one OAuth 2.0 or OpenID Connect provider: the client's
/// id and secret there, the grant, the redirect URI, the scopes, and where
/// the provider's endpoints are.
///
/// An application has one per provider it logs in with (`keycloak`,
/// `google`) or calls APIs through. Usually they come from properties, and
/// the `ClientRegistrationRepository` bean holds them:
///
/// ```properties
/// spring.security.oauth2.client.registration.keycloak.client-id=neon-app
/// spring.security.oauth2.client.registration.keycloak.scope=openid,profile
/// spring.security.oauth2.client.registration.keycloak.redirect-uri=neonbooks:/oauth2/callback
/// spring.security.oauth2.client.provider.keycloak.issuer-uri=https://sso.example.com/realms/neon
/// ```
///
/// Build one in code for a provider the properties cannot describe:
///
/// ```dart
/// final registration = ClientRegistration.withRegistrationId('partner')
///     .clientId('shop')
///     .clientSecret(environment.getRequiredProperty('partner.secret'))
///     .authorizationGrantType(AuthorizationGrantType.clientCredentials)
///     .tokenUri('https://partner.example.com/oauth/token')
///     .scope(['orders.read'])
///     .build();
/// ```
///
/// Spring (Java): `ClientRegistration`, with the same builder.
final class ClientRegistration {
  ClientRegistration._(
    ClientRegistrationBuilder builder,
    this.clientAuthenticationMethod,
  ) : registrationId = builder._registrationId,
      clientId = builder._clientId!,
      clientSecret = builder._clientSecret ?? '',
      authorizationGrantType = builder._authorizationGrantType!,
      redirectUri = builder._redirectUri,
      scopes = Set.unmodifiable(builder._scopes ?? const <String>{}),
      providerDetails = ProviderDetails(
        authorizationUri: builder._authorizationUri,
        tokenUri: builder._tokenUri,
        userInfoEndpoint: UserInfoEndpoint(
          uri: builder._userInfoUri,
          authenticationMethod:
              builder._userInfoAuthenticationMethod ??
              AuthenticationMethod.header,
          userNameAttributeName: builder._userNameAttributeName,
        ),
        jwkSetUri: builder._jwkSetUri,
        issuerUri: builder._issuerUri,
        configurationMetadata: builder._configurationMetadata,
      ),
      clientName = builder._clientName ?? builder._registrationId,
      dpop = builder._dpop,
      responseMode = builder._responseMode;

  /// A builder for the registration [registrationId].
  static ClientRegistrationBuilder withRegistrationId(String registrationId) =>
      ClientRegistrationBuilder._(registrationId);

  /// A builder holding everything of [registration], to change some of
  /// it.
  static ClientRegistrationBuilder withClientRegistration(
    ClientRegistration registration,
  ) => ClientRegistrationBuilder._from(registration);

  /// The registration's id, such as `keycloak`: the `<id>` of the
  /// properties.
  final String registrationId;

  /// The client's id at the provider.
  final String clientId;

  /// The client's secret at the provider; empty for a public client (an
  /// app). A credential: never log it.
  final String clientSecret;

  /// How the client authenticates at the token endpoint.
  final ClientAuthenticationMethod clientAuthenticationMethod;

  /// The grant: how tokens are obtained.
  final AuthorizationGrantType authorizationGrantType;

  /// The redirect URI template, such as
  /// `{baseUrl}/{action}/oauth2/code/{registrationId}` or
  /// `neonbooks:/oauth2/callback`; `expandRedirectUri` fills it in.
  final String? redirectUri;

  /// The scopes asked for; cannot be modified.
  final Set<String> scopes;

  /// The provider's endpoints and metadata.
  final ProviderDetails providerDetails;

  /// A name to show users ("Log in with Google"); the registration id
  /// when not set.
  final String clientName;

  /// Whether the tokens are DPoP-bound: [DPoPMode.auto] by default (when
  /// the provider announces it). Not in Spring (see [DPoPMode]).
  final DPoPMode dpop;

  /// How the provider returns the authorization response:
  /// [ResponseMode.query] (the default of the code flow, a redirect with
  /// the code in the URI) or [ResponseMode.formPost] (the browser posts
  /// it to the redirect URI). Not in Spring (see [ResponseMode]).
  final ResponseMode responseMode;

  /// Whether this registration uses DPoP with [key]: [dpop] decides; for
  /// [DPoPMode.auto] the key must outlive the program
  /// ([DPoPKey.persistent]: the apps' keys, not a server's key made in
  /// memory) and the provider's `dpop_signing_alg_values_supported`
  /// metadata must list its algorithm.
  bool usesDPoP(DPoPKey key) => switch (dpop) {
    DPoPMode.enabled => true,
    DPoPMode.disabled => false,
    DPoPMode.auto =>
      key.persistent &&
          switch (providerDetails
              .configurationMetadata['dpop_signing_alg_values_supported']) {
            final List<Object?> algorithms => algorithms.contains(
              key.algorithm,
            ),
            _ => false,
          },
  };

  @override
  String toString() =>
      'ClientRegistration{registrationId=$registrationId, '
      'clientId=$clientId, clientSecret=[PROTECTED], '
      'clientAuthenticationMethod=$clientAuthenticationMethod, '
      'authorizationGrantType=$authorizationGrantType, '
      'redirectUri=$redirectUri, scopes=$scopes, clientName=$clientName, '
      'dpop=${dpop.name}, responseMode=${responseMode.value}}';
}

/// Builds a [ClientRegistration]; get one from
/// [ClientRegistration.withRegistrationId].
///
/// [build] checks that the grant has what it needs: an
/// `authorization_code` registration needs a client id, a redirect URI,
/// and the authorization and token URIs; a `client_credentials` one a
/// client id and a token URI.
///
/// Spring (Java): `ClientRegistration.Builder`.
final class ClientRegistrationBuilder {
  ClientRegistrationBuilder._(this._registrationId);

  ClientRegistrationBuilder._from(ClientRegistration registration)
    : _registrationId = registration.registrationId,
      _clientId = registration.clientId,
      _clientSecret = registration.clientSecret,
      _clientAuthenticationMethod = registration.clientAuthenticationMethod,
      _authorizationGrantType = registration.authorizationGrantType,
      _redirectUri = registration.redirectUri,
      _scopes = {...registration.scopes},
      _authorizationUri = registration.providerDetails.authorizationUri,
      _tokenUri = registration.providerDetails.tokenUri,
      _userInfoUri = registration.providerDetails.userInfoEndpoint.uri,
      _userInfoAuthenticationMethod =
          registration.providerDetails.userInfoEndpoint.authenticationMethod,
      _userNameAttributeName =
          registration.providerDetails.userInfoEndpoint.userNameAttributeName,
      _jwkSetUri = registration.providerDetails.jwkSetUri,
      _issuerUri = registration.providerDetails.issuerUri,
      _configurationMetadata = {
        ...registration.providerDetails.configurationMetadata,
      },
      _clientName = registration.clientName,
      _dpop = registration.dpop,
      _responseMode = registration.responseMode;

  String _registrationId;
  String? _clientId;
  String? _clientSecret;
  ClientAuthenticationMethod? _clientAuthenticationMethod;
  AuthorizationGrantType? _authorizationGrantType;
  String? _redirectUri;
  Set<String>? _scopes;
  String? _authorizationUri;
  String? _tokenUri;
  String? _userInfoUri;
  AuthenticationMethod? _userInfoAuthenticationMethod;
  String? _userNameAttributeName;
  String? _jwkSetUri;
  String? _issuerUri;
  Map<String, Object?> _configurationMetadata = const {};
  String? _clientName;
  DPoPMode _dpop = DPoPMode.auto;
  ResponseMode _responseMode = ResponseMode.query;

  /// Sets the registration id.
  ClientRegistrationBuilder registrationId(String registrationId) {
    _registrationId = registrationId;
    return this;
  }

  /// Sets the client id.
  ClientRegistrationBuilder clientId(String clientId) {
    _clientId = clientId;
    return this;
  }

  /// Sets the client secret (none for an app).
  ClientRegistrationBuilder clientSecret(String? clientSecret) {
    _clientSecret = clientSecret;
    return this;
  }

  /// Sets how the client authenticates at the token endpoint; without it,
  /// [ClientAuthenticationMethod.none] for an `authorization_code`
  /// registration without a secret, else
  /// [ClientAuthenticationMethod.clientSecretBasic].
  ClientRegistrationBuilder clientAuthenticationMethod(
    ClientAuthenticationMethod? method,
  ) {
    _clientAuthenticationMethod = method;
    return this;
  }

  /// Sets the grant.
  ClientRegistrationBuilder authorizationGrantType(
    AuthorizationGrantType grantType,
  ) {
    _authorizationGrantType = grantType;
    return this;
  }

  /// Sets the redirect URI template (`{baseUrl}`, `{registrationId}`,
  /// `{action}`, `{baseScheme}`, `{baseHost}`, `{basePort}` and
  /// `{basePath}` are filled in).
  ClientRegistrationBuilder redirectUri(String? redirectUri) {
    _redirectUri = redirectUri;
    return this;
  }

  /// Sets the scopes; `null` or empty for none.
  ClientRegistrationBuilder scope(Iterable<String>? scopes) {
    _scopes = scopes == null ? null : {...scopes};
    return this;
  }

  /// Sets the provider's authorization endpoint.
  ClientRegistrationBuilder authorizationUri(String? uri) {
    _authorizationUri = uri;
    return this;
  }

  /// Sets the provider's token endpoint.
  ClientRegistrationBuilder tokenUri(String? uri) {
    _tokenUri = uri;
    return this;
  }

  /// Sets the provider's user-info endpoint.
  ClientRegistrationBuilder userInfoUri(String? uri) {
    _userInfoUri = uri;
    return this;
  }

  /// Sets how the token is sent to the user-info endpoint.
  ClientRegistrationBuilder userInfoAuthenticationMethod(
    AuthenticationMethod? method,
  ) {
    _userInfoAuthenticationMethod = method;
    return this;
  }

  /// Sets the attribute that names the user.
  ClientRegistrationBuilder userNameAttributeName(String? name) {
    _userNameAttributeName = name;
    return this;
  }

  /// Sets the provider's JWK Set URI.
  ClientRegistrationBuilder jwkSetUri(String? uri) {
    _jwkSetUri = uri;
    return this;
  }

  /// Sets the provider's issuer identifier.
  ClientRegistrationBuilder issuerUri(String? uri) {
    _issuerUri = uri;
    return this;
  }

  /// Sets the provider's metadata.
  ClientRegistrationBuilder providerConfigurationMetadata(
    Map<String, Object?> metadata,
  ) {
    _configurationMetadata = {...metadata};
    return this;
  }

  /// Sets the name shown to users.
  ClientRegistrationBuilder clientName(String? name) {
    _clientName = name;
    return this;
  }

  /// Sets whether the tokens are DPoP-bound ([DPoPMode.auto] by
  /// default). Not in Spring (see [DPoPMode]).
  ClientRegistrationBuilder dpop(DPoPMode mode) {
    _dpop = mode;
    return this;
  }

  /// Sets how the provider returns the authorization response
  /// ([ResponseMode.query] by default). Not in Spring (see
  /// [ResponseMode]).
  ClientRegistrationBuilder responseMode(ResponseMode mode) {
    _responseMode = mode;
    return this;
  }

  /// The registration.
  ///
  /// Throws an [ArgumentError] when something the grant needs is missing
  /// or a scope has characters RFC 6749 §3.3 does not allow.
  ClientRegistration build() {
    void require(String? value, String name) {
      if (value == null || value.trim().isEmpty) {
        throw ArgumentError(
          '$name cannot be empty (registration $_registrationId)',
        );
      }
    }

    require(_registrationId, 'registrationId');
    final grant = _authorizationGrantType;
    if (grant == null) {
      throw ArgumentError(
        'authorizationGrantType cannot be null (registration '
        '$_registrationId)',
      );
    }
    require(_clientId, 'clientId');
    if (grant == AuthorizationGrantType.authorizationCode) {
      require(_redirectUri, 'redirectUri');
      require(_authorizationUri, 'authorizationUri');
      require(_tokenUri, 'tokenUri');
    } else if (grant == AuthorizationGrantType.clientCredentials) {
      require(_tokenUri, 'tokenUri');
    }
    for (final scope in _scopes ?? const <String>{}) {
      if (!_validScope(scope)) {
        throw ArgumentError(
          'scope "$scope" contains invalid characters (registration '
          '$_registrationId)',
        );
      }
    }
    final method =
        _clientAuthenticationMethod ??
        (grant == AuthorizationGrantType.authorizationCode &&
                (_clientSecret == null || _clientSecret!.isEmpty)
            ? ClientAuthenticationMethod.none
            : ClientAuthenticationMethod.clientSecretBasic);
    return ClientRegistration._(this, method);
  }

  // RFC 6749 §3.3: scope-token = 1*( %x21 / %x23-5B / %x5D-7E ).
  static bool _validScope(String scope) =>
      scope.isNotEmpty &&
      scope.codeUnits.every(
        (c) =>
            c == 0x21 || (c >= 0x23 && c <= 0x5b) || (c >= 0x5d && c <= 0x7e),
      );
}
