import 'package:spring_web_dart/spring_web_dart.dart';

/// The CORS rules for some paths: which other origins may call them from a
/// browser, with which methods and headers, and whether with cookies.
///
/// A browser keeps a page of `https://shop.example` from reading the
/// answers of `https://api.example` unless the server allows it with
/// `Access-Control-Allow-...` headers; for most requests it first sends
/// an `OPTIONS` "pre-flight" to ask. A configuration says what to allow;
/// the server checks each cross-origin request against it, writes the
/// headers, and answers 403 to what it does not allow.
///
/// Most applications put `@CrossOrigin()` on a controller, or list rules
/// in `WebMvcConfigurer.addCorsMappings`, and the starter builds the
/// configurations. Build one yourself for a [CorsConfigurationSource]
/// bean, usually a [UrlBasedCorsConfigurationSource]. An empty list
/// allows no origin and no request header; empty [allowedMethods] allow
/// `GET` and `HEAD`. [applyPermitDefaultValues] fills the empty lists
/// with permissive defaults.
///
/// ```dart
/// // The shop's pages may read and write the API with their cookies.
/// final config = CorsConfiguration(
///   allowedOrigins: ['https://shop.example'],
///   allowedMethods: ['GET', 'POST'],
///   allowedHeaders: ['*'],
///   allowCredentials: true,
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// CorsConfiguration config = new CorsConfiguration();
/// config.setAllowedOrigins(List.of("https://shop.example"));
/// config.setAllowedMethods(List.of("GET", "POST"));
/// config.setAllowedHeaders(List.of("*"));
/// config.setAllowCredentials(true);
/// ```
final class CorsConfiguration {
  /// A configuration with the given lists (copied, so they can grow
  /// later); [allowCredentials] and [maxAge] are unset by default.
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

  /// The rules of a `@CrossOrigin` annotation, with the defaults of
  /// [applyPermitDefaultValues] for what it leaves out: every origin,
  /// `GET`, `HEAD` and `POST`, every header, 30 minutes. (Spring defaults
  /// the methods to those of the handler instead.) The [maxAge] of the
  /// annotation is in seconds.
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

  /// Origins allowed to call, compared without case
  /// (`https://shop.example`); `*` allows any origin, but not together
  /// with [allowCredentials].
  final List<String> allowedOrigins;

  /// Origins allowed by pattern, for families of origins: `*` matches any
  /// text and `[*]` any port number (`https://*.example`,
  /// `http://localhost:[*]`). The matched origin itself is echoed back,
  /// so patterns work with [allowCredentials].
  final List<String> allowedOriginPatterns;

  /// Methods a pre-flight may ask for (`GET`, `DELETE`, ...); `*` allows
  /// any. Empty allows `GET` and `HEAD`.
  final List<String> allowedMethods;

  /// Request headers a pre-flight may ask for (`Authorization`, ...),
  /// compared without case; `*` allows any.
  final List<String> allowedHeaders;

  /// Response headers, beyond the simple ones, that the page's script may
  /// read (`Access-Control-Expose-Headers`), such as `Location`.
  final List<String> exposedHeaders;

  /// Whether the browser may send cookies and other credentials, and let
  /// the page read the answer (`Access-Control-Allow-Credentials: true`).
  /// `null` and `false` both mean no.
  bool? allowCredentials;

  /// How long the browser may cache a pre-flight answer
  /// (`Access-Control-Max-Age`); `null` sends no such header.
  Duration? maxAge;

  /// Fills what is not set with permissive defaults and returns this
  /// configuration: every origin (when no origin nor pattern is set),
  /// `GET`, `HEAD` and `POST`, every header, and 30 minutes of pre-flight
  /// cache. Used for `@CrossOrigin` and for the mappings of a
  /// [CorsRegistry], so that a bare declaration allows a simple
  /// cross-origin API.
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

  /// A new configuration with the rules of this one and of [other], the
  /// more specific one: a method's `@CrossOrigin` over the class's, a
  /// handler's over the global configuration.
  ///
  /// The lists are merged (a `*` in either makes the result `*`);
  /// [other]'s [allowCredentials] and [maxAge] win when set. A `null`
  /// [other] returns this configuration itself.
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

  /// The `Access-Control-Allow-Origin` value to answer a request from
  /// [origin]: `*` when any origin is allowed, the origin itself when it
  /// is listed or matches a pattern, `null` when it is not allowed (or
  /// blank).
  ///
  /// Throws a [StateError] when [allowedOrigins] has `*` and
  /// [allowCredentials] is true: browsers refuse that combination, so
  /// list the origins or use [allowedOriginPatterns].
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

  /// The `Access-Control-Allow-Methods` list for a pre-flight that asks
  /// for [method], or `null` when that method is not allowed. With `*` the
  /// list is [method] alone; empty [allowedMethods] allow `GET` and
  /// `HEAD`.
  List<String>? checkMethod(String method) {
    final methods = allowedMethods.isEmpty
        ? const ['GET', 'HEAD']
        : allowedMethods;
    if (methods.contains('*')) {
      return [method];
    }
    return methods.contains(method) ? methods : null;
  }

  /// The `Access-Control-Allow-Headers` list for a pre-flight that asks
  /// for the [requested] headers: [requested] itself when all are allowed,
  /// `null` when any one is not. Nothing requested gives an empty list.
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

/// Finds the [CorsConfiguration] that applies to a request.
///
/// Declare a bean of this type to set CORS rules for the whole
/// application, without annotating every controller. The router combines
/// what it returns with the `@CrossOrigin` of the handler, and the
/// security starter's `cors()` uses the same bean. Most applications use
/// [UrlBasedCorsConfigurationSource] rather than implementing this.
///
/// ```dart
/// // The allowed origins are the tenants' sites, which change at runtime.
/// @Component()
/// final class TenantCors implements CorsConfigurationSource {
///   TenantCors(this.tenants);
///   final TenantService tenants;
///
///   @override
///   CorsConfiguration? getCorsConfiguration(ServerHttpRequest request) =>
///       CorsConfiguration(allowedOrigins: tenants.origins())
///         ..applyPermitDefaultValues();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class TenantCors implements CorsConfigurationSource {
///   public CorsConfiguration getCorsConfiguration(
///       HttpServletRequest request) { ... }
/// }
/// ```
abstract interface class CorsConfigurationSource {
  /// The rules for [request], or `null` when no CORS rule applies: such a
  /// request is then handled without CORS headers (and the browser keeps
  /// the answer from the page).
  CorsConfiguration? getCorsConfiguration(ServerHttpRequest request);
}

/// A [CorsConfigurationSource] that picks the configuration by the
/// request's path.
///
/// It is the usual way to declare global CORS rules: register one
/// configuration per path pattern (`/api/**`) and declare the source as a
/// bean. Patterns are tried in the order they were registered; the first
/// that matches the path wins.
///
/// ```dart
/// // Every API path may be called from the shop's pages.
/// @Bean()
/// CorsConfigurationSource corsConfigurationSource() =>
///     UrlBasedCorsConfigurationSource()
///       ..registerCorsConfiguration(
///         '/api/**',
///         CorsConfiguration(allowedOrigins: ['https://shop.example'])
///           ..applyPermitDefaultValues(),
///       );
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// CorsConfigurationSource corsConfigurationSource() {
///   CorsConfiguration config = new CorsConfiguration();
///   config.setAllowedOrigins(List.of("https://shop.example"));
///   var source = new UrlBasedCorsConfigurationSource();
///   source.registerCorsConfiguration(
///       "/api/**", config.applyPermitDefaultValues());
///   return source;
/// }
/// ```
final class UrlBasedCorsConfigurationSource implements CorsConfigurationSource {
  final _configurations = <(PathPattern, CorsConfiguration)>[];

  /// Applies [configuration] to the paths matching [pattern], a path
  /// pattern such as `/api/**` or `/books/{isbn}`. The configuration is
  /// used as it is: call [CorsConfiguration.applyPermitDefaultValues] on
  /// it for the permissive defaults.
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

/// The list of global CORS rules a `WebMvcConfigurer` fills in its
/// `addCorsMappings` method.
///
/// It is a builder-style alternative to a [CorsConfigurationSource] bean:
/// each [addMapping] enables CORS for a path pattern, and its
/// [CorsRegistration] narrows the rules. The starter creates the registry,
/// hands it to every `WebMvcConfigurer` bean, and turns it into a source.
/// When there is also a `CorsConfigurationSource` bean, both apply: for a
/// path they both cover, their rules are combined.
///
/// ```dart
/// @Configuration()
/// class WebConfig with WebMvcConfigurer {
///   // The shop's pages may call the API, also to change data.
///   @override
///   void addCorsMappings(CorsRegistry registry) => registry
///       .addMapping('/api/**')
///       .allowedOrigins(['https://shop.example'])
///       .allowedMethods(['GET', 'POST', 'PUT', 'DELETE']);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Configuration
/// class WebConfig implements WebMvcConfigurer {
///   @Override
///   public void addCorsMappings(CorsRegistry registry) {
///     registry.addMapping("/api/**")
///         .allowedOrigins("https://shop.example")
///         .allowedMethods("GET", "POST", "PUT", "DELETE");
///   }
/// }
/// ```
final class CorsRegistry {
  final _registrations = <CorsRegistration>[];

  /// Enables CORS for the paths matching [pattern] (such as `/api/**`)
  /// and returns the registration to narrow its rules. What the
  /// registration leaves unset gets the defaults of
  /// [CorsConfiguration.applyPermitDefaultValues]: every origin, `GET`,
  /// `HEAD` and `POST`, every header, 30 minutes.
  CorsRegistration addMapping(String pattern) {
    final registration = CorsRegistration._(pattern);
    _registrations.add(registration);
    return registration;
  }

  /// A source with one configuration per mapping, in the order they were
  /// added, with the defaults filled in. The starter calls it once all
  /// `WebMvcConfigurer`s have run.
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

  /// Whether no mapping was added; the starter then uses no source from
  /// the registry.
  bool get isEmpty => _registrations.isEmpty;
}

/// The CORS rules of one path pattern of a [CorsRegistry], set with
/// chained calls.
///
/// It comes from [CorsRegistry.addMapping]; each method sets one rule of
/// the underlying [CorsConfiguration] and returns the registration, so
/// calls chain. The list methods add to what is already there (Spring's
/// replace it).
///
/// ```dart
/// // Pages of any subdomain may call with cookies and read `Location`.
/// registry
///     .addMapping('/api/**')
///     .allowedOriginPatterns(['https://*.shop.example'])
///     .exposedHeaders(['Location'])
///     .allowCredentials(true);
/// ```
///
/// Spring (Java):
/// ```java
/// registry.addMapping("/api/**")
///     .allowedOriginPatterns("https://*.shop.example")
///     .exposedHeaders("Location")
///     .allowCredentials(true);
/// ```
final class CorsRegistration {
  CorsRegistration._(this.pattern);

  /// The path pattern given to [CorsRegistry.addMapping].
  final String pattern;

  final _config = CorsConfiguration();

  /// Adds origins allowed to call (`https://shop.example`, or `*` for
  /// any); see [CorsConfiguration.allowedOrigins].
  CorsRegistration allowedOrigins(List<String> origins) {
    _config.allowedOrigins.addAll(origins);
    return this;
  }

  /// Adds origin patterns (`https://*.example`, `http://localhost:[*]`);
  /// see [CorsConfiguration.allowedOriginPatterns].
  CorsRegistration allowedOriginPatterns(List<String> patterns) {
    _config.allowedOriginPatterns.addAll(patterns);
    return this;
  }

  /// Adds methods a pre-flight may ask for (`PUT`, `DELETE`, or `*`).
  /// Without any, `GET`, `HEAD` and `POST` are allowed.
  CorsRegistration allowedMethods(List<String> methods) {
    _config.allowedMethods.addAll(methods);
    return this;
  }

  /// Adds request headers a pre-flight may ask for. Without any, every
  /// header is allowed.
  CorsRegistration allowedHeaders(List<String> headers) {
    _config.allowedHeaders.addAll(headers);
    return this;
  }

  /// Adds response headers the page's script may read, such as
  /// `Location`.
  CorsRegistration exposedHeaders(List<String> headers) {
    _config.exposedHeaders.addAll(headers);
    return this;
  }

  /// Whether the browser may send cookies with its requests and let the
  /// page read the answer. Not allowed by default; with `true`, list the
  /// origins or use patterns instead of `*`.
  CorsRegistration allowCredentials(bool allow) {
    _config.allowCredentials = allow;
    return this;
  }

  /// How long the browser may cache a pre-flight answer; 30 minutes by
  /// default.
  CorsRegistration maxAge(Duration maxAge) {
    _config.maxAge = maxAge;
    return this;
  }
}

/// Whether [request] comes from a page of another origin: it has an
/// `Origin` header whose scheme, host or port differs from the request's
/// own (an `Origin` that does not parse counts as another origin).
///
/// The router checks CORS rules only for such requests; a filter that
/// handles CORS itself can use it the same way.
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

/// Whether [request] is the question a browser asks before a cross-origin
/// call (a "pre-flight"): an `OPTIONS` request with an `Origin` and an
/// `Access-Control-Request-Method` header.
///
/// A pre-flight is answered from the CORS rules of the request it
/// announces, never passed to a handler.
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

/// Checks a cross-origin [request] against [config] and writes the CORS
/// headers into [response]; returns `false` when the request is not
/// allowed, and the caller then answers 403.
///
/// [preFlight] says whether the request is a pre-flight: then the
/// requested method and headers are checked too, and the answer gets
/// `Access-Control-Allow-Methods`, `-Allow-Headers` and `-Max-Age`.
/// Otherwise the answer gets `Access-Control-Expose-Headers`. `Vary`
/// always lists the CORS request headers, so caches keep answers to
/// different origins apart. When the response already has an
/// `Access-Control-Allow-Origin` (a filter handled CORS), nothing else is
/// written and the result is `true`.
///
/// The router calls it; a filter that answers requests itself can too.
/// Spring's counterpart is `DefaultCorsProcessor`.
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
