import 'package:spring_boot_dart/spring_boot_dart.dart';

const _registrationPrefix = 'spring.security.oauth2.client.registration';

/// The `spring.security.oauth2.client.registration.<id>.*` properties of
/// one registration.
///
/// Spring Boot (Java): `OAuth2ClientProperties.Registration`, plus `dpop`,
/// `response-mode`, `native-sign-in` and `client-secret-jwt`.
@Introspected()
final class OAuth2ClientRegistrationProperties {
  /// The properties of one registration, as read.
  const OAuth2ClientRegistrationProperties({
    this.provider,
    this.clientId,
    this.clientSecret,
    this.clientAuthenticationMethod,
    this.authorizationGrantType,
    this.redirectUri,
    this.scope,
    this.clientName,
    this.dpop,
    this.responseMode,
    this.nativeSignIn,
    this.clientSecretJwt,
  });

  /// The provider of the `provider.*` keys, or a known one (`google`,
  /// `github`, `facebook`, `okta`, `apple`). Default: the registration's
  /// id.
  final String? provider;

  /// The client's id at the provider. Required.
  final String? clientId;

  /// The client's secret; none for an app (a public client). A credential,
  /// never log it.
  final String? clientSecret;

  /// How the client proves who it is at the token endpoint. Default:
  /// `none` without a secret for `authorization_code`, else
  /// `client_secret_basic`.
  @PropertyValues(['client_secret_basic', 'client_secret_post', 'none'])
  final String? clientAuthenticationMethod;

  /// A user's login, or the client's own tokens (server to server).
  /// Default: `authorization_code` with an `issuer-uri` or a known
  /// provider; required otherwise.
  @PropertyValues(['authorization_code', 'client_credentials'])
  final String? authorizationGrantType;

  /// Where the provider sends the browser back (a template such as
  /// `{baseUrl}/login/oauth2/code/{registrationId}`, or
  /// `neonbooks:/oauth2/callback`); the provider must accept it.
  final String? redirectUri;

  /// The scopes asked for (a comma list or a YAML list); `openid` makes it
  /// an OpenID Connect login (an ID token, checked). Default: none; the
  /// provider's defaults for the known providers.
  final Set<String>? scope;

  /// The name on the login page. Default: the issuer, or the known
  /// provider's name.
  final String? clientName;

  /// DPoP (RFC 9449): the tokens are bound to the app's `DPoPKey` and every
  /// request carries a proof signed by it. `auto` (the default) binds them
  /// when the provider announces DPoP and the app has a key kept outside
  /// the program. Not in Spring Boot.
  @PropertyValues(['auto', 'true', 'false'])
  final String? dpop;

  /// How the provider returns the authorization response: in the redirect
  /// URI (`query`, the default), or posted as a form to it (`form_post`;
  /// only a server's `oauth2Login()` receives it, over HTTPS only: its
  /// authorization request cookie is then `SameSite=None; Secure`).
  /// `form_post` is the default of the apple provider. Not in Spring Boot.
  @PropertyValues(['query', 'form_post'])
  final String? responseMode;

  /// Apps (`spring_boot_starter_flutter_security`): `apple` signs in with
  /// Sign in with Apple's sheet on iOS and macOS instead of the browser;
  /// the code then goes to the registration's `token-uri`, the app's
  /// server. Default: `apple` for the apple provider, else `none`.
  @PropertyValues(['none', 'apple'])
  final String? nativeSignIn;

  /// A client secret that is a JWT signed ES256 by the client's own key
  /// (Sign in with Apple's), instead of `client-secret`. Not in Spring
  /// Boot.
  final OAuth2ClientSecretJwtProperties? clientSecretJwt;
}

/// The `client-secret-jwt.*` properties of one registration: a client
/// secret that is a JWT signed ES256 by the client's own key, made again
/// before it expires (Sign in with Apple's). Not in Spring Boot.
///
/// The keys are read at the first token request of their registration,
/// not at startup, from `private-key` (the PEM itself, from an
/// environment variable) or `private-key-location` (`file:`,
/// `resources:`). A key that cannot be read or is no P-256 key fails
/// that request (`invalid_client`), never with the key in the message.
@Introspected()
final class OAuth2ClientSecretJwtProperties {
  /// The JWT properties of one registration.
  const OAuth2ClientSecretJwtProperties({
    this.issuer,
    this.keyId,
    this.privateKey,
    this.privateKeyLocation,
    this.audience,
    this.lifetime = const Duration(hours: 1),
  });

  /// The JWT's `iss` (Apple: the team id). Required.
  final String? issuer;

  /// The JWT's `kid` (Apple: the key id). Required.
  final String? keyId;

  /// The PKCS #8 PEM itself instead of a location (from an environment
  /// variable; `\n` escapes allowed). A credential, never log it.
  final String? privateKey;

  /// The PKCS #8 private key (Apple's `.p8`), such as
  /// `file:/run/secrets/apple.p8`; read at the first token request, never
  /// logged. Either this or `private-key` is required.
  final String? privateKeyLocation;

  /// The JWT's `aud`. Default: the provider's issuer-uri.
  final String? audience;

  /// How long each JWT is valid (at most `180d`, at least `1m`); made
  /// again when a tenth is left.
  final Duration lifetime;

  /// Whether any property is set: a registration without them has no JWT
  /// secret.
  bool get isSet =>
      issuer != null ||
      keyId != null ||
      privateKey != null ||
      privateKeyLocation != null ||
      audience != null;
}

/// The `spring.security.oauth2.client.provider.<id>.*` properties of one
/// provider.
///
/// Spring Boot (Java): `OAuth2ClientProperties.Provider`.
@Introspected()
final class OAuth2ClientProviderProperties {
  /// The properties of one provider, as read.
  const OAuth2ClientProviderProperties({
    this.authorizationUri,
    this.tokenUri,
    this.userInfoUri,
    this.userInfoAuthenticationMethod,
    this.userNameAttribute,
    this.jwkSetUri,
    this.issuerUri,
  });

  /// The provider's login page. Default: from the metadata.
  final String? authorizationUri;

  /// The token endpoint. Default: from the metadata.
  final String? tokenUri;

  /// The user-info endpoint. Default: from the metadata.
  final String? userInfoUri;

  /// How the access token is sent to the user-info endpoint. Default:
  /// `header`.
  @PropertyValues(['header', 'form', 'query'])
  final String? userInfoAuthenticationMethod;

  /// The attribute that names the user. Default: `sub` with `issuer-uri`.
  final String? userNameAttribute;

  /// The provider's public keys; a server checks ID token signatures with
  /// them. Default: from the metadata.
  final String? jwkSetUri;

  /// The provider; the other endpoints come from its OpenID (or OAuth 2.0)
  /// metadata, whose `issuer` must equal it.
  final String? issuerUri;
}

/// The `spring.security.oauth2.client.*` properties: the registrations
/// and the providers, by id.
///
/// The starter reads them to build the `ClientRegistrationRepository`;
/// applications set them and rarely use this class.
///
/// ```properties
/// spring.security.oauth2.client.registration.keycloak.client-id=neon-app
/// spring.security.oauth2.client.registration.keycloak.scope=openid,profile
/// spring.security.oauth2.client.registration.keycloak.redirect-uri=neonbooks:/oauth2/callback
/// spring.security.oauth2.client.provider.keycloak.issuer-uri=https://sso.example.com/realms/neon
/// ```
///
/// Spring Boot (Java): `OAuth2ClientProperties`, with the same names.
@ConfigurationProperties('spring.security.oauth2.client')
final class OAuth2ClientProperties {
  /// The properties [registration] and [provider], by id.
  const OAuth2ClientProperties({
    this.registration = const {},
    this.provider = const {},
  });

  /// Whether [environment] has at least one registration property: the
  /// condition of the starter's repository.
  static bool hasRegistrations(Environment environment) => _ids(
    environment,
    environment is ConfigurableEnvironment ? Binder.get(environment) : null,
    _registrationPrefix,
  ).isNotEmpty;

  // The ids under [prefix]: the first element of every property name
  // below it (relaxed names, YAML lists and environment variables
  // included).
  static Set<String> _ids(
    Environment environment,
    Binder? binder,
    String prefix,
  ) {
    if (binder == null) {
      return const {};
    }
    final entries = binder
        .bind(
          prefix,
          const MapType<String, String>(
            ClassType<String>(),
            ClassType<String>(),
          ),
        )
        .orElse(const {});
    return {
      for (final key in entries.keys)
        if (key.split('.').first.trim().isNotEmpty) key.split('.').first,
    };
  }

  /// The registrations, by id.
  final Map<String, OAuth2ClientRegistrationProperties> registration;

  /// The providers, by id.
  final Map<String, OAuth2ClientProviderProperties> provider;

  /// Checks that every registration has a client id.
  ///
  /// Throws a [StateError] (`Client id of registration 'x' must not be
  /// empty.`) otherwise.
  void validate() {
    for (final MapEntry(key: id, :value) in registration.entries) {
      if (value.clientId == null || value.clientId!.trim().isEmpty) {
        throw StateError("Client id of registration '$id' must not be empty.");
      }
    }
  }
}
