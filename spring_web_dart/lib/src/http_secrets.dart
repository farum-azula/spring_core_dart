import 'package:spring_core_dart/core.dart' show SecretNames;

/// The family's one rule for the HTTP headers and query or form parameters
/// whose values a log never shows: the web starter's request log lines and
/// the `RestClient`'s request log ask it, so a name is masked in both or
/// in neither. A redirect to another origin drops the same headers from a
/// client's call.
///
/// A header is sensitive when it is one of [headers] (credentials, the
/// DPoP proof, cookies) or its name looks secret to [SecretNames]
/// (`X-Api-Key`, `X-Auth-Token`) or holds `session`. A parameter is
/// sensitive when it is one of [parameters] (the OAuth 2.0 and OpenID
/// Connect ones that carry a grant or a proof, signed-URL signatures) or its
/// name looks secret.
///
/// ```dart
/// HttpSecrets.isSensitiveHeader('Authorization');  // true
/// HttpSecrets.isSensitiveHeader('X-Api-Key');      // true
/// HttpSecrets.isSensitiveParameter('code');        // true
/// HttpSecrets.isSensitiveParameter('page');        // false
/// ```
///
/// Spring (Java): Spring's `DispatcherServlet` logs no header values unless
/// `enableLoggingRequestDetails`; Spring Cloud Gateway's and OkHttp's
/// logging redact `Authorization`, `Cookie` and the like.
abstract final class HttpSecrets {
  /// The headers that always carry a credential, in lower case.
  static const headers = {
    'authorization',
    'proxy-authorization',
    'cookie',
    'set-cookie',
    'dpop',
    'x-amz-security-token',
  };

  /// The query and form parameters that always carry a grant, a proof or a
  /// signature, in lower case.
  static const parameters = {
    'code',
    'state',
    'nonce',
    'code_verifier',
    'client_assertion',
    'assertion',
    'id_token_hint',
    'logout_token',
    'jwt',
    'request',
    'sig',
    'signature',
    'x-amz-signature',
    'x-amz-credential',
    'x-goog-signature',
  };

  /// Whether the header [name] (any case) carries a credential.
  static bool isSensitiveHeader(String name) =>
      headers.contains(name.toLowerCase()) ||
      name.toLowerCase().contains('session') ||
      SecretNames.looksSecret(name);

  /// Whether the query or form parameter [name] (any case) carries a
  /// credential.
  static bool isSensitiveParameter(String name) =>
      parameters.contains(name.toLowerCase()) || SecretNames.looksSecret(name);
}
