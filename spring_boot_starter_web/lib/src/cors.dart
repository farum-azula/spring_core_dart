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
/// Every cross-origin request is checked: its origin, and its method (the
/// method a pre-flight announces, or the actual request's own), so an
/// allowed origin cannot send a `DELETE` the rules do not list.
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
  /// later); [allowCredentials], [allowPrivateNetwork] and [maxAge] are
  /// unset by default.
  CorsConfiguration({
    List<String> allowedOrigins = const [],
    List<String> allowedOriginPatterns = const [],
    List<String> allowedMethods = const [],
    List<String> allowedHeaders = const [],
    List<String> exposedHeaders = const [],
    this.allowCredentials,
    this.allowPrivateNetwork,
    this.maxAge,
  }) : allowedOrigins = [...allowedOrigins],
       allowedOriginPatterns = [...allowedOriginPatterns],
       allowedMethods = [...allowedMethods],
       allowedHeaders = [...allowedHeaders],
       exposedHeaders = [...exposedHeaders];

  /// The rules of a `@CrossOrigin` annotation. Without `methods`, the
  /// methods the handler is mapped to are allowed ([mappedMethods], as
  /// the router passes them), as in Spring; what is still left out gets
  /// the defaults of [applyPermitDefaultValues]: every origin, `GET`,
  /// `HEAD` and `POST` (when [mappedMethods] is empty too), every header,
  /// 30 minutes. The [maxAge] of the annotation is in seconds.
  factory CorsConfiguration.fromAnnotation(
    CrossOrigin annotation, {
    List<String> mappedMethods = const [],
  }) {
    final config = CorsConfiguration(
      allowedOrigins: annotation.origins,
      allowedOriginPatterns: annotation.originPatterns,
      allowedMethods: annotation.methods,
      allowedHeaders: annotation.allowedHeaders,
      exposedHeaders: annotation.exposedHeaders,
      allowCredentials: annotation.allowCredentials,
      allowPrivateNetwork: annotation.allowPrivateNetwork,
      maxAge: annotation.maxAge == null
          ? null
          : Duration(seconds: annotation.maxAge!),
    );
    if (config.allowedMethods.isEmpty) {
      config.allowedMethods.addAll(mappedMethods);
    }
    return config.applyPermitDefaultValues();
  }

  /// Origins allowed to call, compared without case
  /// (`https://shop.example`); `*` allows any origin, but not together
  /// with [allowCredentials]. As in Spring, a value may list several,
  /// separated by commas (`'https://a.example, https://b.example'`), and
  /// a trailing `/` is ignored. [checkOrigin] reads them as
  /// [AllowedOrigins] does; the list keeps the values as given.
  final List<String> allowedOrigins;

  /// Origins allowed by pattern, for families of origins, compared with
  /// case: `*` matches any text, as Spring's `.*` (`https://*.example`,
  /// `*.example`), and a port list at the end the ports listed or, with
  /// `[*]`, any port or none (`http://localhost:[3000,3001]`,
  /// `http://localhost:[*]`). Commas and a trailing `/` as in
  /// [allowedOrigins]. The matched origin itself is echoed back, so
  /// patterns work with [allowCredentials]. See [AllowedOrigins], and its
  /// one difference from Spring (an origin longer than 1024 characters is
  /// never allowed).
  final List<String> allowedOriginPatterns;

  /// Methods allowed (`GET`, `DELETE`, ...), compared with case: the one
  /// a pre-flight asks for, and an actual cross-origin request's own (a
  /// `HEAD` too: allow it with `GET` where needed). `*` allows any. Empty
  /// allows `GET` and `HEAD`.
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

  /// Whether a page of a public site may call this server on a private
  /// network (a server on `localhost` or the office network): to a
  /// pre-flight with `Access-Control-Request-Private-Network: true`
  /// (Chrome's Private Network Access) the answer then adds
  /// `Access-Control-Allow-Private-Network: true`. `null` and `false` both
  /// mean no. Like [allowCredentials], it cannot be used with `*` in
  /// [allowedOrigins]: list the origins or use [allowedOriginPatterns].
  ///
  /// Spring (Java): `setAllowPrivateNetwork`.
  bool? allowPrivateNetwork;

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
      allowedOrigins.addAll(_permitAll);
      _defaults.add(_origins);
    }
    if (allowedMethods.isEmpty) {
      allowedMethods.addAll(_permitMethods);
      _defaults.add(_methods);
    }
    if (allowedHeaders.isEmpty) {
      allowedHeaders.addAll(_permitAll);
      _defaults.add(_headers);
    }
    maxAge ??= const Duration(minutes: 30);
    return this;
  }

  static const _permitAll = ['*'];
  static const _permitMethods = ['GET', 'HEAD', 'POST'];
  static const _origins = 'origins';
  static const _methods = 'methods';
  static const _headers = 'headers';

  // The lists [applyPermitDefaultValues] filled (Spring's
  // DEFAULT_PERMIT_ALL and DEFAULT_PERMIT_METHODS markers): in [combine]
  // they give way to the other side's values.
  final _defaults = <String>{};

  bool _isDefault(String rule) {
    final (list, expected) = switch (rule) {
      _origins => (allowedOrigins, _permitAll),
      _methods => (allowedMethods, _permitMethods),
      _ => (allowedHeaders, _permitAll),
    };
    return _defaults.contains(rule) &&
        list.length == expected.length &&
        list.indexed.every((e) => e.$2 == expected[e.$1]);
  }

  /// A new configuration with the rules of this one and of [other], the
  /// more specific one: a method's `@CrossOrigin` over the class's, a
  /// handler's over the global configuration.
  ///
  /// As in Spring, a list that only holds the defaults of
  /// [applyPermitDefaultValues] gives way to the other side's list, so an
  /// `@CrossOrigin()` without `origins` keeps the global origins instead
  /// of widening them to `*`. Other lists are merged (a `*` in either
  /// makes the result `*`); an empty list takes the other's.
  /// [other]'s [allowCredentials], [allowPrivateNetwork] and [maxAge] win
  /// when set. A `null` [other] returns this configuration itself.
  CorsConfiguration combine(CorsConfiguration? other) {
    if (other == null) {
      return this;
    }
    final defaults = <String>{};
    List<String> merge(List<String> a, List<String> b, [String? rule]) {
      final aDefault = rule != null && _isDefault(rule);
      final bDefault = rule != null && other._isDefault(rule);
      if (b.isEmpty || (bDefault && a.isNotEmpty && !aDefault)) {
        if (aDefault) {
          defaults.add(rule);
        }
        return a;
      }
      if (a.isEmpty || aDefault) {
        if (bDefault) {
          defaults.add(rule);
        }
        return b;
      }
      if (a.contains('*') || b.contains('*')) {
        return ['*'];
      }
      return {...a, ...b}.toList();
    }

    final patterns = merge(allowedOriginPatterns, other.allowedOriginPatterns);
    var origins = merge(allowedOrigins, other.allowedOrigins, _origins);
    if (defaults.contains(_origins) && patterns.isNotEmpty) {
      // Default origins next to patterns: the patterns alone, as Spring.
      origins = const [];
      defaults.remove(_origins);
    }
    final combined = CorsConfiguration(
      allowedOrigins: origins,
      allowedOriginPatterns: patterns,
      allowedMethods: merge(allowedMethods, other.allowedMethods, _methods),
      allowedHeaders: merge(allowedHeaders, other.allowedHeaders, _headers),
      exposedHeaders: merge(exposedHeaders, other.exposedHeaders),
      allowCredentials: other.allowCredentials ?? allowCredentials,
      allowPrivateNetwork: other.allowPrivateNetwork ?? allowPrivateNetwork,
      maxAge: other.maxAge ?? maxAge,
    );
    combined._defaults.addAll(defaults);
    return combined;
  }

  /// The `Access-Control-Allow-Origin` value to answer a request from
  /// [origin]: `*` when any origin is allowed, the origin itself (as
  /// sent) when it is listed or matches a pattern, `null` when it is not
  /// allowed (or blank). The check is [AllowedOrigins.checkOrigin], as
  /// Spring's `CorsConfiguration.checkOrigin`.
  ///
  /// Throws a [StateError] when [allowedOrigins] has `*` and
  /// [allowCredentials] or [allowPrivateNetwork] is true: browsers refuse
  /// the first combination, and the second would open a private network
  /// to every site, so list the origins or use [allowedOriginPatterns].
  String? checkOrigin(String origin) {
    final allowed = _allowed.checkOrigin(
      origin,
      allowCredentials: allowCredentials ?? false,
    );
    if (allowed == '*') {
      validateAllowPrivateNetwork();
    }
    return allowed;
  }

  /// Throws a [StateError] when [allowCredentials] is true and
  /// [allowedOrigins] holds `*` (in any of its comma-separated values):
  /// the `Access-Control-Allow-Origin` header cannot be `*` then. The
  /// router checks a handler's configuration at startup, and every
  /// configuration it applies before it handles the request, as Spring.
  ///
  /// Spring (Java): `validateAllowCredentials`.
  void validateAllowCredentials() {
    if ((allowCredentials ?? false) && _allowed.allowsAnyOrigin) {
      throw StateError(
        'When allowCredentials is true, allowedOrigins cannot contain "*" '
        '(the Access-Control-Allow-Origin header cannot be "*" then); list '
        'the origins or use allowedOriginPatterns.',
      );
    }
  }

  /// Throws a [StateError] when [allowPrivateNetwork] is true and
  /// [allowedOrigins] holds `*`: any site could then reach the private
  /// network. Checked like [validateAllowCredentials].
  ///
  /// Spring (Java): `validateAllowPrivateNetwork`.
  void validateAllowPrivateNetwork() {
    if ((allowPrivateNetwork ?? false) && _allowed.allowsAnyOrigin) {
      throw StateError(
        'When allowPrivateNetwork is true, allowedOrigins cannot contain "*" '
        '(every site could reach the private network); list the origins or '
        'use allowedOriginPatterns.',
      );
    }
  }

  // The origins of the lists as they are now: rebuilt when they changed.
  AllowedOrigins get _allowed {
    final cached = _cachedOrigins;
    if (cached != null &&
        _same(cached.$1, allowedOrigins) &&
        _same(cached.$2, allowedOriginPatterns)) {
      return cached.$3;
    }
    final origins = AllowedOrigins(
      allowedOrigins: allowedOrigins,
      allowedOriginPatterns: allowedOriginPatterns,
    );
    _cachedOrigins = ([...allowedOrigins], [...allowedOriginPatterns], origins);
    return origins;
  }

  (List<String>, List<String>, AllowedOrigins)? _cachedOrigins;

  static bool _same(List<String> a, List<String> b) =>
      a.length == b.length && a.indexed.every((e) => e.$2 == b[e.$1]);

  /// The `Access-Control-Allow-Methods` list for [method] (the method a
  /// pre-flight asks for, or an actual request's own), or `null` when
  /// that method is not allowed: then the request gets a 403. With `*`
  /// the list is [method] alone; empty [allowedMethods] allow `GET` and
  /// `HEAD`. Spring's `checkHttpMethod`.
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
}

/// Finds the [CorsConfiguration] that applies to a request.
///
/// Declare a bean of this type named `corsConfigurationSource` to set CORS
/// rules for the whole application, without annotating every controller.
/// Where it returns a configuration for a request, that configuration
/// alone applies: the security starter's CORS filter applies it, as Spring
/// Security applies its `corsConfigurationSource` bean, and the router the
/// same way (Spring MVC leaves a request the filter answered as it is), so
/// neither the handler's `@CrossOrigin` nor the `WebMvcConfigurer`
/// mappings widen it. Where it returns `null`, those apply. As in Spring
/// Security, the name counts: beans of this type with other names are
/// ignored (several never fail the start). Most applications use
/// [UrlBasedCorsConfigurationSource] rather than implementing this.
///
/// ```dart
/// // The allowed origins are the tenants' sites, which change at runtime.
/// @Component('corsConfigurationSource')
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
/// @Component("corsConfigurationSource")
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
/// Its rules are combined with the `@CrossOrigin` of the handler, as
/// Spring MVC combines its global CORS configuration. When there is also
/// a `CorsConfigurationSource` bean named `corsConfigurationSource`, the
/// bean's rules alone apply to the requests it has a configuration for.
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

  /// Adds methods allowed (`PUT`, `DELETE`, or `*`), for pre-flights and
  /// actual requests. Without any, `GET`, `HEAD` and `POST` are allowed.
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

  /// Whether pages of public sites may call this server on a private
  /// network (Chrome's Private Network Access); see
  /// [CorsConfiguration.allowPrivateNetwork]. Not allowed by default; with
  /// `true`, list the origins or use patterns instead of `*`.
  CorsRegistration allowPrivateNetwork(bool allow) {
    _config.allowPrivateNetwork = allow;
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
/// [processCors] checks only such requests against the CORS rules (other
/// requests just get `Vary`); a filter that handles CORS itself can use
/// it the same way.
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

/// Checks [request] against [config] and writes the CORS headers into
/// [response]; returns `false` when the request is not allowed, and the
/// caller then answers 403.
///
/// Call it for every request [config] applies to, a CORS request or not,
/// as Spring calls its `DefaultCorsProcessor`: the answer always gets
/// `Vary: Origin, Access-Control-Request-Method,
/// Access-Control-Request-Headers` (each name only once, with the values
/// already there), so a cache does not give the answer to one origin, or
/// to a request without `Origin`, to another. A request that is not a
/// CORS request ([isCorsRequest] false) is then allowed with nothing else
/// written.
///
/// A CORS request is checked as Spring's `DefaultCorsProcessor` checks
/// it: its origin, then its method ([CorsConfiguration.checkMethod]):
/// [preFlight] says whether the request is a pre-flight, whose announced
/// method (`Access-Control-Request-Method`) and headers are checked, and
/// whose answer gets `Access-Control-Allow-Methods`, `-Allow-Headers` and
/// `-Max-Age`; otherwise the request's own method is checked, so a
/// `DELETE` (or a `HEAD`, an `OPTIONS`) the rules do not allow is refused
/// even from an allowed origin. Both get `Access-Control-Expose-Headers`,
/// `-Allow-Credentials`, and, when [CorsConfiguration.allowPrivateNetwork]
/// is on and the request has `Access-Control-Request-Private-Network:
/// true`, `Access-Control-Allow-Private-Network: true`. When the response
/// already has an `Access-Control-Allow-Origin` (a filter handled CORS),
/// nothing else is written and the result is `true`.
///
/// An `Origin` with a character other than visible US-ASCII (a space, a
/// control character, a letter beyond ASCII) is refused, as Spring
/// refuses an `Origin` it cannot parse, and so is a pre-flight that asks
/// for such a method or request header: no browser sends one, and the
/// answer could not echo it in a header.
///
/// The router calls it for every request to a handler with CORS rules,
/// and the security starter's CORS filter for every request with CORS
/// rules; a filter that answers requests itself can too. Spring's
/// counterpart is `DefaultCorsProcessor.processRequest`.
bool processCors(
  CorsConfiguration config,
  ServerHttpRequest request,
  ServerHttpResponse response, {
  required bool preFlight,
}) {
  final headers = response.headers;
  addVary(headers, const [
    HttpHeaders.originHeader,
    HttpHeaders.accessControlRequestMethodHeader,
    HttpHeaders.accessControlRequestHeadersHeader,
  ]);
  final origin = request.headers[HttpHeaders.originHeader];
  if (origin != null && !_isVisibleAscii(origin)) {
    return false; // malformed: Spring's "Reject: origin is malformed"
  }
  if (!isCorsRequest(request)) {
    return true;
  }
  if (headers.contains(HttpHeaders.accessControlAllowOriginHeader)) {
    return true; // handled already (a filter)
  }
  final allowOrigin = config.checkOrigin(origin!);
  if (allowOrigin == null) {
    return false;
  }
  // Spring's getMethodToUse: the announced method of a pre-flight, the
  // request's own otherwise.
  final method = preFlight
      ? (request.headers[HttpHeaders.accessControlRequestMethodHeader] ?? '')
            .trim()
      : request.method.value;
  if (!_isVisibleAscii(method)) {
    return false;
  }
  final allowMethods = config.checkMethod(method);
  if (allowMethods == null) {
    return false;
  }
  List<String>? allowHeaders;
  if (preFlight) {
    final requestedHeaders = [
      for (final value in request.headers.getAll(
        HttpHeaders.accessControlRequestHeadersHeader,
      ))
        for (final header in value.split(','))
          if (header.trim().isNotEmpty) header.trim(),
    ];
    if (!requestedHeaders.every(_isVisibleAscii)) {
      return false;
    }
    allowHeaders = config.checkHeaders(requestedHeaders);
    if (allowHeaders == null) {
      return false;
    }
  }
  headers.set(HttpHeaders.accessControlAllowOriginHeader, allowOrigin);
  if (preFlight) {
    headers.set(
      HttpHeaders.accessControlAllowMethodsHeader,
      allowMethods.join(','),
    );
    if (allowHeaders!.isNotEmpty) {
      headers.set(
        HttpHeaders.accessControlAllowHeadersHeader,
        allowHeaders.join(', '),
      );
    }
  }
  if (config.exposedHeaders.isNotEmpty) {
    headers.set(
      HttpHeaders.accessControlExposeHeadersHeader,
      config.exposedHeaders.join(', '),
    );
  }
  if (config.allowCredentials ?? false) {
    headers.set(HttpHeaders.accessControlAllowCredentialsHeader, 'true');
  }
  if ((config.allowPrivateNetwork ?? false) &&
      (request.headers[_requestPrivateNetwork] ?? '').toLowerCase() == 'true') {
    headers.set(_allowPrivateNetwork, 'true');
  }
  if (config.maxAge case final maxAge? when preFlight) {
    headers.set(HttpHeaders.accessControlMaxAgeHeader, '${maxAge.inSeconds}');
  }
  return true;
}

// Chrome's Private Network Access headers, as Spring's
// DefaultCorsProcessor names them.
const _requestPrivateNetwork = 'Access-Control-Request-Private-Network';
const _allowPrivateNetwork = 'Access-Control-Allow-Private-Network';

// Whether [value] has only visible US-ASCII characters (`!` to `~`).
bool _isVisibleAscii(String value) =>
    value.codeUnits.every((unit) => unit > 0x20 && unit < 0x7F);

/// Adds the names of [values] (each a name or a comma-separated list) to
/// the `Vary` header of [headers], each unless it is there already, in
/// any of its values or case, or `Vary` is `*`.
///
/// How the CORS processing adds its names, and how a handler's own
/// `Vary` (a `ResponseEntity`'s, an `ErrorResponse`'s) joins the names
/// already there, as Spring's `HttpEntityMethodProcessor` merges them.
/// Not exported: `package:spring_boot_starter_web/spring_boot_starter_web.dart`
/// hides it.
void addVary(HttpHeaders headers, Iterable<String> values) {
  final present = {
    for (final value in headers.getAll(HttpHeaders.varyHeader))
      for (final name in value.split(','))
        if (name.trim().isNotEmpty) name.trim().toLowerCase(),
  };
  if (present.contains('*')) {
    return;
  }
  for (final value in values) {
    for (final name in value.split(',')) {
      final trimmed = name.trim();
      if (trimmed.isNotEmpty && present.add(trimmed.toLowerCase())) {
        headers.add(HttpHeaders.varyHeader, trimmed);
      }
    }
  }
}
