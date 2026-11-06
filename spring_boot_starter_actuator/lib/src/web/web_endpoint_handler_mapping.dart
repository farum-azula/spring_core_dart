import 'dart:async';

import 'package:spring_boot_actuator/spring_boot_actuator.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

const _log = SpringLog(
  'spring.boot.actuate.endpoint.web.WebFluxEndpointHandlerMapping',
);

/// The media types the endpoints answer, the preferred first:
/// `application/vnd.spring-boot.actuator.v3+json`, `...v2+json` and
/// `application/json`.
///
/// Spring Boot (Java): `ActuatorMediaType` and the endpoints' default
/// `produces`.
const List<String> actuatorMediaTypes = [
  'application/vnd.spring-boot.actuator.v3+json',
  'application/vnd.spring-boot.actuator.v2+json',
  MediaType.applicationJson,
];

/// An extra path at which an endpoint answers with fixed selectors: the
/// health groups' `additional-path` (`/livez` is the `liveness` group of
/// `health`).
final class AdditionalEndpointPath {
  /// [path] answers the endpoint [endpointId] with the [selectors].
  const AdditionalEndpointPath(this.path, this.endpointId, this.selectors);

  /// The path, from the root of the server (after the context path).
  final String path;

  /// The endpoint it answers.
  final EndpointId endpointId;

  /// The selector segments it passes (`['liveness']`).
  final List<String> selectors;
}

/// Answers the exposed endpoints over HTTP: `GET <base-path>/<id>` and
/// the paths of their selectors, and the discovery page at the base path
/// with the `_links` to every endpoint.
///
/// The starter declares it as the `webEndpointHandlerMapping` bean at
/// order `-100`, so it comes before the controllers and the static
/// resources, as in Spring Boot. Every request still passes the filters
/// first: the security filter chain decides who may call an endpoint.
///
/// An answer is JSON of the type the client accepts:
/// `application/vnd.spring-boot.actuator.v3+json` by default,
/// `application/json` when asked; `406` for a client that accepts
/// neither. `null` from an operation is a `404`, a missing or invalid
/// parameter a `400`, another method than `GET` and `HEAD` a `405`.
///
/// Spring Boot (Java): `WebFluxEndpointHandlerMapping` (with its links
/// handler, `EndpointLinksResolver`).
final class WebEndpointHandlerMapping
    implements HandlerMapping, Ordered, DescribableHandlerMapping {
  /// The mapping of [endpoints] (enabled and exposed) under [basePath]
  /// (`/actuator`; empty for the root), each at its id or its entry in
  /// [pathMappings]; with [linksEnabled], the discovery page at
  /// [basePath]. Answers are written with [mapper]; [roleChecker] tells
  /// the roles of the request's user.
  WebEndpointHandlerMapping({
    required List<ExposableEndpoint> endpoints,
    required this.mapper,
    this.basePath = '/actuator',
    Map<String, String> pathMappings = const {},
    this.linksEnabled = true,
    this.roleChecker,
    List<AdditionalEndpointPath> additionalPaths = const [],
  }) : endpoints = List.unmodifiable(endpoints),
       pathMappings = {
         for (final MapEntry(:key, :value) in pathMappings.entries)
           EndpointId.toLowerCaseKey(key): value,
       } {
    _routes
      ..addAll([
        for (final endpoint in this.endpoints)
          for (final operation in endpoint.operations)
            _Route(
              endpoint,
              operation,
              '${rootPathOf(endpoint.id)}${_selectorPath(operation)}',
            ),
      ])
      ..addAll([
        for (final extra in additionalPaths) ?_additional(extra),
      ])
      ..sort((a, b) => a.pattern.compareTo(b.pattern));
  }

  /// The exposed endpoints.
  final List<ExposableEndpoint> endpoints;

  /// The base path (`/actuator`), empty for the root.
  final String basePath;

  /// The paths of endpoints by id (in lower case), instead of their ids.
  final Map<String, String> pathMappings;

  /// Whether the base path answers the discovery page.
  final bool linksEnabled;

  /// Writes the answers that are not an [OperationResponseBody].
  final ObjectMapper mapper;

  /// Tells the roles of the request's user, for `when-authorized`.
  final PrincipalRoleChecker? roleChecker;

  final _routes = <_Route>[];

  static const Set<HttpMethod> _getAndHead = {HttpMethod.get, HttpMethod.head};

  @override
  int get order => -100;

  /// The path of the endpoint [id]: the base path and its id or mapped
  /// path (`/actuator/health`).
  String rootPathOf(EndpointId id) {
    final mapped = pathMappings[id.toLowerCaseString()]?.trim();
    final segment = mapped == null || mapped.isEmpty ? id.value : mapped;
    final clean = segment.startsWith('/') ? segment.substring(1) : segment;
    return '$basePath/$clean';
  }

  static String _selectorPath(EndpointOperation operation) => [
    for (final selector in operation.selectors)
      if (selector.selector == SelectorMatch.allRemaining)
        '/{*${selector.name}}'
      else
        '/{${selector.name}}',
  ].join();

  _Route? _additional(AdditionalEndpointPath extra) {
    for (final endpoint in endpoints) {
      if (endpoint.id != extra.endpointId) {
        continue;
      }
      for (final operation in endpoint.operations) {
        final selectors = operation.selectors;
        if (selectors.length == 1 &&
            selectors.single.selector == SelectorMatch.allRemaining) {
          final path = extra.path.startsWith('/')
              ? extra.path
              : '/${extra.path}';
          return _Route(endpoint, operation, path, fixed: extra.selectors);
        }
      }
    }
    return null;
  }

  // The base path itself; `/actuator/` is not it, as Spring 6 matches no
  // trailing slash.
  bool _isLinksPath(String path) =>
      linksEnabled && basePath.isNotEmpty && path == basePath;

  /// The endpoint [path] is for: the discovery page, an exposed endpoint,
  /// or `null`. The actuator starter's filter records it on the request
  /// for the security matchers (`EndpointRequest`).
  EndpointRequestTarget? targetOf(String path) {
    if (_isLinksPath(path)) {
      return const EndpointRequestTarget.links();
    }
    for (final route in _routes) {
      if (route.pattern.match(path) != null) {
        return EndpointRequestTarget.endpoint(route.endpoint.id);
      }
    }
    return null;
  }

  @override
  HttpHandler? getHandler(ServerHttpRequest request) {
    final path = request.path;
    if (_isLinksPath(path)) {
      _checkMethod(request);
      return _Handler(this, request, _writeLinks);
    }
    for (final route in _routes) {
      final match = route.pattern.match(path);
      if (match == null) {
        continue;
      }
      _checkMethod(request);
      return _Handler(
        this,
        request,
        (request, response, accepted) =>
            _invoke(route, match, request, response, accepted),
        produces: route.operation.produces,
      );
    }
    return null;
  }

  static void _checkMethod(ServerHttpRequest request) {
    if (!_getAndHead.contains(request.method)) {
      throw HttpRequestMethodNotSupportedException(
        request.method,
        _getAndHead,
      );
    }
  }

  Future<void> _invoke(
    _Route route,
    PathMatch match,
    ServerHttpRequest request,
    ServerHttpResponse response,
    MediaType accepted,
  ) async {
    final arguments = <String, Object?>{
      for (final MapEntry(:key, :value) in request.queryParameters.entries)
        if (value.isNotEmpty) key: value.length == 1 ? value.single : value,
    };
    final selectors = route.operation.selectors;
    if (route.fixed case final fixed?) {
      arguments[selectors.single.name] = fixed;
    } else {
      for (final selector in selectors) {
        final value = match.variables[selector.name] ?? '';
        arguments[selector.name] =
            selector.selector == SelectorMatch.allRemaining
            ? [
                for (final part in value.split('/'))
                  if (part.isNotEmpty) part,
              ]
            : value;
      }
    }
    final apiVersion =
        accepted.equalsTypeAndSubtype(
          MediaType.parse(ApiVersion.v2.mediaType),
        )
        ? ApiVersion.v2
        : ApiVersion.v3;
    final context = InvocationContext(
      securityContext: SecurityContext.of(
        request.principal,
        roles: roleChecker,
      ),
      apiVersion: apiVersion,
      arguments: arguments,
    );
    final Object? result;
    try {
      result = await route.operation.invoke(context);
    } on MissingParametersException catch (error) {
      throw ResponseStatusException(
        HttpStatus.badRequest,
        'Missing parameters: ${error.parameters.join(',')}',
      );
    } on InvalidEndpointRequestException catch (error) {
      _log.debug(() => error.message);
      throw ResponseStatusException(HttpStatus.badRequest, error.reason);
    }
    switch (result) {
      case null:
        await _write(request, response, WebEndpointResponse.notFound, null);
      case final WebEndpointResponse<Object?> answer:
        await _write(
          request,
          response,
          answer.status,
          answer.body,
          contentType: answer.contentType ?? '$accepted',
        );
      default:
        await _write(
          request,
          response,
          WebEndpointResponse.ok,
          result,
          contentType: '$accepted',
        );
    }
  }

  Future<void> _writeLinks(
    ServerHttpRequest request,
    ServerHttpResponse response,
    MediaType accepted,
  ) => _write(
    request,
    response,
    WebEndpointResponse.ok,
    {'_links': linksOf(request.uri)},
    contentType: '$accepted',
  );

  /// The `_links` of the discovery page requested at [requestUri]: `self`
  /// and, for each operation of each exposed endpoint, its id
  /// (`health`) or its id and selectors (`health-path`), with the `href`
  /// built from [requestUri] and whether it is `templated`.
  ///
  /// ```json
  /// {"self": {"href": "http://localhost:8080/actuator", "templated": false},
  ///  "health": {"href": "http://localhost:8080/actuator/health",
  ///   "templated": false},
  ///  "health-path": {"href": "http://localhost:8080/actuator/health/{*path}",
  ///   "templated": true}}
  /// ```
  ///
  /// Spring Boot (Java): `EndpointLinksResolver.resolveLinks`.
  Map<String, Object?> linksOf(Uri requestUri) {
    var self = requestUri.replace(query: '').toString();
    if (self.endsWith('?')) {
      self = self.substring(0, self.length - 1);
    }
    while (self.endsWith('/')) {
      self = self.substring(0, self.length - 1);
    }
    Map<String, Object?> link(String href) => {
      'href': href,
      'templated': href.contains('{'),
    };
    final links = <String, Object?>{'self': link(self)};
    final sorted = [...endpoints]
      ..sort(
        (a, b) => a.id.toLowerCaseString().compareTo(
          b.id.toLowerCaseString(),
        ),
      );
    for (final endpoint in sorted) {
      for (final operation in endpoint.operations) {
        final id = [
          endpoint.id.value,
          for (final selector in operation.selectors) selector.name,
        ].join('-');
        final relative = rootPathOf(
          endpoint.id,
        ).substring(basePath.length);
        links[id] = link('$self$relative${_selectorPath(operation)}');
      }
    }
    return links;
  }

  Future<void> _write(
    ServerHttpRequest request,
    ServerHttpResponse response,
    int status,
    Object? body, {
    String? contentType,
  }) async {
    response.statusCode = status;
    if (body != null) {
      final text = mapper.writeValueAsString(_jsonTree(body));
      response.headers.contentType = contentType;
      if (request.method != HttpMethod.head) {
        response.write(text);
      }
    }
    await response.close();
  }

  // The answer as maps, lists and plain values; values that write
  // themselves are asked, others are left to the ObjectMapper.
  static Object? _jsonTree(Object? value) => switch (value) {
    final OperationResponseBody body => _jsonTree(body.toJson()),
    final Map<Object?, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries)
        '$key': _jsonTree(value),
    },
    final List<Object?> list => [for (final item in list) _jsonTree(item)],
    _ => value,
  };

  /// The type of the answer: the first of [produces] (the actuator's
  /// types by default) the request accepts, in the order of its quality.
  /// Throws an `HttpMediaTypeNotAcceptableException` when there is none.
  static MediaType negotiate(
    ServerHttpRequest request, [
    List<String> produces = const [],
  ]) {
    final producible = [
      for (final type in produces.isEmpty ? actuatorMediaTypes : produces)
        MediaType.parse(type),
    ];
    List<MediaType> accepted;
    try {
      accepted = MediaType.parseMediaTypes(
        request.headers.getAll(HttpHeaders.acceptHeader).join(','),
      );
    } on InvalidMediaTypeException {
      accepted = const [];
    }
    if (accepted.isEmpty) {
      accepted = [MediaType.parse(MediaType.all)];
    }
    final byQuality =
        [
          for (final (index, type) in accepted.indexed) (index, type),
        ]..sort((a, b) {
          final quality = b.$2.qualityValue.compareTo(a.$2.qualityValue);
          return quality != 0 ? quality : a.$1.compareTo(b.$1);
        });
    for (final (_, type) in byQuality) {
      if (type.qualityValue <= 0) {
        continue;
      }
      for (final candidate in producible) {
        if (type.includes(candidate)) {
          return candidate;
        }
      }
    }
    throw HttpMediaTypeNotAcceptableException([
      for (final type in producible) '$type',
    ]);
  }

  @override
  List<Map<String, Object?>> describeHandlers() => [
    if (linksEnabled && basePath.isNotEmpty)
      describeRequestMapping(
        handler: 'Actuator root web endpoint',
        className: 'WebEndpointHandlerMapping',
        methodName: 'links',
        descriptor: '(ServerHttpRequest) -> Map<String, Object?>',
        methods: const ['GET'],
        patterns: [basePath],
        produces: actuatorMediaTypes,
      ),
    for (final route in _routes)
      describeRequestMapping(
        handler: "Actuator web endpoint '${route.endpoint.id}'",
        className:
            route.operation.className ??
            route.endpoint.beanName ??
            '${route.endpoint.id}',
        methodName: route.operation.name,
        descriptor: _descriptor(route.operation),
        methods: const ['GET'],
        patterns: [route.pattern.pattern],
        produces: route.operation.produces.isEmpty
            ? actuatorMediaTypes
            : route.operation.produces,
      ),
  ];
}

// The parameters of an operation: `(List<String> path)`.
String _descriptor(EndpointOperation operation) {
  final parameters = [
    for (final p in operation.parameters) '${p.type.type} ${p.name}',
  ];
  return '(${parameters.join(', ')})';
}

/// The handler of one request: picks the media type, then answers.
final class _Handler implements HttpHandler {
  _Handler(
    this.mapping,
    ServerHttpRequest request,
    this.answer, {
    List<String> produces = const [],
  }) : accepted = WebEndpointHandlerMapping.negotiate(request, produces);

  final WebEndpointHandlerMapping mapping;
  final MediaType accepted;
  final Future<void> Function(
    ServerHttpRequest request,
    ServerHttpResponse response,
    MediaType accepted,
  )
  answer;

  @override
  Future<void> handle(ServerHttpRequest request, ServerHttpResponse response) =>
      answer(request, response, accepted);
}

/// One operation at its path pattern; [fixed] selectors for an additional
/// path.
final class _Route {
  _Route(this.endpoint, this.operation, String pattern, {this.fixed})
    : pattern = PathPattern.parse(pattern);

  final ExposableEndpoint endpoint;
  final EndpointOperation operation;
  final PathPattern pattern;
  final List<String>? fixed;
}

/// Records on each request the endpoint it is for
/// ([EndpointRequestTarget]), before the security filter chain, so
/// `EndpointRequest` matchers work.
///
/// The starter declares it as the `webEndpointRequestFilter` bean, at
/// order `-5000`: after the forwarded headers, before the security
/// filters (`-100`).
final class WebEndpointRequestFilter implements WebFilter, Ordered {
  /// The filter of [mapping]'s endpoints.
  WebEndpointRequestFilter(this.mapping);

  /// The order of the filter.
  static const filterOrder = -5000;

  /// The mapping whose paths are known.
  final WebEndpointHandlerMapping mapping;

  @override
  int get order => filterOrder;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) {
    if (mapping.targetOf(request.path) case final target?) {
      request.attributes[EndpointRequestTarget.attribute] = target;
    } else {
      request.attributes.remove(EndpointRequestTarget.attribute);
    }
    return chain.doFilter(request, response);
  }
}
