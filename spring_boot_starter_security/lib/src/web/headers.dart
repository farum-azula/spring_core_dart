import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// Writes one or more response headers, like Spring's `HeaderWriter`.
abstract interface class HeaderWriter {
  /// Writes the headers for [request] into [response].
  void writeHeaders(ServerHttpRequest request, ServerHttpResponse response);
}

/// A fixed header, like Spring's `StaticHeadersWriter`.
final class StaticHeadersWriter implements HeaderWriter {
  /// Writes [name]: [value].
  const StaticHeadersWriter(this.name, this.value);

  /// The header.
  final String name;

  /// The value.
  final String value;

  @override
  void writeHeaders(ServerHttpRequest request, ServerHttpResponse response) =>
      response.headers.set(name, value);
}

/// `Cache-Control: no-cache, no-store, max-age=0, must-revalidate`,
/// `Pragma: no-cache`, `Expires: 0`, like Spring's
/// `CacheControlHeadersWriter`: authenticated pages are not kept by
/// browsers or proxies. A controller setting its own `Cache-Control`
/// replaces them.
final class CacheControlHeadersWriter implements HeaderWriter {
  /// The writer.
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

/// `Strict-Transport-Security` on secure requests only, like Spring's
/// `HstsHeaderWriter` (`max-age=31536000 ; includeSubDomains`).
final class HstsHeaderWriter implements HeaderWriter {
  /// HSTS for [maxAge].
  const HstsHeaderWriter({
    this.maxAge = const Duration(days: 365),
    this.includeSubDomains = true,
    this.preload = false,
  });

  /// How long browsers remember.
  final Duration maxAge;

  /// Whether subdomains are included.
  final bool includeSubDomains;

  /// Whether to ask for the preload list.
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

/// The `X-Frame-Options` modes, like Spring's `XFrameOptionsMode`.
enum XFrameOptionsMode {
  /// Never in a frame (Spring's default).
  deny('DENY'),

  /// Only in frames of the same origin.
  sameOrigin('SAMEORIGIN');

  XFrameOptionsMode(this.value);

  /// The header value.
  final String value;
}

/// What `HeaderWriterFilter` writes; built by `HttpSecurity.headers`.
final class HeaderWriterFilter implements WebFilter {
  /// A filter writing [writers] before the rest of the chain (a
  /// controller may still replace them).
  HeaderWriterFilter(List<HeaderWriter> writers)
    : writers = List.unmodifiable(writers);

  /// The writers.
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

/// Answers CORS requests before authentication, like Spring's
/// `CorsFilter`: a pre-flight never needs credentials (browsers send none),
/// so it is answered here with the router's CORS configuration — the
/// `CorsConfigurationSource` bean and `@CrossOrigin` — and never reaches
/// the rules; an actual cross-origin request gets its CORS headers and goes
/// on to be authenticated as usual. An invalid CORS request is refused
/// (403).
final class CorsFilter implements WebFilter {
  /// A filter asking [configurationFor].
  const CorsFilter(this.configurationFor);

  /// The configuration for a request.
  final CorsConfiguration? Function(ServerHttpRequest request) configurationFor;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    if (!isCorsRequest(request)) {
      return await chain.doFilter(request, response);
    }
    final preFlight = isPreFlightRequest(request);
    final config = configurationFor(request);
    if (config == null) {
      if (preFlight) {
        // Nothing allows it: the browser gets no CORS headers and blocks.
        response.statusCode = HttpStatus.forbidden;
        await response.close();
        return;
      }
      return await chain.doFilter(request, response);
    }
    if (!processCors(config, request, response, preFlight: preFlight)) {
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
