import 'package:spring_boot_starter_oauth2_client/src/core/parameter_names.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/sha256.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration.dart';

/// Fills in the redirect URI template of [registration]: the URI the
/// provider sends the browser back to after the login.
///
/// The templates are Spring's: `{registrationId}`, `{action}` (`login` by
/// default), and the parts of [baseUrl] (the application's own address):
/// `{baseUrl}`, `{baseScheme}`, `{baseHost}`, `{basePort}` (`:8080`, or
/// empty) and `{basePath}`. A server passes the address of the request;
/// an app has none and keeps the default `http://127.0.0.1`, which is
/// right for a loopback redirect (the browser picks the port). An app
/// that registers a scheme of its own sets its redirect URI without
/// templates (`neonbooks:/oauth2/callback`).
///
/// ```dart
/// expandRedirectUri(registration, baseUrl: Uri.parse('https://shop.example.com'));
/// // https://shop.example.com/login/oauth2/code/keycloak
/// ```
///
/// Throws an [ArgumentError] when the registration has no redirect URI.
///
/// Spring (Java): the expansion in `DefaultOAuth2AuthorizationRequestResolver`.
String expandRedirectUri(
  ClientRegistration registration, {
  Uri? baseUrl,
  String action = 'login',
}) {
  final template = registration.redirectUri;
  if (template == null || template.isEmpty) {
    throw ArgumentError(
      'The registration ${registration.registrationId} has no redirect URI',
    );
  }
  final base = baseUrl ?? Uri.parse('http://127.0.0.1');
  var path = base.path;
  if (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path.isNotEmpty && !path.startsWith('/')) {
    path = '/$path';
  }
  final port = base.hasPort ? ':${base.port}' : '';
  final variables = {
    'registrationId': registration.registrationId,
    'baseScheme': base.scheme,
    'baseHost': base.host,
    'basePort': port,
    'basePath': path,
    'baseUrl': '${base.scheme}://${base.host}$port$path',
    'action': action,
  };
  return template.replaceAllMapped(
    RegExp(r'\{([A-Za-z]+)\}'),
    (match) => variables[match[1]] ?? match[0]!,
  );
}

/// The request that sends the user to the provider's login page, and what
/// the client must remember to check the answer.
///
/// The client builds it before the login: the URI of the provider's page
/// with `response_type=code`, the `client_id`, the `redirect_uri`, the
/// `scope`, a random `state` (the answer must bring it back: no forged
/// redirect), a random `nonce` for OpenID Connect (the ID token must
/// carry its hash: no replayed token) and a PKCE `code_challenge` (only
/// the holder of the matching verifier can exchange the code). The
/// verifier and the nonce stay in [attributes], never sent.
///
/// The app login builds and checks it for you; a server's `oauth2Login()`
/// keeps it in the session between the redirect and the callback.
///
/// ```dart
/// final request = OAuth2AuthorizationRequest.forRegistration(
///   registration,
///   redirectUri: 'http://127.0.0.1:49152/callback',
/// );
/// openBrowser(request.authorizationRequestUri);
/// // ...later, the redirect's state must equal request.state.
/// ```
///
/// Spring (Java): `OAuth2AuthorizationRequest`, made by
/// `DefaultOAuth2AuthorizationRequestResolver` with
/// `OAuth2AuthorizationRequestCustomizers.withPkce()`. PKCE is always on
/// here, for confidential clients too (as the OAuth 2.0 Security BCP, RFC
/// 9700, recommends).
final class OAuth2AuthorizationRequest {
  /// A request with every part given;
  /// [OAuth2AuthorizationRequest.forRegistration] builds one with
  /// fresh random values.
  OAuth2AuthorizationRequest({
    required this.authorizationUri,
    required this.clientId,
    required this.redirectUri,
    required this.state,
    this.grantType = AuthorizationGrantType.authorizationCode,
    Set<String> scopes = const {},
    Map<String, String> additionalParameters = const {},
    Map<String, Object?> attributes = const {},
  }) : scopes = Set.unmodifiable(scopes),
       additionalParameters = Map.unmodifiable(additionalParameters),
       attributes = Map.unmodifiable(attributes);

  /// A request for [registration] coming back to [redirectUri] (already
  /// expanded), with a fresh `state` (32 random bytes), a PKCE verifier
  /// (64 bytes) and `S256` challenge, and for the `openid` scope a fresh
  /// `nonce` (32 bytes, its SHA-256 hash sent). [additionalParameters]
  /// go into the URI too (`prompt`, `login_hint`, ...); they cannot
  /// replace the parameters above.
  ///
  /// Throws an [ArgumentError] when the registration is not an
  /// `authorization_code` one.
  factory OAuth2AuthorizationRequest.forRegistration(
    ClientRegistration registration, {
    required String redirectUri,
    Map<String, String> additionalParameters = const {},
  }) {
    if (registration.authorizationGrantType !=
        AuthorizationGrantType.authorizationCode) {
      throw ArgumentError(
        'Invalid Authorization Grant Type '
        '(${registration.authorizationGrantType}) for Client Registration '
        'with Id: ${registration.registrationId}',
      );
    }
    final codeVerifier = generateSecureKey(64);
    final openid = registration.scopes.contains('openid');
    final nonce = openid ? generateSecureKey() : null;
    return OAuth2AuthorizationRequest(
      authorizationUri: registration.providerDetails.authorizationUri!,
      clientId: registration.clientId,
      redirectUri: redirectUri,
      scopes: registration.scopes,
      state: generateSecureKey(),
      additionalParameters: {
        ...additionalParameters,
        PkceParameterNames.codeChallenge: sha256Base64Url(codeVerifier),
        PkceParameterNames.codeChallengeMethod: 'S256',
        if (nonce != null) OidcParameterNames.nonce: sha256Base64Url(nonce),
      },
      attributes: {
        OAuth2ParameterNames.registrationId: registration.registrationId,
        PkceParameterNames.codeVerifier: codeVerifier,
        OidcParameterNames.nonce: ?nonce,
      },
    );
  }

  /// The provider's login page, without the parameters.
  final String authorizationUri;

  /// Always [AuthorizationGrantType.authorizationCode].
  final AuthorizationGrantType grantType;

  /// The client's id.
  final String clientId;

  /// The redirect URI sent; the token request must send the same.
  final String redirectUri;

  /// The scopes asked for.
  final Set<String> scopes;

  /// The random value the redirect must bring back.
  final String state;

  /// More parameters of the URI: the PKCE challenge, the nonce hash and
  /// any given.
  final Map<String, String> additionalParameters;

  /// What the client keeps and never sends: `registration_id`,
  /// `code_verifier` and `nonce` (the raw nonce).
  final Map<String, Object?> attributes;

  /// The registration this request is for, from [attributes].
  String? get registrationId =>
      attributes[OAuth2ParameterNames.registrationId] as String?;

  /// The PKCE code verifier, from [attributes]; sent with the code.
  String? get codeVerifier =>
      attributes[PkceParameterNames.codeVerifier] as String?;

  /// The raw nonce, from [attributes]; the ID token carries its hash.
  String? get nonce => attributes[OidcParameterNames.nonce] as String?;

  /// The full URI of the provider's page: [authorizationUri] with
  /// `response_type`, `client_id`, `scope`, `state`, `redirect_uri` and
  /// [additionalParameters]; a query already in [authorizationUri] (such
  /// as Facebook's) is kept.
  Uri get authorizationRequestUri {
    final base = Uri.parse(authorizationUri);
    final parameters = <String, String>{
      ...base.queryParameters,
      ...additionalParameters,
      OAuth2ParameterNames.responseType: 'code',
      OAuth2ParameterNames.clientId: clientId,
      if (scopes.isNotEmpty) OAuth2ParameterNames.scope: scopes.join(' '),
      OAuth2ParameterNames.state: state,
      OAuth2ParameterNames.redirectUri: redirectUri,
    };
    return base.replace(queryParameters: parameters);
  }

  @override
  String toString() =>
      'OAuth2AuthorizationRequest [authorizationUri=$authorizationUri, '
      'clientId=$clientId, redirectUri=$redirectUri, scopes=$scopes, '
      'state=[PROTECTED]]';
}

/// What the provider sent back on the redirect after the login: a `code`
/// and the `state`, or an `error`.
///
/// Spring (Java): `OAuth2AuthorizationResponse`.
final class OAuth2AuthorizationResponse {
  /// A response to [redirectUri] with its parameters.
  const OAuth2AuthorizationResponse({
    required this.redirectUri,
    this.code,
    this.state,
    this.error,
    this.errorDescription,
    this.errorUri,
    this.issuer,
  });

  /// Reads the parameters of the URI the provider redirected to.
  ///
  /// The parameters are taken from the query (`response_mode=query`, the
  /// default of the code flow). A parameter given twice counts as invalid
  /// (RFC 6749 §3.1): the response then has neither code nor state, and
  /// fails the checks.
  factory OAuth2AuthorizationResponse.fromRedirect(Uri uri) {
    final all = uri.queryParametersAll;
    String? one(String name) => switch (all[name]) {
      [final value] => value,
      _ => null,
    };
    return OAuth2AuthorizationResponse(
      redirectUri: uri.replace(query: '').removeFragment().toString(),
      code: one(OAuth2ParameterNames.code),
      state: one(OAuth2ParameterNames.state),
      error: one(OAuth2ParameterNames.error),
      errorDescription: one(OAuth2ParameterNames.errorDescription),
      errorUri: one(OAuth2ParameterNames.errorUri),
      issuer: one(OAuth2ParameterNames.issuer),
    );
  }

  /// Where the browser was sent, without the query.
  final String redirectUri;

  /// The authorization code; a credential, never log it.
  final String? code;

  /// The `state` sent back.
  final String? state;

  /// The error code, such as `access_denied`.
  final String? error;

  /// The error's description.
  final String? errorDescription;

  /// A link about the error.
  final String? errorUri;

  /// The `iss` parameter (RFC 9207): who sent the response.
  final String? issuer;

  /// Whether the provider answered with an error.
  bool get statusError => error != null && error!.isNotEmpty;

  @override
  String toString() =>
      'OAuth2AuthorizationResponse [redirectUri=$redirectUri, '
      'code=[PROTECTED], error=$error]';
}

/// The request sent and the response received: what the token endpoint
/// needs to exchange the code.
///
/// Spring (Java): `OAuth2AuthorizationExchange`.
final class OAuth2AuthorizationExchange {
  /// The exchange of [authorizationRequest] and [authorizationResponse].
  const OAuth2AuthorizationExchange(
    this.authorizationRequest,
    this.authorizationResponse,
  );

  /// The request the client sent.
  final OAuth2AuthorizationRequest authorizationRequest;

  /// The response the provider sent back.
  final OAuth2AuthorizationResponse authorizationResponse;
}
