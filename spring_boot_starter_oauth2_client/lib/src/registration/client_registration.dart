// The documentation has properties lines, which cannot be wrapped.
// ignore_for_file: lines_longer_than_80_chars

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
      clientName = builder._clientName ?? builder._registrationId;

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

  @override
  String toString() =>
      'ClientRegistration{registrationId=$registrationId, '
      'clientId=$clientId, clientSecret=[PROTECTED], '
      'clientAuthenticationMethod=$clientAuthenticationMethod, '
      'authorizationGrantType=$authorizationGrantType, '
      'redirectUri=$redirectUri, scopes=$scopes, clientName=$clientName}';
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
      _clientName = registration.clientName;

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
