import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// A request was refused before any security rule looked at it, like
/// Spring's `RequestRejectedException`: `400 Bad Request` (without the
/// reason, which goes to the log).
class RequestRejectedException extends ErrorResponseException {
  /// Refused for [reason].
  RequestRejectedException(this.reason) : super(HttpStatus.badRequest);

  /// Why, for logs.
  final String reason;

  @override
  String toString() => 'RequestRejectedException: $reason';
}

/// Checks a request before the security rules, like Spring's
/// `HttpFirewall`.
abstract interface class HttpFirewall {
  /// Throws [RequestRejectedException] when [request] must not go on.
  void check(ServerHttpRequest request);
}

/// Refuses requests whose path could be read two ways, like Spring's
/// `StrictHttpFirewall` (docs/security.md, rule 3): a rule and the router must
/// never see different paths.
///
/// Refused (400):
///
/// - in the path: `;` and `%3B` (path parameters), encoded `/` (`%2F`),
///   `\` and `%5C`, encoded `%` (`%25`), encoded `.` (`%2E`), `//`, `.`
///   and `..` segments, control characters and non-ASCII bytes, `%00`,
///   line separators (`%0A`, `%0D`, `%E2%80%A8`, `%E2%80%A9`);
/// - a request target that is not a path (`//host/path`, which Dart reads
///   as a host);
/// - methods other than DELETE, GET, HEAD, OPTIONS, PATCH, POST and PUT
///   (TRACE echoes the request, cookies included);
/// - control characters in header names and values.
///
/// On a real server `dart:io` has already normalized `..`, `%2E` and `\`
/// (RFC 3986), so those reach the application normalized; the router and
/// the rules then see the same normalized path. Spring refuses them with
/// 400 instead: one of the documented differences.
final class StrictHttpFirewall implements HttpFirewall {
  /// A firewall; [allowedMethods] replaces the default methods.
  StrictHttpFirewall({
    Set<HttpMethod>? allowedMethods,
    this.allowSemicolon = false,
    this.allowUrlEncodedSlash = false,
    this.allowBackSlash = false,
    this.allowUrlEncodedPercent = false,
    this.allowUrlEncodedPeriod = false,
  }) : allowedMethods =
           allowedMethods ??
           const {
             HttpMethod.delete,
             HttpMethod.get,
             HttpMethod.head,
             HttpMethod.options,
             HttpMethod.patch,
             HttpMethod.post,
             HttpMethod.put,
           };

  /// The methods let through.
  final Set<HttpMethod> allowedMethods;

  /// Whether `;` is allowed in the path.
  final bool allowSemicolon;

  /// Whether `%2F` is allowed.
  final bool allowUrlEncodedSlash;

  /// Whether `\` and `%5C` are allowed.
  final bool allowBackSlash;

  /// Whether `%25` is allowed.
  final bool allowUrlEncodedPercent;

  /// Whether `%2E` is allowed.
  final bool allowUrlEncodedPeriod;

  static const _lineSeparators = ['%0a', '%0d', '%e2%80%a8', '%e2%80%a9'];

  @override
  void check(ServerHttpRequest request) {
    if (!allowedMethods.contains(request.method)) {
      _reject(
        'The request was rejected because the HTTP method '
        '"${request.method.value}" was not included within the list of '
        'allowed HTTP methods',
      );
    }
    final uri = request.uri;
    if (uri.hasAuthority && !uri.hasScheme) {
      // `//host/path`: a network-path reference, not a path.
      _reject('The request target is not a path: //${uri.authority}');
    }
    <String>{request.path, uri.path}.forEach(_checkPath);
    request.headers.forEach((name, values) {
      if (!_printable(name)) {
        _reject('The request header name contains an invalid character');
      }
      for (final value in values) {
        if (_hasControl(value)) {
          _reject('The request header "$name" contains an invalid character');
        }
      }
    });
  }

  void _checkPath(String path) {
    final lower = path.toLowerCase();
    if (!allowSemicolon && (path.contains(';') || lower.contains('%3b'))) {
      _reject(
        'The request was rejected because the URL contained a '
        'potentially malicious String ";"',
      );
    }
    if (!allowUrlEncodedSlash && lower.contains('%2f')) {
      _reject(
        'The request was rejected because the URL contained a '
        'potentially malicious String "%2F"',
      );
    }
    if (!allowBackSlash && (path.contains(r'\') || lower.contains('%5c'))) {
      _reject(
        'The request was rejected because the URL contained a '
        r'potentially malicious String "\"',
      );
    }
    if (!allowUrlEncodedPercent && lower.contains('%25')) {
      _reject(
        'The request was rejected because the URL contained a '
        'potentially malicious String "%25"',
      );
    }
    if (!allowUrlEncodedPeriod && lower.contains('%2e')) {
      _reject(
        'The request was rejected because the URL contained a '
        'potentially malicious String "%2E"',
      );
    }
    if (lower.contains('%00')) {
      _reject(
        'The request was rejected because the URL contained a '
        'potentially malicious String "%00"',
      );
    }
    for (final separator in _lineSeparators) {
      if (lower.contains(separator)) {
        _reject(
          'The request was rejected because the URL contained a '
          'line separator',
        );
      }
    }
    if (path.contains('//')) {
      _reject(
        'The request was rejected because the URL contained a '
        'potentially malicious String "//"',
      );
    }
    if (!_normalized(path)) {
      _reject('The request was rejected because the URL was not normalized');
    }
    if (!_printable(path)) {
      _reject(
        'The request was rejected because the URL contained an '
        'invalid character',
      );
    }
  }

  // No `.` or `..` segment.
  static bool _normalized(String path) {
    for (final segment in path.split('/')) {
      if (segment == '.' || segment == '..') {
        return false;
      }
    }
    return true;
  }

  // Printable ASCII only (paths arrive percent-encoded).
  static bool _printable(String text) {
    for (final unit in text.codeUnits) {
      if (unit < 0x21 || unit > 0x7e) {
        return false;
      }
    }
    return true;
  }

  static bool _hasControl(String text) {
    for (final unit in text.codeUnits) {
      if ((unit < 0x20 && unit != 0x09) || unit == 0x7f) {
        return true;
      }
      if (unit == 0x2028 || unit == 0x2029) {
        return true;
      }
    }
    return false;
  }

  static Never _reject(String reason) => throw RequestRejectedException(reason);
}
