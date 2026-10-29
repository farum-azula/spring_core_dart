import 'dart:convert';

import 'package:spring_boot_starter_oauth2_client/src/core/oauth2_error.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/parameter_names.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/tokens.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// The largest token response read (1 MiB).
const int _maxResponseBytes = 1 << 20;

/// What the provider's token endpoint answered: the access token, maybe a
/// refresh token, and the other parameters (the OpenID Connect
/// `id_token` among them).
///
/// The token response clients return it; the login and the authorized
/// client manager turn it into an authorized client. [toString] shows no
/// token.
///
/// ```dart
/// final response = await tokenClient.getTokenResponse(grantRequest);
/// final idToken = response.additionalParameters['id_token'] as String?;
/// ```
///
/// Spring (Java): `OAuth2AccessTokenResponse`.
final class OAuth2AccessTokenResponse {
  /// A response with [accessToken], an optional [refreshToken] and the
  /// [additionalParameters].
  OAuth2AccessTokenResponse({
    required this.accessToken,
    this.refreshToken,
    Map<String, Object?> additionalParameters = const {},
  }) : additionalParameters = Map.unmodifiable(additionalParameters);

  /// Reads a successful token response (RFC 6749 §5.1) of [json],
  /// received at [now] (the current time by default).
  ///
  /// `access_token` and `token_type` (`Bearer` or `DPoP`, any case, as
  /// Spring Security 6.5 reads them) are required; the token's
  /// [OAuth2AccessToken.tokenType] is [TokenType.bearer] or
  /// [TokenType.dpop].
  /// `expires_in` (a number, or a number in a string) sets the expiry;
  /// without it the token counts as expiring a second after it was issued,
  /// as in Spring. Without `scope`, [requestedScopes] are the token's
  /// (RFC 6749 §5.1: the scope is as requested). Everything else, such
  /// as `id_token`, goes to [additionalParameters].
  ///
  /// Throws an [OAuth2AuthorizationException] (`invalid_token_response`)
  /// for anything else.
  factory OAuth2AccessTokenResponse.fromJson(
    Map<String, Object?> json, {
    Set<String> requestedScopes = const {},
    DateTime? now,
  }) {
    Never invalid(String why) => throw OAuth2AuthorizationException(
      OAuth2Error(
        OAuth2ErrorCodes.invalidTokenResponse,
        'An error occurred while attempting to retrieve the OAuth 2.0 '
        'Access Token Response: $why',
      ),
    );
    final value = json[OAuth2ParameterNames.accessToken];
    if (value is! String || value.isEmpty) {
      invalid('no access_token');
    }
    final type = switch (json[OAuth2ParameterNames.tokenType]) {
      final String name when name.toLowerCase() == 'bearer' => TokenType.bearer,
      final String name when name.toLowerCase() == 'dpop' => TokenType.dpop,
      _ => invalid('token_type must be Bearer or DPoP'),
    };
    final expiresIn = switch (json[OAuth2ParameterNames.expiresIn]) {
      null => 0,
      final int seconds => seconds,
      final num seconds => seconds.toInt(),
      final String text => int.tryParse(text) ?? invalid('bad expires_in'),
      _ => invalid('bad expires_in'),
    };
    final scope = switch (json[OAuth2ParameterNames.scope]) {
      null => null,
      final String text => text,
      _ => invalid('bad scope'),
    };
    final refresh = switch (json[OAuth2ParameterNames.refreshToken]) {
      null => null,
      final String text when text.isNotEmpty => text,
      _ => invalid('bad refresh_token'),
    };
    final issuedAt = (now ?? DateTime.now()).toUtc();
    final expiresAt = issuedAt.add(
      Duration(seconds: expiresIn > 0 ? expiresIn : 1),
    );
    final scopes = scope == null
        ? requestedScopes
        : {
            for (final part in scope.split(' '))
              if (part.isNotEmpty) part,
          };
    return OAuth2AccessTokenResponse(
      accessToken: OAuth2AccessToken(
        type,
        value,
        issuedAt: issuedAt,
        expiresAt: expiresAt,
        scopes: scopes,
      ),
      refreshToken: refresh == null
          ? null
          : OAuth2RefreshToken(refresh, issuedAt: issuedAt),
      additionalParameters: {
        for (final MapEntry(:key, :value) in json.entries)
          if (!const {
            OAuth2ParameterNames.accessToken,
            OAuth2ParameterNames.tokenType,
            OAuth2ParameterNames.expiresIn,
            OAuth2ParameterNames.refreshToken,
            OAuth2ParameterNames.scope,
          }.contains(key))
            key: value,
      },
    );
  }

  /// Reads the token endpoint's HTTP [response], received at [now].
  ///
  /// A 2xx answer is read with [OAuth2AccessTokenResponse.fromJson]. An
  /// error answer (RFC 6749 §5.2: `{"error": "invalid_grant", ...}`)
  /// throws an [OAuth2AuthorizationException] with that error; any other
  /// answer one with `invalid_token_response`. The body is never put in
  /// a message (it may hold tokens).
  factory OAuth2AccessTokenResponse.fromHttpResponse(
    HttpResponse response, {
    Set<String> requestedScopes = const {},
    DateTime? now,
  }) {
    final status = response.statusCode;
    Never invalid(String why) => throw OAuth2AuthorizationException(
      OAuth2Error(
        OAuth2ErrorCodes.invalidTokenResponse,
        'An error occurred while attempting to retrieve the OAuth 2.0 '
        'Access Token Response: $why',
      ),
    );
    if (response.bodyBytes.length > _maxResponseBytes) {
      invalid('the response is too large (HTTP $status)');
    }
    Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      json = null;
    }
    if (!response.isSuccess) {
      if (oauth2ErrorOf(json) case final error?) {
        throw OAuth2AuthorizationException(
          error,
          'The token endpoint answered HTTP $status: $error',
        );
      }
      invalid('HTTP $status');
    }
    if (json is! Map<String, Object?>) {
      invalid('the response is not a JSON object (HTTP $status)');
    }
    return OAuth2AccessTokenResponse.fromJson(
      json,
      requestedScopes: requestedScopes,
      now: now,
    );
  }

  /// The access token.
  final OAuth2AccessToken accessToken;

  /// The refresh token, or `null` when none was issued.
  final OAuth2RefreshToken? refreshToken;

  /// The other parameters, such as `id_token`; cannot be modified.
  final Map<String, Object?> additionalParameters;

  /// A copy with [refreshToken] instead (the refresh grant keeps the old
  /// refresh token when the provider issues no new one).
  OAuth2AccessTokenResponse withRefreshToken(
    OAuth2RefreshToken? refreshToken,
  ) => OAuth2AccessTokenResponse(
    accessToken: accessToken,
    refreshToken: refreshToken,
    additionalParameters: additionalParameters,
  );

  @override
  String toString() =>
      'OAuth2AccessTokenResponse [accessToken=[PROTECTED], '
      'tokenType=${accessToken.tokenType}, expiresAt=${accessToken.expiresAt}, '
      'refreshToken=${refreshToken == null ? 'none' : '[PROTECTED]'}]';
}

/// The OAuth 2.0 error of an error body (`{"error": "...",
/// "error_description": "...", "error_uri": "..."}`), or `null` when
/// [json] is not one.
OAuth2Error? oauth2ErrorOf(Object? json) {
  if (json is! Map<String, Object?>) {
    return null;
  }
  final code = json[OAuth2ParameterNames.error];
  if (code is! String || code.isEmpty) {
    return null;
  }
  final description = json[OAuth2ParameterNames.errorDescription];
  final uri = json[OAuth2ParameterNames.errorUri];
  return OAuth2Error(
    code,
    description is String ? description : null,
    uri is String ? uri : null,
  );
}
