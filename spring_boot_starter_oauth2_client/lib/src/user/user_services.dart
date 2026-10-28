import 'dart:convert';

import 'package:spring_boot_starter_oauth2_client/src/core/oauth2_error.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/parameter_names.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/tokens.dart';
import 'package:spring_boot_starter_oauth2_client/src/oidc/oidc_id_token.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration.dart';
import 'package:spring_boot_starter_oauth2_client/src/user/oauth2_user.dart';
import 'package:spring_security_core/spring_security_core.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// The largest user-info answer read (1 MiB).
const int _maxUserInfoBytes = 1 << 20;

/// What a user service gets to load a user: the registration and the
/// access token of the login.
///
/// Spring (Java): `OAuth2UserRequest`.
class OAuth2UserRequest {
  /// A request for the user of [accessToken] at [clientRegistration];
  /// [additionalParameters] are the other parameters of the token
  /// response.
  OAuth2UserRequest(
    this.clientRegistration,
    this.accessToken, {
    Map<String, Object?> additionalParameters = const {},
  }) : additionalParameters = Map.unmodifiable(additionalParameters);

  /// The registration of the login.
  final ClientRegistration clientRegistration;

  /// The access token of the login, sent to the user-info endpoint.
  final OAuth2AccessToken accessToken;

  /// The other parameters of the token response.
  final Map<String, Object?> additionalParameters;
}

/// What the OIDC user service gets: an [OAuth2UserRequest] with the
/// checked ID token.
///
/// Spring (Java): `OidcUserRequest`.
class OidcUserRequest extends OAuth2UserRequest {
  /// A request for the user of [idToken].
  OidcUserRequest(
    super.clientRegistration,
    super.accessToken,
    this.idToken, {
    super.additionalParameters,
  });

  /// The ID token of the login, already checked.
  final OidcIdToken idToken;
}

/// Loads the user of a login: what the provider says about them and the
/// authorities they start with.
///
/// The login calls the OAuth 2.0 one ([DefaultOAuth2UserService]) or the
/// OpenID Connect one ([OidcUserService]). Declare your own bean of the
/// same type to load users differently, for example to add the roles of
/// your own database:
///
/// ```dart
/// @Bean()
/// OAuth2UserService<OidcUserRequest, OidcUser> oidcUserService(Roles roles) {
///   final delegate = OidcUserService(transport);
///   return OAuth2UserService.from((request) async {
///     final user = await delegate.loadUser(request);
///     return DefaultOidcUser(
///       [...user.authorities, ...await roles.of(user.subject!)],
///       user.idToken,
///       userInfo: user.userInfo,
///     );
///   });
/// }
/// ```
///
/// Spring (Java): `OAuth2UserService<R, U>`.
abstract interface class OAuth2UserService<
  R extends OAuth2UserRequest,
  U extends OAuth2User
> {
  /// A service calling [load].
  factory OAuth2UserService.from(Future<U> Function(R request) load) =
      _FunctionUserService<R, U>;

  /// The user of [userRequest].
  ///
  /// Throws an [OAuth2AuthenticationException] when the user cannot be
  /// loaded.
  Future<U> loadUser(R userRequest);
}

final class _FunctionUserService<
  R extends OAuth2UserRequest,
  U extends OAuth2User
>
    implements OAuth2UserService<R, U> {
  _FunctionUserService(this._load);

  final Future<U> Function(R request) _load;

  @override
  Future<U> loadUser(R userRequest) => _load(userRequest);
}

/// Loads an OAuth 2.0 user from the provider's user-info endpoint (GitHub's
/// `/user`, Facebook's `/me`).
///
/// The access token goes in the `Authorization` header (or the form, as
/// the registration says); the JSON answer becomes the user's attributes,
/// and the registration's user name attribute names the user. The user
/// gets `OAUTH2_USER` and `SCOPE_<scope>` for each scope of the token.
///
/// Spring (Java): `DefaultOAuth2UserService`.
class DefaultOAuth2UserService
    implements OAuth2UserService<OAuth2UserRequest, OAuth2User> {
  /// A service calling the endpoint through [transport].
  DefaultOAuth2UserService(this.transport);

  /// The HTTP transport.
  final HttpTransport transport;

  @override
  Future<OAuth2User> loadUser(OAuth2UserRequest userRequest) async {
    final registration = userRequest.clientRegistration;
    final endpoint = registration.providerDetails.userInfoEndpoint;
    final nameAttribute = endpoint.userNameAttributeName;
    if (endpoint.uri == null || endpoint.uri!.isEmpty) {
      throw OAuth2AuthenticationException(
        OAuth2Error(
          OAuth2ErrorCodes.missingUserInfoUri,
          'Missing required UserInfo Uri in UserInfoEndpoint for Client '
          'Registration: ${registration.registrationId}',
        ),
      );
    }
    if (nameAttribute == null || nameAttribute.isEmpty) {
      throw OAuth2AuthenticationException(
        OAuth2Error(
          OAuth2ErrorCodes.missingUserNameAttribute,
          'Missing required "user name" attribute name in UserInfoEndpoint '
          'for Client Registration: ${registration.registrationId}',
        ),
      );
    }
    final attributes = await loadUserAttributes(transport, userRequest);
    final authorities = <GrantedAuthority>[
      OAuth2UserAuthority(
        attributes,
        userNameAttributeName: nameAttribute,
      ),
      for (final scope in userRequest.accessToken.scopes)
        SimpleGrantedAuthority('SCOPE_$scope'),
    ];
    try {
      return DefaultOAuth2User(authorities, attributes, nameAttribute);
    } on ArgumentError catch (e) {
      throw OAuth2AuthenticationException(
        OAuth2Error(
          OAuth2ErrorCodes.invalidUserInfoResponse,
          'An error occurred while attempting to retrieve the UserInfo '
          'Resource: ${e.message}',
        ),
      );
    }
  }
}

/// The attributes the user-info endpoint of [userRequest] returns.
///
/// Throws an [OAuth2AuthenticationException] (`invalid_user_info_response`)
/// when the endpoint fails or answers with something other than a JSON
/// object.
Future<Map<String, Object?>> loadUserAttributes(
  HttpTransport transport,
  OAuth2UserRequest userRequest,
) async {
  final registration = userRequest.clientRegistration;
  final endpoint = registration.providerDetails.userInfoEndpoint;
  final uri = Uri.parse(endpoint.uri!);
  final token = userRequest.accessToken.tokenValue;
  Never fail(String details) => throw OAuth2AuthenticationException(
    OAuth2Error(
      OAuth2ErrorCodes.invalidUserInfoResponse,
      'An error occurred while attempting to retrieve the UserInfo '
      'Resource: $details',
    ),
  );
  final headers = HttpHeaders({
    HttpHeaders.acceptHeader: MediaType.applicationJson,
  });
  final HttpRequest request;
  if (endpoint.authenticationMethod == AuthenticationMethod.form) {
    headers.set(
      HttpHeaders.contentTypeHeader,
      '${MediaType.applicationFormUrlencoded};charset=UTF-8',
    );
    request = HttpRequest(
      method: HttpMethod.post,
      url: uri,
      headers: headers,
      body: utf8.encode(
        formUrlEncodeAll({OAuth2ParameterNames.accessToken: token}),
      ),
      followRedirects: false,
    );
  } else if (endpoint.authenticationMethod == AuthenticationMethod.query) {
    request = HttpRequest(
      method: HttpMethod.get,
      url: uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          OAuth2ParameterNames.accessToken: token,
        },
      ),
      headers: headers,
      followRedirects: false,
    );
  } else {
    headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request = HttpRequest(
      method: HttpMethod.get,
      url: uri,
      headers: headers,
      followRedirects: false,
    );
  }
  final HttpResponse response;
  try {
    response = await transport.send(request);
  } on HttpTransportException catch (e) {
    fail(e.message);
  }
  if (!response.isSuccess) {
    final challenge = response.headers[HttpHeaders.wwwAuthenticateHeader];
    final code = challenge == null
        ? null
        : RegExp('error="([^"]*)"').firstMatch(challenge)?[1];
    fail(
      'Error details: [UserInfo Uri: ${endpoint.uri}, Status: '
      '${response.statusCode}${code == null ? '' : ', Error Code: $code'}]',
    );
  }
  if (response.bodyBytes.length > _maxUserInfoBytes) {
    fail('the response is too large');
  }
  Object? json;
  try {
    json = jsonDecode(utf8.decode(response.bodyBytes));
  } on FormatException {
    fail('the response is not JSON');
  }
  if (json is! Map<String, Object?> || json.isEmpty) {
    fail('the response is not a JSON object');
  }
  return json;
}

/// Loads an OpenID Connect user: the ID token's claims, plus the user
/// info when the provider has the endpoint.
///
/// The user info is asked for when the registration has a user-info URI
/// and the access token has one of the scopes [accessibleScopes]
/// (`profile`, `email`, `address`, `phone`). Its `sub` must be the ID
/// token's: an answer about someone else fails the login
/// (`invalid_user_info_response`). The user gets `OIDC_USER` and
/// `SCOPE_<scope>` for each scope of the token, and is named by the
/// registration's user name attribute (`sub` when not set).
///
/// Spring (Java): `OidcUserService`.
class OidcUserService implements OAuth2UserService<OidcUserRequest, OidcUser> {
  /// A service calling the user-info endpoint through [transport].
  OidcUserService(
    this.transport, {
    this.accessibleScopes = const {'profile', 'email', 'address', 'phone'},
  });

  /// The HTTP transport.
  final HttpTransport transport;

  /// The scopes that allow reading the user info; with none, it is always
  /// read when the endpoint exists.
  final Set<String> accessibleScopes;

  @override
  Future<OidcUser> loadUser(OidcUserRequest userRequest) async {
    OidcUserInfo? userInfo;
    if (_shouldRetrieveUserInfo(userRequest)) {
      final claims = await loadUserAttributes(transport, userRequest);
      final subject = claims['sub'];
      if (subject is! String || subject.isEmpty) {
        throw OAuth2AuthenticationException(
          const OAuth2Error(
            OAuth2ErrorCodes.invalidUserInfoResponse,
            'The UserInfo Response has no sub',
          ),
        );
      }
      if (subject != userRequest.idToken.subject) {
        throw OAuth2AuthenticationException(
          const OAuth2Error(
            OAuth2ErrorCodes.invalidUserInfoResponse,
            'The sub of the UserInfo Response does not match the ID Token',
          ),
        );
      }
      userInfo = OidcUserInfo(claims);
    }
    final nameAttribute = userRequest
        .clientRegistration
        .providerDetails
        .userInfoEndpoint
        .userNameAttributeName;
    final authorities = <GrantedAuthority>[
      OidcUserAuthority(
        userRequest.idToken,
        userInfo: userInfo,
        userNameAttributeName: nameAttribute,
      ),
      for (final scope in userRequest.accessToken.scopes)
        SimpleGrantedAuthority('SCOPE_$scope'),
    ];
    try {
      return DefaultOidcUser(
        authorities,
        userRequest.idToken,
        userInfo: userInfo,
        nameAttributeKey: nameAttribute == null || nameAttribute.isEmpty
            ? 'sub'
            : nameAttribute,
      );
    } on ArgumentError catch (e) {
      throw OAuth2AuthenticationException(
        OAuth2Error(
          OAuth2ErrorCodes.invalidUserInfoResponse,
          'The user cannot be named: ${e.message}',
        ),
      );
    }
  }

  bool _shouldRetrieveUserInfo(OidcUserRequest request) {
    final registration = request.clientRegistration;
    final uri = registration.providerDetails.userInfoEndpoint.uri;
    if (uri == null || uri.isEmpty) {
      return false;
    }
    if (registration.authorizationGrantType !=
        AuthorizationGrantType.authorizationCode) {
      return false;
    }
    return accessibleScopes.isEmpty ||
        request.accessToken.scopes.any(accessibleScopes.contains);
  }
}
