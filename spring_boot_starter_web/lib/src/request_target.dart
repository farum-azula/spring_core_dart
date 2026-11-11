// Tomcat's default: an encoded slash (encodedSolidusHandling=reject),
// backslash or NUL in the path is a 400. The servers keep the path
// percent-encoded, so they are still visible here. A raw backslash is
// not: Uri.parse has made it a "/" already.
final _encodedSeparator = RegExp('%(?:2f|5c|00)', caseSensitive: false);

/// Why a server must answer 400 to a request for [uri] instead of handing
/// it to the dispatcher, or `null` for a target it may route.
///
/// Refused: an encoded `/`, `\` or NUL in the path (`%2F`, `%5C`, `%00`),
/// a `.` or `..` segment, also behind matrix parameters or encoded
/// (`/a/%2e%2e;x/b`), and a percent-escape that does not decode to UTF-8,
/// in the path or the query. The router and the security rules then see
/// one path, the one the controllers get.
///
/// The built-in `dart:io` server asks it for every request; a
/// `WebServer` of another kind (a function behind a platform's gateway)
/// should too. [uri] is the request target as it was sent, still
/// percent-encoded.
///
/// Spring (Java): Tomcat's `encodedSolidusHandling=reject` and Spring
/// Security's `StrictHttpFirewall`.
String? requestTargetProblem(Uri uri) {
  final path = uri.hasAuthority && !uri.hasScheme
      ? '//${uri.authority}${uri.path}'
      : uri.path;
  if (_encodedSeparator.hasMatch(path)) {
    return r'The path contains an encoded "/", "\" or NUL';
  }
  for (final segment in path.split('/')) {
    final semicolon = segment.indexOf(';');
    final value = semicolon < 0 ? segment : segment.substring(0, semicolon);
    final String decoded;
    try {
      decoded = Uri.decodeComponent(value);
    } on Object {
      return 'The path contains an invalid percent-encoding';
    }
    if (decoded == '.' || decoded == '..') {
      return 'The path contains a "." or ".." segment';
    }
  }
  if (uri.hasQuery) {
    for (final pair in uri.query.split('&')) {
      try {
        pair.split('=').forEach(Uri.decodeQueryComponent);
      } on Object {
        return 'The query contains an invalid percent-encoding';
      }
    }
  }
  return null;
}
