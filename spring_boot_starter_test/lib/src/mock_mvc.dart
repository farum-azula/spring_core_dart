import 'dart:async';
import 'dart:convert';

import 'package:matcher/matcher.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test_api/hooks.dart' show TestFailure;

/// Sends HTTP requests to the application's controllers in memory, without
/// a server or a socket, and checks the responses.
///
/// Use it to test the web layer as a client sees it: URL mapping, request
/// binding, `@Valid` checks, filters, exception handlers and the JSON or
/// `ProblemDetail` answers. It runs the same dispatcher a real server
/// runs, so a test that passes here behaves the same over HTTP, but it is
/// faster and needs no free port. With `spring_boot_starter_web`,
/// `app.mockMvc` of a `springBootTest` (or an `@Autowired() late MockMvc
/// mvc;` field in a test class) gives one.
///
/// Each call returns a [ResultActions]: chain [ResultActions.andExpect]
/// to check the response, and `await` the chain, or a failed expectation
/// is never reported.
///
/// ```dart
/// final app = springBootTest(springApplication);
///
/// test('finds a book, rejects an invalid one', () async {
///   final mvc = app.mockMvc;
///   await mvc.get('/api/books/978-0').andExpect(
///     status: 200,
///     json: {'isbn': '978-0', 'title': 'Dune'},
///   );
///   // An empty ISBN fails validation: a 400 with a ProblemDetail body.
///   await mvc
///       .post('/api/books', json: {'isbn': ''})
///       .andExpect(
///         status: 400,
///         contentType: MediaType.applicationProblemJson,
///       );
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
  /// A `MockMvc` that sends requests to [handler], usually the web starter's
  /// `dispatcherHandler` bean. Create one yourself to add
  /// [defaultPostProcessors], such as a logged-in user for every request:
  ///
  /// ```dart
  /// final mvc = MockMvc(
  ///   app.getBean<DispatcherHandler>(),
  ///   defaultPostProcessors: [user('ada')], // spring_boot_starter_security
  /// );
  /// ```
  MockMvc(this.handler, {this.defaultPostProcessors = const []});

  /// The `MockMvc` of [context], sending requests to its
  /// `dispatcherHandler` bean. Throws a [StateError] when the context has
  /// none, that is without `spring_boot_starter_web`.
  factory MockMvc.of(ApplicationContext context) {
    if (!context.containsBean('dispatcherHandler')) {
      throw StateError(
        'MockMvc needs spring_boot_starter_web: the context has no '
        "'dispatcherHandler' bean",
      );
    }
    return MockMvc(context.getBeanByName('dispatcherHandler') as HttpHandler);
  }

  /// The handler that answers the requests, as the server would call it.
  final HttpHandler handler;

  /// Applied to every request, before the post-processors of the request
  /// itself: a default user, common headers.
  final List<RequestPostProcessor> defaultPostProcessors;

  /// Sends the request that [request] describes; the shortcuts [get],
  /// [post] and the others build one for you. Use it for what they do not
  /// cover: cookies, a principal, a post-processor, another method.
  ///
  /// ```dart
  /// await mvc.perform(
  ///   MockRequestBuilder(HttpMethod.head, '/api/books/{isbn}', ['978-0']),
  /// ).andExpect(status: 200);
  /// ```
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

  /// Sends a `GET` to [path] with [headers] and query [params]; a `List`
  /// value sends the parameter several times (`{'id': [1, 2]}`).
  ResultActions get(
    String path, {
    Map<String, String> headers = const {},
    Map<String, Object> params = const {},
  }) => perform(
    MockRequestBuilder(HttpMethod.get, path)
      ..headers.addAll(headers)
      ..params.addAll(params),
  );

  /// Sends a `POST` to [path]. [json] is encoded as the body with
  /// `Content-Type: application/json`; otherwise [body], a `String` or
  /// bytes, is sent as is. When both are given, [json] wins.
  ResultActions post(
    String path, {
    Object? json,
    Object? body,
    Map<String, String> headers = const {},
  }) => perform(_withBody(HttpMethod.post, path, json, body, headers));

  /// Sends a `PUT`, with a body as for [post].
  ResultActions put(
    String path, {
    Object? json,
    Object? body,
    Map<String, String> headers = const {},
  }) => perform(_withBody(HttpMethod.put, path, json, body, headers));

  /// Sends a `PATCH`, with a body as for [post].
  ResultActions patch(
    String path, {
    Object? json,
    Object? body,
    Map<String, String> headers = const {},
  }) => perform(_withBody(HttpMethod.patch, path, json, body, headers));

  /// Sends a `DELETE` to [path] with [headers].
  ResultActions delete(String path, {Map<String, String> headers = const {}}) =>
      perform(
        MockRequestBuilder(HttpMethod.delete, path)..headers.addAll(headers),
      );

  /// Sends a `multipart/form-data` upload to [path]: the [files] and the
  /// text fields [params] as one body, through the same multipart parsing
  /// and limits as the server. A `POST` unless [method] says otherwise, like
  /// Spring's `MockMvcRequestBuilders.multipart`.
  ///
  /// A file without an original file name is a plain part; with
  /// `application/json` it fills a `@RequestPart` object.
  ///
  /// ```dart
  /// // A cover image plus the book's data as a JSON part.
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
    return await _perform(builder);
  }());

  /// Opens a WebSocket connection to the endpoint at [path] in memory and
  /// returns the client's end of it; the application's handler gets the
  /// server's end.
  ///
  /// Use it to test a `spring_boot_starter_websocket` endpoint: send
  /// messages on the returned session and read its answers. [headers] and
  /// [postProcessors] change the handshake request (a user, a token).
  /// Throws a [WebSocketException] with the status and body when the
  /// handshake is refused.
  ///
  /// ```dart
  /// final session = await mvc.webSocket('/ws/chat');
  /// session.sendMessage('hello');
  /// ```
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
    postProcessors.forEach(builder.with_);
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

/// Describes one request for [MockMvc.perform]: method, path, headers,
/// query parameters, cookies, user and body.
///
/// The shortcuts of [MockMvc] ([MockMvc.get], [MockMvc.post] and the
/// others) build it for you; build it yourself for cookies, a principal,
/// a [RequestPostProcessor] (a test user, a CSRF token) or a method
/// without a shortcut. Its collections are mutable, so a cascade fills
/// them.
///
/// ```dart
/// await mvc.perform(
///   MockRequestBuilder(HttpMethod.get, '/api/books')
///     ..params['q'] = 'dune'
///     ..headers['Accept'] = 'application/json',
/// ).andExpect(status: 200);
/// ```
///
/// Spring (Java): `MockHttpServletRequestBuilder`, from `get(...)`,
/// `post(...)` and the other `MockMvcRequestBuilders`.
final class MockRequestBuilder {
  /// A [method] request to [path]. Each `{name}` placeholder of [path] is
  /// filled, in order, from [uriVariables], URL-encoded; extra placeholders
  /// stay as written.
  MockRequestBuilder(
    this.method,
    String path, [
    List<Object?> uriVariables = const [],
  ]) : path = _expand(path, uriVariables);

  /// The HTTP method.
  final HttpMethod method;

  /// The path, with the URI variables filled in; it may carry a query
  /// (`/api/books?q=dune`).
  final String path;

  /// The headers to send, by name.
  final Map<String, String> headers = {};

  /// Query parameters to add; a `List` value sends the parameter once per
  /// element.
  final Map<String, Object> params = {};

  /// Cookies to send, by name.
  final Map<String, String> cookies = {};

  /// The authenticated user the request comes from; `null` for an anonymous
  /// request. With `spring_boot_starter_security`, its `user(...)`
  /// post-processor sets a full security context instead.
  Principal? principal;

  Object? _content;
  final _postProcessors = <RequestPostProcessor>[];

  /// Sets the body: a `String` (sent as UTF-8) or bytes. No `Content-Type`
  /// is added; set one in [headers].
  // Spring's `content(...)` request builder method, used in cascades: public
  // API, not a property.
  // ignore: use_setters_to_change_properties
  void content(Object body) => _content = body;

  /// Sets the body to [value] encoded as JSON, and `Content-Type:
  /// application/json` unless [headers] already have a content type.
  void json(Object? value) {
    _content = jsonEncode(value);
    headers.putIfAbsent(
      HttpHeaders.contentTypeHeader,
      () => MediaType.applicationJson,
    );
  }

  /// Adds [processor], which changes the request just before it is sent,
  /// after the [MockMvc.defaultPostProcessors]. Spring's `.with(...)`;
  /// the trailing `_` is there because `with` is a Dart keyword.
  void with_(RequestPostProcessor processor) => _postProcessors.add(processor);

  /// Builds the request; [MockMvc] calls it, and then applies the
  /// post-processors, which this does not.
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

/// A request that [MockMvc] sent, whose response can be checked: chain
/// [andExpect] and [andDo], then `await` the chain.
///
/// It is a `Future` of the [MvcResult], so `await` gives the result and a
/// failed expectation fails the test where it is awaited. A chain that is
/// not awaited checks nothing the test sees.
///
/// ```dart
/// final result = await mvc
///     .get('/api/books', params: {'q': 'dune'})
///     .andExpect(status: 200, json: hasLength(1))
///     .andReturn();
/// final first = (result.response.json! as List).first;
/// ```
///
/// Spring (Java): `ResultActions`, from `mockMvc.perform(...)`.
final class ResultActions implements Future<MvcResult> {
  ResultActions._(this._result);

  final Future<MvcResult> _result;

  /// Checks the response; each argument left out is not checked.
  ///
  /// - [status]: the status code, exactly.
  /// - [contentType]: a media type compatible with the response's
  ///   (`application/json` matches `application/json;charset=utf-8`).
  /// - [headers]: each listed header has exactly this value.
  /// - [body]: the body as text, equal to a `String` or matching a matcher.
  /// - [json]: the body decoded from JSON, equal to a value or matching a
  ///   matcher (`hasLength(1)`, `containsPair('title', 'Dune')`). A body
  ///   that is not JSON throws a `FormatException`.
  ///
  /// A failed check throws a `TestFailure` that names the request and shows
  /// the whole response. Spring's `andExpect(status().isOk())`,
  /// `content().json(...)` and the like, as named arguments.
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

  /// Runs [action] with the result, for example to log the response while
  /// writing a test: `.andDo((result) => log.info(result.response.bodyText))`.
  /// Spring's `andDo(print())`.
  ResultActions andDo(void Function(MvcResult result) action) =>
      ResultActions._(
        _result.then((result) {
          action(result);
          return result;
        }),
      );

  /// The [MvcResult], for checks that [andExpect] cannot express. The same
  /// as awaiting this object; Spring's spelling.
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

/// The request a [MockMvc] call sent and the response it got.
///
/// Get it with `await` or [ResultActions.andReturn] to read what
/// [ResultActions.andExpect] cannot check: response bytes, cookies, or the
/// events of a stream. For a server-sent event stream it is ready once the
/// headers are out, while the application is still writing; read the
/// events from [MockServerHttpResponse.eventStream] and end the stream
/// with [cancel].
///
/// ```dart
/// final result = await app.mockMvc.get('/api/books/changes').andReturn();
/// final next = result.response.eventStream.first; // the next event
/// ...
/// await result.cancel(); // the client goes away
/// ```
///
/// Spring (Java): `MvcResult`.
final class MvcResult {
  MvcResult._(this.request, this.response, this._handled);

  /// The request as it was sent, after the post-processors.
  final MockServerHttpRequest request;

  /// The response: `statusCode`, `headers`, `cookies`, `bodyText`,
  /// `bodyBytes`, `json`. For a stream it is still being written; see
  /// [MockServerHttpResponse.eventStream].
  final MockServerHttpResponse response;

  final Future<void> _handled;

  /// Completes when the application has finished handling the request;
  /// for a stream, when the stream ended or [cancel] was called.
  Future<void> get completion => _handled;

  /// Ends a streamed response from the client's side, as if the client went
  /// away, and completes when the application has finished the request.
  Future<void> cancel() {
    response.disconnect();
    return _handled;
  }
}
