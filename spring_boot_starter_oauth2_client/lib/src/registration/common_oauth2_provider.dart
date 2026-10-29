// The documentation has properties lines, which cannot be wrapped.
// ignore_for_file: lines_longer_than_80_chars

import 'package:spring_boot_starter_oauth2_client/src/endpoint/jwt_client_secret.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration.dart';

const _defaultRedirectUrl = '{baseUrl}/{action}/oauth2/code/{registrationId}';

/// The well-known providers whose endpoints need no configuration:
/// Google, GitHub, Facebook, Okta, and Apple (not in Spring).
///
/// A registration named after one (or with `provider=<name>`) gets its
/// endpoints, scopes and user name attribute from here, so the
/// properties hold only the client:
///
/// ```properties
/// spring.security.oauth2.client.registration.github.client-id=Iv1.8a61f9b3a7aba766
/// spring.security.oauth2.client.registration.github.client-secret=${GITHUB_SECRET}
/// ```
///
/// Okta has no fixed address: set
/// `spring.security.oauth2.client.provider.okta.issuer-uri` (or its
/// endpoints) too. In code, [getBuilder] starts a registration:
///
/// ```dart
/// final google = CommonOAuth2Provider.google
///     .getBuilder('google')
///     .clientId(clientId)
///     .build();
/// ```
///
/// Spring (Java): `CommonOAuth2Provider`, with the same URIs. Spring has
/// no `APPLE`: [apple] is this package's addition.
enum CommonOAuth2Provider {
  /// Google: OpenID Connect, scopes `openid profile email`.
  google,

  /// GitHub: OAuth 2.0, scope `read:user`, the user named by `id`.
  github,

  /// Facebook: OAuth 2.0, scopes `public_profile email`, the client
  /// secret in the form.
  facebook,

  /// Okta: OpenID Connect, scopes `openid profile email`; the endpoints
  /// come from the issuer.
  okta,

  /// Sign in with Apple: OpenID Connect, scopes `openid name email`,
  /// `client_secret_post`, the response as a form post
  /// ([ResponseMode.formPost], which Apple requires for `name` and
  /// `email`), no user-info endpoint (the ID token holds `sub` and the
  /// e-mail; the name comes once, in the first login's `user`).
  ///
  /// A server's client secret is a JWT it signs itself with the key of
  /// its Apple developer account (`client-secret-jwt.*`, see
  /// [JwtClientSecret]); an app on iOS or macOS signs in with the
  /// system's sheet instead (`spring_boot_starter_flutter_security`).
  /// Not in Spring's `CommonOAuth2Provider`.
  apple;

  /// A builder for the registration [registrationId] with this provider's
  /// endpoints, scopes, authentication method and the redirect URI
  /// `{baseUrl}/{action}/oauth2/code/{registrationId}`; add the client id
  /// (and secret) and build.
  ClientRegistrationBuilder getBuilder(String registrationId) {
    ClientRegistrationBuilder builder(ClientAuthenticationMethod method) =>
        ClientRegistration.withRegistrationId(registrationId)
            .clientAuthenticationMethod(method)
            .authorizationGrantType(AuthorizationGrantType.authorizationCode)
            .redirectUri(_defaultRedirectUrl);
    return switch (this) {
      google =>
        builder(ClientAuthenticationMethod.clientSecretBasic)
            .scope(['openid', 'profile', 'email'])
            .authorizationUri('https://accounts.google.com/o/oauth2/v2/auth')
            .tokenUri('https://www.googleapis.com/oauth2/v4/token')
            .jwkSetUri('https://www.googleapis.com/oauth2/v3/certs')
            .issuerUri('https://accounts.google.com')
            .userInfoUri('https://www.googleapis.com/oauth2/v3/userinfo')
            .userNameAttributeName('sub')
            .clientName('Google'),
      github =>
        builder(ClientAuthenticationMethod.clientSecretBasic)
            .scope(['read:user'])
            .authorizationUri('https://github.com/login/oauth/authorize')
            .tokenUri('https://github.com/login/oauth/access_token')
            .userInfoUri('https://api.github.com/user')
            .userNameAttributeName('id')
            .clientName('GitHub'),
      facebook =>
        builder(ClientAuthenticationMethod.clientSecretPost)
            .scope(['public_profile', 'email'])
            .authorizationUri('https://www.facebook.com/v2.8/dialog/oauth')
            .tokenUri('https://graph.facebook.com/v2.8/oauth/access_token')
            .userInfoUri('https://graph.facebook.com/me?fields=id,name,email')
            .userNameAttributeName('id')
            .clientName('Facebook'),
      okta =>
        builder(ClientAuthenticationMethod.clientSecretBasic)
            .scope(['openid', 'profile', 'email'])
            .userNameAttributeName('sub')
            .clientName('Okta'),
      apple =>
        builder(ClientAuthenticationMethod.clientSecretPost)
            .scope(['openid', 'name', 'email'])
            .authorizationUri('https://appleid.apple.com/auth/authorize')
            .tokenUri('https://appleid.apple.com/auth/token')
            .jwkSetUri('https://appleid.apple.com/auth/keys')
            .issuerUri('https://appleid.apple.com')
            .userNameAttributeName('sub')
            .responseMode(ResponseMode.formPost)
            .clientName('Apple'),
    };
  }

  /// The provider named [id], ignoring case and `-` / `_` (`GitHub`,
  /// `github`), or `null`.
  static CommonOAuth2Provider? of(String id) {
    final normalized = id.toLowerCase().replaceAll(RegExp('[-_]'), '');
    for (final provider in values) {
      if (provider.name == normalized) {
        return provider;
      }
    }
    return null;
  }
}
