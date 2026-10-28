import 'dart:async';
import 'dart:convert';

import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/client/http_response.dart';
import 'package:spring_web_dart/src/client/http_transport.dart';
import 'package:spring_web_dart/src/client/streamed_http_response.dart';
import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_method.dart';
import 'package:spring_web_dart/src/media_type.dart';
import 'package:spring_web_dart/src/sse/server_sent_event.dart';

/// A fake HTTP connection for tests: it answers requests with responses
/// prepared in advance, without any network, and records every request
/// sent.
///
/// It replaces the real [HttpTransport] under the code being tested,
/// typically a Feign client, so a test decides what the remote service
/// answers (data, errors, failures, event streams) and checks what the
/// client sent. Prepare an answer with [when] for a method and a path.
/// Several answers prepared for the same request are used in order, and
/// the last one repeats. A request without a prepared answer throws a
/// `StateError` that lists the prepared ones.
///
/// ```dart
/// // The catalog service a Feign client calls is played by the mock.
/// final catalog = MockHttpTransport()
///   ..when(HttpMethod.get, '/books/978-0')
///       .respond(200, json: {'isbn': '978-0', 'title': 'Dune'})
///   ..when(HttpMethod.get, '/books/000').respond(404)
///   ..when(HttpMethod.get, '/flaky')
///       .fail(HttpTransportException('down')); // to test retries
///
/// final app = springBootTest(
///   springApplication,
///   overrides: [BeanOverride<HttpTransport>(catalog)],
/// );
///
/// test('finds a book', () async {
///   final book = await app.getBean<CatalogClient>().find('978-0');
///   expect(book.title, 'Dune');
///   expect(catalog.lastRequest.headers['Accept'], 'application/json');
/// });
/// ```
///
/// Spring (Java):
/// ```java
/// MockRestServiceServer server =
///     MockRestServiceServer.bindTo(builder).build();
/// server.expect(requestTo("/books/978-0"))
///     .andRespond(withSuccess("{\"title\":\"Dune\"}",
///         MediaType.APPLICATION_JSON));
/// ```
class MockHttpTransport implements HttpTransport {
  /// A mock with no prepared answer yet; add them with [when].
  MockHttpTransport();

  final _expectations = <_Expectation>[];
  final _requests = <HttpRequest>[];

  /// Starts preparing the answer to [method] requests for [path]; finish
  /// it with one of the methods of the returned [MockResponseBuilder].
  ///
  /// [path] is a path (`/books/1`, any host matches) or a full URL
  /// (`https://api.neon.books/books/1`, scheme, host and port must match).
  /// A trailing `/` does not matter. Without a `?` any query matches; with
  /// one (`/books?q=dune`) the query must have exactly the same parameters
  /// and values.
  MockResponseBuilder when(HttpMethod method, String path) {
    final expectation = _Expectation(method, path);
    _expectations.add(expectation);
    return MockResponseBuilder._(expectation);
  }

  /// Every request sent so far, in order, including those that had no
  /// prepared answer.
  List<HttpRequest> get requests => List.unmodifiable(_requests);

  /// The last request sent, to check its headers or body; throws a
  /// `StateError` when none was sent.
  HttpRequest get lastRequest => _requests.isEmpty
      ? throw StateError('No request was sent')
      : _requests.last;

  /// Forgets the prepared answers and the recorded requests, for example
  /// between two tests that share the mock.
  void reset() {
    _expectations.clear();
    _requests.clear();
  }

  @override
  Future<HttpResponse> send(HttpRequest request) async =>
      await (await _answer(request)).read();

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) => _answer(request);

  Future<StreamedHttpResponse> _answer(HttpRequest request) async {
    _requests.add(request);
    final matching = [
      for (final expectation in _expectations)
        if (expectation.matches(request)) expectation,
    ];
    if (matching.isEmpty) {
      throw StateError(
        'MockHttpTransport: no response prepared for $request. Expected: '
        '${_expectations.isEmpty ? 'nothing' : _expectations.join(', ')}',
      );
    }
    final expectation = matching.firstWhere(
      (e) => !e.used,
      orElse: () => matching.last,
    )..used = true;
    final answer =
        expectation.answer ??
        (throw StateError(
          'MockHttpTransport: when($expectation) has no respond(...)',
        ));
    return await answer(request);
  }

  @override
  void close() {}
}

/// Sets how a [MockHttpTransport] answers one prepared request; returned
/// by [MockHttpTransport.when].
///
/// Call exactly one of its methods: a fixed response ([respond]), one
/// computed from the request ([respondWith]), a stream ([respondStream],
/// [respondEvents]) or a failure ([fail]). A request matched before any
/// of them was called throws a `StateError`.
///
/// ```dart
/// // The remote service answers a created book with its location.
/// transport.when(HttpMethod.post, '/books').respondWith(
///   (request) => HttpResponse(
///     201,
///     headers: HttpHeaders({'Location': '/books/978-0'}),
///     request: request,
///   ),
/// );
/// ```
///
/// Spring (Java): `ResponseActions.andRespond(...)`.
class MockResponseBuilder {
  MockResponseBuilder._(this._expectation);

  final _Expectation _expectation;

  /// Answers with [status], [headers] and at most one kind of body:
  /// [json], encoded, with `Content-Type: application/json` unless
  /// [headers] set another; [body], text sent in UTF-8; or [bytes]. With
  /// none of them the body is empty. If several are given, [json] wins,
  /// then [body].
  void respond(
    int status, {
    Object? json,
    String? body,
    List<int>? bytes,
    Map<String, String> headers = const {},
  }) {
    final responseHeaders = HttpHeaders(headers);
    final List<int> content;
    if (json != null) {
      content = utf8.encode(jsonEncode(json));
      if (!responseHeaders.contains(HttpHeaders.contentTypeHeader)) {
        responseHeaders.set(
          HttpHeaders.contentTypeHeader,
          MediaType.applicationJson,
        );
      }
    } else if (body != null) {
      content = utf8.encode(body);
    } else {
      content = bytes ?? const [];
    }
    _expectation.answer = (request) async => StreamedHttpResponse(
      status,
      headers: responseHeaders.copy(),
      body: Stream.value(content),
      request: request,
    );
  }

  /// Answers with the response [handler] builds from the request, for an
  /// answer that depends on what was sent (an echo, a generated id).
  void respondWith(
    FutureOr<HttpResponse> Function(HttpRequest request) handler,
  ) => _expectation.answer = (request) async {
    final response = await handler(request);
    return StreamedHttpResponse(
      response.statusCode,
      headers: response.headers,
      body: Stream.value(response.bodyBytes),
      request: response.request ?? request,
    );
  };

  /// Answers with a stream of server-sent events, as an
  /// `EventStream` endpoint does: `Content-Type: text/event-stream` (unless
  /// [headers] set another), then [events], one chunk each. Data that is
  /// not a `String` is written as JSON. The stream ends after the last
  /// event, so a client that reconnects sends a new request; with
  /// [keepOpen] it stays open until the client cancels.
  ///
  /// ```dart
  /// transport.when(HttpMethod.get, '/orders/events').respondEvents([
  ///   ServerSentEvent({'id': 1, 'status': 'NEW'}, id: '1'),
  /// ]);
  /// ```
  void respondEvents(
    List<ServerSentEvent<Object?>> events, {
    int status = 200,
    bool keepOpen = false,
    Map<String, String> headers = const {},
  }) {
    final responseHeaders = HttpHeaders(headers);
    if (!responseHeaders.contains(HttpHeaders.contentTypeHeader)) {
      responseHeaders.set(
        HttpHeaders.contentTypeHeader,
        MediaType.textEventStream,
      );
    }
    respondStream(status, () async* {
      for (final event in events) {
        yield utf8.encode(
          event.encode((data) => data is String ? data : jsonEncode(data)),
        );
      }
      if (keepOpen) {
        await Completer<void>().future;
      }
    }, headers: responseHeaders.toMap());
  }

  /// Answers with [status], [headers] and the byte stream [body] returns;
  /// [body] is called again for each request, so every request gets a
  /// fresh stream. Use it for a slow or endless body.
  void respondStream(
    int status,
    Stream<List<int>> Function() body, {
    Map<String, String> headers = const {},
  }) => _expectation.answer = (request) async => StreamedHttpResponse(
    status,
    headers: HttpHeaders(headers),
    body: body(),
    request: request,
  );

  /// Makes the request fail with [error] instead of answering, as a lost
  /// connection does; an [HttpTransportException] tests how the client
  /// retries or reports it.
  void fail(Object error) =>
      // Any object can be prepared as the failure, as the caller passes it.
      // ignore: only_throw_errors
      _expectation.answer = (request) async => throw error;
}

final class _Expectation {
  _Expectation(this.method, this.path)
    : _uri = Uri.parse(path),
      _hasQuery = path.contains('?');

  final HttpMethod method;
  final String path;
  final Uri _uri;
  final bool _hasQuery;
  bool used = false;
  Future<StreamedHttpResponse> Function(HttpRequest request)? answer;

  bool matches(HttpRequest request) {
    if (request.method != method) {
      return false;
    }
    final url = request.url;
    if (_uri.hasScheme &&
        (_uri.scheme != url.scheme ||
            _uri.host != url.host ||
            _uri.port != url.port)) {
      return false;
    }
    if (_normalize(_uri.path) != _normalize(url.path)) {
      return false;
    }
    if (_hasQuery &&
        !_sameQuery(_uri.queryParametersAll, url.queryParametersAll)) {
      return false;
    }
    return true;
  }

  static String _normalize(String path) {
    final withSlash = path.startsWith('/') ? path : '/$path';
    return withSlash.length > 1 && withSlash.endsWith('/')
        ? withSlash.substring(0, withSlash.length - 1)
        : withSlash;
  }

  static bool _sameQuery(
    Map<String, List<String>> a,
    Map<String, List<String>> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    for (final MapEntry(:key, :value) in a.entries) {
      final other = b[key];
      if (other == null || other.join('\u0000') != value.join('\u0000')) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() => '${method.value} $path';
}
