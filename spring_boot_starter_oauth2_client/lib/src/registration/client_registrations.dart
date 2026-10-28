import 'dart:convert';

import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _oidcMetadataPath = '/.well-known/openid-configuration';
const _oauthMetadataPath = '/.well-known/oauth-authorization-server';

/// The largest metadata document read (1 MiB).
const int _maxMetadataBytes = 1 << 20;

/// Builds registrations from what a provider publishes about itself, so
/// only its address (the issuer) has to be configured.
///
/// OpenID Connect providers (Keycloak, Auth0, Okta, Google, Microsoft
/// Entra ID) publish their endpoints at
/// `<issuer>/.well-known/openid-configuration`; plain OAuth 2.0 servers
/// at `/.well-known/oauth-authorization-server` (RFC 8414). The
/// `issuer-uri` property does this for you; call it yourself to build a
/// registration in code:
///
/// ```dart
/// final registration = (await ClientRegistrations.fromIssuerLocation(
///   'https://sso.example.com/realms/neon',
///   transport: transport,
/// ))
///     .registrationId('keycloak')
///     .clientId('neon-app')
///     .scope(['openid', 'profile'])
///     .redirectUri('neonbooks:/oauth2/callback')
///     .build();
/// ```
///
/// The `issuer` the provider names in its metadata must be exactly the
/// one asked for, or the call fails: otherwise a provider could pass
/// tokens off as another's.
///
/// Spring (Java): `ClientRegistrations`. The result is a `Future` (the
/// metadata comes over the network) and the transport is a parameter.
abstract final class ClientRegistrations {
  /// A builder filled from the OpenID Connect metadata of [issuer]
  /// (`<issuer>/.well-known/openid-configuration`).
  ///
  /// Throws an [ArgumentError] when the metadata cannot be found, does
  /// not name [issuer], or lacks an endpoint; an [HttpTransportException]
  /// when the provider cannot be reached.
  static Future<ClientRegistrationBuilder> fromOidcIssuerLocation(
    String issuer, {
    HttpTransport? transport,
  }) {
    final uri = _issuerUri(issuer);
    return _resolve(issuer, transport, [
      (fetch) => _oidc(fetch, issuer, _append(uri, _oidcMetadataPath)),
    ]);
  }

  /// A builder filled from the metadata of [issuer], trying in order, as
  /// Spring does: `<issuer>/.well-known/openid-configuration`, then
  /// `/.well-known/openid-configuration<issuer path>` and
  /// `/.well-known/oauth-authorization-server<issuer path>` (RFC 8414).
  /// A 4xx answer moves to the next; anything else stops.
  ///
  /// The builder has the authorization, token, JWK Set and user-info
  /// URIs, the issuer, the metadata (`end_session_endpoint`,
  /// `revocation_endpoint`, ...), the grant `authorization_code`, the
  /// redirect URI `{baseUrl}/{action}/oauth2/code/{registrationId}`, the
  /// user name attribute `sub` and the client authentication method the
  /// provider supports (`client_secret_basic` first). The registration id
  /// is the issuer's host until you set it.
  ///
  /// Throws an [ArgumentError] when no metadata is found, it does not
  /// name [issuer], or it lacks an endpoint; an [HttpTransportException]
  /// when the provider cannot be reached.
  static Future<ClientRegistrationBuilder> fromIssuerLocation(
    String issuer, {
    HttpTransport? transport,
  }) {
    final uri = _issuerUri(issuer);
    return _resolve(issuer, transport, [
      (fetch) => _oidc(fetch, issuer, _append(uri, _oidcMetadataPath)),
      (fetch) => _oidc(fetch, issuer, _prepend(uri, _oidcMetadataPath)),
      (fetch) => _oauth(fetch, issuer, _prepend(uri, _oauthMetadataPath)),
    ]);
  }

  static Uri _issuerUri(String issuer) {
    final uri = Uri.tryParse(issuer);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError.value(issuer, 'issuer', 'not an absolute URI');
    }
    return uri;
  }

  static String _trimmedPath(Uri uri) => uri.path.endsWith('/')
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;

  static Uri _append(Uri issuer, String suffix) => issuer
      .replace(
        path: '${_trimmedPath(issuer)}$suffix',
        query: '',
      )
      .removeFragment();

  static Uri _prepend(Uri issuer, String prefix) => issuer
      .replace(
        path: '$prefix${_trimmedPath(issuer)}',
        query: '',
      )
      .removeFragment();

  static Future<ClientRegistrationBuilder> _resolve(
    String issuer,
    HttpTransport? given,
    List<
      Future<ClientRegistrationBuilder?> Function(
        Future<Map<String, Object?>?> Function(Uri) fetch,
      )
    >
    attempts,
  ) async {
    final transport = given ?? platformHttpTransport();
    try {
      Future<Map<String, Object?>?> fetch(Uri uri) async {
        final response = await transport.send(
          HttpRequest(
            method: HttpMethod.get,
            url: uri,
            headers: HttpHeaders({
              HttpHeaders.acceptHeader: MediaType.applicationJson,
            }),
          ),
        );
        final status = response.statusCode;
        if (status >= 400 && status < 500) {
          return null; // try the next location
        }
        if (!response.isSuccess) {
          throw ArgumentError(
            'Unable to resolve Configuration with the provided Issuer of '
            '"$issuer": HTTP $status at $uri',
          );
        }
        if (response.bodyBytes.length > _maxMetadataBytes) {
          throw ArgumentError(
            'The configuration metadata of "$issuer" is too large',
          );
        }
        final Object? json;
        try {
          json = jsonDecode(utf8.decode(response.bodyBytes));
        } on FormatException {
          throw ArgumentError(
            'The configuration metadata of "$issuer" is not JSON',
          );
        }
        if (json is! Map<String, Object?>) {
          throw ArgumentError(
            'The configuration metadata of "$issuer" is not a JSON object',
          );
        }
        return json;
      }

      for (final attempt in attempts) {
        final builder = await attempt(fetch);
        if (builder != null) {
          return builder;
        }
      }
      throw ArgumentError(
        'Unable to resolve Configuration with the provided Issuer of '
        '"$issuer"',
      );
    } finally {
      if (given == null) {
        transport.close();
      }
    }
  }

  static Future<ClientRegistrationBuilder?> _oidc(
    Future<Map<String, Object?>?> Function(Uri) fetch,
    String issuer,
    Uri location,
  ) async {
    final metadata = await fetch(location);
    if (metadata == null) {
      return null;
    }
    final builder = _withProviderConfiguration(
      metadata,
      issuer,
    ).jwkSetUri(_required(metadata, 'jwks_uri', issuer));
    final userInfo = metadata['userinfo_endpoint'];
    if (userInfo is String && userInfo.isNotEmpty) {
      builder.userInfoUri(userInfo);
    }
    return builder;
  }

  static Future<ClientRegistrationBuilder?> _oauth(
    Future<Map<String, Object?>?> Function(Uri) fetch,
    String issuer,
    Uri location,
  ) async {
    final metadata = await fetch(location);
    if (metadata == null) {
      return null;
    }
    final builder = _withProviderConfiguration(metadata, issuer);
    final jwks = metadata['jwks_uri'];
    if (jwks is String && jwks.isNotEmpty) {
      builder.jwkSetUri(jwks);
    }
    final userInfo = metadata['userinfo_endpoint'];
    if (userInfo is String && userInfo.isNotEmpty) {
      builder.userInfoUri(userInfo);
    }
    return builder;
  }

  static ClientRegistrationBuilder _withProviderConfiguration(
    Map<String, Object?> metadata,
    String issuer,
  ) {
    final metadataIssuer = metadata['issuer'];
    if (metadataIssuer != issuer) {
      throw ArgumentError(
        'The Issuer "$metadataIssuer" provided in the configuration '
        'metadata did not match the requested issuer "$issuer"',
      );
    }
    final host = Uri.parse(issuer).host;
    return ClientRegistration.withRegistrationId(host)
        .userNameAttributeName('sub')
        .authorizationGrantType(AuthorizationGrantType.authorizationCode)
        .clientAuthenticationMethod(
          _clientAuthenticationMethod(
            metadata['token_endpoint_auth_methods_supported'],
          ),
        )
        .redirectUri('{baseUrl}/{action}/oauth2/code/{registrationId}')
        .authorizationUri(_required(metadata, 'authorization_endpoint', issuer))
        .providerConfigurationMetadata(metadata)
        .tokenUri(_required(metadata, 'token_endpoint', issuer))
        .issuerUri(issuer)
        .clientName(issuer);
  }

  static String _required(
    Map<String, Object?> metadata,
    String name,
    String issuer,
  ) {
    final value = metadata[name];
    if (value is! String || value.isEmpty) {
      throw ArgumentError(
        'The configuration metadata of "$issuer" has no $name',
      );
    }
    return value;
  }

  // Spring's choice: client_secret_basic when listed (or nothing is
  // listed: it is the default), else client_secret_post, else none.
  static ClientAuthenticationMethod? _clientAuthenticationMethod(
    Object? supported,
  ) {
    if (supported is! List ||
        supported.contains(
          ClientAuthenticationMethod.clientSecretBasic.value,
        )) {
      return ClientAuthenticationMethod.clientSecretBasic;
    }
    if (supported.contains(ClientAuthenticationMethod.clientSecretPost.value)) {
      return ClientAuthenticationMethod.clientSecretPost;
    }
    if (supported.contains(ClientAuthenticationMethod.none.value)) {
      return ClientAuthenticationMethod.none;
    }
    return null;
  }
}
