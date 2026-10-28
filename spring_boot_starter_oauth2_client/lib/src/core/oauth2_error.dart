import 'package:spring_security_core/spring_security_core.dart';

/// An OAuth 2.0 error: a standard code, an optional description and a
/// link to a page about it.
///
/// Providers answer failed requests with one (`{"error":
/// "invalid_grant", "error_description": "Code expired"}`), and the
/// redirect back from a refused login carries one (`?error=access_denied`).
/// The OAuth2 client turns both into this object, inside an
/// [OAuth2AuthorizationException] or an [OAuth2AuthenticationException],
/// so code can react to the code rather than to a message:
///
/// ```dart
/// try {
///   await login.login('keycloak');
/// } on OAuth2AuthenticationException catch (e) {
///   // The user pressed "Cancel" on the provider's page.
///   if (e.error.errorCode == OAuth2ErrorCodes.accessDenied) return;
///   rethrow;
/// }
/// ```
///
/// The description comes from the provider or from this package; it never
/// holds a token or a code, so it may be logged.
///
/// Spring (Java): `OAuth2Error` of `spring-security-oauth2-core`.
final class OAuth2Error {
  /// An error with the code [errorCode] (such as `invalid_grant`), an
  /// optional [description] and [uri].
  const OAuth2Error(this.errorCode, [this.description, this.uri]);

  /// The standard error code, such as `invalid_grant` or `access_denied`;
  /// see [OAuth2ErrorCodes].
  final String errorCode;

  /// A sentence for developers explaining the error, or `null`.
  final String? description;

  /// A link to a page about the error, or `null`.
  final String? uri;

  @override
  bool operator ==(Object other) =>
      other is OAuth2Error &&
      other.errorCode == errorCode &&
      other.description == description &&
      other.uri == uri;

  @override
  int get hashCode => Object.hash(errorCode, description, uri);

  @override
  String toString() => '[$errorCode] ${description ?? ''}';
}

/// The error codes of OAuth 2.0 and OpenID Connect, and those this
/// package adds for checks of its own.
///
/// Compare [OAuth2Error.errorCode] with them instead of writing the
/// strings.
///
/// Spring (Java): `OAuth2ErrorCodes`, plus the codes Spring Security's
/// login classes use as plain strings (`invalid_state_parameter`,
/// `invalid_nonce`, ...).
abstract final class OAuth2ErrorCodes {
  /// The request is missing a parameter or is otherwise malformed.
  static const invalidRequest = 'invalid_request';

  /// The client is not allowed to use this grant.
  static const unauthorizedClient = 'unauthorized_client';

  /// The user or the provider refused the authorization (the user pressed
  /// "Cancel").
  static const accessDenied = 'access_denied';

  /// The provider does not support the `response_type`.
  static const unsupportedResponseType = 'unsupported_response_type';

  /// A requested scope is unknown or not allowed.
  static const invalidScope = 'invalid_scope';

  /// The access token is expired, revoked or malformed.
  static const invalidToken = 'invalid_token';

  /// The access token lacks a scope the resource needs.
  static const insufficientScope = 'insufficient_scope';

  /// The provider had an internal error.
  static const serverError = 'server_error';

  /// The provider is overloaded or down for maintenance.
  static const temporarilyUnavailable = 'temporarily_unavailable';

  /// The client failed to authenticate at the token endpoint.
  static const invalidClient = 'invalid_client';

  /// The code or refresh token is invalid, expired, revoked or was issued
  /// to another client: the user must log in again.
  static const invalidGrant = 'invalid_grant';

  /// The provider does not support the grant type.
  static const unsupportedGrantType = 'unsupported_grant_type';

  /// The provider does not support revoking this kind of token.
  static const unsupportedTokenType = 'unsupported_token_type';

  /// A redirect URI is invalid.
  static const invalidRedirectUri = 'invalid_redirect_uri';

  /// The token endpoint's answer could not be read.
  static const invalidTokenResponse = 'invalid_token_response';

  /// The user-info endpoint's answer could not be read, or its subject
  /// differs from the ID token's.
  static const invalidUserInfoResponse = 'invalid_user_info_response';

  /// The registration has no user-info URI.
  static const missingUserInfoUri = 'missing_user_info_uri';

  /// The registration has no user name attribute.
  static const missingUserNameAttribute = 'missing_user_name_attribute';

  /// The `state` of the redirect is missing or differs from the one sent:
  /// a forged or replayed redirect.
  static const invalidStateParameter = 'invalid_state_parameter';

  /// The redirect came from another issuer than the one asked (RFC 9207
  /// `iss` parameter): a mix-up attack.
  static const invalidIssuer = 'invalid_issuer';

  /// The ID token is missing, malformed or failed a check.
  static const invalidIdToken = 'invalid_id_token';

  /// The ID token's `nonce` differs from the one sent: a replayed token.
  static const invalidNonce = 'invalid_nonce';

  /// No registration has the requested id.
  static const clientRegistrationNotFound = 'client_registration_not_found';
}

/// A failed OAuth 2.0 call: the provider refused a code or a refresh
/// token, answered with something unreadable, or could not be reached.
///
/// The token response clients and the authorized client manager throw it.
/// [error] tells what happened; `invalid_grant` means the stored tokens are
/// dead and the user must log in again, while `invalid_token_response`
/// with a network problem may pass by itself.
///
/// ```dart
/// try {
///   await manager.authorize(request);
/// } on OAuth2AuthorizationException catch (e) {
///   if (e.error.errorCode == OAuth2ErrorCodes.invalidGrant) {
///     await login.logout(); // the refresh token was revoked
///   }
/// }
/// ```
///
/// Spring (Java): `OAuth2AuthorizationException`.
class OAuth2AuthorizationException implements Exception {
  /// A failure described by [error]; [message] defaults to the error's
  /// text, [cause] is the underlying exception, if any.
  OAuth2AuthorizationException(this.error, [String? message, this.cause])
    : message = message ?? error.toString();

  /// The OAuth 2.0 error, such as `invalid_grant`.
  final OAuth2Error error;

  /// What happened, for logs; never contains a token.
  final String message;

  /// The exception that caused this one, such as a transport error, or
  /// `null`.
  final Object? cause;

  @override
  // The text names the actual class, subclasses included, like Java's
  // getClass().getName().
  // ignore: no_runtimetype_tostring
  String toString() => '$runtimeType: $message';
}

/// An [OAuth2AuthorizationException] about one registration, named by
/// [clientRegistrationId].
///
/// The authorized client providers throw it, so the manager's failure
/// handler knows which stored client to remove.
///
/// Spring (Java): `ClientAuthorizationException`.
class ClientAuthorizationException extends OAuth2AuthorizationException {
  /// A failure of the registration [clientRegistrationId] described by
  /// [error].
  ClientAuthorizationException(
    super.error,
    this.clientRegistrationId, [
    super.message,
    super.cause,
  ]);

  /// The registration whose authorization failed.
  final String clientRegistrationId;
}

/// No authorized client exists for an `authorization_code` registration:
/// the user has to log in first.
///
/// The manager throws it when asked for the token of someone who never
/// logged in (or logged out). An app answers by showing its login
/// button; a server redirects to the login.
///
/// Spring (Java): `ClientAuthorizationRequiredException`.
class ClientAuthorizationRequiredException
    extends ClientAuthorizationException {
  /// The registration [clientRegistrationId] needs a login.
  ClientAuthorizationRequiredException(String clientRegistrationId)
    : super(
        const OAuth2Error(
          'client_authorization_required',
          'Authorization required for Client Registration Id',
        ),
        clientRegistrationId,
        'Authorization required for Client Registration Id: '
        '$clientRegistrationId',
      );
}

/// A refused OAuth 2.0 or OpenID Connect login, with the standard [error]
/// code.
///
/// The app login (`OAuth2LoginService.login`) and the user services throw
/// it: a forged redirect (`invalid_state_parameter`), the user's "Cancel"
/// (`access_denied`), an ID token for someone else (`invalid_id_token`),
/// a replayed one (`invalid_nonce`). It is an [AuthenticationException],
/// so code that handles failed logins of any kind catches it too.
///
/// ```dart
/// try {
///   await login.login('keycloak');
/// } on OAuth2AuthenticationException catch (e) {
///   showError('Login failed (${e.error.errorCode})');
/// }
/// ```
///
/// Spring (Java): `OAuth2AuthenticationException`.
class OAuth2AuthenticationException extends AuthenticationException {
  /// A refusal with [error]; the log [message] defaults to the error's
  /// description, else its code.
  OAuth2AuthenticationException(this.error, [String? message, Object? cause])
    : super(message ?? error.description ?? error.errorCode, cause);

  /// The OAuth 2.0 error, such as `invalid_id_token`.
  final OAuth2Error error;
}
