import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/cors.dart';
import 'package:spring_boot_starter_web/src/handler_mapping_descriptions.dart';
import 'package:spring_boot_starter_web/src/response_writer.dart';
import 'package:spring_boot_starter_web/src/static_files_stub.dart'
    if (dart.library.io) 'package:spring_boot_starter_web/src/static_files_io.dart';
import 'package:spring_boot_starter_web/src/static_resource_path.dart';
import 'package:spring_boot_starter_web/src/web_exceptions.dart';
import 'package:spring_boot_starter_web/src/web_logging.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog(
  'spring.web.servlet.resource.ResourceHttpRequestHandler',
);

/// The mappings of static resources a `WebMvcConfigurer` adds in
/// `addResourceHandlers`: path patterns, the locations their files come
/// from and how they are cached.
///
/// The starter maps `spring.web.resources.static-locations` under
/// `spring.mvc.static-path-pattern` (`/**`) by itself; add a mapping here
/// for another pattern (files under `/docs/**` from another directory) or
/// other caching (fingerprinted files cached for a year). A registration
/// with the same pattern as the default replaces it. When several
/// patterns match a request, the most specific one serves it.
///
/// ```dart
/// @Configuration()
/// class WebConfig with WebMvcConfigurer {
///   // The built Flutter web app under /app/, its fingerprinted assets
///   // cached for a year.
///   @override
///   void addResourceHandlers(ResourceHandlerRegistry registry) {
///     registry
///         .addResourceHandler(['/app/**'])
///         .addResourceLocations(['file:build/web/']);
///     registry
///         .addResourceHandler(['/app/assets/**'])
///         .addResourceLocations(['file:build/web/assets/'])
///         .setCacheControl(
///           CacheControl.maxAge(const Duration(days: 365)).immutable(),
///         );
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Configuration
/// class WebConfig implements WebMvcConfigurer {
///   @Override
///   public void addResourceHandlers(ResourceHandlerRegistry registry) {
///     registry.addResourceHandler("/app/**")
///         .addResourceLocations("file:build/web/");
///   }
/// }
/// ```
final class ResourceHandlerRegistry {
  final _registrations = <ResourceHandlerRegistration>[];

  /// Adds a mapping for [pathPatterns] (`/docs/**`); the returned
  /// registration takes its locations and caching.
  ResourceHandlerRegistration addResourceHandler(List<String> pathPatterns) {
    final registration = ResourceHandlerRegistration._(
      List.unmodifiable(pathPatterns),
    );
    _registrations.add(registration);
    return registration;
  }

  /// Whether a registration maps exactly [pathPattern].
  bool hasMappingForPattern(String pathPattern) =>
      _registrations.any((r) => r.pathPatterns.contains(pathPattern));

  /// The registrations in the order they were added (read-only).
  List<ResourceHandlerRegistration> get registrations =>
      List.unmodifiable(_registrations);
}

/// One mapping of a [ResourceHandlerRegistry]: its path patterns, its
/// locations, and the caching of its answers, set with chained calls.
///
/// Locations are `resources:` folders of `lib/resources/` (embedded by
/// the generator: `resources:static/`) or `file:` directories read at run
/// time (`file:build/web/`, `file:/srv/site/`); a missing trailing `/` is
/// added. The first location that has the file serves it. Any other
/// prefix, and `resources:` alone (it would serve the configuration
/// files), stop the start.
final class ResourceHandlerRegistration {
  ResourceHandlerRegistration._(this.pathPatterns);

  /// The path patterns this registration maps.
  final List<String> pathPatterns;

  final _locations = <String>[];

  /// The `max-age` of the answers in seconds (`0`: `no-store`), or `null`
  /// for no `Cache-Control`; [cacheControl] wins over it.
  int? cachePeriod;

  /// The `Cache-Control` of the answers, or `null`.
  CacheControl? cacheControl;

  /// Whether the files' modification time is sent as `Last-Modified`.
  bool useLastModified = true;

  /// Whether precompressed `.br` and `.gz` files next to the ones asked
  /// for are served to clients that take them.
  bool compressed = false;

  /// The locations, in order.
  List<String> get locations => List.unmodifiable(_locations);

  /// Adds [locations] after those already added. Returns this
  /// registration.
  ResourceHandlerRegistration addResourceLocations(List<String> locations) {
    _locations.addAll(locations);
    return this;
  }

  /// Sets `Cache-Control: max-age=<seconds>` ([seconds] `0`: `no-store`,
  /// `null`: none). Returns this registration.
  ResourceHandlerRegistration setCachePeriod(int? seconds) {
    cachePeriod = seconds;
    return this;
  }

  /// Sets the `Cache-Control` of the answers; it wins over
  /// [setCachePeriod]. Returns this registration.
  ResourceHandlerRegistration setCacheControl(CacheControl? cacheControl) {
    this.cacheControl = cacheControl;
    return this;
  }

  /// Whether `Last-Modified` is sent and `If-Modified-Since` checked
  /// (`true` by default). Returns this registration.
  ResourceHandlerRegistration setUseLastModified(bool useLastModified) {
    this.useLastModified = useLastModified;
    return this;
  }

  /// Serves precompressed `.br` / `.gz` files next to the ones asked for
  /// (`spring.web.resources.chain.compressed` for the default mapping).
  /// Spring configures the same with `resourceChain(true)
  /// .addResolver(new EncodedResourceResolver())`. Returns this
  /// registration.
  ResourceHandlerRegistration setCompressed(bool compressed) {
    this.compressed = compressed;
    return this;
  }

  /// The handler that serves this registration's files, with the media
  /// types of [mimeMappings] (`server.mime-mappings`) on top of the
  /// built-in ones. Throws an [ArgumentError] for a location it cannot
  /// read.
  ResourceHttpRequestHandler getRequestHandler({
    Map<String, String> mimeMappings = const {},
  }) => ResourceHttpRequestHandler(
    locations: _locations,
    cacheControl: cacheControl?.headerValue == null ? null : cacheControl,
    cacheSeconds: cachePeriod,
    useLastModified: useLastModified,
    compressed: compressed,
    mimeMappings: mimeMappings,
  );
}

/// A static resource a [ResourceHttpRequestHandler] found: the content and
/// what its answer needs.
final class StaticResource {
  StaticResource._(this.resource, this.filename, this._eTag, this._variant);

  /// The content: a `FileSystemResource` (the file with its symbolic
  /// links resolved) or an embedded `resources:` file.
  final Resource resource;

  /// The file name the request asked for, which decides the media type.
  final String filename;

  final String Function() _eTag;
  final StaticResource? Function(String extension) _variant;

  /// The weak `ETag` of the content: its length and modification time for
  /// a file, its length and a hash for an embedded file.
  String get eTag => _eTag();

  /// The modification time of a file; `null` for an embedded file.
  DateTime? get lastModified => switch (resource) {
    final FileSystemResource file => file.lastModified().toUtc(),
    _ => null,
  };

  /// The precompressed variant next to it (`app.js.br` for [extension]
  /// `.br`) in the same location, or `null`.
  StaticResource? variant(String extension) => _variant(extension);
}

/// Serves the files of its locations: the handler of one mapping of
/// static resources.
///
/// [getResource] finds the file a path asks for, after the path passed
/// the checks of a static path (no `..`, no encoded separators, no dot
/// files except `.well-known/`, nothing outside the location, symbolic
/// links included); [handleResource] answers with it: `Content-Type` from
/// the extension (never guessed from the content, and
/// `X-Content-Type-Options: nosniff`), `ETag` and `Last-Modified` with
/// `304`, `Cache-Control`, `Range`, `HEAD`, and a precompressed variant
/// with `Content-Encoding` and `Vary: Accept-Encoding` when [compressed].
///
/// The starter makes one per mapping (`ResourceHandlerRegistration`);
/// applications do not create one, except to serve a file of their own
/// locations from a controller or a filter.
///
/// ```dart
/// final docs = ResourceHttpRequestHandler(locations: ['file:docs/']);
/// final found = docs.getResource('guide/index.html');
/// if (found != null) {
///   await docs.handleResource(found, request, response, writer);
/// }
/// ```
///
/// Spring (Java): `ResourceHttpRequestHandler` with a
/// `PathResourceResolver` (and an `EncodedResourceResolver` when
/// compressed).
final class ResourceHttpRequestHandler {
  /// A handler of [locations] (`resources:static/`, `file:web/`). Throws
  /// an [ArgumentError] for a location with another prefix, or for
  /// `resources:` alone.
  ResourceHttpRequestHandler({
    required List<String> locations,
    this.cacheControl,
    this.cacheSeconds,
    this.useLastModified = true,
    this.compressed = false,
    Map<String, String> mimeMappings = const {},
  }) : _locations = [for (final l in locations) _Location.parse(l)],
       mimeMappings = {
         for (final MapEntry(:key, :value) in mimeMappings.entries)
           _extension(key): value.trim(),
       };

  final List<_Location> _locations;

  /// The `Cache-Control` of the answers; wins over [cacheSeconds].
  final CacheControl? cacheControl;

  /// `max-age` in seconds when [cacheControl] is `null`; `0` sends
  /// `no-store`, `null` or less than `0` nothing.
  final int? cacheSeconds;

  /// Whether `Last-Modified` is sent and `If-Modified-Since` checked.
  final bool useLastModified;

  /// Whether precompressed `.br` / `.gz` variants are served.
  final bool compressed;

  /// The media types by extension (lower case, without the dot) that win
  /// over the built-in ones.
  final Map<String, String> mimeMappings;

  /// The locations as written.
  List<String> get locations => [for (final l in _locations) l.text];

  static String _extension(String key) {
    final trimmed = key.trim().toLowerCase();
    return trimmed.startsWith('.') ? trimmed.substring(1) : trimmed;
  }

  /// The file [pathWithinMapping] asks for (the part of the request path
  /// under the mapping's pattern, still percent-encoded), or `null` when
  /// the path is refused or no location has such a regular file.
  StaticResource? getResource(String pathWithinMapping) {
    final segments = staticResourceSegments(pathWithinMapping);
    if (segments == null) {
      _log.debug(
        () => 'Refused the static path ${logQuoted(pathWithinMapping)}',
      );
      return null;
    }
    return resolveSegments(segments);
  }

  /// The file at [segments] (decoded, already checked as
  /// `getResource` checks them), or `null`; a directory (an empty last
  /// segment) is never one.
  StaticResource? resolveSegments(List<String> segments) {
    if (segments.isEmpty || segments.any((s) => s.isEmpty)) {
      return null;
    }
    for (final location in _locations) {
      if (location.find(segments) case final found?) {
        return found;
      }
    }
    return null;
  }

  /// The media type of [filename]: `server.mime-mappings`, then the
  /// built-in types by extension, `application/json` for
  /// `apple-app-site-association`, else `application/octet-stream`.
  String getMediaType(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot >= 0 && dot < filename.length - 1) {
      final extension = filename.substring(dot + 1).toLowerCase();
      if (mimeMappings[extension] case final type?) {
        return type;
      }
    }
    return MediaTypeFactory.getMediaType(filename) ??
        (filename == appleAppSiteAssociation
            ? MediaType.applicationJson
            : MediaType.applicationOctetStream);
  }

  /// Answers a `GET` or `HEAD` [request] with [found]: the caching headers
  /// first, then a `304` (or `412`) when the request's conditions say so,
  /// else the content (with `Range`) through [writer].
  Future<void> handleResource(
    StaticResource found,
    ServerHttpRequest request,
    ServerHttpResponse response,
    ResponseWriter writer,
  ) async {
    response.statusCode = 200;
    final headers = response.headers..set('X-Content-Type-Options', 'nosniff');
    var target = found;
    String? coding;
    if (compressed) {
      final variants = [
        for (final (name, extension) in _codings)
          if (found.variant(extension) case final variant?) (name, variant),
      ];
      if (variants.isNotEmpty) {
        // The answer depends on Accept-Encoding, for caches.
        addVary(headers, const [HttpHeaders.acceptEncodingHeader]);
        final accepted = _acceptedCodings(request);
        for (final (name, variant) in variants) {
          if (accepted.contains(name)) {
            target = variant;
            coding = name;
            break;
          }
        }
      }
    }
    final control = cacheControl?.headerValue ?? _cacheSecondsValue();
    if (control != null) {
      headers.set(HttpHeaders.cacheControlHeader, control);
    }
    headers.eTag = target.eTag;
    if (useLastModified) {
      headers.lastModified = target.lastModified;
    }
    if (writer.checkNotModified(request, response)) {
      _log.trace(() => 'Resource not modified');
      return await response.close();
    }
    headers.contentType = getMediaType(found.filename);
    if (coding != null) {
      headers.set(HttpHeaders.contentEncodingHeader, coding);
    }
    await writer.writeResource(
      target.resource,
      request,
      response,
      conditional: false,
    );
  }

  String? _cacheSecondsValue() => switch (cacheSeconds) {
    null => null,
    0 => CacheControl.noStore().headerValue,
    final seconds when seconds > 0 => CacheControl.maxAge(
      Duration(seconds: seconds),
    ).headerValue,
    _ => null,
  };

  // Spring's EncodedResourceResolver: Brotli first, then gzip.
  static const _codings = [('br', '.br'), ('gzip', '.gz')];

  // The codings of Accept-Encoding with a quality above 0.
  static Set<String> _acceptedCodings(ServerHttpRequest request) => {
    for (final value in request.headers.getAll(
      HttpHeaders.acceptEncodingHeader,
    ))
      for (final item in value.split(',')) ?_coding(item),
  };

  static String? _coding(String item) {
    final parts = item.split(';');
    final name = parts.first.trim().toLowerCase();
    if (name.isEmpty) {
      return null;
    }
    for (final parameter in parts.skip(1)) {
      final pair = parameter.split('=');
      if (pair.length == 2 && pair.first.trim().toLowerCase() == 'q') {
        final q = double.tryParse(pair.last.trim());
        if (q == null || q <= 0) {
          return null;
        }
      }
    }
    return name;
  }
}

/// The handler mapping of the static resources: it answers the requests
/// no controller took with the files of the mappings of a
/// [ResourceHandlerRegistry].
///
/// Asked after the controllers (its order is
/// `Ordered.lowestPrecedence - 1`, as Spring's), so a controller always
/// wins over a file of the same path. For a request it picks the most
/// specific matching pattern, checks the path and finds the file; with
/// no file it returns `null` and the request goes on (a 404 in the end).
/// It also serves:
///
/// - the welcome page: `/` with `Accept` taking HTML is answered with the
///   `index.html` that `/index.html` would get, when [welcomePage] (the
///   default mapping is `/**`, as Spring Boot's
///   `WelcomePageHandlerMapping`);
/// - with [spaFallback], a single-page app's deep links: a `GET` or `HEAD`
///   of a path that is no file, whose last segment has no extension, that
///   lists `text/html` in `Accept` and is not under `.well-known/`, gets
///   that `index.html` too (not in Spring Boot);
/// - with [directoryIndex], a path with no file whose folder holds an
///   `index.html` gets that file (`/guide` and `/guide/` get
///   `guide/index.html`), before the single-page app's fallback (not in
///   Spring Boot).
///
/// Only `GET` and `HEAD` read a file: `OPTIONS` is answered with `Allow`,
/// a CORS pre-flight from the CORS rules, other methods with 405. The
/// CORS rules are the global ones (`addCorsMappings`, or the
/// `corsConfigurationSource` bean), as Spring applies them to its
/// resource handler mapping. Filters, the security filter chain among
/// them, run before it as before any handler; `HandlerInterceptor`s do
/// not, as they are for controller methods.
///
/// The starter declares it as the `resourceHandlerMapping` bean; an
/// application configures it through `spring.web.resources.*` and
/// `WebMvcConfigurer.addResourceHandlers`.
///
/// Spring (Java): the `SimpleUrlHandlerMapping` of `ResourceHandlerRegistry`
/// and Spring Boot's `WelcomePageHandlerMapping`.
final class ResourceHandlerMapping
    implements HandlerMapping, Ordered, DescribableHandlerMapping {
  /// A mapping of [handlers] (each pattern with its handler) answering
  /// through [writer].
  ResourceHandlerMapping({
    required List<(PathPattern, ResourceHttpRequestHandler)> handlers,
    required this.writer,
    this.welcomePage = false,
    this.spaFallback = false,
    this.directoryIndex = false,
    this.corsConfigurationFor,
  }) : handlers = List.unmodifiable(
         <(PathPattern, ResourceHttpRequestHandler)>[...handlers]
           ..sort((a, b) => a.$1.compareTo(b.$1)),
       );

  /// A mapping of every registration of [registry], the media types of
  /// [mimeMappings] on top of the built-in ones. Throws an [ArgumentError]
  /// for a location it cannot read.
  factory ResourceHandlerMapping.fromRegistry(
    ResourceHandlerRegistry registry, {
    required ResponseWriter writer,
    Map<String, String> mimeMappings = const {},
    bool welcomePage = false,
    bool spaFallback = false,
    bool directoryIndex = false,
    CorsConfiguration? Function(ServerHttpRequest request)?
    corsConfigurationFor,
  }) => ResourceHandlerMapping(
    handlers: [
      for (final registration in registry.registrations)
        for (final pattern in registration.pathPatterns)
          (
            PathPattern.parse(pattern),
            registration.getRequestHandler(mimeMappings: mimeMappings),
          ),
    ],
    writer: writer,
    welcomePage: welcomePage,
    spaFallback: spaFallback,
    directoryIndex: directoryIndex,
    corsConfigurationFor: corsConfigurationFor,
  );

  /// The patterns and their handlers, the most specific first.
  final List<(PathPattern, ResourceHttpRequestHandler)> handlers;

  /// Writes the files and the errors.
  final ResponseWriter writer;

  /// Whether `/` is answered with `index.html` for clients that take HTML.
  final bool welcomePage;

  /// Whether a single-page app's deep links get `index.html`.
  final bool spaFallback;

  /// Whether a path with no file gets the `index.html` of its folder.
  final bool directoryIndex;

  /// The CORS rules of a request, or `null` for none.
  final CorsConfiguration? Function(ServerHttpRequest request)?
  corsConfigurationFor;

  @override
  int get order => Ordered.lowestPrecedence - 1;

  /// Every mapping as text, such as `/** -> [resources:static/]`, for
  /// diagnostics.
  List<String> get mappings => [
    for (final (pattern, handler) in handlers)
      '$pattern -> ${handler.locations}',
  ];

  /// Every pattern for the actuator's `mappings` endpoint, the most
  /// specific first, as Spring WebFlux lists its resource handlers
  /// (`{"predicate": "/**", "handler": "ResourceWebHandler
  /// [resources:static/]"}`), then the welcome page and the single-page
  /// app's fallback when they are on.
  @override
  List<Map<String, Object?>> describeHandlers() => [
    for (final (pattern, handler) in handlers)
      {
        'predicate': pattern.pattern,
        'handler': 'ResourceWebHandler [${handler.locations.join(', ')}]',
      },
    if (welcomePage && handlers.isNotEmpty)
      {'predicate': '(GET && /)', 'handler': 'WelcomePage [index.html]'},
    if (directoryIndex && handlers.isNotEmpty)
      {'predicate': '/**', 'handler': 'DirectoryIndex [index.html]'},
    if (spaFallback && handlers.isNotEmpty)
      {'predicate': '(GET && /**)', 'handler': 'SpaFallback [index.html]'},
  ];

  @override
  HttpHandler? getHandler(ServerHttpRequest request) {
    if (handlers.isEmpty) {
      return null;
    }
    final path = request.path;
    // An empty segment or matrix parameters anywhere in the path, also in
    // the part the pattern fixes (which extractPathWithinPattern skips).
    if (path.contains('//') || path.contains(';')) {
      _log.debug(() => 'Refused the static path ${logQuoted(path)}');
      return null;
    }
    final mapped = _handlerFor(path);
    if (mapped == null) {
      return null;
    }
    final (pattern, handler) = mapped;
    final segments = staticResourceSegments(
      pattern.extractPathWithinPattern(path),
    );
    if (segments == null) {
      _log.debug(() => 'Refused the static path ${logQuoted(path)}');
      return null;
    }
    var found = handler.resolveSegments(segments);
    var serving = handler;
    if (found == null && directoryIndex) {
      // The folder's index.html, found as any file: the segments were
      // checked above (no `..`, no hidden folder, no escape), and the
      // location keeps the resolved file inside itself (symbolic links
      // included). A trailing `/` is the folder itself.
      final folder = [
        for (final segment in segments)
          if (segment.isNotEmpty) segment,
      ];
      if (folder.isNotEmpty) {
        found = handler.resolveSegments([...folder, 'index.html']);
        if (found != null) {
          _log.debug(() => 'Serving the index.html of ${logQuoted(path)}');
        }
      }
    }
    if (found == null && welcomePage && path == '/' && _takesHtml(request)) {
      (found, serving) = _index() ?? (null, handler);
      if (found != null) {
        _log.debug(() => 'Serving the welcome page');
      }
    }
    if (found == null &&
        spaFallback &&
        _isDeepLink(request, segments) &&
        _listsHtml(request)) {
      (found, serving) = _index() ?? (null, handler);
      if (found != null) {
        _log.debug(() => 'Serving index.html for ${logQuoted(path)}');
      }
    }
    if (found == null) {
      return null;
    }
    return _StaticHandler(this, serving, found);
  }

  (PathPattern, ResourceHttpRequestHandler)? _handlerFor(String path) {
    for (final entry in handlers) {
      if (entry.$1.matches(path)) {
        return entry;
      }
    }
    return null;
  }

  // The index.html `/index.html` would get.
  (StaticResource?, ResourceHttpRequestHandler)? _index() {
    final mapped = _handlerFor('/index.html');
    if (mapped == null) {
      return null;
    }
    final (pattern, handler) = mapped;
    final segments = staticResourceSegments(
      pattern.extractPathWithinPattern('/index.html'),
    );
    if (segments == null) {
      return null;
    }
    return (handler.resolveSegments(segments), handler);
  }

  // A GET or HEAD whose last segment has no extension, not under
  // .well-known/ (deep-link verification must see a 404, not HTML).
  static bool _isDeepLink(ServerHttpRequest request, List<String> segments) {
    if (request.method != HttpMethod.get && request.method != HttpMethod.head) {
      return false;
    }
    if (segments.isNotEmpty && segments.first == '.well-known') {
      return false;
    }
    final last = segments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
    return !last.contains('.');
  }

  static List<MediaType> _accept(ServerHttpRequest request) {
    final header = request.headers.getAll(HttpHeaders.acceptHeader).join(',');
    if (header.trim().isEmpty) {
      return [MediaType.parse(MediaType.all)];
    }
    try {
      return MediaType.parseMediaTypes(header);
    } on InvalidMediaTypeException {
      return const [];
    }
  }

  // Spring Boot's welcome page: an Accept that includes text/html (none
  // means all).
  static bool _takesHtml(ServerHttpRequest request) {
    final html = MediaType.parse(MediaType.textHtml);
    return _accept(
      request,
    ).any((type) => type.qualityValue > 0 && type.includes(html));
  }

  // The fallback is stricter: text/html named (a browser's navigation),
  // not just */* (a script's fetch of a missing API path).
  static bool _listsHtml(ServerHttpRequest request) => _accept(request).any(
    (type) =>
        type.qualityValue > 0 &&
        type.type == 'text' &&
        type.subtype == MediaType.parse(MediaType.textHtml).subtype,
  );
}

// Answers one request with a file a ResourceHandlerMapping found.
final class _StaticHandler implements HttpHandler {
  _StaticHandler(this.mapping, this.handler, this.found);

  final ResourceHandlerMapping mapping;
  final ResourceHttpRequestHandler handler;
  final StaticResource found;

  static const Set<HttpMethod> _allowed = {HttpMethod.get, HttpMethod.head};

  @override
  Future<void> handle(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    final config = mapping.corsConfigurationFor?.call(request);
    if (isPreFlightRequest(request)) {
      if (config != null &&
          !processCors(config, request, response, preFlight: true)) {
        await response.send(403, 'Invalid CORS request');
        return;
      }
      response.statusCode = 200;
      return await response.close();
    }
    if (config != null &&
        !processCors(config, request, response, preFlight: false)) {
      await response.send(403, 'Invalid CORS request');
      return;
    }
    if (request.method == HttpMethod.options) {
      response
        ..statusCode = 200
        ..headers.set(HttpHeaders.allowHeader, 'GET,HEAD,OPTIONS');
      return await response.close();
    }
    if (!_allowed.contains(request.method)) {
      throw HttpRequestMethodNotSupportedException(request.method, _allowed);
    }
    _log.debug(() => 'Serving ${found.resource.description}');
    await handler.handleResource(found, request, response, mapping.writer);
  }
}

// A location of a ResourceHttpRequestHandler.
sealed class _Location {
  _Location(this.text);

  final String text;

  static _Location parse(String location) {
    var text = location.trim();
    if (!text.endsWith('/')) {
      text = '$text/';
    }
    if (text.startsWith(Resources.prefix)) {
      var folder = text.substring(Resources.prefix.length);
      while (folder.startsWith('/')) {
        folder = folder.substring(1);
      }
      final segments = folder.split('/')..removeLast();
      if (segments.isEmpty ||
          !segments.indexed.every(
            (e) => isAllowedStaticSegment(e.$2, first: e.$1 == 0),
          )) {
        throw ArgumentError.value(
          location,
          'location',
          'A static location must be a folder of lib/resources/ '
              '(resources:static/), not its root, which holds the '
              'configuration files',
        );
      }
      return _ResourcesLocation(text, segments);
    }
    if (text.startsWith(ResourceLoader.filePrefix)) {
      final path = FileSystemResource.fromFileUrl(text).path;
      return _FileLocation(text, path);
    }
    throw ArgumentError.value(
      location,
      'location',
      'A static location starts with resources: (lib/resources/) or file: '
          '(a directory)',
    );
  }

  StaticResource? find(List<String> segments);

  // The file at [segments] in the directory [directory], with its
  // variants in the same directory.
  static StaticResource? findIn(
    _CanonicalCache cache,
    String directory,
    List<String> segments,
  ) {
    final base = cache.canonical(directory);
    if (base == null) {
      return null;
    }
    final file = findStaticFile(base, segments);
    if (file == null) {
      return null;
    }
    return StaticResource._(
      file,
      segments.last,
      () => _fileETag(file),
      (extension) => findIn(cache, directory, [
        ...segments.sublist(0, segments.length - 1),
        '${segments.last}$extension',
      ]),
    );
  }

  static String _fileETag(FileSystemResource file) =>
      'W/"${file.contentLength().toRadixString(16)}-'
      '${file.lastModified().millisecondsSinceEpoch.toRadixString(16)}"';
}

// A `file:` directory.
final class _FileLocation extends _Location {
  _FileLocation(super.text, this.path);

  final String path;
  final _cache = _CanonicalCache();

  @override
  StaticResource? find(List<String> segments) =>
      _Location.findIn(_cache, path, segments);
}

// A folder of lib/resources/: in the directories added to Resources (test
// resources), then embedded, then on disk in lib/resources/, as
// `Resources.resolve` looks.
final class _ResourcesLocation extends _Location {
  _ResourcesLocation(super.text, this.folder);

  final List<String> folder;
  final _cache = _CanonicalCache();
  final _eTags = <String, String>{};

  @override
  StaticResource? find(List<String> segments) {
    final relative = [...folder, ...segments].join('/');
    for (final directory in Resources.directories) {
      if (_Location.findIn(_cache, '$directory/${folder.join('/')}', segments)
          case final found?) {
        return found;
      }
    }
    if (Resources.paths.contains(relative)) {
      final resource = Resources.resolveEmbedded(relative);
      return StaticResource._(
        resource,
        segments.last,
        () => _eTags[relative] ??= _embeddedETag(resource),
        (extension) => find([
          ...segments.sublist(0, segments.length - 1),
          '${segments.last}$extension',
        ]),
      );
    }
    return _Location.findIn(
      _cache,
      '${Resources.directory}/${folder.join('/')}',
      segments,
    );
  }

  // The length and an FNV-1a hash of the bytes.
  static String _embeddedETag(Resource resource) {
    final bytes = resource.readAsBytesSync();
    var hash = 0x811C9DC5;
    for (final byte in bytes) {
      hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF;
    }
    return 'W/"${bytes.length.toRadixString(16)}-${hash.toRadixString(16)}"';
  }
}

// The canonical paths of the directories looked in, kept once found (a
// directory created after the start is found then).
final class _CanonicalCache {
  final _paths = <String, String>{};

  String? canonical(String directory) {
    if (!staticFilesSupported) {
      return null;
    }
    if (_paths[directory] case final known?) {
      return known;
    }
    final found = canonicalDirectory(directory);
    if (found != null) {
      _paths[directory] = found;
    }
    return found;
  }
}
