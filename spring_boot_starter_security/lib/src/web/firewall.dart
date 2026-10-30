import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// The error an [HttpFirewall] throws to refuse a request before any
/// security rule or controller sees it.
///
/// The client gets `400 Bad Request` without the reason; the reason goes
/// to the debug log. Throw it from your own firewall.
///
/// Spring (Java): `RequestRejectedException`.
class RequestRejectedException extends ErrorResponseException {
  /// A refusal for [reason], answered with status 400.
  RequestRejectedException(this.reason) : super(HttpStatus.badRequest);

  /// Why the request was refused, for the log; never sent to the client.
  final String reason;

  @override
  String toString() => 'RequestRejectedException: $reason';
}

/// A check that runs on every request before a security chain is chosen,
/// to refuse requests that are malformed or could be misread.
///
/// The starter uses a [StrictHttpFirewall]. Declare an `HttpFirewall` bean
/// to replace it, usually a `StrictHttpFirewall` with one rule relaxed.
///
/// Spring (Java): `HttpFirewall`.
abstract interface class HttpFirewall {
  /// Returns normally to let [request] through; throws a
  /// [RequestRejectedException] to refuse it.
  void check(ServerHttpRequest request);
}

/// The default [HttpFirewall]: it refuses requests whose path could be
/// read two ways, so a security rule and the router never disagree on
/// which path was asked for.
///
/// An attacker who can make a rule read `/admin` differently from the
/// router (with `;`, encoded slashes, `..` and so on) could reach a
/// protected controller through an unprotected rule. These requests are
/// refused with 400 before any rule is looked at:
///
/// - in the path: `;` and `%3B` (path parameters), encoded `/` (`%2F`),
///   `\` and `%5C`, encoded `%` (`%25`), encoded `.` (`%2E`), `//`, `.`
///   and `..` segments, spaces, control and non-ASCII characters, `%00`,
///   line separators (`%0A`, `%0D`, `%E2%80%A8`, `%E2%80%A9`);
/// - a request target that is not a path (`//host/path`, which Dart reads
///   as a host);
/// - methods other than DELETE, GET, HEAD, OPTIONS, PATCH, POST and PUT
///   (TRACE echoes the request, cookies included);
/// - header names that are not printable ASCII, and header values with
///   control characters (a tab is allowed).
///
/// The `allow...` options relax one rule each; turn one on only when an
/// application really needs such paths, and declare the firewall as a
/// bean.
///
/// ```dart
/// // Paths carry encoded slashes (`/files/a%2Fb`).
/// @Bean()
/// HttpFirewall firewall() => StrictHttpFirewall(allowUrlEncodedSlash: true);
/// ```
///
/// Spring (Java): `StrictHttpFirewall`. One difference: on a real server
/// `dart:io` normalizes `..`, `%2E` and `\` (RFC 3986) before the
/// application, so those reach the router and the rules already
/// normalized and are not refused; Spring refuses them with 400.
final class StrictHttpFirewall implements HttpFirewall {
  /// A firewall with every check on, unless relaxed by the `allow...`
  /// options; [allowedMethods] replaces the default list of methods.
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

  /// The methods let through; others are refused with 400.
  final Set<HttpMethod> allowedMethods;

  /// Whether `;` and `%3B` are allowed in the path; `false` by default
  /// because path parameters (`/admin;x=y`) can hide a path from a rule.
  final bool allowSemicolon;

  /// Whether an encoded slash `%2F` is allowed in the path; `false` by
  /// default.
  final bool allowUrlEncodedSlash;

  /// Whether `\` and `%5C` are allowed in the path; `false` by default.
  final bool allowBackSlash;

  /// Whether an encoded percent sign `%25` is allowed in the path, which
  /// allows double encoding; `false` by default.
  final bool allowUrlEncodedPercent;

  /// Whether an encoded period `%2E` is allowed in the path; `false` by
  /// default.
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

  // No `.` or `..` segment, also with path parameters (`..;x`, which
  // `allowSemicolon` lets through and a router strips to `..`).
  static bool _normalized(String path) {
    for (final segment in path.split('/')) {
      final semicolon = segment.indexOf(';');
      final name = semicolon < 0 ? segment : segment.substring(0, semicolon);
      if (name == '.' || name == '..') {
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
