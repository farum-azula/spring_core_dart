import 'dart:async';

import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// Adds one or more security headers to every response of a chain.
///
/// The defaults (no sniffing, no caching, HSTS, no framing) come from
/// `HttpSecurity.headers`. Implement it for a header of your own, and add
/// it with `headers((h) => h.addHeaderWriter(...))`.
///
/// ```dart
/// // Keep the browser from sending powerful features to the page.
/// final class PermissionsPolicyWriter implements HeaderWriter {
///   const PermissionsPolicyWriter();
///
///   @override
///   void writeHeaders(
///     ServerHttpRequest request,
///     ServerHttpResponse response,
///   ) => response.headers.set('Permissions-Policy', 'camera=()');
/// }
/// ```
///
/// Spring (Java): `HeaderWriter`.
abstract interface class HeaderWriter {
  /// Sets the headers for [request] on [response]; called before the
  /// controller runs, so the controller may still replace them.
  void writeHeaders(ServerHttpRequest request, ServerHttpResponse response);
}

/// A [HeaderWriter] that sets one header to a fixed value on every
/// response.
///
/// ```dart
/// http.headers((h) => h.addHeaderWriter(const StaticHeadersWriter(
///     'Cross-Origin-Opener-Policy', 'same-origin')));
/// ```
///
/// Spring (Java): `StaticHeadersWriter`.
final class StaticHeadersWriter implements HeaderWriter {
  /// A writer setting the header [name] to [value], replacing any value
  /// set before.
  const StaticHeadersWriter(this.name, this.value);

  /// The header name.
  final String name;

  /// The text sent in the header.
  final String value;

  @override
  void writeHeaders(ServerHttpRequest request, ServerHttpResponse response) =>
      response.headers.set(name, value);
}

/// The [HeaderWriter] that forbids caching:
/// `Cache-Control: no-cache, no-store, max-age=0, must-revalidate`,
/// `Pragma: no-cache` and `Expires: 0`.
///
/// Pages shown to a logged-in user must not stay in a browser's or a
/// proxy's cache, where the next user of the machine could see them. On by
/// default. It writes nothing when one of the three headers is already
/// set. A controller that sets its own `Cache-Control` replaces it, and
/// then the `Pragma` and `Expires` written here are removed too.
///
/// Spring (Java): `CacheControlHeadersWriter`.
final class CacheControlHeadersWriter implements HeaderWriter {
  /// The stateless writer.
  const CacheControlHeadersWriter();

  @override
  void writeHeaders(ServerHttpRequest request, ServerHttpResponse response) {
    final headers = response.headers;
    if (headers.contains(HttpHeaders.cacheControlHeader) ||
        headers.contains(HttpHeaders.expiresHeader) ||
        headers.contains(HttpHeaders.pragmaHeader)) {
      return;
    }
    headers
      ..set(
        HttpHeaders.cacheControlHeader,
        'no-cache, no-store, max-age=0, must-revalidate',
      )
      ..set(HttpHeaders.pragmaHeader, 'no-cache')
      ..set(HttpHeaders.expiresHeader, '0');
  }
}

/// The [HeaderWriter] of `Strict-Transport-Security` (HSTS), which tells
/// browsers to use only HTTPS for this site from now on.
///
/// It protects against an attacker who downgrades a user's next visit to
/// plain HTTP. The header is sent on secure (HTTPS) requests only, as the
/// standard requires. On by default, with
/// `max-age=31536000 ; includeSubDomains`.
///
/// ```dart
/// // Two years, and ask to be on the browsers' preload list.
/// http.headers((h) => h.httpStrictTransportSecurity(
///     const HstsHeaderWriter(maxAge: Duration(days: 730), preload: true)));
/// ```
///
/// Spring (Java): `HstsHeaderWriter`.
final class HstsHeaderWriter implements HeaderWriter {
  /// A writer telling browsers to use HTTPS for [maxAge] (one year by
  /// default), for subdomains too unless [includeSubDomains] is `false`.
  const HstsHeaderWriter({
    this.maxAge = const Duration(days: 365),
    this.includeSubDomains = true,
    this.preload = false,
  });

  /// How long browsers remember to use HTTPS only, sent in seconds.
  final Duration maxAge;

  /// Whether the rule also covers every subdomain; `true` by default.
  /// Set it to `false` when a subdomain is still served over HTTP.
  final bool includeSubDomains;

  /// Whether to add `preload`, asking to be built into browsers' HSTS
  /// lists; `false` by default, as it is hard to undo.
  final bool preload;

  @override
  void writeHeaders(ServerHttpRequest request, ServerHttpResponse response) {
    if (!request.isSecure) {
      return;
    }
    final value = StringBuffer('max-age=${maxAge.inSeconds}');
    if (includeSubDomains) {
      value.write(' ; includeSubDomains');
    }
    if (preload) {
      value.write(' ; preload');
    }
    response.headers.set('Strict-Transport-Security', '$value');
  }
}

/// The values of the `X-Frame-Options` header, which says whether other
/// pages may show this one in a frame.
///
/// Framing lets an attacker's page lay invisible buttons over yours
/// (clickjacking). The default is [deny].
///
/// Spring (Java): `XFrameOptionsMode`.
enum XFrameOptionsMode {
  /// Never in a frame; the default, as in Spring.
  deny('DENY'),

  /// Only in frames of pages of the same origin, for an application that
  /// frames its own pages.
  sameOrigin('SAMEORIGIN');

  XFrameOptionsMode(this.value);

  /// The text sent in the `X-Frame-Options` header, such as `DENY`.
  final String value;
}

/// The filter that adds the security headers to every response of a
/// chain, error answers included.
///
/// `HttpSecurity` adds it with the writers configured by `headers`;
/// applications do not create it.
///
/// Spring (Java): `HeaderWriterFilter`.
final class HeaderWriterFilter implements WebFilter {
  /// A filter running [writers] before the rest of the chain, so a
  /// controller may still replace the headers.
  HeaderWriterFilter(List<HeaderWriter> writers)
    : writers = List.unmodifiable(writers);

  /// The writers, in order; cannot be modified.
  final List<HeaderWriter> writers;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) {
    // Written now, so every answer has them, errors included; the rest of
    // the chain may replace them.
    for (final writer in writers) {
      writer.writeHeaders(request, response);
    }
    return chain.doFilter(request, _CacheHeaderResponse(response));
  }
}

// When the application sets its own Cache-Control, the Pragma and Expires
// written for it go too, like Spring's lazy CacheControlHeadersWriter.
final class _CacheHeaderResponse extends ServerHttpResponseDecorator {
  _CacheHeaderResponse(super.delegate);

  static const _ours = 'no-cache, no-store, max-age=0, must-revalidate';
  bool _checked = false;

  void _beforeCommit() {
    if (_checked || isCommitted) {
      return;
    }
    _checked = true;
    final h = headers;
    final cacheControl = h[HttpHeaders.cacheControlHeader];
    if (cacheControl != null && cacheControl != _ours) {
      if (h[HttpHeaders.pragmaHeader] == 'no-cache') {
        h.remove(HttpHeaders.pragmaHeader);
      }
      if (h[HttpHeaders.expiresHeader] == '0') {
        h.remove(HttpHeaders.expiresHeader);
      }
    }
  }

  @override
  void add(List<int> bytes) {
    _beforeCommit();
    super.add(bytes);
  }

  @override
  void write(String text) {
    _beforeCommit();
    super.write(text);
  }

  @override
  Future<void> flush() {
    _beforeCommit();
    return super.flush();
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    _beforeCommit();
    return super.addStream(stream);
  }

  @override
  Future<void> close() {
    _beforeCommit();
    return super.close();
  }
}

/// The filter that answers CORS checks before the security rules, so a
/// browser can call the API from another origin.
///
/// Before a cross-origin request, a browser sends a pre-flight `OPTIONS`
/// request without credentials; the rules would refuse it. This filter
/// answers every pre-flight itself from the CORS configuration, so they
/// never reach the rules. An actual cross-origin request gets its CORS
/// headers here and then goes on to be authenticated as usual.
///
/// - A pre-flight that the configuration allows: `200`, with the CORS
///   headers.
/// - A CORS request the configuration refuses: `403` (see `processCors`):
///   an origin it does not allow, or a method it does not allow (the
///   method a pre-flight announces, or an actual request's own).
/// - A pre-flight with no configuration for its path: `200` with no CORS
///   headers (and no `Vary`), as in Spring, so the browser blocks the
///   request it announced.
/// - Any other request: passed on; with a configuration for its path, its
///   answer gets `Vary: Origin, Access-Control-Request-Method,
///   Access-Control-Request-Headers`, as in Spring (see `processCors`).
///
/// By default the configuration is the dispatcher's
/// (`DispatcherHandler.corsConfigurationFor`): the rules of the handler
/// the request goes to, the handler mappings asked in order as for the
/// request itself and the router choosing as it does (path, method,
/// `consumes`, `produces`, `headers`), or those of the
/// `CorsConfigurationSource` bean named `corsConfigurationSource` alone
/// where it has some. A request another mapping takes, such as a
/// WebSocket handshake, gets only the bean's rules (the endpoint checks
/// the origin itself), never the `addCorsMappings` rules. The router
/// leaves a request this filter allowed as it is, so CORS works the same
/// with and without security. Change it with `HttpSecurity.cors`.
///
/// Spring (Java): `CorsFilter`. Spring adds it only with `.cors()`.
final class CorsFilter implements WebFilter {
  /// A filter taking each request's CORS rules from [configurationFor].
  const CorsFilter(this.configurationFor);

  /// The CORS rules for a request, or `null` when its path has none.
  final FutureOr<CorsConfiguration?> Function(ServerHttpRequest request)
  configurationFor;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    // Spring's CorsFilter: no configuration lets every request through
    // untouched; processCors only adds Vary to a request that is not a
    // CORS request; and every pre-flight ends here.
    final config = await configurationFor(request);
    final preFlight = isPreFlightRequest(request);
    if (config != null &&
        !processCors(config, request, response, preFlight: preFlight)) {
      await response.send(HttpStatus.forbidden, 'Invalid CORS request');
      return;
    }
    if (preFlight) {
      response.statusCode = HttpStatus.ok;
      await response.close();
      return;
    }
    await chain.doFilter(request, response);
  }
}
