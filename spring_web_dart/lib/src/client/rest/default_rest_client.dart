import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/client/http_response.dart';
import 'package:spring_web_dart/src/client/http_transport.dart';
import 'package:spring_web_dart/src/client/rest/client_http_request_interceptor.dart';
import 'package:spring_web_dart/src/client/rest/http_message_converter.dart';
import 'package:spring_web_dart/src/client/rest/rest_client.dart';
import 'package:spring_web_dart/src/client/rest/rest_client_exception.dart';
import 'package:spring_web_dart/src/client/rest/uri_builder.dart';
import 'package:spring_web_dart/src/client/rest/uri_template.dart';
import 'package:spring_web_dart/src/client/streamed_http_response.dart';
import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_method.dart';
import 'package:spring_web_dart/src/http_secrets.dart';
import 'package:spring_web_dart/src/http_status.dart';
import 'package:spring_web_dart/src/media_type.dart';
import 'package:spring_web_dart/src/response_entity.dart';
import 'package:spring_web_dart/src/sse/event_stream.dart';
import 'package:spring_web_dart/src/sse/server_sent_event.dart';
import 'package:spring_web_dart/src/sse/sse_connection.dart';

/// The [RestClient] that `RestClientBuilder.build` returns. Not exported:
/// applications see the interface.
final class DefaultRestClient implements RestClient {
  /// A client with the settings of the builder, frozen.
  DefaultRestClient(
    this._builder, {
    required this.baseUrl,
    required this.defaultUriVariables,
    required this.defaultHeaders,
    required this.defaultCookies,
    required this.defaultRequests,
    required this.statusHandlers,
    required this.interceptors,
    required this.converters,
    required this.transport,
    required this.readTimeout,
    required this.connectTimeout,
    required this.followRedirects,
    required this.sensitiveHeaders,
  });

  // The builder as it was, for mutate.
  final RestClientBuilder _builder;

  /// The base URL, or `null`.
  final String? baseUrl;

  /// The values of variables the calls do not give.
  final Map<String, Object?> defaultUriVariables;

  /// The headers of every request (read-only).
  final HttpHeaders defaultHeaders;

  /// The cookies of every request.
  final Map<String, List<String>> defaultCookies;

  /// Run on every new request spec.
  final List<void Function(RequestHeadersSpec spec)> defaultRequests;

  /// The builder's status handlers, in order.
  final List<StatusHandler> statusHandlers;

  /// The interceptors, the first outermost.
  final List<ClientHttpRequestInterceptor> interceptors;

  /// The converters, asked in order.
  final List<HttpMessageConverter> converters;

  /// Sends the requests.
  final HttpTransport transport;

  /// The requests' read timeout.
  final Duration? readTimeout;

  /// The requests' connect timeout.
  final Duration? connectTimeout;

  /// Whether the transport follows redirects.
  final bool followRedirects;

  /// More credential headers, in lower case.
  final Set<String> sensitiveHeaders;

  static const _log = SpringLog('web.client.RestClient');

  /// How many templates a client keeps; then it starts again.
  static const templateCacheSize = 256;

  final _templates = <String, UriTemplate>{};

  @override
  RequestHeadersUriSpec get() => _headersSpec(HttpMethod.get);

  @override
  RequestHeadersUriSpec head() => _headersSpec(HttpMethod.head);

  @override
  RequestBodyUriSpec post() => _bodySpec(HttpMethod.post);

  @override
  RequestBodyUriSpec put() => _bodySpec(HttpMethod.put);

  @override
  RequestBodyUriSpec patch() => _bodySpec(HttpMethod.patch);

  @override
  RequestHeadersUriSpec delete() => _headersSpec(HttpMethod.delete);

  @override
  RequestHeadersUriSpec options() => _headersSpec(HttpMethod.options);

  @override
  RequestBodyUriSpec method(HttpMethod method) => _bodySpec(method);

  @override
  RestClientBuilder mutate() => _builder.clone();

  RequestHeadersUriSpec _headersSpec(HttpMethod method) =>
      _initialized<_HeadersSpec>(_HeadersSpec(this, method));

  RequestBodyUriSpec _bodySpec(HttpMethod method) =>
      _initialized<_BodySpec>(_BodySpec(this, method));

  S _initialized<S extends _RequestSpec>(S spec) {
    for (final initializer in defaultRequests) {
      initializer(spec as RequestHeadersSpec);
    }
    return spec;
  }

  /// The URI of [template] with [variables], relative to [baseUrl].
  Uri expand(String template, Object? variables) {
    var compiled = _templates[template];
    if (compiled == null) {
      if (_templates.length >= templateCacheSize) {
        _templates.clear();
      }
      compiled = _templates[template] = UriTemplate(_withBase(template));
    }
    return compiled.expand(variables, defaultUriVariables);
  }

  static final _scheme = RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*:');

  // [template] put after the base URL: one `/` between the paths, the
  // base's query before the template's.
  String _withBase(String template) {
    final base = baseUrl;
    if (base == null || base.isEmpty || _scheme.hasMatch(template)) {
      return template;
    }
    final (basePath, baseQuery) = _splitQuery(base);
    final (path, query) = _splitQuery(template);
    final String joined;
    if (path.isEmpty) {
      joined = basePath;
    } else if (basePath.endsWith('/') && path.startsWith('/')) {
      joined = '$basePath${path.substring(1)}';
    } else if (basePath.endsWith('/') || path.startsWith('/')) {
      joined = '$basePath$path';
    } else {
      joined = '$basePath/$path';
    }
    final queries = [?baseQuery, ?query];
    return queries.isEmpty ? joined : '$joined?${queries.join('&')}';
  }

  static (String, String?) _splitQuery(String text) {
    final question = text.indexOf('?');
    return question < 0
        ? (text, null)
        : (text.substring(0, question), text.substring(question + 1));
  }

  /// The body of [response] read as [type] by the first converter that can;
  /// an empty body is `null` for a nullable [type].
  Object? readBody(TypeInfo<Object?> type, HttpResponse response) {
    final bytes = response.bodyBytes;
    final status = response.statusCode;
    if (bytes.isEmpty ||
        status == HttpStatus.noContent ||
        status == HttpStatus.notModified) {
      if (type.nullable) {
        return null;
      }
      throw RestClientException(
        'The response ${_describe(response)} has no body, expected $type',
      );
    }
    return readBytes(type, bytes, response.headers.contentType, response);
  }

  /// [bytes] of [contentType] read as [type]; [response] names the call in
  /// errors.
  Object? readBytes(
    TypeInfo<Object?> type,
    Uint8List bytes,
    String? contentType, [
    HttpResponse? response,
  ]) {
    for (final converter in converters) {
      if (converter.canRead(type, contentType)) {
        try {
          return converter.read(type, bytes, contentType);
        } on Object catch (error) {
          throw RestClientException(
            'Error while extracting the response '
            '${response == null ? '' : '${_describe(response)} '}'
            'for type [$type] and content type [${contentType ?? 'none'}]: '
            '$error',
            cause: error,
          );
        }
      }
    }
    throw RestClientException(
      'No HttpMessageConverter for type [$type] and content type '
      '[${contentType ?? 'none'}]'
      '${response == null ? '' : ' (${_describe(response)})'}',
    );
  }

  static String _describe(HttpResponse response) {
    final request = response.request;
    return request == null
        ? '(${response.statusCode})'
        : 'of ${request.method.value} ${_withoutQuery(request.url)} '
              '(${response.statusCode})';
  }

  static String _withoutQuery(Uri url) {
    final text = url.toString();
    final question = text.indexOf('?');
    return question < 0 ? text : text.substring(0, question);
  }

  /// The body reader that exceptions and exchanges use.
  Object? Function(TypeInfo<Object?> type) readerOf(HttpResponse response) =>
      (type) => readBody(type, response);

  /// Runs [request] through the interceptors to [terminal].
  Future<HttpResponse> intercepted(
    HttpRequest request,
    Future<HttpResponse> Function(HttpRequest request, List<int>? body)
    terminal,
  ) => interceptors.isEmpty
      ? terminal(request, request.body)
      : _Chain(interceptors, 0, terminal).execute(request, request.body);

  /// [request] as it is sent: with [body], and its timeouts cut to what is
  /// left of the deadline of the code that sends it (the shorter of the
  /// two).
  HttpRequest prepared(HttpRequest request, List<int>? body) {
    final left = RequestDeadline.current?.remaining;
    if (left == null && identical(body, request.body)) {
      return request;
    }
    return HttpRequest(
      method: request.method,
      url: request.url,
      headers: request.headers,
      body: body,
      timeout: _shorter(request.timeout, left),
      readTimeout: _shorter(request.readTimeout, left),
      connectTimeout: request.connectTimeout,
      followRedirects: request.followRedirects,
      sensitiveHeaders: request.sensitiveHeaders,
      abort: request.abort,
      attributes: request.attributes,
    );
  }

  static Duration? _shorter(Duration? timeout, Duration? left) =>
      timeout == null || (left != null && left < timeout) ? left : timeout;

  /// Fails when the deadline of the code that sends [request] has passed.
  void checkDeadline(HttpRequest request) {
    final deadline = RequestDeadline.current;
    if (deadline != null && deadline.isExpired) {
      throw ResourceAccessException(
        'I/O error on ${request.method.value} request for '
        '"${_withoutQuery(request.url)}": the deadline of the enclosing '
        'request (${deadline.budget.inMilliseconds} ms) has passed',
        cause: RequestDeadlineExceededException(deadline.budget),
      );
    }
  }

  /// The [ResourceAccessException] of a transport [error] for [request].
  ResourceAccessException accessFailure(
    HttpRequest request,
    HttpTransportException error,
  ) {
    final deadline = RequestDeadline.current;
    final atDeadline =
        deadline != null &&
        error.isTimeout &&
        deadline.remaining <= const Duration(milliseconds: 5);
    final limit = atDeadline
        ? ' (the deadline of the enclosing request, '
              '${deadline.budget.inMilliseconds} ms, has passed)'
        : '';
    return ResourceAccessException(
      'I/O error on ${request.method.value} request for '
      '"${_withoutQuery(request.url)}": ${error.message}$limit',
      cause: error,
    );
  }

  /// Sends [request] whole (the terminal of a normal call).
  Future<HttpResponse> send(HttpRequest request, List<int>? body) async {
    final sent = prepared(request, body);
    final watch = _logRequest(sent);
    try {
      final response = await transport.send(sent);
      _logResponse(response.statusCode, watch);
      return response;
    } on HttpTransportException catch (error) {
      _logFailure(error, watch);
      throw accessFailure(sent, error);
    }
  }

  Stopwatch? _logRequest(HttpRequest request) {
    if (!_log.isEnabled(SpringLogLevel.debug)) {
      return null;
    }
    _log.debug('---> ${request.method.value} ${_maskedUrl(request.url)}');
    if (_log.isEnabled(SpringLogLevel.trace)) {
      final lines = <String>[];
      request.headers.forEach((name, values) {
        final masked =
            HttpSecrets.isSensitiveHeader(name) ||
            request.sensitiveHeaders.contains(name.toLowerCase()) ||
            sensitiveHeaders.contains(name.toLowerCase());
        for (final value in values) {
          lines.add('$name: ${masked ? '***' : value}');
        }
      });
      if (lines.isNotEmpty) {
        _log.trace(lines.join('\n'));
      }
    }
    return Stopwatch()..start();
  }

  void _logResponse(int status, Stopwatch? watch) {
    if (watch != null) {
      _log.debug('<--- $status (${watch.elapsedMilliseconds} ms)');
    }
  }

  void _logFailure(HttpTransportException error, Stopwatch? watch) {
    if (watch != null) {
      _log.debug(
        '<--- ERROR ${error.message} (${watch.elapsedMilliseconds} ms)',
      );
    }
  }

  // The URL with the values of credential query parameters as `***`.
  static String _maskedUrl(Uri url) {
    if (!url.hasQuery ||
        !url.queryParametersAll.keys.any(HttpSecrets.isSensitiveParameter)) {
      return '$url';
    }
    final masked = url.query
        .split('&')
        .map((pair) {
          final equals = pair.indexOf('=');
          final name = Uri.decodeQueryComponent(
            equals < 0 ? pair : pair.substring(0, equals),
          );
          return equals >= 0 && HttpSecrets.isSensitiveParameter(name)
              ? '${pair.substring(0, equals)}=***'
              : pair;
        })
        .join('&');
    return url.replace(query: masked).toString();
  }
}

final class _Chain implements ClientHttpRequestExecution {
  _Chain(this._interceptors, this._index, this._terminal);

  final List<ClientHttpRequestInterceptor> _interceptors;
  final int _index;
  final Future<HttpResponse> Function(HttpRequest request, List<int>? body)
  _terminal;

  @override
  Future<HttpResponse> execute(HttpRequest request, List<int>? body) =>
      _index < _interceptors.length
      ? _interceptors[_index].intercept(
          request,
          body,
          _Chain(_interceptors, _index + 1, _terminal),
        )
      : _terminal(request, body);
}

/// What every request spec holds and does; the fluent methods are in
/// [_HeadersSpec] and [_BodySpec], which return themselves.
abstract class _RequestSpec {
  _RequestSpec(this.client, this.method);

  final DefaultRestClient client;
  final HttpMethod method;
  Uri? _uri;
  HttpHeaders? _headers;
  Map<String, List<String>>? _cookies;
  Map<String, Object?>? _attributes;
  Object? _body;
  TypeInfo<Object?>? _bodyType;

  HttpHeaders get _ownHeaders => _headers ??= HttpHeaders();

  void _setUri(Object uri, Object? variables) {
    _uri = switch (uri) {
      final String template => client.expand(template, variables),
      final Uri value when value.hasScheme => value,
      final Uri value => client.expand(value.toString(), null),
      final Object? Function(UriBuilder builder) build => switch (build(
        UriBuilder(client.baseUrl ?? '', client.defaultUriVariables),
      )) {
        final Uri built => built,
        final other => throw ArgumentError.value(
          other,
          'uri',
          'The UriBuilder function must return a Uri (call build())',
        ),
      },
      _ => throw ArgumentError.value(
        uri,
        'uri',
        'A URI template (String), a Uri or a function of a UriBuilder',
      ),
    };
  }

  void _addCookie(String name, String value) =>
      ((_cookies ??= {})[name] ??= []).add(value);

  Map<String, Object?> get _ownAttributes => _attributes ??= {};

  // The request's own map: interceptors may change it, and a call without
  // attributes and interceptors allocates none.
  Map<String, Object?> _requestAttributes() => switch (_attributes) {
    final own? => {...own},
    null when client.interceptors.isEmpty => const {},
    null => {},
  };

  // Spring's name.
  // ignore: use_to_and_as_if_applicable
  ResponseSpec retrieve() => _ResponseSpec(this);

  // The request as the spec describes it, before the interceptors.
  HttpRequest _request({Future<void>? abort, Map<String, String>? extra}) {
    final headers = HttpHeaders()..addHeaders(client.defaultHeaders);
    final own = _headers;
    if (own != null) {
      own.names.forEach(headers.remove);
      headers.addHeaders(own);
    }
    if (extra != null) {
      extra.forEach((name, value) {
        if (!headers.contains(name)) {
          headers.set(name, value);
        }
      });
    }
    _setCookies(headers);
    List<int>? bytes;
    final body = _body;
    if (body != null) {
      final declared = headers.contentType;
      final converter = client.converters
          .where((candidate) => candidate.canWrite(body, declared))
          .firstOrNull;
      if (converter == null) {
        throw RestClientException(
          'No HttpMessageConverter writes ${body.runtimeType} as '
          '[${declared ?? 'no content type'}]',
        );
      }
      final ({List<int> bytes, String contentType}) written;
      try {
        written = converter.write(body, declared, _bodyType);
      } on Object catch (error) {
        throw RestClientException(
          'Cannot write the body (${body.runtimeType}): $error',
          cause: error,
        );
      }
      bytes = written.bytes;
      headers.contentType = written.contentType;
    }
    return HttpRequest(
      method: method,
      url: _uri ?? client.expand('', null),
      headers: headers,
      body: bytes,
      readTimeout: client.readTimeout,
      connectTimeout: client.connectTimeout,
      followRedirects: client.followRedirects,
      sensitiveHeaders: client.sensitiveHeaders,
      abort: abort,
      attributes: _requestAttributes(),
    );
  }

  void _setCookies(HttpHeaders headers) {
    final own = _cookies;
    if (client.defaultCookies.isEmpty && own == null) {
      return;
    }
    final all = <String, List<String>>{
      ...client.defaultCookies,
      ...?own,
    };
    headers.set(
      HttpHeaders.cookieHeader,
      [
        for (final MapEntry(key: name, value: values) in all.entries)
          for (final value in values) '$name=$value',
      ].join('; '),
    );
  }

  // Sends the request whole through the interceptors.
  Future<(HttpRequest, HttpResponse)> _exchange() async {
    final request = _request();
    client.checkDeadline(request);
    final response = await client.intercepted(request, client.send);
    return (response.request ?? request, response);
  }

  Future<T> exchange<T>(ExchangeFunction<T> exchange) async {
    final (request, response) = await _exchange();
    return await exchange(
      request,
      ConvertibleClientHttpResponse(response, client.readBody),
    );
  }
}

/// A request without a body: `GET`, `HEAD`, `DELETE`, `OPTIONS`.
final class _HeadersSpec extends _RequestSpec implements RequestHeadersUriSpec {
  _HeadersSpec(super.client, super.method);

  @override
  _HeadersSpec uri(Object uri, [Object? variables]) {
    _setUri(uri, variables);
    return this;
  }

  @override
  _HeadersSpec header(String name, String value) {
    _ownHeaders.add(name, value);
    return this;
  }

  @override
  _HeadersSpec headers(void Function(HttpHeaders headers) configure) {
    configure(_ownHeaders);
    return this;
  }

  @override
  _HeadersSpec accept(String mediaTypes) {
    _ownHeaders.set(HttpHeaders.acceptHeader, mediaTypes);
    return this;
  }

  @override
  _HeadersSpec cookie(String name, String value) {
    _addCookie(name, value);
    return this;
  }

  @override
  _HeadersSpec attribute(String name, Object? value) {
    _ownAttributes[name] = value;
    return this;
  }

  @override
  _HeadersSpec attributes(
    void Function(Map<String, Object?> attributes) configure,
  ) {
    configure(_ownAttributes);
    return this;
  }
}

/// What to read from the response of a request spec.
final class _ResponseSpec implements ResponseSpec {
  _ResponseSpec(this.spec);

  final _RequestSpec spec;
  List<StatusHandler>? _handlers;

  DefaultRestClient get client => spec.client;

  @override
  ResponseSpec onStatus(
    bool Function(HttpStatusCode status) predicate,
    RestClientErrorHandler handler,
  ) {
    (_handlers ??= []).add(StatusHandler(predicate, handler));
    return this;
  }

  // Synchronous unless a handler is not: most answers take no handler.
  FutureOr<void> _applyStatusHandlers(
    HttpRequest request,
    HttpResponse response,
  ) {
    final status = response.statusCode;
    for (final handlers in [?_handlers, client.statusHandlers]) {
      for (final handler in handlers) {
        if (handler.predicate(status)) {
          return handler.handler(request, response);
        }
      }
    }
    if (status.isError) {
      throw RestClientResponseException.of(
        response,
        bodyReader: client.readerOf(response),
      );
    }
  }

  @override
  Future<T> body<T>([TypeInfo<T>? type]) async {
    final request = spec._request();
    client.checkDeadline(request);
    final response = await client.intercepted(request, client.send);
    final handled = _applyStatusHandlers(response.request ?? request, response);
    if (handled is Future<void>) {
      await handled;
    }
    return client.readBody(type ?? ClassType<T>(nullable: null is T), response)
        as T;
  }

  @override
  Future<ResponseEntity<T>> toEntity<T>([TypeInfo<T>? type]) async {
    final request = spec._request();
    client.checkDeadline(request);
    final response = await client.intercepted(request, client.send);
    final handled = _applyStatusHandlers(response.request ?? request, response);
    if (handled is Future<void>) {
      await handled;
    }
    final body = client.readBody(
      (type ?? ClassType<T>(nullable: true)).asNullable(),
      response,
    ) as T?;
    return ResponseEntity<T>(
      response.statusCode,
      body: body,
      headers: response.headers,
    );
  }

  @override
  Future<ResponseEntity<void>> toBodilessEntity() async {
    final request = spec._request();
    client.checkDeadline(request);
    final response = await client.intercepted(request, client.send);
    final handled = _applyStatusHandlers(response.request ?? request, response);
    if (handled is Future<void>) {
      await handled;
    }
    return ResponseEntity<void>(
      response.statusCode,
      headers: response.headers,
    );
  }

  // One streamed request through the interceptors: the interceptors see
  // the status and headers (and the whole body of an error), the stream
  // gets the body.
  Future<StreamedHttpResponse> _connect(
    _Cancellation cancellation, {
    Map<String, String>? extra,
  }) async {
    final request = spec._request(abort: cancellation.attempt(), extra: extra);
    if (cancellation.isCancelled) {
      throw const _StreamCancelled();
    }
    client.checkDeadline(request);
    StreamedHttpResponse? streamed;
    late final HttpResponse placeholder;
    final response = await client.intercepted(request, (request, body) async {
      final sent = client.prepared(request, body);
      final StreamedHttpResponse answer;
      try {
        answer = await client.transport.stream(sent);
      } on HttpTransportException catch (error) {
        throw client.accessFailure(sent, error);
      }
      if (!answer.isSuccess) {
        return await answer.read();
      }
      streamed = answer;
      return placeholder = HttpResponse(
        answer.statusCode,
        headers: answer.headers,
        request: answer.request ?? sent,
      );
    });
    final live = streamed;
    if (live != null && identical(response, placeholder)) {
      return live;
    }
    // An interceptor answered by itself: its response is the stream.
    if (live != null) {
      unawaited(live.discard());
    }
    if (!response.isSuccess) {
      await _applyStatusHandlers(response.request ?? request, response);
      // A handler let an error status through: the stream ends.
      return StreamedHttpResponse(
        HttpStatus.noContent,
        body: const Stream.empty(),
        request: response.request ?? request,
      );
    }
    return StreamedHttpResponse(
      response.statusCode,
      headers: response.headers,
      body: Stream.value(response.bodyBytes),
      request: response.request ?? request,
    );
  }

  @override
  EventStream<T> eventStream<T>({
    TypeInfo<T>? type,
    SseReconnect reconnect = const SseReconnect(),
  }) {
    final target = type ?? ClassType<T>(nullable: null is T);
    return EventStream<T>(() {
      final cancellation = _Cancellation();
      final events = connectServerSentEvents(
        (lastEventId) => _connect(
          cancellation,
          extra: {
            HttpHeaders.acceptHeader: MediaType.textEventStream,
            HttpHeaders.cacheControlHeader: 'no-cache',
            'Last-Event-ID': ?lastEventId,
          },
        ),
        reconnect: SseReconnect(
          enabled: reconnect.enabled,
          delay: reconnect.delay,
          maxAttempts: reconnect.maxAttempts,
          retryIf: (error) => reconnect.retryIf(
            error is ResourceAccessException && error.cause != null
                ? error.cause!
                : error,
          ),
        ),
      );
      return _cancellable(events, cancellation).transform(
        StreamTransformer<
          ServerSentEvent<String>,
          ServerSentEvent<T>
        >.fromHandlers(
          handleData: (event, sink) {
            if (target.type == String) {
              sink.add(event.withData<T>(event.data as T));
              return;
            }
            if (event.data.isEmpty) {
              return;
            }
            try {
              final value = client.readBytes(
                target,
                utf8.encode(event.data),
                MediaType.applicationJson,
              );
              sink.add(event.withData<T>(value as T));
            } on Object catch (error, stackTrace) {
              sink.addError(error, stackTrace);
            }
          },
        ),
      );
    });
  }

  @override
  Stream<List<int>> bodyStream() {
    final cancellation = _Cancellation();
    StreamSubscription<List<int>>? body;
    late final StreamController<List<int>> out;
    out = StreamController<List<int>>(
      onListen: () async {
        final StreamedHttpResponse response;
        try {
          response = await _connect(cancellation);
        } on Object catch (error, stackTrace) {
          if (!cancellation.isCancelled) {
            out.addError(error, stackTrace);
            unawaited(out.close());
          }
          return;
        }
        if (cancellation.isCancelled) {
          unawaited(response.discard());
          return;
        }
        body = response.body.listen(
          out.add,
          onError: out.addError,
          onDone: out.close,
        );
        if (out.isPaused) {
          body?.pause();
        }
      },
      onPause: () => body?.pause(),
      onResume: () => body?.resume(),
      onCancel: () {
        cancellation.cancel();
        return body?.cancel();
      },
    );
    return out.stream;
  }

  // [events] whose cancellation also gives up a connection still opening.
  static Stream<ServerSentEvent<String>> _cancellable(
    Stream<ServerSentEvent<String>> events,
    _Cancellation cancellation,
  ) {
    StreamSubscription<ServerSentEvent<String>>? source;
    late final StreamController<ServerSentEvent<String>> out;
    out = StreamController<ServerSentEvent<String>>(
      sync: true,
      onListen: () => source = events.listen(
        out.add,
        onError: out.addError,
        onDone: out.close,
      ),
      onPause: () => source?.pause(),
      onResume: () => source?.resume(),
      onCancel: () {
        cancellation.cancel();
        return source?.cancel();
      },
    );
    return out.stream;
  }
}

/// A request with a body.
final class _BodySpec extends _RequestSpec implements RequestBodyUriSpec {
  _BodySpec(super.client, super.method);

  @override
  _BodySpec uri(Object uri, [Object? variables]) {
    _setUri(uri, variables);
    return this;
  }

  @override
  _BodySpec header(String name, String value) {
    _ownHeaders.add(name, value);
    return this;
  }

  @override
  _BodySpec headers(void Function(HttpHeaders headers) configure) {
    configure(_ownHeaders);
    return this;
  }

  @override
  _BodySpec accept(String mediaTypes) {
    _ownHeaders.set(HttpHeaders.acceptHeader, mediaTypes);
    return this;
  }

  @override
  _BodySpec cookie(String name, String value) {
    _addCookie(name, value);
    return this;
  }

  @override
  _BodySpec attribute(String name, Object? value) {
    _ownAttributes[name] = value;
    return this;
  }

  @override
  _BodySpec attributes(
    void Function(Map<String, Object?> attributes) configure,
  ) {
    configure(_ownAttributes);
    return this;
  }

  @override
  _BodySpec contentType(String mediaType) {
    _ownHeaders.contentType = mediaType;
    return this;
  }

  @override
  _BodySpec body(Object? body, [TypeInfo<Object?>? type]) {
    if (body != null &&
        (method == HttpMethod.get || method == HttpMethod.head)) {
      throw ArgumentError.value(
        body,
        'body',
        'A ${method.value} request has no body (a browser refuses one)',
      );
    }
    _body = body;
    _bodyType = type;
    return this;
  }
}

/// Whether the listener of a streamed answer has left: a request not sent
/// yet is not sent, and the one waiting for its response is given up
/// through `HttpRequest.abort`.
final class _Cancellation {
  Completer<void>? _waiting;

  bool isCancelled = false;

  Future<void> attempt() => (_waiting = Completer<void>()).future;

  void cancel() {
    isCancelled = true;
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) {
      waiting.complete();
    }
  }
}

/// A request that was not sent because the listener had left.
final class _StreamCancelled implements Exception {
  const _StreamCancelled();

  @override
  String toString() => 'the stream was cancelled before its request';
}
