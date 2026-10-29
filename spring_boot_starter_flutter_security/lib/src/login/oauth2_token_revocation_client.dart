import 'dart:convert';

import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

/// Revokes tokens at the provider (RFC 7009), so a token stolen after
/// logout is worthless.
///
/// `OAuth2LoginService.logout` calls it for the refresh and the access
/// token when the provider's metadata has a `revocation_endpoint`. The
/// client authenticates as at the token endpoint (`client_secret_basic`,
/// `client_secret_post` or, for an app, `none`: only its `client_id`). A
/// refusal is reported as an [OAuth2AuthorizationException]; the logout
/// goes on anyway.
///
/// ```dart
/// await revocation.revoke(registration, authorizedClient.refreshToken!);
/// ```
///
/// Spring Security has no such client (its servers forget tokens with the
/// session).
class OAuth2TokenRevocationClient {
  /// A client sending through [transport].
  OAuth2TokenRevocationClient(this.transport);

  /// The HTTP transport.
  final HttpTransport transport;

  /// Revokes [token] at the `revocation_endpoint` of [registration]; does
  /// nothing when the provider has none. Returns whether a request was
  /// sent and accepted (HTTP 200).
  ///
  /// Throws an [OAuth2AuthorizationException] when the provider refused
  /// or could not be reached, or the registration's client
  /// authentication method is not one of the three above.
  Future<bool> revoke(
    ClientRegistration registration,
    AbstractOAuth2Token token,
  ) async {
    final endpoint = registration.providerDetails.revocationEndpoint;
    if (endpoint == null) {
      return false;
    }
    final headers = HttpHeaders({
      HttpHeaders.contentTypeHeader:
          '${MediaType.applicationFormUrlencoded};charset=UTF-8',
    });
    final form = {
      OAuth2ParameterNames.token: token.tokenValue,
      OAuth2ParameterNames.tokenTypeHint: token is OAuth2RefreshToken
          ? OAuth2ParameterNames.refreshToken
          : OAuth2ParameterNames.accessToken,
      ..._clientAuthentication(registration, headers),
    };
    final HttpResponse response;
    try {
      response = await transport.send(
        HttpRequest(
          method: HttpMethod.post,
          url: Uri.parse(endpoint),
          headers: headers,
          body: utf8.encode(_formUrlEncode(form)),
          // Credentials never follow a redirect elsewhere.
          followRedirects: false,
        ),
      );
    } on HttpTransportException catch (e) {
      throw OAuth2AuthorizationException(
        OAuth2Error(
          OAuth2ErrorCodes.serverError,
          'The token could not be revoked: ${e.message}',
        ),
        null,
        e,
      );
    }
    if (response.isSuccess) {
      return true;
    }
    Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      json = null;
    }
    throw OAuth2AuthorizationException(
      oauth2ErrorOf(json) ??
          OAuth2Error(
            OAuth2ErrorCodes.serverError,
            'The revocation endpoint answered HTTP ${response.statusCode}',
          ),
    );
  }

  // The client authentication of the token endpoint (RFC 6749 §2.3.1):
  // HTTP Basic in [headers], or form parameters.
  static Map<String, String> _clientAuthentication(
    ClientRegistration registration,
    HttpHeaders headers,
  ) {
    final method = registration.clientAuthenticationMethod;
    if (method == ClientAuthenticationMethod.clientSecretBasic) {
      final credentials =
          '${Uri.encodeQueryComponent(registration.clientId)}:'
          '${Uri.encodeQueryComponent(registration.clientSecret)}';
      headers.set(
        HttpHeaders.authorizationHeader,
        'Basic ${base64Encode(utf8.encode(credentials))}',
      );
      return const {};
    }
    if (method == ClientAuthenticationMethod.clientSecretPost) {
      return {
        OAuth2ParameterNames.clientId: registration.clientId,
        OAuth2ParameterNames.clientSecret: registration.clientSecret,
      };
    }
    if (method == ClientAuthenticationMethod.none) {
      return {OAuth2ParameterNames.clientId: registration.clientId};
    }
    throw OAuth2AuthorizationException(
      OAuth2Error(
        OAuth2ErrorCodes.invalidClient,
        'The revocation supports client_secret_basic, client_secret_post '
        'and none. Client [${registration.registrationId}] is using '
        '[$method] instead.',
      ),
    );
  }

  static String _formUrlEncode(Map<String, String> form) => [
    for (final MapEntry(:key, :value) in form.entries)
      '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}',
  ].join('&');
}
