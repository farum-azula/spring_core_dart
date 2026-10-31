import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_feign/src/feign_client.dart';
import 'package:spring_boot_starter_feign/src/feign_client_config.dart';
import 'package:spring_boot_starter_feign/src/feign_exception.dart';
import 'package:spring_boot_starter_feign/src/request_template.dart';
import 'package:spring_boot_starter_feign/src/retryer.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// The engine behind one `@FeignClient` interface: the generated class
/// hands every method call to it, and it makes the HTTP call.
///
/// For each call it builds a [RequestTemplate] from the method's mapping
/// annotations and the arguments, lets the [interceptors] change it, adds
/// the configured default headers and query parameters, and sends it
/// through the [transport]. A 2xx answer is decoded into the method's
/// return type with the [mapper]; another status becomes an exception
/// through the [errorDecoder]. A `RetryableException` (no connection, a
/// timeout, a `Retry-After`) is tried again as long as the [retryer]
/// allows, each attempt on a new template. When the call still fails and
/// the client has a [fallback], the fallback bean answers instead.
///
/// Methods returning `EventStream<T>` (or `Stream<T>`) read
/// `text/event-stream` responses: each listener opens its own connection,
/// every event's data is decoded into `T`, and a lost connection is opened
/// again with `Last-Event-ID` (see
/// [FeignClientConfig.eventStreamReconnect]).
///
/// The starter's `FeignClientFactory` creates one per client bean;
/// applications never create or call it, they call the interface. Every
/// method is checked at creation, so a path variable without a parameter
/// or a method without a mapping stops the application at startup with
/// the reason.
///
/// Spring (Java): Feign's `SynchronousMethodHandler` behind the proxy that
/// `FeignClientFactoryBean` creates.
final class FeignInvocationHandler implements InvocationHandler {
  /// The handler of the interface described by [metadata]. Throws a
  /// [StateError] listing every problem found in its methods, or when no
  /// URL is configured.
  FeignInvocationHandler({
    required InterfaceMetadata<Object> metadata,
    required this.client,
    required this.config,
    required this.environment,
    required this.mapper,
    required this.transport,
    this.interceptors = const [],
    this.errorDecoder = const DefaultErrorDecoder(),
    this.retryer = Retryer.never,
    this.fallback,
  }) : typeName = metadata.typeName,
       _log = SpringLog('feign.${metadata.typeName}') {
    final problems = <String>[];
    _baseUrl = _resolveBaseUrl(problems);
    for (final method in metadata.methods) {
      final plan = _Plan.compile(this, method, problems);
      if (plan != null) {
        _plans[method] = plan;
      }
    }
    if (problems.isNotEmpty) {
      throw StateError(
        'Invalid Feign client $typeName:\n'
        '${problems.map((p) => '  - $p').join('\n')}',
      );
    }
  }

  /// The name of the interface, such as `CatalogClient`; the logger is
  /// `feign.<typeName>`.
  final String typeName;

  /// The interface's `@FeignClient` annotation.
  final FeignClient client;

  /// The client's settings from `spring.cloud.openfeign.client.config.*`.
  final FeignClientConfig config;

  /// Resolves the `${...}` placeholders of the URL, the paths and the
  /// mapping headers.
  final Environment environment;

  /// Writes request bodies as JSON and reads response bodies.
  final ObjectMapper mapper;

  /// Sends the requests.
  final HttpTransport transport;

  /// Change every request before it is sent, in this order, at every
  /// attempt.
  final List<RequestInterceptor> interceptors;

  /// Turns a response with an error status into the exception the call
  /// throws.
  final ErrorDecoder errorDecoder;

  /// Decides whether and when a failed attempt is tried again; by
  /// default never.
  final Retryer retryer;

  /// Gives the fallback bean that answers when a call fails; it is looked
  /// up at the first failure. `null` when the client has none.
  final Object Function()? fallback;

  final SpringLog _log;
  final _plans = Map<ProxyMethod, _Plan>.identity();
  late final String _baseUrl;

  // `@FeignClient(url:)`, else the `url` property (an empty or blank
  // annotation url counts as none, like Spring's default ""); without a
  // scheme `http://` is put in front, like Spring Cloud OpenFeign.
  String _resolveBaseUrl(List<String> problems) {
    String? resolve(String? url) {
      if (url == null || url.trim().isEmpty) {
        return null;
      }
      try {
        final resolved = environment.resolveRequiredPlaceholders(url.trim());
        return resolved.trim().isEmpty ? null : resolved.trim();
      } on Object catch (error) {
        problems.add('cannot resolve the URL "$url": $error');
        return '';
      }
    }

    final url = resolve(client.url) ?? resolve(config.url);
    if (url == null) {
      problems.add(
        'no URL: set @FeignClient(url: ...) or '
        'spring.cloud.openfeign.client.config.${client.configKey}.url',
      );
      return '';
    }
    if (url.isEmpty || url.contains('://')) {
      return url;
    }
    return 'http://$url';
  }

  @override
  Object? invoke(ProxyMethod method, List<Object?> arguments) {
    final plan = _plans[method]!;
    final eventType = plan.eventType;
    if (eventType != null) {
      return eventType.accept(
        _EventStreamFactory(this, plan, method, arguments),
      );
    }
    return _execute(plan, method, arguments);
  }

  // The raw events of one listener of an event stream method.
  Stream<ServerSentEvent<String>> _openEvents(
    _Plan plan,
    List<Object?> arguments,
  ) => connectServerSentEvents(
    (lastEventId) => _connectEvents(plan, arguments, lastEventId),
    reconnect: SseReconnect(
      enabled: config.eventStreamReconnect,
      delay: config.eventStreamReconnectDelay,
      maxAttempts: config.eventStreamMaxAttempts,
      retryIf: (error) =>
          error is RetryableException || error is HttpTransportException,
    ),
    onReconnect: (error, delay, attempt) {
      if (config.loggerLevel != FeignLoggerLevel.none) {
        _log.debug(
          '---> RECONNECTING ${plan.methodKey} (attempt $attempt) in '
          '${delay.inMilliseconds} ms${error == null ? '' : ' after $error'}',
          fields: {'client': client.name},
        );
      }
    },
  );

  Future<StreamedHttpResponse> _connectEvents(
    _Plan plan,
    List<Object?> arguments,
    String? lastEventId,
  ) async {
    final request = _request(
      await _prepare(
        plan,
        arguments,
        await plan.multipart(arguments),
        lastEventId: lastEventId,
      ),
    );
    final watch = Stopwatch()..start();
    _logRequest(request);
    final StreamedHttpResponse response;
    try {
      response = await transport.stream(request);
    } on HttpTransportException catch (error) {
      _logError(error, watch);
      throw RetryableException(
        -1,
        '${error.message} executing ${request.method.value} ${request.url}',
        request: request,
        cause: error,
      );
    }
    final status = response.statusCode;
    if (response.isSuccess) {
      if (config.loggerLevel != FeignLoggerLevel.none) {
        _log.debug(
          '<--- $status${_phrase(status)} '
          '(${watch.elapsedMilliseconds} ms, event stream)',
          fields: {'client': client.name},
        );
      }
      return response;
    }
    final whole = await response.read();
    _logResponse(whole, watch.elapsed);
    if (status == 404 && dismiss404) {
      // Like an empty result: the stream ends.
      return StreamedHttpResponse(
        HttpStatus.noContent,
        body: const Stream.empty(),
        request: request,
      );
    }
    throw errorDecoder.decode(plan.methodKey, whole);
  }

  /// Whether a 404 gives an empty result instead of an exception: set by
  /// `@FeignClient(dismiss404: true)` or the `dismiss404` property. For an
  /// event stream, a dismissed 404 ends the stream.
  bool get dismiss404 => client.dismiss404 || config.dismiss404;

  // A fresh template for a call with [arguments] (and its [multipart]
  // body), changed by the interceptors, then completed with the configured
  // defaults.
  Future<RequestTemplate> _prepare(
    _Plan plan,
    List<Object?> arguments,
    _Multipart? multipart, {
    String? lastEventId,
  }) async {
    final template = plan.template(arguments, multipart);
    if (lastEventId != null) {
      template.headers.set('Last-Event-ID', lastEventId);
    }
    for (final interceptor in interceptors) {
      await interceptor.apply(template);
    }
    plan.applyDefaults(template);
    return template;
  }

  HttpRequest _request(RequestTemplate template) => HttpRequest(
    method: template.method,
    url: template.url,
    headers: template.headers,
    body: template.body,
    readTimeout: config.readTimeout,
    followRedirects: config.followRedirects,
  );

  Future<Object?> _execute(
    _Plan plan,
    ProxyMethod method,
    List<Object?> arguments,
  ) async {
    try {
      return await _call(plan, method, arguments);
    } on Object catch (error) {
      final backup = fallback?.call();
      if (backup == null) {
        rethrow;
      }
      _log.debug(
        'fallback for ${plan.methodKey} after $error',
        fields: {'client': client.name},
      );
      final result = method.callOn(backup, arguments);
      return result is Future ? await result : result;
    }
  }

  Future<Object?> _call(
    _Plan plan,
    ProxyMethod method,
    List<Object?> arguments,
  ) async {
    // A multipart body is built once (files are read once): every attempt
    // sends the same bytes with the same boundary.
    final multipart = await plan.multipart(arguments);
    for (var attempt = 1; ; attempt++) {
      // Like Feign, the interceptors run for every attempt — here on a
      // fresh template, so a refreshed token reaches the retry.
      final request = _request(await _prepare(plan, arguments, multipart));
      try {
        final response = await _send(request, plan, method);
        return plan.decode(response, method);
      } on RetryableException catch (error) {
        final delay = retryer.nextDelay(attempt, error);
        if (delay == null) {
          rethrow;
        }
        if (config.loggerLevel != FeignLoggerLevel.none) {
          _log.debug(
            '---> RETRYING ${plan.methodKey} (attempt ${attempt + 1}) in '
            '${delay.inMilliseconds} ms',
            fields: {'client': client.name},
          );
        }
        await Future<void>.delayed(delay);
      }
    }
  }

  Future<HttpResponse> _send(
    HttpRequest request,
    _Plan plan,
    ProxyMethod method,
  ) async {
    final watch = Stopwatch()..start();
    _logRequest(request);
    final HttpResponse response;
    try {
      response = await transport.send(request);
    } on HttpTransportException catch (error) {
      _logError(error, watch);
      throw RetryableException(
        -1,
        '${error.message} executing ${request.method.value} ${request.url}',
        request: request,
        cause: error,
      );
    }
    _logResponse(response, watch.elapsed);
    final status = response.statusCode;
    // Like Feign, a method returning the raw response gets every status.
    if (status.is2xxSuccessful || _Plan.isRaw(method)) {
      return response;
    }
    // Like Feign, a void method still throws.
    if (status == HttpStatus.notFound && dismiss404 && !method.isVoid) {
      return response;
    }
    throw errorDecoder.decode(plan.methodKey, response);
  }

  static String _phrase(int status) => switch (HttpStatus.resolve(status)) {
    final known? => ' ${known.reasonPhrase}',
    null => '',
  };

  void _logError(HttpTransportException error, Stopwatch watch) {
    if (config.loggerLevel == FeignLoggerLevel.none) {
      return;
    }
    _log.debug(
      '<--- ERROR ${error.message} (${watch.elapsedMilliseconds} ms)',
      fields: {'client': client.name},
    );
  }

  void _logRequest(HttpRequest request) {
    if (config.loggerLevel == FeignLoggerLevel.none) {
      return;
    }
    final lines = ['---> ${request.method.value} ${request.url}'];
    if (config.loggerLevel.index >= FeignLoggerLevel.headers.index) {
      request.headers.forEach(
        (name, values) => _logHeader(lines, name, values),
      );
    }
    final body = request.body;
    if (config.loggerLevel == FeignLoggerLevel.full && body != null) {
      lines.add(utf8.decode(body, allowMalformed: true));
    }
    if (config.loggerLevel.index >= FeignLoggerLevel.headers.index) {
      lines.add('---> END HTTP (${body?.length ?? 0}-byte body)');
    }
    _log.debug(lines.join('\n'), fields: {'client': client.name});
  }

  // Credentials (tokens, cookies, the DPoP proof, the configured ones)
  // as `***`.
  late final Set<String> _sensitiveHeaders = {
    ...FeignClientConfig.alwaysSensitiveHeaders,
    for (final name in config.sensitiveHeaders) name.trim().toLowerCase(),
  };

  void _logHeader(List<String> lines, String name, List<String> values) {
    final masked = _sensitiveHeaders.contains(name.toLowerCase());
    for (final value in values) {
      lines.add('$name: ${masked ? '***' : value}');
    }
  }

  void _logResponse(HttpResponse response, Duration elapsed) {
    if (config.loggerLevel == FeignLoggerLevel.none) {
      return;
    }
    final lines = [
      // One entry, written on two lines to stay within 80 columns.
      // ignore: no_adjacent_strings_in_list
      '<--- ${response.statusCode}${_phrase(response.statusCode)} '
          '(${elapsed.inMilliseconds} ms)',
    ];
    if (config.loggerLevel.index >= FeignLoggerLevel.headers.index) {
      response.headers.forEach(
        (name, values) => _logHeader(lines, name, values),
      );
    }
    if (config.loggerLevel == FeignLoggerLevel.full) {
      lines.add(response.bodyText);
    }
    if (config.loggerLevel.index >= FeignLoggerLevel.headers.index) {
      lines.add('<--- END HTTP (${response.bodyBytes.length}-byte body)');
    }
    _log.debug(lines.join('\n'), fields: {'client': client.name});
  }
}

/// A parameter bound to a path variable, query parameter, header or part:
/// its name in the request, its position in the arguments, and whether a
/// `null` argument is an error (the parameter is not nullable).
typedef _Binding = ({String name, int index, bool required});

/// An encoded multipart body and its `Content-Type`, which carries the
/// boundary.
typedef _Multipart = ({Uint8List bytes, String contentType});

/// How one method becomes a request and how its answer is read, worked
/// out once when the client is created.
final class _Plan {
  _Plan._(
    this.handler,
    this.methodKey,
    this.httpMethod,
    this.path,
    this.pathVariables,
    this.queries,
    this.queryMaps,
    this.headers,
    this.headerMaps,
    this.cookies,
    this.staticHeaders,
    this.body,
    this.parts,
    this.produces,
    this.consumes,
    this.parameters,
    this.eventType,
  );

  static final _variable = RegExp(r'\{([^{}/]+)\}');

  static _Plan? compile(
    FeignInvocationHandler handler,
    ProxyMethod method,
    List<String> problems,
  ) {
    final name = '${handler.typeName}.${method.name}';
    final methodKey =
        '${handler.typeName}#${method.name}'
        '(${method.parameters.map((p) => p.type).join(',')})';
    final mappings = method.annotations.whereType<Mapping>().toList();
    if (mappings.length != 1) {
      problems.add(
        '$name needs exactly one of @GetMapping, @PostMapping, @PutMapping, '
        '@PatchMapping, @DeleteMapping, @RequestMapping',
      );
      return null;
    }
    final eventType = _eventType(method.returnType);
    if (eventType != null && method.isFuture) {
      problems.add(
        '$name returns a Future of a stream: return EventStream<T> directly '
        '(it connects when listened to)',
      );
    } else if (eventType == null && !method.isFuture) {
      problems.add(
        '$name must return a Future (HTTP calls are asynchronous) or an '
        'EventStream<T> (server-sent events)',
      );
    }
    final mapping = mappings.single;
    final path = _join(
      handler.environment.resolvePlaceholders(handler.client.path),
      handler.environment.resolvePlaceholders(mapping.path),
    );
    final pathVariables = <String, _Binding>{};
    final queries = <_Binding>[];
    final queryMaps = <int>[];
    final headers = <_Binding>[];
    final headerMaps = <int>[];
    final cookies = <(String, int)>[];
    final parts = <_Binding>[];
    int? body;
    final unannotated = <int>[];
    // Values of path variables, query parameters, headers and cookies must
    // be single values (or lists of them); maps only for query parameters
    // and headers, one per entry.
    void check(BeanParameter parameter, String role, {bool map = false}) {
      final reason = _unsupported(parameter.type, handler.mapper, map: map);
      if (reason != null) {
        problems.add(
          '$name: the $role parameter ${parameter.name} is $reason '
          '(${parameter.type}); use a String, number, bool, enum, DateTime '
          'or a List of them'
          '${map ? ', or a Map<String, ...> for one per entry' : ''}',
        );
      }
    }

    // A nullable parameter is optional (a null argument is left out, an
    // empty path variable); any other is required. A default value of the
    // Dart parameter is simply the argument.
    _Binding bind(String name, int index) => (
      name: name,
      index: index,
      required: !method.parameters[index].type.nullable,
    );

    for (final (index, parameter) in method.parameters.indexed) {
      final annotations = parameter.annotations;
      final pathVariable = annotations.whereType<PathVariable>().firstOrNull;
      final requestParam = annotations.whereType<RequestParam>().firstOrNull;
      final requestHeader = annotations.whereType<RequestHeader>().firstOrNull;
      final cookieValue = annotations.whereType<CookieValue>().firstOrNull;
      final requestBody = annotations.whereType<RequestBody>().firstOrNull;
      final requestPart = annotations.whereType<RequestPart>().firstOrNull;
      final count = [
        pathVariable,
        requestParam,
        requestHeader,
        cookieValue,
        requestBody,
        requestPart,
      ].whereType<Object>().length;
      if (count > 1) {
        problems.add('$name: parameter ${parameter.name} has several roles');
        continue;
      }
      final isMap = parameter.type is MapType;
      if (pathVariable != null) {
        check(parameter, '@PathVariable');
        final name = pathVariable.name ?? parameter.name;
        pathVariables[name] = bind(name, index);
      } else if (requestParam != null) {
        check(parameter, '@RequestParam', map: true);
        // Like Spring Cloud OpenFeign: a Map is a query map, its name unused.
        if (isMap) {
          queryMaps.add(index);
        } else {
          queries.add(
            bind(requestParam.name ?? parameter.name, index),
          );
        }
      } else if (requestHeader != null) {
        check(parameter, '@RequestHeader', map: true);
        if (isMap) {
          headerMaps.add(index);
        } else {
          headers.add(
            bind(requestHeader.name ?? parameter.name, index),
          );
        }
      } else if (cookieValue != null) {
        check(parameter, '@CookieValue');
        cookies.add((cookieValue.name ?? parameter.name, index));
      } else if (requestBody != null) {
        if (body != null) {
          problems.add('$name has more than one @RequestBody');
        }
        body = index;
      } else if (requestPart != null) {
        parts.add(
          bind(requestPart.name ?? parameter.name, index),
        );
      } else {
        unannotated.add(index);
      }
    }
    // A multipart body: `consumes: multipart/form-data` or a @RequestPart
    // parameter (which needs no other consumes).
    final consumes = mapping.consumes;
    final multipart =
        parts.isNotEmpty || (consumes != null && _isMultipart(consumes));
    if (parts.isNotEmpty && consumes != null && !_isMultipart(consumes)) {
      problems.add(
        '$name has @RequestPart parameters but consumes "$consumes": a '
        'multipart body needs consumes: MediaType.multipartFormData (or none)',
      );
    }
    if (multipart && body != null) {
      problems.add(
        '$name: a multipart method takes @RequestPart parameters, not '
        '@RequestBody (${method.parameters[body].name})',
      );
    }
    // Like Feign: one parameter without annotation is the body (of a
    // method without parts).
    if (unannotated.isNotEmpty) {
      if (body == null && unannotated.length == 1 && !multipart) {
        body = unannotated.single;
      } else {
        for (final index in unannotated) {
          problems.add(
            '$name: parameter ${method.parameters[index].name} needs '
            '@PathVariable, @RequestParam, @RequestHeader, @CookieValue, '
            '${multipart ? '@RequestPart' : '@RequestBody or @RequestPart'}',
          );
        }
      }
    }
    final variables = {
      for (final match in _variable.allMatches(path)) match[1]!,
    };
    for (final variable in variables) {
      if (!pathVariables.containsKey(variable)) {
        problems.add(
          '$name: the path variable {$variable} of "$path" has no '
          '@PathVariable parameter',
        );
      }
    }
    for (final variable in pathVariables.keys) {
      if (!variables.contains(variable)) {
        problems.add(
          '$name: @PathVariable "$variable" is not in the path "$path"',
        );
      }
    }
    final staticHeaders = <(String, String)>[];
    for (final header in mapping.headers) {
      // Spring's syntax, read like Spring Cloud OpenFeign's SpringMvcContract:
      // "Name=value" is sent; "Name", "!Name" and "Name!=value" are
      // conditions for a server and are ignored.
      final equals = header.indexOf('=');
      if (equals < 0 || (equals > 0 && header[equals - 1] == '!')) {
        if (header.contains(':')) {
          problems.add(
            '$name: header "$header" must look like "Name=value" '
            "(Spring's syntax)",
          );
        }
        continue;
      }
      final headerName = header.substring(0, equals).trim();
      if (headerName.isEmpty || headerName.contains(RegExp(r'[\s:]'))) {
        problems.add(
          '$name: header "$header" must look like "Name=value" '
          "(Spring's syntax)",
        );
        continue;
      }
      staticHeaders.add((
        handler.environment.resolvePlaceholders(headerName),
        handler.environment.resolvePlaceholders(
          header.substring(equals + 1).trim(),
        ),
      ));
    }
    return _Plan._(
      handler,
      methodKey,
      mapping.method,
      path,
      pathVariables,
      queries,
      queryMaps,
      headers,
      headerMaps,
      cookies,
      staticHeaders,
      body,
      multipart ? parts : null,
      mapping.produces,
      consumes,
      method.parameters,
      method.isFuture ? null : eventType,
    );
  }

  // The data type T of `EventStream<T>` / `Stream<T>`, or null.
  static TypeInfo<Object?>? _eventType(TypeInfo<Object?> type) =>
      type is GenericType<Object?> && type.isSubtypeOf<Stream<Object?>>()
      ? type.arguments.firstOrNull ?? const DynamicType()
      : null;

  // Why values of [type] cannot go into a URL, a header or a cookie, or
  // null when they can (or only the value itself can tell: `Object`,
  // `dynamic`, classes the mapper writes some other way).
  static String? _unsupported(
    TypeInfo<Object?> type,
    ObjectMapper mapper, {
    bool map = false,
  }) {
    switch (type) {
      case MapType(:final value) when map:
        return value is MapType ? 'a Map of Maps' : _unsupported(value, mapper);
      case MapType():
        return 'a Map';
      case ListType(:final element) || SetType(:final element):
        return element is MapType || element is ListType || element is SetType
            ? 'a nested collection'
            : _unsupported(element, mapper);
      case GenericType():
        return 'an object';
      case ClassType():
        return _isObject(type, mapper) ? 'an object' : null;
      case EnumType() || DynamicType():
        return null;
    }
  }

  // Whether the mapper writes values of [type] as a JSON object: an
  // introspected class with properties, without `toJson()` and without a
  // custom deserializer (which marks a value type with a JSON form of its
  // own).
  static bool _isObject(ClassType<Object?> type, ObjectMapper mapper) {
    final introspection = mapper.introspector.forType(type.type);
    return introspection != null &&
        !introspection.hasToJson &&
        introspection.properties.isNotEmpty &&
        !type.accept(_HasDeserializer(mapper));
  }

  final FeignInvocationHandler handler;
  final String methodKey;
  final HttpMethod httpMethod;
  final String path;
  final Map<String, _Binding> pathVariables;
  final List<_Binding> queries;
  final List<int> queryMaps;
  final List<_Binding> headers;
  final List<int> headerMaps;
  final List<(String, int)> cookies;
  final List<(String, String)> staticHeaders;
  final int? body;

  /// The `@RequestPart` parameters of a multipart method; `null` for a
  /// method that sends no multipart body.
  final List<_Binding>? parts;
  final String? produces;
  final String? consumes;
  final List<BeanParameter> parameters;

  /// The data type `T` of a method returning `EventStream<T>`; `null` for
  /// a normal call.
  final TypeInfo<Object?>? eventType;

  ObjectMapper get mapper => handler.mapper;

  static String _join(String left, String right) {
    if (left.isEmpty) {
      return right;
    }
    if (right.isEmpty) {
      return left;
    }
    final a = left.endsWith('/') ? left.substring(0, left.length - 1) : left;
    final b = right.startsWith('/') ? right : '/$right';
    return '$a$b';
  }

  // The argument of [binding]: null for an optional one, else an error
  // naming the parameter.
  Object? _valueOf(List<Object?> arguments, _Binding binding, String role) {
    final value = arguments[binding.index];
    if (value != null) {
      return value;
    }
    if (binding.required) {
      throw _missing(role, binding);
    }
    return null;
  }

  ArgumentError _missing(String role, _Binding binding) => ArgumentError(
    'The required $role "${binding.name}" of $methodKey must not be null',
    parameters[binding.index].name,
  );

  /// A new template for a call with [arguments]: the path with its
  /// variables, the query, the headers and cookies, and the body (for a
  /// multipart method, the body built by [multipart]). The configured
  /// defaults are not in it yet: [applyDefaults] adds them after the
  /// interceptors. A `null` argument for a non-nullable parameter throws
  /// an [ArgumentError]; for a nullable one, the query parameter, header
  /// or cookie is left out and a path variable becomes an empty string. A
  /// path variable `.` or `..` (or with such a segment between slashes)
  /// throws an [ArgumentError] too.
  RequestTemplate template(List<Object?> arguments, _Multipart? multipart) {
    final decodeSlash = handler.config.decodeSlash;
    var expanded = path;
    for (final MapEntry(key: name, value: binding) in pathVariables.entries) {
      final value = arguments[binding.index];
      if (value == null) {
        if (binding.required) {
          throw _missing('@PathVariable', binding);
        }
        // Like Spring's URI template expansion: null is an empty string.
        expanded = expanded.replaceAll('{$name}', '');
        continue;
      }
      final encoded = Uri.encodeComponent(
        _joined(value, parameters[binding.index].type, '@PathVariable "$name"'),
      );
      // Spring Cloud OpenFeign's decode-slash: "a/b" stays a path.
      final segment = decodeSlash ? encoded.replaceAll('%2F', '/') : encoded;
      // `.` and `..` would move the call to another path: Dart's Uri
      // removes dot segments, `%2E` included, before the request is sent.
      if (segment.split('/').any((part) => part == '.' || part == '..')) {
        throw ArgumentError.value(
          value,
          parameters[binding.index].name,
          'The @PathVariable "$name" of $methodKey must not be "." or ".." '
          '(nor contain such a segment): it would change the path of the '
          'URL',
        );
      }
      expanded = expanded.replaceAll('{$name}', segment);
    }
    var url = Uri.parse(_join(handler._baseUrl, expanded));
    // A query written in the mapping path stays as written; the
    // parameters of the call are appended to it.
    final query = <String, List<String>>{};
    void addQuery(String name, Object? value, TypeInfo<Object?> type) {
      // forEach would create the entry of a parameter without values too.
      // ignore: prefer_foreach
      for (final text in _texts(value, type, '@RequestParam "$name"')) {
        (query[name] ??= []).add(text);
      }
    }

    for (final binding in queries) {
      addQuery(
        binding.name,
        _valueOf(arguments, binding, '@RequestParam'),
        parameters[binding.index].type,
      );
    }
    for (final index in queryMaps) {
      final type = parameters[index].type;
      final valueType = type is MapType ? type.value : const DynamicType();
      _entries(
        arguments[index],
        '@RequestParam ${parameters[index].name}',
      ).forEach((name, value) => addQuery(name, value, valueType));
    }
    if (query.isNotEmpty) {
      url = appendQuery(url, [
        for (final MapEntry(key: name, value: values) in query.entries)
          for (final value in values) (name, value),
      ]);
    }
    final requestHeaders = HttpHeaders();
    for (final (name, value) in staticHeaders) {
      requestHeaders.add(name, value);
    }
    void setHeader(String name, Object? value, TypeInfo<Object?> type) {
      final texts = _texts(value, type, '@RequestHeader "$name"');
      if (texts.isEmpty) {
        return;
      }
      requestHeaders.remove(name);
      for (final text in texts) {
        requestHeaders.add(name, text);
      }
    }

    for (final binding in headers) {
      setHeader(
        binding.name,
        _valueOf(arguments, binding, '@RequestHeader'),
        parameters[binding.index].type,
      );
    }
    for (final index in headerMaps) {
      final type = parameters[index].type;
      final valueType = type is MapType ? type.value : const DynamicType();
      _entries(
        arguments[index],
        '@RequestHeader ${parameters[index].name}',
      ).forEach((name, value) => setHeader(name, value, valueType));
    }
    // Like Spring Cloud OpenFeign: the cookies of the call in one header.
    final cookieValues = [
      for (final (name, index) in cookies)
        if (arguments[index] case final value?)
          // The interpolation cannot be wrapped (dart format keeps it).
          // ignore: lines_longer_than_80_chars
          '$name=${_joined(value, parameters[index].type, '@CookieValue "$name"')}',
    ];
    if (cookieValues.isNotEmpty) {
      final existing = requestHeaders[HttpHeaders.cookieHeader];
      requestHeaders.set(
        HttpHeaders.cookieHeader,
        [?existing, ...cookieValues].join('; '),
      );
    }
    if (eventType != null && !requestHeaders.contains('Cache-Control')) {
      requestHeaders.set('Cache-Control', 'no-cache');
    }
    List<int>? bytes;
    final bodyIndex = body;
    if (multipart != null) {
      // The encoder's type with the boundary replaces any other (an
      // explicit `consumes: multipart/form-data` too).
      bytes = multipart.bytes;
      requestHeaders.contentType = multipart.contentType;
    } else if (bodyIndex != null && arguments[bodyIndex] != null) {
      final value = arguments[bodyIndex]!;
      final String contentType;
      final declared = requestHeaders.contentType ?? consumes;
      final form = declared != null && _isForm(declared);
      if (value is Uint8List) {
        bytes = value;
        contentType = MediaType.applicationOctetStream;
      } else if (value is String) {
        bytes = utf8.encode(value);
        contentType = '${MediaType.textPlain}; charset=utf-8';
      } else if (form) {
        // Like Spring Cloud OpenFeign's SpringFormEncoder: a Map or an
        // object as `name=value&...`.
        bytes = ascii.encode(
          _formBody(value, parameters[bodyIndex].type, declared),
        );
        contentType = declared;
      } else {
        try {
          bytes = utf8.encode(mapper.writeValueAsString(value));
        } on Object catch (error) {
          throw EncodeException(
            'cannot write the body of $methodKey: $error',
            cause: error,
          );
        }
        contentType = MediaType.applicationJson;
      }
      if (!requestHeaders.contains(HttpHeaders.contentTypeHeader)) {
        requestHeaders.contentType = consumes ?? contentType;
      }
    }
    return RequestTemplate(
      method: httpMethod,
      url: url,
      methodKey: methodKey,
      clientName: handler.client.name,
      headers: requestHeaders,
      body: bytes,
    );
  }

  static bool _isForm(String contentType) =>
      _is(contentType, MediaType.applicationFormUrlencoded);

  static bool _isMultipart(String contentType) =>
      _is(contentType, MediaType.multipartFormData);

  static bool _is(String contentType, String expected) {
    try {
      return MediaType.parse(contentType)
          .equalsTypeAndSubtype(MediaType.parse(expected));
    } on ArgumentError {
      return false;
    }
  }

  /// The `multipart/form-data` body of a call with [arguments], built
  /// once per call so that retries send the same bytes; `null` for a
  /// method without `@RequestPart` parameters. As with Spring Cloud
  /// OpenFeign's `SpringFormEncoder`, each `@RequestPart` becomes:
  /// - a `MultipartFile` (or a list of them): a file part each, with the
  ///   file's name and content type;
  /// - `Uint8List` / `List<int>`: a file part without file name;
  /// - a String, number, bool, enum or DateTime (or a list of them): a
  ///   text field each;
  /// - anything else (an object, a Map, a list of objects): a JSON part
  ///   written with the client's `ObjectMapper`.
  ///
  /// A `null` argument leaves the part out for a nullable parameter, and
  /// throws an [ArgumentError] for any other.
  Future<_Multipart?> multipart(List<Object?> arguments) async {
    final bindings = parts;
    if (bindings == null) {
      return null;
    }
    final encoded = <MultipartBodyPart>[];
    for (final binding in bindings) {
      final value = arguments[binding.index];
      if (value == null) {
        if (binding.required) {
          throw _missing('@RequestPart', binding);
        }
        continue;
      }
      encoded.addAll(
        await _parts(binding.name, value, parameters[binding.index].type),
      );
    }
    final body = MultipartBody(encoded);
    return (bytes: body.encode(), contentType: body.contentType);
  }

  Future<List<MultipartBodyPart>> _parts(
    String name,
    Object value,
    TypeInfo<Object?> type,
  ) async {
    final what = '@RequestPart "$name"';
    switch (value) {
      case MultipartFile():
        return [await _file(name, value)];
      case Uint8List():
        return [MultipartBodyPart.file(name, value)];
      case String() || num() || bool() || DateTime() || Enum():
        return [MultipartBodyPart.field(name, _text(value, type, what))];
      case List<int>() when _isBytes(type):
        return [MultipartBodyPart.file(name, value)];
      case Iterable<Object?>()
          when value.every((item) => item == null || item is MultipartFile):
        return [
          for (final file in value.whereType<MultipartFile>())
            await _file(name, file),
        ];
      case Iterable<Object?>()
          when value.every((item) => item == null || _isSimple(item)):
        return [
          for (final text in _texts(value, type, what))
            MultipartBodyPart.field(name, text),
        ];
      case Map() || Iterable():
        return [MultipartBodyPart.json(name, _json(value, what))];
    }
    // A value type with a JSON form of its own (e.g. `Money` as "10 EUR")
    // is a text field; an object a JSON part.
    final Object? tree;
    try {
      tree = mapper.valueToTree(value, type);
    } on JsonMappingException catch (error) {
      throw EncodeException(
        'cannot write $what of $methodKey: $error',
        cause: error,
      );
    }
    return switch (tree) {
      String() || num() || bool() => [MultipartBodyPart.field(name, '$tree')],
      _ => [MultipartBodyPart.json(name, _json(value, what))],
    };
  }

  static bool _isSimple(Object value) =>
      value is String ||
      value is num ||
      value is bool ||
      value is DateTime ||
      value is Enum;

  // Whether [type] is `List<int>` (bytes, like Java's `byte[]`).
  static bool _isBytes(TypeInfo<Object?> type) =>
      type is ListType<Object?> && type.element.type == int;

  static Future<MultipartBodyPart> _file(
    String name,
    MultipartFile file,
  ) async => MultipartBodyPart.file(
    name,
    await file.bytes,
    filename: file.originalFilename,
    contentType: file.contentType,
  );

  String _json(Object value, String what) {
    try {
      return mapper.writeValueAsString(value);
    } on Object catch (error) {
      throw EncodeException(
        'cannot write $what of $methodKey: $error',
        cause: error,
      );
    }
  }

  // [value] (a Map or an object the mapper writes as one) as an
  // `application/x-www-form-urlencoded` body in the charset of
  // [contentType] (UTF-8 by default): one `name=value` per entry, one per
  // item of a list, null values left out.
  String _formBody(Object value, TypeInfo<Object?> type, String contentType) {
    const what = 'the form body';
    final Object? tree;
    try {
      tree = value is Map ? value : mapper.valueToTree(value, type);
    } on JsonMappingException catch (error) {
      throw EncodeException(
        'cannot write $what of $methodKey: $error',
        cause: error,
      );
    }
    if (tree is! Map<Object?, Object?>) {
      throw EncodeException(
        '$what of $methodKey must be a Map or an object, not '
        '${value.runtimeType}',
      );
    }
    final encoding = MediaType.parse(contentType).charset ?? utf8;
    String encode(String text) =>
        Uri.encodeQueryComponent(text, encoding: encoding);
    final valueType = type is MapType ? type.value : const DynamicType();
    return [
      for (final MapEntry(:key, value: item) in tree.entries)
        if (key != null && item != null)
          for (final text in _texts(item, valueType, '$what entry "$key"'))
            '${encode('$key')}=${encode(text)}',
    ].join('&');
  }

  /// Adds what the configuration sets for every request, after the
  /// interceptors ran: the `default-request-headers` and
  /// `default-query-parameters` whose names the request does not have
  /// yet, and an `Accept` header when there is none (the mapping's
  /// `produces`, else `application/json`, or `text/event-stream` for an
  /// event stream).
  void applyDefaults(RequestTemplate template) {
    final config = handler.config;
    final headers = template.headers;
    config.defaultRequestHeaders.forEach((name, values) {
      if (!headers.contains(name)) {
        for (final value in values) {
          headers.add(name, value);
        }
      }
    });
    final query = template.url.queryParametersAll;
    config.defaultQueryParameters.forEach((name, values) {
      if (!query.containsKey(name)) {
        for (final value in values) {
          template.query(name, value);
        }
      }
    });
    if (!headers.contains(HttpHeaders.acceptHeader)) {
      headers.set(
        HttpHeaders.acceptHeader,
        produces ??
            (eventType != null
                ? MediaType.textEventStream
                : MediaType.applicationJson),
      );
    }
  }

  // The entries of a Map argument, keys as text (null: none).
  Map<String, Object?> _entries(Object? value, String what) => switch (value) {
    null => const {},
    final Map<Object?, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries)
        if (key != null) _text(key, const DynamicType(), what): value,
    },
    _ => throw EncodeException(
      '$what of $methodKey must be a Map, not ${value.runtimeType}',
    ),
  };

  // A query or header value as texts: none for null, one per item of a
  // list (null items left out).
  List<String> _texts(Object? value, TypeInfo<Object?> type, String what) {
    if (value == null) {
      return const [];
    }
    if (value is Iterable<Object?>) {
      final element = switch (type) {
        ListType(:final element) || SetType(:final element) => element,
        _ => const DynamicType(),
      };
      return [
        for (final item in value)
          if (item != null) _text(item, element, what),
      ];
    }
    return [_text(value, type, what)];
  }

  // A path variable or cookie value as text: a list joined with commas.
  String _joined(Object value, TypeInfo<Object?> type, String what) =>
      value is Iterable<Object?>
      ? _texts(value, type, what).join(',')
      : _text(value, type, what);

  // One value as text: enums by their JSON form, dates in ISO-8601; a
  // value the mapper writes as a JSON object or array is an error.
  String _text(Object value, TypeInfo<Object?> type, String what) {
    switch (value) {
      case String():
        return value;
      case num() || bool():
        return '$value';
      case DateTime():
        return value.toIso8601String();
    }
    final Object? tree;
    try {
      tree = mapper.valueToTree(value, type);
    } on JsonMappingException catch (error) {
      throw EncodeException(
        'cannot write $what of $methodKey: $error',
        cause: error,
      );
    }
    return switch (tree) {
      String() || num() || bool() => '$tree',
      _ => throw EncodeException(
        '$what of $methodKey is ${tree is List ? 'a list' : 'an object'} '
        '(${value.runtimeType}): it needs a single value such as a String, '
        'a number or an enum',
      ),
    };
  }

  static final _skip = Object();

  // The value of one event's [data] ([_skip] for empty data of a non-text
  // type); throws DecodeException.
  Object? decodeEvent(String data, TypeInfo<Object?> type) {
    if (type.type == String) {
      return data;
    }
    if (data.isEmpty) {
      return _skip;
    }
    try {
      return mapper.treeToValue<Object?>(jsonDecode(data), type);
    } on JsonMappingException catch (error) {
      throw DecodeException(
        200,
        'cannot read an event of $methodKey: $error',
        cause: error,
      );
    } on FormatException catch (error) {
      throw DecodeException(
        200,
        'an event of $methodKey is not JSON: ${error.message}',
        cause: error,
      );
    }
  }

  /// Whether [method] returns the raw `HttpResponse` (Feign's
  /// `Response`). Such a method gets every response as it is: no error
  /// decoding, no 404 handling, no body decoding.
  static bool isRaw(ProxyMethod method) =>
      method.returnType is ClassType<Object?> &&
      method.returnType.type == HttpResponse;

  Object? decode(HttpResponse response, ProxyMethod method) {
    if (isRaw(method)) {
      return response;
    }
    final status = response.statusCode;
    final type = method.returnType;
    final entity =
        type is GenericType<Object?> &&
        type.isSubtypeOf<ResponseEntity<Object?>>();
    // A dismissed 404 (never for void methods, see _send).
    if (status == HttpStatus.notFound && handler.dismiss404) {
      if (entity) {
        return _entity(type, response, null);
      }
      if (type.nullable) {
        return null;
      }
      throw FeignException.errorStatus(methodKey, response);
    }
    if (method.isVoid) {
      return null;
    }
    if (entity) {
      final bodyType = type.arguments.firstOrNull ?? const DynamicType();
      // ResponseEntity<void>: the body is ignored, like Spring.
      if (bodyType case DynamicType(isVoid: true)) {
        return _entity(type, response, null);
      }
      return _entity(type, response, _body(response, bodyType, emptyOk: true));
    }
    return _body(response, type);
  }

  ResponseEntity<Object?> _entity(
    GenericType<Object?> type,
    HttpResponse response,
    Object? body,
  ) => (type.arguments.firstOrNull ?? const DynamicType()).accept(
    _EntityFactory(response.statusCode, body, response.headers),
  );

  Object? _body(
    HttpResponse response,
    TypeInfo<Object?> type, {
    bool emptyOk = false,
  }) {
    final bytes = response.bodyBytes;
    if (bytes.isEmpty || response.statusCode == HttpStatus.noContent) {
      if (emptyOk || type.nullable) {
        return null;
      }
      throw DecodeException(
        response.statusCode,
        'empty response body for $methodKey, expected $type',
        request: response.request,
      );
    }
    if (type.type == Uint8List) {
      return bytes;
    }
    if (type.type == String) {
      return response.bodyText;
    }
    try {
      return mapper.treeToValue<Object?>(jsonDecode(response.bodyText), type);
    } on JsonMappingException catch (error) {
      throw DecodeException(
        response.statusCode,
        'cannot read the response of $methodKey: $error',
        request: response.request,
        cause: error,
      );
    } on FormatException catch (error) {
      throw DecodeException(
        response.statusCode,
        'the response of $methodKey is not JSON: ${error.message}',
        request: response.request,
        cause: error,
      );
    }
  }
}

/// Builds a `ResponseEntity<T>` whose type argument is the declared body
/// type, so the generated code's cast to the method's return type
/// succeeds.
final class _EntityFactory implements TypeInfoVisitor<ResponseEntity<Object?>> {
  _EntityFactory(this.status, this.body, this.headers);

  final int status;
  final Object? body;
  final HttpHeaders headers;

  @override
  ResponseEntity<Object?> visitClass<T>(ClassType<T> type) =>
      ResponseEntity<T>(status, body: body as T?, headers: headers);

  @override
  ResponseEntity<Object?> visitList<E>(ListType<E> type) =>
      ResponseEntity<List<E>>(status, body: body as List<E>?, headers: headers);

  @override
  ResponseEntity<Object?> visitSet<E>(SetType<E> type) =>
      ResponseEntity<Set<E>>(status, body: body as Set<E>?, headers: headers);

  @override
  ResponseEntity<Object?> visitMap<K, V>(MapType<K, V> type) =>
      ResponseEntity<Map<K, V>>(
        status,
        body: body as Map<K, V>?,
        headers: headers,
      );

  @override
  ResponseEntity<Object?> visitEnum<E extends Enum>(EnumType<E> type) =>
      ResponseEntity<E>(status, body: body as E?, headers: headers);

  @override
  ResponseEntity<Object?> visitGeneric<T>(GenericType<T> type) =>
      ResponseEntity<T>(status, body: body as T?, headers: headers);

  @override
  ResponseEntity<Object?> visitDynamic(DynamicType type) =>
      ResponseEntity<Object?>(status, body: body, headers: headers);
}

/// Builds the `EventStream<T>` of an event stream method with the data
/// type's type argument, so the generated cast succeeds.
final class _EventStreamFactory
    implements TypeInfoVisitor<EventStream<Object?>> {
  _EventStreamFactory(this.handler, this.plan, this.method, this.arguments);

  final FeignInvocationHandler handler;
  final _Plan plan;
  final ProxyMethod method;
  final List<Object?> arguments;

  EventStream<T> _create<T>(TypeInfo<Object?> type) => EventStream<T>(
    () => _withFallback<T>(
      handler
          ._openEvents(plan, arguments)
          .transform(
            StreamTransformer<
              ServerSentEvent<String>,
              ServerSentEvent<T>
            >.fromHandlers(
              handleData: (event, sink) {
                try {
                  final value = plan.decodeEvent(event.data, type);
                  if (!identical(value, _Plan._skip)) {
                    sink.add(event.withData<T>(value as T));
                  }
                } on Object catch (error, stackTrace) {
                  sink.addError(error, stackTrace);
                }
              },
            ),
          ),
    ),
  );

  // When the stream fails before its first event, the fallback's stream
  // takes over (decoding errors do not count).
  Stream<ServerSentEvent<T>> _withFallback<T>(
    Stream<ServerSentEvent<T>> source,
  ) {
    final fallback = handler.fallback;
    if (fallback == null) {
      return source;
    }
    return Stream<ServerSentEvent<T>>.multi((controller) {
      var received = false;
      StreamSubscription<ServerSentEvent<T>>? current;
      void follow(Stream<ServerSentEvent<T>> stream, {required bool primary}) {
        current = stream.listen(
          (event) {
            received = true;
            controller.add(event);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (primary && !received && error is! DecodeException) {
              final failed = current;
              current = null;
              unawaited(failed?.cancel());
              handler._log.debug(
                'fallback for ${plan.methodKey} after $error',
                fields: {'client': handler.client.name},
              );
              final Stream<ServerSentEvent<T>> backup;
              try {
                final result = method.callOn(fallback(), arguments);
                backup = result is EventStream<T>
                    ? result.events
                    : (result! as Stream<T>).map(ServerSentEvent<T>.new);
              } on Object catch (fallbackError, fallbackStack) {
                controller.addError(fallbackError, fallbackStack);
                unawaited(controller.close());
                return;
              }
              follow(backup, primary: false);
              return;
            }
            controller.addError(error, stackTrace);
          },
          onDone: controller.close,
        );
      }

      follow(source, primary: true);
      controller
        ..onPause = (() => current?.pause())
        ..onResume = (() => current?.resume())
        ..onCancel = (() => current?.cancel());
    });
  }

  @override
  EventStream<Object?> visitClass<T>(ClassType<T> type) => _create<T>(type);

  @override
  EventStream<Object?> visitList<E>(ListType<E> type) => _create<List<E>>(type);

  @override
  EventStream<Object?> visitSet<E>(SetType<E> type) => _create<Set<E>>(type);

  @override
  EventStream<Object?> visitMap<K, V>(MapType<K, V> type) =>
      _create<Map<K, V>>(type);

  @override
  EventStream<Object?> visitEnum<E extends Enum>(EnumType<E> type) =>
      _create<E>(type);

  @override
  EventStream<Object?> visitGeneric<T>(GenericType<T> type) => _create<T>(type);

  @override
  EventStream<Object?> visitDynamic(DynamicType type) => _create<Object?>(type);
}

/// Whether a custom `JsonDeserializer` of the mapper reads the class: the
/// sign of a value type with a JSON form of its own (such as `Money` as
/// `"10 EUR"`), which may then be used as a single value in a path, query
/// or header.
final class _HasDeserializer implements TypeInfoVisitor<bool> {
  _HasDeserializer(this.mapper);

  final ObjectMapper mapper;

  @override
  bool visitClass<T>(ClassType<T> type) =>
      mapper.deserializers.any((deserializer) => deserializer.handles<T>());

  @override
  bool visitList<E>(ListType<E> type) => false;

  @override
  bool visitSet<E>(SetType<E> type) => false;

  @override
  bool visitMap<K, V>(MapType<K, V> type) => false;

  @override
  bool visitEnum<E extends Enum>(EnumType<E> type) => false;

  @override
  bool visitGeneric<T>(GenericType<T> type) => false;

  @override
  bool visitDynamic(DynamicType type) => false;
}
