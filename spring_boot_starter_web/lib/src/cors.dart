import 'package:spring_web_dart/spring_web_dart.dart';

/// Which cross-origin requests are allowed, like Spring's
/// `CorsConfiguration`. Empty lists allow nothing, except
/// [applyPermitDefaultValues].
///
/// ```dart
/// final config = CorsConfiguration(
///   allowedOrigins: ['https://shop.example'],
///   allowedMethods: ['GET', 'POST'],
///   allowedHeaders: ['*'],
///   allowCredentials: true,
/// );
/// ```
final class CorsConfiguration {
  /// A configuration; see the members.
  CorsConfiguration({
    List<String> allowedOrigins = const [],
    List<String> allowedOriginPatterns = const [],
    List<String> allowedMethods = const [],
    List<String> allowedHeaders = const [],
    List<String> exposedHeaders = const [],
    this.allowCredentials,
    this.maxAge,
  }) : allowedOrigins = [...allowedOrigins],
       allowedOriginPatterns = [...allowedOriginPatterns],
       allowedMethods = [...allowedMethods],
       allowedHeaders = [...allowedHeaders],
       exposedHeaders = [...exposedHeaders];

  /// From a `@CrossOrigin` annotation, with Spring's defaults for what it
  /// leaves out (every origin, header, the handler's methods, 30 minutes).
  factory CorsConfiguration.fromAnnotation(CrossOrigin annotation) =>
      CorsConfiguration(
        allowedOrigins: annotation.origins,
        allowedOriginPatterns: annotation.originPatterns,
        allowedMethods: annotation.methods,
        allowedHeaders: annotation.allowedHeaders,
        exposedHeaders: annotation.exposedHeaders,
        allowCredentials: annotation.allowCredentials,
        maxAge: annotation.maxAge == null
            ? null
            : Duration(seconds: annotation.maxAge!),
      ).applyPermitDefaultValues();

  /// Allowed origins (`https://shop.example`), `*` for any.
  final List<String> allowedOrigins;

  /// Allowed origin patterns (`https://*.example`, `http://localhost:[*]`).
  final List<String> allowedOriginPatterns;

  /// Allowed methods (`GET`, ...), `*` for any.
  final List<String> allowedMethods;

  /// Allowed request headers, `*` for any.
  final List<String> allowedHeaders;

  /// Response headers the browser may read.
  final List<String> exposedHeaders;

  /// Whether credentials (cookies) are allowed.
  bool? allowCredentials;

  /// How long the browser may cache a pre-flight answer.
  Duration? maxAge;

  /// Fills what is not set like Spring: every origin, `GET`, `HEAD` and
  /// `POST`, every header, 30 minutes.
  CorsConfiguration applyPermitDefaultValues() {
    if (allowedOrigins.isEmpty && allowedOriginPatterns.isEmpty) {
      allowedOrigins.add('*');
    }
    if (allowedMethods.isEmpty) {
      allowedMethods.addAll(['GET', 'HEAD', 'POST']);
    }
    if (allowedHeaders.isEmpty) {
      allowedHeaders.add('*');
    }
    maxAge ??= const Duration(minutes: 30);
    return this;
  }

  /// This configuration with [other]'s values added (a method's
  /// `@CrossOrigin` over the class's or the global one).
  CorsConfiguration combine(CorsConfiguration? other) {
    if (other == null) {
      return this;
    }
    List<String> merge(List<String> a, List<String> b) {
      if (a.contains('*') || b.contains('*')) {
        return ['*'];
      }
      return {...a, ...b}.toList();
    }

    return CorsConfiguration(
      allowedOrigins: merge(allowedOrigins, other.allowedOrigins),
      allowedOriginPatterns: merge(
        allowedOriginPatterns,
        other.allowedOriginPatterns,
      ),
      allowedMethods: merge(allowedMethods, other.allowedMethods),
      allowedHeaders: merge(allowedHeaders, other.allowedHeaders),
      exposedHeaders: merge(exposedHeaders, other.exposedHeaders),
      allowCredentials: other.allowCredentials ?? allowCredentials,
      maxAge: other.maxAge ?? maxAge,
    );
  }

  /// The `Access-Control-Allow-Origin` value for [origin], or `null` when
  /// it is not allowed.
  String? checkOrigin(String origin) {
    final trimmed = origin.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (allowedOrigins.contains('*')) {
      if (allowCredentials ?? false) {
        throw StateError(
          'When allowCredentials is true, allowedOrigins cannot contain "*" '
          '(the Access-Control-Allow-Origin header cannot be "*" then); list '
          'the origins or use allowedOriginPatterns.',
        );
      }
      return '*';
    }
    for (final allowed in allowedOrigins) {
      if (allowed.toLowerCase() == trimmed.toLowerCase()) {
        return trimmed;
      }
    }
    for (final pattern in allowedOriginPatterns) {
      if (_originPattern(pattern).hasMatch(trimmed)) {
        return trimmed;
      }
    }
    return null;
  }

  /// The allowed methods for a pre-flight asking for [method], or `null`.
  List<String>? checkMethod(String method) {
    final methods = allowedMethods.isEmpty
        ? const ['GET', 'HEAD']
        : allowedMethods;
    if (methods.contains('*')) {
      return [method];
    }
    return methods.contains(method) ? methods : null;
  }

  /// The allowed headers of [requested], or `null` when one is not
  /// allowed.
  List<String>? checkHeaders(List<String> requested) {
    if (requested.isEmpty) {
      return const [];
    }
    if (allowedHeaders.contains('*')) {
      return requested;
    }
    final allowed = {for (final h in allowedHeaders) h.toLowerCase()};
    for (final header in requested) {
      if (!allowed.contains(header.toLowerCase())) {
        return null;
      }
    }
    return requested;
  }

  static RegExp _originPattern(String pattern) {
    final out = StringBuffer('^');
    for (var i = 0; i < pattern.length; i++) {
      final char = pattern[i];
      if (pattern.startsWith('[*]', i)) {
        out.write(r'\d+');
        i += 2;
      } else if (char == '*') {
        out.write('.*');
      } else {
        out.write(RegExp.escape(char));
      }
    }
    out.write(r'$');
    return RegExp(out.toString(), caseSensitive: false);
  }
}

/// The CORS configuration of a request, like Spring's
/// `CorsConfigurationSource`. A bean of this type is the global
/// configuration (Spring Security's `.cors()` uses it too).
abstract interface class CorsConfigurationSource {
  /// The configuration for [request], or `null` for none.
  CorsConfiguration? getCorsConfiguration(ServerHttpRequest request);
}

/// A [CorsConfigurationSource] by path pattern, like Spring's
/// `UrlBasedCorsConfigurationSource`.
///
/// ```dart
/// @Bean()
/// CorsConfigurationSource cors() => UrlBasedCorsConfigurationSource()
///   ..registerCorsConfiguration('/api/**',
///       CorsConfiguration(allowedOrigins: ['https://shop.example']));
/// ```
final class UrlBasedCorsConfigurationSource implements CorsConfigurationSource {
  final _configurations = <(PathPattern, CorsConfiguration)>[];

  /// Applies [configuration] to the paths matching [pattern].
  void registerCorsConfiguration(
    String pattern,
    CorsConfiguration configuration,
  ) => _configurations.add((PathPattern.parse(pattern), configuration));

  @override
  CorsConfiguration? getCorsConfiguration(ServerHttpRequest request) {
    for (final (pattern, configuration) in _configurations) {
      if (pattern.matches(request.path)) {
        return configuration;
      }
    }
    return null;
  }
}

/// CORS mappings of a `WebMvcConfigurer`, like Spring's `CorsRegistry`.
///
/// ```dart
/// @override
/// void addCorsMappings(CorsRegistry registry) => registry
///     .addMapping('/api/**')
///     .allowedOrigins(['https://shop.example']);
/// ```
final class CorsRegistry {
  final _registrations = <CorsRegistration>[];

  /// Enables CORS for [pattern] with Spring's defaults (every origin,
  /// `GET`, `HEAD`, `POST`); change them on the registration.
  CorsRegistration addMapping(String pattern) {
    final registration = CorsRegistration._(pattern);
    _registrations.add(registration);
    return registration;
  }

  /// The configurations by pattern.
  UrlBasedCorsConfigurationSource toSource() {
    final source = UrlBasedCorsConfigurationSource();
    for (final registration in _registrations) {
      source.registerCorsConfiguration(
        registration.pattern,
        registration._config.applyPermitDefaultValues(),
      );
    }
    return source;
  }

  /// Whether nothing was registered.
  bool get isEmpty => _registrations.isEmpty;
}

/// One mapping of a [CorsRegistry].
final class CorsRegistration {
  CorsRegistration._(this.pattern);

  /// The path pattern.
  final String pattern;

  final _config = CorsConfiguration();

  /// Allowed origins.
  CorsRegistration allowedOrigins(List<String> origins) {
    _config.allowedOrigins.addAll(origins);
    return this;
  }

  /// Allowed origin patterns.
  CorsRegistration allowedOriginPatterns(List<String> patterns) {
    _config.allowedOriginPatterns.addAll(patterns);
    return this;
  }

  /// Allowed methods.
  CorsRegistration allowedMethods(List<String> methods) {
    _config.allowedMethods.addAll(methods);
    return this;
  }

  /// Allowed request headers.
  CorsRegistration allowedHeaders(List<String> headers) {
    _config.allowedHeaders.addAll(headers);
    return this;
  }

  /// Response headers the browser may read.
  CorsRegistration exposedHeaders(List<String> headers) {
    _config.exposedHeaders.addAll(headers);
    return this;
  }

  /// Whether credentials are allowed.
  CorsRegistration allowCredentials(bool allow) {
    _config.allowCredentials = allow;
    return this;
  }

  /// The pre-flight cache time.
  CorsRegistration maxAge(Duration maxAge) {
    _config.maxAge = maxAge;
    return this;
  }
}

/// Whether [request] is a CORS request (it has an `Origin` that differs
/// from its own scheme, host and port).
bool isCorsRequest(ServerHttpRequest request) {
  final origin = request.headers[HttpHeaders.originHeader];
  if (origin == null) {
    return false;
  }
  final parsed = Uri.tryParse(origin);
  if (parsed == null) {
    return true;
  }
  final own = request.uri;
  return parsed.scheme != own.scheme ||
      parsed.host != own.host ||
      _port(parsed) != _port(own);
}

/// Whether [request] is a CORS pre-flight (`OPTIONS` with `Origin` and
/// `Access-Control-Request-Method`).
bool isPreFlightRequest(ServerHttpRequest request) =>
    request.method == HttpMethod.options &&
    request.headers.contains(HttpHeaders.originHeader) &&
    request.headers.contains(HttpHeaders.accessControlRequestMethodHeader);

int _port(Uri uri) => uri.hasPort
    ? uri.port
    : switch (uri.scheme) {
        'https' || 'wss' => 443,
        _ => 80,
      };

/// Checks [request] against [config] and writes the CORS headers, like
/// Spring's `DefaultCorsProcessor`; `false` when it is rejected (the
/// response is then a 403).
bool processCors(
  CorsConfiguration config,
  ServerHttpRequest request,
  ServerHttpResponse response, {
  required bool preFlight,
}) {
  final headers = response.headers;
  for (final vary in [
    HttpHeaders.originHeader,
    HttpHeaders.accessControlRequestMethodHeader,
    HttpHeaders.accessControlRequestHeadersHeader,
  ]) {
    if (!headers.getAll(HttpHeaders.varyHeader).contains(vary)) {
      headers.add(HttpHeaders.varyHeader, vary);
    }
  }
  if (headers.contains(HttpHeaders.accessControlAllowOriginHeader)) {
    return true; // handled already (a filter)
  }
  final origin = request.headers[HttpHeaders.originHeader]!;
  final allowOrigin = config.checkOrigin(origin);
  if (allowOrigin == null) {
    return false;
  }
  List<String>? allowMethods;
  List<String>? allowHeaders;
  if (preFlight) {
    final requested =
        request.headers[HttpHeaders.accessControlRequestMethodHeader] ?? '';
    allowMethods = config.checkMethod(requested.trim());
    if (allowMethods == null) {
      return false;
    }
    final requestedHeaders = [
      for (final value in request.headers.getAll(
        HttpHeaders.accessControlRequestHeadersHeader,
      ))
        for (final header in value.split(','))
          if (header.trim().isNotEmpty) header.trim(),
    ];
    allowHeaders = config.checkHeaders(requestedHeaders);
    if (allowHeaders == null) {
      return false;
    }
  }
  headers.set(HttpHeaders.accessControlAllowOriginHeader, allowOrigin);
  if (preFlight) {
    headers.set(
      HttpHeaders.accessControlAllowMethodsHeader,
      allowMethods!.join(','),
    );
    if (allowHeaders!.isNotEmpty) {
      headers.set(
        HttpHeaders.accessControlAllowHeadersHeader,
        allowHeaders.join(', '),
      );
    }
    if (config.maxAge case final maxAge?) {
      headers.set(HttpHeaders.accessControlMaxAgeHeader, '${maxAge.inSeconds}');
    }
  } else if (config.exposedHeaders.isNotEmpty) {
    headers.set(
      HttpHeaders.accessControlExposeHeadersHeader,
      config.exposedHeaders.join(', '),
    );
  }
  if (config.allowCredentials ?? false) {
    headers.set(HttpHeaders.accessControlAllowCredentialsHeader, 'true');
  }
  return true;
}
