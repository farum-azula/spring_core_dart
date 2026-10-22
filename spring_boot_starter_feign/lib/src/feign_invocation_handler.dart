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

/// Performs the calls of one `@FeignClient` interface: builds the request
/// from the mapping annotations and arguments, runs the
/// [RequestInterceptor]s, sends it with retries, turns errors into
/// exceptions and the body into the method's return type, and calls the
/// fallback when the call fails. Created by `FeignClientFactory`.
///
/// Every method is checked when the client bean is created, so a path
/// variable without a parameter or a method without a mapping stops the
/// application at startup with the reason.
///
/// Methods returning `EventStream<T>` (or `Stream<T>`) read
/// `text/event-stream` responses: each listener opens a connection, every
/// event's data is decoded into `T`, and lost connections are opened again
/// with `Last-Event-ID` (see `FeignClientConfig.eventStreamReconnect`).
///
/// Spring (Java): Feign's `SynchronousMethodHandler` behind the proxy that
/// `FeignClientFactoryBean` creates.
final class FeignInvocationHandler implements InvocationHandler {
  /// The handler of the interface described by [metadata].
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
        'Invalid Feign client $typeName:\n${problems.map((p) => '  - $p').join('\n')}',
      );
    }
  }

  /// The interface name.
  final String typeName;

  /// The `@FeignClient` annotation.
  final FeignClient client;

  /// The client's settings.
  final FeignClientConfig config;

  /// Placeholders in `url`, `path` and headers are resolved here.
  final Environment environment;

  /// Writes request bodies and reads response bodies.
  final ObjectMapper mapper;

  /// Sends the requests.
  final HttpTransport transport;

  /// Applied to every request, in order.
  final List<RequestInterceptor> interceptors;

  /// Turns error responses into exceptions.
  final ErrorDecoder errorDecoder;

  /// Decides about retries.
  final Retryer retryer;

  /// Returns the fallback bean (looked up on the first failure).
  final Object Function()? fallback;

  final SpringLog _log;
  final _plans = Map<ProxyMethod, _Plan>.identity();
  late final String _baseUrl;

  String _resolveBaseUrl(List<String> problems) {
    final url = client.url ?? config.url;
    if (url == null || url.trim().isEmpty) {
      problems.add(
        'no URL: set @FeignClient(url: ...) or '
        'spring.cloud.openfeign.client.config.${client.name}.url',
      );
      return '';
    }
    try {
      return environment.resolveRequiredPlaceholders(url.trim());
    } on Object catch (error) {
      problems.add('cannot resolve the URL "$url": $error');
      return '';
    }
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
    final template = plan.template(arguments);
    if (lastEventId != null) {
      template.header('Last-Event-ID', lastEventId);
    }
    for (final interceptor in interceptors) {
      await interceptor.apply(template);
    }
    final request = HttpRequest(
      method: template.method,
      url: template.url,
      headers: template.headers,
      body: template.body,
      timeout: config.readTimeout,
    );
    final watch = Stopwatch()..start();
    _logRequest(request);
    final StreamedHttpResponse response;
    try {
      response = await transport.stream(request);
    } on HttpTransportException catch (error) {
      _log.debug(
        '<--- ERROR ${error.message} (${watch.elapsedMilliseconds} ms)',
        fields: {'client': client.name},
      );
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
          '<--- $status ${HttpStatus.reasonPhrase(status)} '
          '(${watch.elapsedMilliseconds} ms, event stream)',
          fields: {'client': client.name},
        );
      }
      return response;
    }
    final whole = await response.read();
    _logResponse(whole, watch.elapsed);
    if (status == 404 && config.dismiss404) {
      // Like an empty result: the stream ends.
      return StreamedHttpResponse(
        HttpStatus.noContent,
        body: const Stream.empty(),
        request: request,
      );
    }
    throw errorDecoder.decode(plan.methodKey, whole);
  }

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
    final template = plan.template(arguments);
    for (final interceptor in interceptors) {
      await interceptor.apply(template);
    }
    final request = HttpRequest(
      method: template.method,
      url: template.url,
      headers: template.headers,
      body: template.body,
      timeout: config.readTimeout,
    );
    for (var attempt = 1; ; attempt++) {
      try {
        final response = await _send(request, plan, method);
        return plan.decode(response, method);
      } on RetryableException catch (error) {
        final delay = retryer.nextDelay(attempt, error);
        if (delay == null) {
          rethrow;
        }
        _log.debug(
          '---> RETRYING ${plan.methodKey} (attempt ${attempt + 1}) in '
          '${delay.inMilliseconds} ms',
          fields: {'client': client.name},
        );
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
      _log.debug(
        '<--- ERROR ${error.message} (${watch.elapsedMilliseconds} ms)',
        fields: {'client': client.name},
      );
      throw RetryableException(
        -1,
        '${error.message} executing ${request.method.value} ${request.url}',
        request: request,
        cause: error,
      );
    }
    _logResponse(response, watch.elapsed);
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return response;
    }
    if (status == 404 && config.dismiss404) {
      return response;
    }
    throw errorDecoder.decode(plan.methodKey, response);
  }

  void _logRequest(HttpRequest request) {
    if (config.loggerLevel == FeignLoggerLevel.none) {
      return;
    }
    final lines = ['---> ${request.method.value} ${request.url}'];
    if (config.loggerLevel.index >= FeignLoggerLevel.headers.index) {
      request.headers.forEach((name, value) {
        lines.add(
          '$name: ${name.toLowerCase() == 'authorization' ? '***' : value}',
        );
      });
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

  void _logResponse(HttpResponse response, Duration elapsed) {
    if (config.loggerLevel == FeignLoggerLevel.none) {
      return;
    }
    final lines = [
      '<--- ${response.statusCode} ${HttpStatus.reasonPhrase(response.statusCode)} '
          '(${elapsed.inMilliseconds} ms)',
    ];
    if (config.loggerLevel.index >= FeignLoggerLevel.headers.index) {
      response.headers.forEach((name, value) => lines.add('$name: $value'));
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

/// How one method becomes a request, worked out once.
final class _Plan {
  _Plan._(
    this.handler,
    this.methodKey,
    this.httpMethod,
    this.path,
    this.pathVariables,
    this.queries,
    this.headers,
    this.staticHeaders,
    this.body,
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
    final pathVariables = <String, int>{};
    final queries = <(String, int)>[];
    final headers = <(String, int)>[];
    int? body;
    final unannotated = <int>[];
    for (final (index, parameter) in method.parameters.indexed) {
      final pathVariable = parameter.annotations
          .whereType<PathVariable>()
          .firstOrNull;
      final requestParam = parameter.annotations
          .whereType<RequestParam>()
          .firstOrNull;
      final requestHeader = parameter.annotations
          .whereType<RequestHeader>()
          .firstOrNull;
      final requestBody = parameter.annotations
          .whereType<RequestBody>()
          .firstOrNull;
      final count = [
        pathVariable,
        requestParam,
        requestHeader,
        requestBody,
      ].whereType<Object>().length;
      if (count > 1) {
        problems.add('$name: parameter ${parameter.name} has several roles');
        continue;
      }
      if (pathVariable != null) {
        pathVariables[pathVariable.name ?? parameter.name] = index;
      } else if (requestParam != null) {
        queries.add((requestParam.name ?? parameter.name, index));
      } else if (requestHeader != null) {
        headers.add((requestHeader.name ?? parameter.name, index));
      } else if (requestBody != null) {
        if (body != null) {
          problems.add('$name has more than one @RequestBody');
        }
        body = index;
      } else {
        unannotated.add(index);
      }
    }
    // Like Feign: one parameter without annotation is the body.
    if (unannotated.isNotEmpty) {
      if (body == null && unannotated.length == 1) {
        body = unannotated.single;
      } else {
        for (final index in unannotated) {
          problems.add(
            '$name: parameter ${method.parameters[index].name} needs '
            '@PathVariable, @RequestParam, @RequestHeader or @RequestBody',
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
      final colon = header.indexOf(':');
      if (colon <= 0) {
        problems.add('$name: header "$header" must look like "Name: value"');
        continue;
      }
      staticHeaders.add((
        header.substring(0, colon).trim(),
        handler.environment.resolvePlaceholders(
          header.substring(colon + 1).trim(),
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
      headers,
      staticHeaders,
      body,
      mapping.produces,
      mapping.consumes,
      method.parameters,
      method.isFuture ? null : eventType,
    );
  }

  // The data type T of `EventStream<T>` / `Stream<T>`, or null.
  static TypeInfo<Object?>? _eventType(TypeInfo<Object?> type) =>
      type is GenericType<Object?> && type.isSubtypeOf<Stream<Object?>>()
      ? type.arguments.firstOrNull ?? const DynamicType()
      : null;

  final FeignInvocationHandler handler;
  final String methodKey;
  final HttpMethod httpMethod;
  final String path;
  final Map<String, int> pathVariables;
  final List<(String, int)> queries;
  final List<(String, int)> headers;
  final List<(String, String)> staticHeaders;
  final int? body;
  final String? produces;
  final String? consumes;
  final List<BeanParameter> parameters;

  /// The data type of an event stream method (`null`: a normal call).
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

  RequestTemplate template(List<Object?> arguments) {
    var expanded = path;
    for (final MapEntry(key: name, value: index) in pathVariables.entries) {
      final value = arguments[index];
      if (value == null) {
        throw ArgumentError(
          'The path variable "$name" of $methodKey must not be null',
        );
      }
      expanded = expanded.replaceAll(
        '{$name}',
        Uri.encodeComponent(_text(value, parameters[index].type)),
      );
    }
    var url = Uri.parse(_join(handler._baseUrl, expanded));
    final query = {
      for (final MapEntry(:key, :value) in url.queryParametersAll.entries)
        key: [...value],
    };
    for (final (name, index) in queries) {
      final value = arguments[index];
      if (value == null) {
        continue;
      }
      final type = parameters[index].type;
      final elementType = switch (type) {
        ListType(:final element) || SetType(:final element) => element,
        _ => type,
      };
      final items = value is Iterable<Object?> ? value : <Object?>[value];
      for (final item in items) {
        if (item != null) {
          (query[name] ??= []).add(_text(item, elementType));
        }
      }
    }
    if (query.isNotEmpty) {
      url = url.replace(queryParameters: query);
    }
    final requestHeaders = HttpHeaders();
    handler.config.defaultRequestHeaders.forEach(requestHeaders.set);
    for (final (name, value) in staticHeaders) {
      requestHeaders.set(name, value);
    }
    final stream = eventType != null;
    if (!requestHeaders.contains(HttpHeaders.accept)) {
      requestHeaders.set(
        HttpHeaders.accept,
        produces ??
            (stream ? MediaType.textEventStream : MediaType.applicationJson),
      );
    }
    if (stream && !requestHeaders.contains('Cache-Control')) {
      requestHeaders.set('Cache-Control', 'no-cache');
    }
    for (final (name, index) in headers) {
      final value = arguments[index];
      if (value == null) {
        continue;
      }
      if (value is Iterable<Object?>) {
        requestHeaders.remove(name);
        for (final item in value) {
          if (item != null) {
            requestHeaders.add(name, _text(item, const DynamicType()));
          }
        }
      } else {
        requestHeaders.set(name, _text(value, parameters[index].type));
      }
    }
    List<int>? bytes;
    final bodyIndex = body;
    if (bodyIndex != null && arguments[bodyIndex] != null) {
      final value = arguments[bodyIndex]!;
      final String contentType;
      if (value is Uint8List) {
        bytes = value;
        contentType = MediaType.applicationOctetStream;
      } else if (value is String) {
        bytes = utf8.encode(value);
        contentType = '${MediaType.textPlain}; charset=utf-8';
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
      if (!requestHeaders.contains(HttpHeaders.contentType)) {
        requestHeaders.set(HttpHeaders.contentType, consumes ?? contentType);
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

  // A path, query or header value as text: enums by their JSON form,
  // dates in ISO-8601, objects as JSON.
  String _text(Object value, TypeInfo<Object?> type) {
    switch (value) {
      case String():
        return value;
      case num() || bool():
        return '$value';
      case DateTime():
        return value.toIso8601String();
    }
    final tree = mapper.valueToTree(value, type);
    return switch (tree) {
      String() || num() || bool() => '$tree',
      _ => jsonEncode(tree),
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

  Object? decode(HttpResponse response, ProxyMethod method) {
    final status = response.statusCode;
    final type = method.returnType;
    final entity =
        type is GenericType<Object?> &&
        type.isSubtypeOf<ResponseEntity<Object?>>();
    if (status == 404 && handler.config.dismiss404) {
      if (entity) {
        return _entity(type, response, null);
      }
      if (method.isVoid || type.nullable) {
        return null;
      }
      throw FeignException.errorStatus(methodKey, response);
    }
    if (method.isVoid) {
      return null;
    }
    if (entity) {
      final bodyType = type.arguments.firstOrNull ?? const DynamicType();
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

/// Builds a `ResponseEntity<T>` with the body type's type argument.
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
                controller
                  ..addError(fallbackError, fallbackStack)
                  ..close();
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
