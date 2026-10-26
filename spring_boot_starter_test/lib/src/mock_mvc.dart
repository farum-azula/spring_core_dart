import 'dart:async';
import 'dart:convert';

import 'package:matcher/matcher.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test_api/hooks.dart' show TestFailure;

/// Calls the application's controllers without a socket, like Spring's
/// `MockMvc`: the same dispatcher a real server uses (filters, mapping,
/// binding, error handling), with requests built in the test.
///
/// ```dart
/// final app = springBootTest(springApplication);
///
/// test('finds a book', () async {
///   final mvc = app.mockMvc;
///   await mvc.get('/api/books/978-0').andExpect(
///     status: 200,
///     json: {'isbn': '978-0', 'title': 'Dune'},
///   );
///   await mvc
///       .post('/api/books', json: {'isbn': ''})
///       .andExpect(status: 400, contentType: MediaType.applicationProblemJson);
/// });
/// ```
///
/// Spring (Java):
/// ```java
/// mockMvc.perform(get("/api/books/978-0"))
///     .andExpect(status().isOk())
///     .andExpect(jsonPath("$.title").value("Dune"));
/// ```
final class MockMvc {
  /// Calls [handler] (the web starter's `dispatcherHandler`).
  MockMvc(this.handler, {this.defaultPostProcessors = const []});

  /// The `MockMvc` of [context]: its `dispatcherHandler` bean (the web
  /// starter's [HttpHandler]).
  factory MockMvc.of(ApplicationContext context) {
    if (!context.containsBean('dispatcherHandler')) {
      throw StateError(
        'MockMvc needs spring_boot_starter_web: the context has no '
        "'dispatcherHandler' bean",
      );
    }
    return MockMvc(context.getBeanByName('dispatcherHandler') as HttpHandler);
  }

  /// Answers the requests.
  final HttpHandler handler;

  /// Applied to every request first (a default user, headers).
  final List<RequestPostProcessor> defaultPostProcessors;

  /// Performs [request].
  ResultActions perform(MockRequestBuilder request) =>
      ResultActions._(_perform(request));

  Future<MvcResult> _perform(MockRequestBuilder builder) async {
    var request = builder.build();
    for (final processor in [
      ...defaultPostProcessors,
      ...builder._postProcessors,
    ]) {
      request = processor.postProcessRequest(request);
    }
    final response = MockServerHttpResponse();
    final handled = handler.handle(request, response);
    // A stream (server-sent events) answers before it ends: the result is
    // ready once its headers are out; read it with `result.response`.
    final streaming = Completer<void>();
    unawaited(
      response.committed.then((_) {
        if (_isStreaming(response) && !streaming.isCompleted) {
          streaming.complete();
        }
      }),
    );
    await Future.any([handled, streaming.future]);
    if (!response.isClosed && !_isStreaming(response)) {
      await response.closed;
    }
    return MvcResult._(request, response, handled);
  }

  static bool _isStreaming(MockServerHttpResponse response) {
    final type = (response.headers.contentType ?? '').toLowerCase();
    return type.startsWith(MediaType.textEventStream) ||
        type.startsWith(MediaType.applicationNdjson);
  }

  /// A `GET` of [path] (with an optional query).
  ResultActions get(
    String path, {
    Map<String, String> headers = const {},
    Map<String, Object> params = const {},
  }) => perform(
    MockRequestBuilder(HttpMethod.get, path)
      ..headers.addAll(headers)
      ..params.addAll(params),
  );

  /// A `POST` with a [json] body (or [body]).
  ResultActions post(
    String path, {
    Object? json,
    Object? body,
    Map<String, String> headers = const {},
  }) => perform(_withBody(HttpMethod.post, path, json, body, headers));

  /// A `PUT` with a [json] body (or [body]).
  ResultActions put(
    String path, {
    Object? json,
    Object? body,
    Map<String, String> headers = const {},
  }) => perform(_withBody(HttpMethod.put, path, json, body, headers));

  /// A `PATCH` with a [json] body (or [body]).
  ResultActions patch(
    String path, {
    Object? json,
    Object? body,
    Map<String, String> headers = const {},
  }) => perform(_withBody(HttpMethod.patch, path, json, body, headers));

  /// A `DELETE` of [path].
  ResultActions delete(String path, {Map<String, String> headers = const {}}) =>
      perform(
        MockRequestBuilder(HttpMethod.delete, path)..headers.addAll(headers),
      );

  /// A `multipart/form-data` request (a `POST` unless [method] says
  /// otherwise) with [files] and the text fields [params], like Spring's
  /// `MockMvcRequestBuilders.multipart`. A file without an original file
  /// name is a plain part: with `application/json` it is a JSON part for
  /// `@RequestPart`.
  ///
  /// ```dart
  /// await mvc.multipart('/api/covers', files: [
  ///   MockMultipartFile('cover', 'dune.png', 'image/png', bytes),
  ///   MockMultipartFile('book', null, 'application/json',
  ///       utf8.encode('{"isbn": "978-0"}')),
  /// ], params: {'note': 'first edition'}).andExpect(status: 201);
  /// ```
  ResultActions multipart(
    String path, {
    List<MultipartFile> files = const [],
    Map<String, String> params = const {},
    Map<String, String> headers = const {},
    HttpMethod method = HttpMethod.post,
  }) => ResultActions._(() async {
    final body = MultipartBody([
      for (final MapEntry(:key, :value) in params.entries)
        MultipartBodyPart.field(key, value),
      for (final file in files)
        MultipartBodyPart.file(
          file.name,
          await file.bytes,
          filename: file.originalFilename,
          contentType: file.contentType,
        ),
    ]);
    final builder = MockRequestBuilder(method, path)
      ..headers.addAll(headers)
      ..headers[HttpHeaders.contentTypeHeader] = body.contentType
      ..content(body.encode());
    return _perform(builder);
  }());

  /// Opens a WebSocket to [path] in memory (the application's endpoint
  /// gets the server's end); throws when the handshake is refused.
  Future<WebSocketSession> webSocket(
    String path, {
    Map<String, String> headers = const {},
    List<RequestPostProcessor> postProcessors = const [],
  }) async {
    final builder = MockRequestBuilder(HttpMethod.get, path)
      ..headers.addAll({
        HttpHeaders.upgradeHeader: 'websocket',
        HttpHeaders.connectionHeader: 'Upgrade',
        'Sec-WebSocket-Version': '13',
        ...headers,
      });
    for (final processor in postProcessors) {
      builder.with_(processor);
    }
    var request = builder.build();
    for (final processor in [
      ...defaultPostProcessors,
      ...builder._postProcessors,
    ]) {
      request = processor.postProcessRequest(request);
    }
    final response = MockServerHttpResponse();
    final handled = handler.handle(request, response);
    final client = await Future.any<Object?>([
      request.webSocketClient,
      handled.then((_) => null),
    ]);
    if (client is WebSocketSession) {
      return client;
    }
    throw WebSocketException(
      'Handshake refused: ${response.statusCode} ${response.bodyText}',
      url: request.uri,
    );
  }

  static MockRequestBuilder _withBody(
    HttpMethod method,
    String path,
    Object? json,
    Object? body,
    Map<String, String> headers,
  ) {
    final builder = MockRequestBuilder(method, path)..headers.addAll(headers);
    if (json != null) {
      builder.json(json);
    } else if (body != null) {
      builder.content(body);
    }
    return builder;
  }
}

/// Changes a request before it is performed, like Spring's
/// `RequestPostProcessor` (Spring Security's `user(...)`, `jwt()` and
/// `csrf()` are ones).
abstract interface class RequestPostProcessor {
  /// The request to perform instead of [request] (usually it, changed).
  MockServerHttpRequest postProcessRequest(MockServerHttpRequest request);
}

/// A [RequestPostProcessor] from a function.
final class FunctionRequestPostProcessor implements RequestPostProcessor {
  /// Applies [process].
  const FunctionRequestPostProcessor(this.process);

  /// The function.
  final MockServerHttpRequest Function(MockServerHttpRequest request) process;

  @override
  MockServerHttpRequest postProcessRequest(MockServerHttpRequest request) =>
      process(request);
}

/// Builds a request for [MockMvc.perform], like Spring's
/// `MockHttpServletRequestBuilder`.
///
/// ```dart
/// await mvc.perform(
///   MockRequestBuilder(HttpMethod.get, '/api/books')
///     ..params['q'] = 'dune'
///     ..headers['Accept'] = 'application/json',
/// ).andExpect(status: 200);
/// ```
final class MockRequestBuilder {
  /// A [method] request to [path] (`{name}` placeholders are filled from
  /// [uriVariables], encoded).
  MockRequestBuilder(
    this.method,
    String path, [
    List<Object?> uriVariables = const [],
  ]) : path = _expand(path, uriVariables);

  /// The method.
  final HttpMethod method;

  /// The path (with an optional query).
  final String path;

  /// Headers to send.
  final Map<String, String> headers = {};

  /// Query parameters to add (a `List` for several values).
  final Map<String, Object> params = {};

  /// Cookies to send.
  final Map<String, String> cookies = {};

  /// The authenticated user, if any.
  Principal? principal;

  Object? _content;
  final _postProcessors = <RequestPostProcessor>[];

  /// The body: a `String` or bytes.
  void content(Object body) => _content = body;

  /// A JSON body (`Content-Type: application/json`).
  void json(Object? value) {
    _content = jsonEncode(value);
    headers.putIfAbsent(
      HttpHeaders.contentTypeHeader,
      () => MediaType.applicationJson,
    );
  }

  /// Adds [processor] (Spring's `.with(...)`).
  void with_(RequestPostProcessor processor) => _postProcessors.add(processor);

  /// The request.
  MockServerHttpRequest build() {
    final request = MockServerHttpRequest(method, path);
    headers.forEach(request.headers.set);
    params.forEach((name, value) {
      for (final item in value is Iterable ? value : [value]) {
        request.addParameter(name, '$item');
      }
    });
    cookies.forEach(request.addCookie);
    if (_content case final content?) {
      request.setBody(content);
    }
    request.principal = principal;
    return request;
  }

  static String _expand(String path, List<Object?> variables) {
    if (variables.isEmpty) {
      return path;
    }
    var index = 0;
    return path.replaceAllMapped(RegExp(r'\{[^{}/]+\}'), (match) {
      if (index >= variables.length) {
        return match[0]!;
      }
      return Uri.encodeComponent('${variables[index++]}');
    });
  }
}

/// A performed request: check it with [andExpect], or read [andReturn],
/// like Spring's `ResultActions`. Await it for the [MvcResult].
final class ResultActions implements Future<MvcResult> {
  ResultActions._(this._result);

  final Future<MvcResult> _result;

  /// Checks the response: [status], [contentType] (compatible media
  /// type), [headers] (each value exact), [body] (exact text, or a
  /// matcher), [json] (equal after decoding, or a matcher).
  ResultActions andExpect({
    int? status,
    String? contentType,
    Map<String, String> headers = const {},
    Object? body,
    Object? json,
  }) => ResultActions._(
    _result.then((result) {
      final response = result.response;
      void fail(String what, Object? expected, Object? actual) =>
          throw TestFailure(
            '${result.request.method.value} ${result.request.uri}: '
            'expected $what $expected, got $actual\n'
            'Response: ${response.statusCode} ${response.headers.toMap()}\n'
            '${response.bodyText}',
          );
      if (status != null && response.statusCode != status) {
        fail('status', status, response.statusCode);
      }
      if (contentType != null) {
        final actual = response.headers.contentType;
        if (actual == null ||
            !MediaType.parse(actual)
                .isCompatibleWith(MediaType.parse(contentType))) {
          fail('Content-Type', contentType, actual);
        }
      }
      headers.forEach((name, value) {
        if (response.headers[name] != value) {
          fail('header $name', value, response.headers[name]);
        }
      });
      if (body != null) {
        _check('body', body, response.bodyText, fail);
      }
      if (json != null) {
        _check('JSON', json, response.json, fail);
      }
      return result;
    }),
  );

  static void _check(
    String what,
    Object expected,
    Object? actual,
    void Function(String, Object?, Object?) fail,
  ) {
    final matcher = expected is Matcher ? expected : equals(expected);
    if (!matcher.matches(actual, {})) {
      fail(what, StringDescription().addDescriptionOf(matcher), actual);
    }
  }

  /// Runs [action] with the result (Spring's `andDo`).
  ResultActions andDo(void Function(MvcResult result) action) =>
      ResultActions._(
        _result.then((result) {
          action(result);
          return result;
        }),
      );

  /// The result.
  Future<MvcResult> andReturn() => _result;

  @override
  Stream<MvcResult> asStream() => _result.asStream();

  @override
  Future<MvcResult> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) => _result.catchError(onError, test: test);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(MvcResult value) onValue, {
    Function? onError,
  }) => _result.then(onValue, onError: onError);

  @override
  Future<MvcResult> timeout(
    Duration timeLimit, {
    FutureOr<MvcResult> Function()? onTimeout,
  }) => _result.timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<MvcResult> whenComplete(FutureOr<void> Function() action) =>
      _result.whenComplete(action);
}

/// The request and the response of a [MockMvc] call, like Spring's
/// `MvcResult`.
final class MvcResult {
  MvcResult._(this.request, this.response, this._handled);

  /// The request performed.
  final MockServerHttpRequest request;

  /// The response (still being written for a stream: see
  /// [MockServerHttpResponse.eventStream]).
  final MockServerHttpResponse response;

  final Future<void> _handled;

  /// Completes when the application finished the request (a stream
  /// ended, or [cancel] was called).
  Future<void> get completion => _handled;

  /// Ends a streamed response from the client's side.
  Future<void> cancel() {
    response.disconnect();
    return _handled;
  }
}
