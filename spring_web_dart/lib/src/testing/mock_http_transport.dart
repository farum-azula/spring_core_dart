import 'dart:async';
import 'dart:convert';

import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/client/http_response.dart';
import 'package:spring_web_dart/src/client/http_transport.dart';
import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_method.dart';
import 'package:spring_web_dart/src/media_type.dart';

/// An [HttpTransport] for tests: answers with prepared responses and
/// records every request, like Spring's `MockRestServiceServer`. Several
/// `when` calls for the same request are answered in order, the last one
/// repeats; a request nobody expected throws a `StateError` listing the
/// expected ones.
///
/// ```dart
/// final transport = MockHttpTransport();
/// transport.when(HttpMethod.get, '/books/1').respond(200, json: {'isbn': '1', 'title': 'Dune'});
/// transport.when(HttpMethod.get, '/books?q=dune').respond(200, json: []);
/// transport.when(HttpMethod.post, 'https://api.neon.books/books')
///     .respondWith((request) => HttpResponse(201, request: request));
/// transport.when(HttpMethod.get, '/flaky').fail(HttpTransportException('down'));
///
/// // In a Spring Boot test: BeanOverride<HttpTransport>(transport)
/// expect(transport.lastRequest.headers['Accept'], 'application/json');
/// ```
///
/// Spring (Java):
/// ```java
/// MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
/// server.expect(requestTo("/books/1"))
///     .andRespond(withSuccess("{\"isbn\":\"1\"}", MediaType.APPLICATION_JSON));
/// ```
class MockHttpTransport implements HttpTransport {
  /// An empty mock: add expectations with [when].
  MockHttpTransport();

  final _expectations = <_Expectation>[];
  final _requests = <HttpRequest>[];

  /// Prepares the answer to [method] requests for [path]: a path
  /// (`/books/1`) or a full URL (`https://api.neon.books/books/1`); with a
  /// `?` the query must match too.
  MockResponseBuilder when(HttpMethod method, String path) {
    final expectation = _Expectation(method, path);
    _expectations.add(expectation);
    return MockResponseBuilder._(expectation);
  }

  /// The requests sent so far, in order.
  List<HttpRequest> get requests => List.unmodifiable(_requests);

  /// The last request sent; throws `StateError` when there was none.
  HttpRequest get lastRequest => _requests.isEmpty
      ? throw StateError('No request was sent')
      : _requests.last;

  /// Forgets the expectations and the recorded requests.
  void reset() {
    _expectations.clear();
    _requests.clear();
  }

  @override
  Future<HttpResponse> send(HttpRequest request) async {
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
    return answer(request);
  }

  @override
  void close() {}
}

/// Sets the answer of one expected request of a [MockHttpTransport].
///
/// ```dart
/// transport.when(HttpMethod.get, '/books/1').respond(404);
/// ```
///
/// Spring (Java): `ResponseActions.andRespond(...)`.
class MockResponseBuilder {
  MockResponseBuilder._(this._expectation);

  final _Expectation _expectation;

  /// Answers with [status] and a body: [json] (encoded, with
  /// `Content-Type: application/json`), [body] text or [bytes].
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
      if (!responseHeaders.contains(HttpHeaders.contentType)) {
        responseHeaders.set(HttpHeaders.contentType, MediaType.applicationJson);
      }
    } else if (body != null) {
      content = utf8.encode(body);
    } else {
      content = bytes ?? const [];
    }
    _expectation.answer = (request) async => HttpResponse(
      status,
      headers: responseHeaders.copy(),
      body: content,
      request: request,
    );
  }

  /// Answers with what [handler] returns for the request.
  void respondWith(
    FutureOr<HttpResponse> Function(HttpRequest request) handler,
  ) => _expectation.answer = (request) async => handler(request);

  /// Fails the request with [error] (e.g. an `HttpTransportException` to
  /// test retries).
  void fail(Object error) =>
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
  Future<HttpResponse> Function(HttpRequest request)? answer;

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
