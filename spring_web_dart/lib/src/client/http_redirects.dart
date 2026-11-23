import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_method.dart';
import 'package:spring_web_dart/src/http_secrets.dart';

/// The one rule for a redirect a transport follows itself, so that a
/// credential is treated alike on every platform.
///
/// It follows `GET` and `HEAD`, and a `303` after any method (then a
/// `GET`); it never follows `https` to `http`, or to another scheme. A hop
/// to another origin drops the headers that carry a credential.
abstract final class HttpRedirects {
  /// The most redirects one request follows, as `HttpClient`'s default.
  static const int maxRedirects = 5;

  static const Set<int> _statuses = {301, 302, 303, 307, 308};

  /// Where a [status] answer with [location] to [method] on [url] leads, or
  /// `null` when it is not a redirect to follow: the `3xx` is then the
  /// answer.
  static ({HttpMethod method, Uri url})? next(
    HttpMethod method,
    Uri url,
    int status,
    String? location,
  ) {
    if (!_statuses.contains(status) || location == null) {
      return null;
    }
    final safe = method == HttpMethod.get || method == HttpMethod.head;
    if (!safe && status != 303) {
      return null;
    }
    final Uri target;
    try {
      target = url.resolve(location);
    } on FormatException {
      return null;
    }
    if (url.scheme == 'https' && target.scheme != 'https') {
      return null;
    }
    if (target.scheme != 'http' && target.scheme != 'https') {
      return null;
    }
    return (
      method: status == 303 && method != HttpMethod.head
          ? HttpMethod.get
          : method,
      url: target,
    );
  }

  /// The names in [headers] that carry a credential of [request]:
  /// [HttpSecrets.isSensitiveHeader] and its `sensitiveHeaders`.
  static List<String> credentialHeaders(
    HttpHeaders headers,
    HttpRequest request,
  ) => [
    for (final name in headers.names)
      if (HttpSecrets.isSensitiveHeader(name) ||
          request.sensitiveHeaders.contains(name.toLowerCase()))
        name,
  ];

  /// Prepares [headers] for the hop from [from] to [to]: another origin
  /// gets none of the credentials of [request].
  static void applyHop(
    HttpHeaders headers,
    HttpRequest request,
    Uri from,
    Uri to,
  ) {
    if (!_sameOrigin(from, to)) {
      credentialHeaders(headers, request).forEach(headers.remove);
    }
  }

  static bool _sameOrigin(Uri a, Uri b) =>
      a.scheme == b.scheme && a.host == b.host && a.port == b.port;
}
