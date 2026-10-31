import 'dart:convert';

import 'package:spring_boot_dart/spring_boot_dart.dart' show SpringLog;
import 'package:spring_boot_starter_oauth2_client/src/core/log_support.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/oauth2_error.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/parameter_names.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/tokens.dart';
import 'package:spring_boot_starter_oauth2_client/src/dpop/dpop_key.dart';
import 'package:spring_boot_starter_oauth2_client/src/dpop/dpop_nonces.dart';
import 'package:spring_boot_starter_oauth2_client/src/dpop/dpop_proof_builder.dart';
import 'package:spring_boot_starter_oauth2_client/src/endpoint/access_token_response.dart';
import 'package:spring_boot_starter_oauth2_client/src/endpoint/authorization_request.dart';
import 'package:spring_boot_starter_oauth2_client/src/endpoint/jwt_client_secret.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.security.oauth2.client.endpoint');

/// What every request to the token endpoint has: the registration (the
/// client and the provider) and the grant.
///
/// Spring (Java): `AbstractOAuth2AuthorizationGrantRequest`.
abstract class AbstractOAuth2AuthorizationGrantRequest {
  /// A request of [grantType] for [clientRegistration].
  AbstractOAuth2AuthorizationGrantRequest(
    this.grantType,
    this.clientRegistration,
  );

  /// The grant.
  final AuthorizationGrantType grantType;

  /// The client and its provider.
  final ClientRegistration clientRegistration;
}

/// The exchange of an authorization code for tokens, after the login.
///
/// Spring (Java): `OAuth2AuthorizationCodeGrantRequest`.
class OAuth2AuthorizationCodeGrantRequest
    extends AbstractOAuth2AuthorizationGrantRequest {
  /// The exchange of the code in [authorizationExchange] for
  /// [clientRegistration].
  OAuth2AuthorizationCodeGrantRequest(
    ClientRegistration clientRegistration,
    this.authorizationExchange,
  ) : super(AuthorizationGrantType.authorizationCode, clientRegistration);

  /// The request sent (its redirect URI and code verifier) and the
  /// response received (its code).
  final OAuth2AuthorizationExchange authorizationExchange;
}

/// New tokens for a refresh token, before the access token expires.
///
/// Spring (Java): `OAuth2RefreshTokenGrantRequest`.
class OAuth2RefreshTokenGrantRequest
    extends AbstractOAuth2AuthorizationGrantRequest {
  /// A refresh of [accessToken] with [refreshToken], optionally narrowed
  /// to [scopes].
  OAuth2RefreshTokenGrantRequest(
    ClientRegistration clientRegistration,
    this.accessToken,
    this.refreshToken, {
    Set<String> scopes = const {},
  }) : scopes = Set.unmodifiable(scopes),
       super(AuthorizationGrantType.refreshToken, clientRegistration);

  /// The access token being replaced.
  final OAuth2AccessToken accessToken;

  /// The refresh token sent.
  final OAuth2RefreshToken refreshToken;

  /// The scopes asked for; empty for those of the old token.
  final Set<String> scopes;
}

/// A token for the client itself, no user involved (server to server).
///
/// Spring (Java): `OAuth2ClientCredentialsGrantRequest`.
class OAuth2ClientCredentialsGrantRequest
    extends AbstractOAuth2AuthorizationGrantRequest {
  /// A client credentials request of [clientRegistration].
  OAuth2ClientCredentialsGrantRequest(ClientRegistration clientRegistration)
    : super(AuthorizationGrantType.clientCredentials, clientRegistration);
}

/// Calls the provider's token endpoint for one kind of grant and reads
/// the answer.
///
/// The login uses the `authorization_code` client, the authorized client
/// manager the `refresh_token` and `client_credentials` ones. Declare a
/// bean of the same type to talk to a provider that wants something
/// special (an extra parameter, a signed client assertion).
///
/// ```dart
/// // An extra `audience` parameter that Auth0 needs.
/// @Bean()
/// OAuth2AccessTokenResponseClient<OAuth2ClientCredentialsGrantRequest>
/// clientCredentials(HttpTransport transport) =>
///     DefaultClientCredentialsTokenResponseClient(
///       transport,
///       parameters: (request) => {'audience': 'https://api.example.com'},
///     );
/// ```
///
/// Spring (Java): `OAuth2AccessTokenResponseClient`.
abstract interface class OAuth2AccessTokenResponseClient<
  T extends AbstractOAuth2AuthorizationGrantRequest
> {
  /// The provider's answer to [grantRequest].
  ///
  /// Throws an [OAuth2AuthorizationException]: with the provider's error
  /// (`invalid_grant`, ...) when it refused, `invalid_token_response`
  /// when the answer could not be read or the provider not reached.
  Future<OAuth2AccessTokenResponse> getTokenResponse(T grantRequest);
}

/// The base of the token response clients: the form, the client
/// authentication, the DPoP proof and the answer, on the [HttpTransport].
///
/// The client authenticates as its registration says:
/// `client_secret_basic` puts `client_id:client_secret` in HTTP Basic,
/// each form-urlencoded first (RFC 6749 §2.3.1, as Spring does);
/// `client_secret_post` puts both in the form; `none` puts only the
/// `client_id` in the form. Other methods fail. The secret is the
/// registration's, or what the [clientSecretResolver] answers for it
/// (Sign in with Apple's JWT, [JwtClientSecret]).
///
/// With a [dPoPKey] and a registration that uses DPoP
/// ([ClientRegistration.usesDPoP]), and for the refresh of a DPoP token,
/// each request carries a `DPoP` proof for `POST` to the token endpoint
/// (RFC 9449 §5). When the provider answers `use_dpop_nonce` with a
/// `DPoP-Nonce` header, the request is sent once more with that nonce;
/// the last nonce of each provider goes into the next proof. The provider
/// may still issue a `Bearer` token (RFC 9449 §5 allows it): it is kept as
/// such. A `DPoP` token without a proof sent is refused
/// (`invalid_token_response`): it could not be used.
abstract class AbstractTokenResponseClient<
  T extends AbstractOAuth2AuthorizationGrantRequest
>
    implements OAuth2AccessTokenResponseClient<T> {
  /// A client sending its requests through [transport]; `parameters`
  /// adds form parameters to each request (it cannot replace the
  /// standard ones), `clock` gives the current time, [dPoPKey] signs the
  /// DPoP proofs (none without it), [clientSecretResolver] gives secrets
  /// that are not fixed.
  AbstractTokenResponseClient(
    this.transport, {
    this._parameters,
    DateTime Function()? clock,
    this.dPoPKey,
    this.clientSecretResolver,
  }) : _clock = clock ?? DateTime.now;

  /// The HTTP transport.
  final HttpTransport transport;

  /// The key of the DPoP proofs, or `null` for `Bearer` tokens only.
  final DPoPKey? dPoPKey;

  /// Gives the client secret of a registration when it is not its fixed
  /// one, or `null` for the fixed secrets only.
  final OAuth2ClientSecretResolver? clientSecretResolver;

  final Map<String, String> Function(T request)? _parameters;
  final DateTime Function() _clock;
  final DPoPNonces _nonces = DPoPNonces();

  /// The grant's own form parameters (`grant_type` and the rest).
  Map<String, String> grantParameters(T request);

  /// The scopes the token is for when the answer names none.
  Set<String> requestedScopes(T request);

  @override
  Future<OAuth2AccessTokenResponse> getTokenResponse(T grantRequest) async {
    final registration = grantRequest.clientRegistration;
    final tokenUri = registration.providerDetails.tokenUri;
    if (tokenUri == null || tokenUri.isEmpty) {
      throw OAuth2AuthorizationException(
        OAuth2Error(
          OAuth2ErrorCodes.invalidRequest,
          'The registration ${registration.registrationId} has no token URI',
        ),
      );
    }
    final url = Uri.parse(tokenUri);
    final key = dPoPKey;
    final proofs = key != null && _dPoP(grantRequest, key)
        ? DPoPProofBuilder(key, clock: _clock)
        : null;
    final form = <String, String>{
      ...?_parameters?.call(grantRequest),
      ...grantParameters(grantRequest),
    };
    final secret = await _clientSecret(registration);
    Future<HttpResponse> send(String? nonce) async {
      final headers = HttpHeaders({
        HttpHeaders.acceptHeader: '${MediaType.applicationJson};charset=UTF-8',
        HttpHeaders.contentTypeHeader:
            '${MediaType.applicationFormUrlencoded};charset=UTF-8',
      });
      final body = {
        ...form,
        ...clientAuthentication(registration, headers, clientSecret: secret),
      };
      if (proofs != null) {
        headers.set(
          dPoPHeader,
          await proofs.build(method: 'POST', url: url, nonce: nonce),
        );
      }
      _log.debug(
        () =>
            'Sending the ${logText(form['grant_type'])} token request of '
            'registration ${logText(registration.registrationId)} to '
            '${logEndpoint(url)}',
      );
      final response = await transport.send(
        HttpRequest(
          method: HttpMethod.post,
          url: url,
          headers: headers,
          body: utf8.encode(formUrlEncodeAll(body)),
          // Credentials and codes never follow a redirect elsewhere.
          followRedirects: false,
        ),
      );
      _log.debug(
        () =>
            'The token endpoint ${logEndpoint(url)} answered '
            '${response.statusCode.value}',
      );
      return response;
    }

    HttpResponse response;
    try {
      response = await send(_nonces.of(url));
      if (proofs != null) {
        // The nonce of this answer, never an older one: asked again, the
        // request goes once more, not in a loop.
        final nonce = _nonces.remember(url, response.headers);
        if (nonce != null && tokenEndpointWantsNonce(response)) {
          _log.debug(
            "The token endpoint of registration '"
            "${registration.registrationId}' asked for a DPoP nonce; sending "
            'the request again with it',
          );
          response = await send(nonce);
          _nonces.remember(url, response.headers);
        }
      }
    } on HttpTransportException catch (e) {
      throw OAuth2AuthorizationException(
        OAuth2Error(
          OAuth2ErrorCodes.invalidTokenResponse,
          'An error occurred while attempting to retrieve the OAuth 2.0 '
          'Access Token Response: ${e.message}',
        ),
        null,
        e,
      );
    }
    final tokens = OAuth2AccessTokenResponse.fromHttpResponse(
      response,
      requestedScopes: requestedScopes(grantRequest),
      now: _clock(),
    );
    if (proofs == null && tokens.accessToken.tokenType == TokenType.dpop) {
      throw OAuth2AuthorizationException(
        const OAuth2Error(
          OAuth2ErrorCodes.invalidTokenResponse,
          'An error occurred while attempting to retrieve the OAuth 2.0 '
          'Access Token Response: a DPoP token was issued although no DPoP '
          'proof was sent',
        ),
      );
    }
    return tokens;
  }

  // The resolver's secret for the methods that send one. A resolver that
  // has a secret for a registration sending none is a configuration
  // mistake: refused, never silently sent without it.
  Future<String?> _clientSecret(ClientRegistration registration) async {
    final resolver = clientSecretResolver;
    if (resolver == null) {
      return null;
    }
    final method = registration.clientAuthenticationMethod;
    if (method == ClientAuthenticationMethod.clientSecretBasic ||
        method == ClientAuthenticationMethod.clientSecretPost) {
      return await resolver.resolve(registration);
    }
    if (resolver is JwtClientSecretResolver &&
        resolver.handles(registration.registrationId)) {
      throw OAuth2AuthorizationException(
        OAuth2Error(
          OAuth2ErrorCodes.invalidClient,
          'Client [${registration.registrationId}] has a client secret JWT '
          'but uses [$method]: set its client-authentication-method to '
          'client_secret_post (or client_secret_basic)',
        ),
      );
    }
    return null;
  }

  // DPoP when the registration uses it, and always to refresh a DPoP
  // token: its refresh token is bound to the key too (RFC 9449 §5).
  bool _dPoP(T request, DPoPKey key) =>
      request.clientRegistration.usesDPoP(key) ||
      (request is OAuth2RefreshTokenGrantRequest &&
          request.accessToken.tokenType == TokenType.dpop);
}

/// Puts the client authentication of [registration] into [headers] (HTTP
/// Basic) or returns it as form parameters; [clientSecret] replaces the
/// registration's secret when given.
///
/// Throws an [OAuth2AuthorizationException] for a method other than
/// `client_secret_basic`, `client_secret_post` and `none`.
Map<String, String> clientAuthentication(
  ClientRegistration registration,
  HttpHeaders headers, {
  String? clientSecret,
}) {
  final method = registration.clientAuthenticationMethod;
  final secret = clientSecret ?? registration.clientSecret;
  if (method == ClientAuthenticationMethod.clientSecretBasic) {
    final credentials =
        '${formUrlEncode(registration.clientId)}:'
        '${formUrlEncode(secret)}';
    headers.set(
      HttpHeaders.authorizationHeader,
      'Basic ${base64Encode(utf8.encode(credentials))}',
    );
    return const {};
  }
  if (method == ClientAuthenticationMethod.clientSecretPost) {
    return {
      OAuth2ParameterNames.clientId: registration.clientId,
      OAuth2ParameterNames.clientSecret: secret,
    };
  }
  if (method == ClientAuthenticationMethod.none) {
    return {OAuth2ParameterNames.clientId: registration.clientId};
  }
  throw OAuth2AuthorizationException(
    OAuth2Error(
      OAuth2ErrorCodes.invalidClient,
      'This class supports client_secret_basic, client_secret_post and '
      'none by default. Client [${registration.registrationId}] is using '
      '[$method] instead.',
    ),
  );
}

/// Exchanges an authorization code for tokens: `grant_type=
/// authorization_code`, the `code`, the `redirect_uri` the authorization
/// request actually used (none when it had none, as a code of Sign in
/// with Apple's sheet), and the PKCE `code_verifier`.
///
/// Spring (Java): `RestClientAuthorizationCodeTokenResponseClient`
/// (`DefaultAuthorizationCodeTokenResponseClient` before Spring Security
/// 6.4), on the `HttpTransport` instead of a `RestClient`.
class DefaultAuthorizationCodeTokenResponseClient
    extends AbstractTokenResponseClient<OAuth2AuthorizationCodeGrantRequest> {
  /// A client sending through [transport].
  DefaultAuthorizationCodeTokenResponseClient(
    super.transport, {
    super.parameters,
    super.clock,
    super.dPoPKey,
    super.clientSecretResolver,
  });

  @override
  Map<String, String> grantParameters(
    OAuth2AuthorizationCodeGrantRequest request,
  ) {
    final exchange = request.authorizationExchange;
    final code = exchange.authorizationResponse.code;
    if (code == null || code.isEmpty) {
      throw OAuth2AuthorizationException(
        const OAuth2Error(
          OAuth2ErrorCodes.invalidRequest,
          'The authorization response has no code',
        ),
      );
    }
    final redirectUri = exchange.authorizationRequest.redirectUri;
    return {
      OAuth2ParameterNames.grantType: request.grantType.value,
      OAuth2ParameterNames.code: code,
      // RFC 6749 §4.1.3: required when the authorization request had one;
      // a code of Sign in with Apple's sheet was issued without.
      if (redirectUri.isNotEmpty) OAuth2ParameterNames.redirectUri: redirectUri,
      PkceParameterNames.codeVerifier:
          ?exchange.authorizationRequest.codeVerifier,
    };
  }

  @override
  Set<String> requestedScopes(OAuth2AuthorizationCodeGrantRequest request) =>
      request.authorizationExchange.authorizationRequest.scopes;
}

/// Gets new tokens with a refresh token: `grant_type=refresh_token`, the
/// `refresh_token`, and the `scope` when narrowed. When the provider
/// issues no new refresh token, the old one is kept in the answer.
///
/// Spring (Java): `RestClientRefreshTokenTokenResponseClient`
/// (`DefaultRefreshTokenTokenResponseClient` before Spring Security 6.4).
class DefaultRefreshTokenTokenResponseClient
    extends AbstractTokenResponseClient<OAuth2RefreshTokenGrantRequest> {
  /// A client sending through [transport].
  DefaultRefreshTokenTokenResponseClient(
    super.transport, {
    super.parameters,
    super.clock,
    super.dPoPKey,
    super.clientSecretResolver,
  });

  @override
  Map<String, String> grantParameters(OAuth2RefreshTokenGrantRequest request) =>
      {
        OAuth2ParameterNames.grantType: request.grantType.value,
        OAuth2ParameterNames.refreshToken: request.refreshToken.tokenValue,
        if (request.scopes.isNotEmpty)
          OAuth2ParameterNames.scope: request.scopes.join(' '),
      };

  @override
  Set<String> requestedScopes(OAuth2RefreshTokenGrantRequest request) =>
      request.scopes.isNotEmpty ? request.scopes : request.accessToken.scopes;

  @override
  Future<OAuth2AccessTokenResponse> getTokenResponse(
    OAuth2RefreshTokenGrantRequest grantRequest,
  ) async {
    final response = await super.getTokenResponse(grantRequest);
    return response.refreshToken == null
        ? response.withRefreshToken(grantRequest.refreshToken)
        : response;
  }
}

/// Gets a token for the client itself: `grant_type=client_credentials`
/// and the registration's `scope`.
///
/// Spring (Java): `RestClientClientCredentialsTokenResponseClient`
/// (`DefaultClientCredentialsTokenResponseClient` before Spring Security
/// 6.4).
class DefaultClientCredentialsTokenResponseClient
    extends AbstractTokenResponseClient<OAuth2ClientCredentialsGrantRequest> {
  /// A client sending through [transport].
  DefaultClientCredentialsTokenResponseClient(
    super.transport, {
    super.parameters,
    super.clock,
    super.dPoPKey,
    super.clientSecretResolver,
  });

  @override
  Map<String, String> grantParameters(
    OAuth2ClientCredentialsGrantRequest request,
  ) => {
    OAuth2ParameterNames.grantType: request.grantType.value,
    if (request.clientRegistration.scopes.isNotEmpty)
      OAuth2ParameterNames.scope: request.clientRegistration.scopes.join(' '),
  };

  @override
  Set<String> requestedScopes(OAuth2ClientCredentialsGrantRequest request) =>
      request.clientRegistration.scopes;
}
