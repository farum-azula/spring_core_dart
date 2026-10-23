import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/client/http_response.dart';
import 'package:spring_web_dart/src/client/http_transport.dart';
import 'package:spring_web_dart/src/client/streamed_http_response.dart';
import 'package:spring_web_dart/src/http_headers.dart';

/// An [HttpTransport] on `dart:io`'s `HttpClient`: the VM, Flutter mobile
/// and desktop. Follows redirects when the request says so
/// (`HttpRequest.followRedirects`, as far as `HttpClient` does: `GET` and
/// `HEAD`, and `303` after a `POST`). The request's `readTimeout` limits
/// each wait for data (the response, then every chunk of the body), its
/// `timeout` the whole exchange; the request is aborted when one runs out.
/// Like Spring's `JdkClientHttpRequestFactory`.
///
/// ```dart
/// import 'package:spring_web_dart/io.dart';
///
/// final transport = IoHttpTransport(connectTimeout: const Duration(seconds: 3));
/// final response = await transport.send(
///   HttpRequest(method: HttpMethod.get, url: Uri.parse('https://api.neon.books/books')),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// var factory = new JdkClientHttpRequestFactory(HttpClient.newHttpClient());
/// factory.setReadTimeout(Duration.ofSeconds(5));
/// ```
class IoHttpTransport implements HttpTransport {
  /// A transport on [client] (a new `HttpClient` by default);
  /// [connectTimeout] limits opening connections.
  IoHttpTransport({Duration? connectTimeout, io.HttpClient? client})
    : _client = client ?? io.HttpClient() {
    if (connectTimeout != null) {
      _client.connectionTimeout = connectTimeout;
    }
  }

  final io.HttpClient _client;

  @override
  Future<HttpResponse> send(HttpRequest request) =>
      _exchange(request, (incoming, _) async {
        final readTimeout = request.readTimeout;
        final chunks = readTimeout == null
            ? incoming
            : incoming.timeout(
                readTimeout,
                onTimeout: (sink) => sink.addError(_ReadTimeout(readTimeout)),
              );
        final bytes = await chunks.fold<BytesBuilder>(
          BytesBuilder(copy: false),
          (builder, chunk) => builder..add(chunk),
        );
        return HttpResponse(
          incoming.statusCode,
          headers: _headers(incoming),
          body: bytes.takeBytes(),
          request: request,
        );
      });

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) =>
      _exchange(request, (incoming, outgoing) async {
        late final StreamSubscription<List<int>> subscription;
        late final StreamController<List<int>> body;
        body = StreamController<List<int>>(
          onListen: () => subscription = incoming.listen(
            body.add,
            onError: (Object error, StackTrace stackTrace) => body.addError(
              error is io.IOException
                  ? HttpTransportException(
                      'response broke: $error',
                      request: request,
                      cause: error,
                    )
                  : error,
              stackTrace,
            ),
            onDone: body.close,
          ),
          onPause: () => subscription.pause(),
          onResume: () => subscription.resume(),
          // Cancelling alone would keep the connection open to drain it.
          onCancel: () async {
            await subscription.cancel();
            outgoing.abort();
          },
        );
        return StreamedHttpResponse(
          incoming.statusCode,
          headers: _headers(incoming),
          body: body.stream,
          request: request,
        );
      });

  // Sends [request] and hands the response to [read]; the request's timeout
  // covers both, its read timeout the wait for the response, and failures
  // become HttpTransportException.
  Future<T> _exchange<T>(
    HttpRequest request,
    Future<T> Function(
      io.HttpClientResponse incoming,
      io.HttpClientRequest outgoing,
    )
    read,
  ) async {
    io.HttpClientRequest? pending;
    Future<T> exchange() async {
      final outgoing = pending = await _client.openUrl(
        request.method.value,
        request.url,
      );
      outgoing.followRedirects = request.followRedirects;
      // The request's headers replace HttpClient's defaults (User-Agent,
      // Accept-Encoding); further values of the same name are added.
      request.headers.forEach((name, values) {
        if (name.toLowerCase() == 'content-length') {
          return;
        }
        outgoing.headers.set(name, values.first, preserveHeaderCase: true);
        for (final value in values.skip(1)) {
          outgoing.headers.add(name, value, preserveHeaderCase: true);
        }
      });
      final body = request.body;
      if (body != null) {
        outgoing
          ..contentLength = body.length
          ..add(body);
      }
      final readTimeout = request.readTimeout;
      final incoming = readTimeout == null
          ? await outgoing.close()
          : await outgoing.close().timeout(
              readTimeout,
              onTimeout: () => throw _ReadTimeout(readTimeout),
            );
      return read(incoming, outgoing);
    }

    final timeout = request.timeout;
    try {
      return timeout == null
          ? await exchange()
          : await exchange().timeout(timeout);
    } on _ReadTimeout catch (error) {
      pending?.abort(error);
      throw HttpTransportException(
        'no data within ${error.timeout.inMilliseconds} ms (read timeout)',
        request: request,
        cause: error,
        isTimeout: true,
      );
    } on TimeoutException catch (error) {
      pending?.abort(error);
      throw HttpTransportException(
        'no response within ${timeout!.inMilliseconds} ms',
        request: request,
        cause: error,
        isTimeout: true,
      );
    } on io.SocketException catch (error) {
      throw HttpTransportException(
        'connection failed: ${error.message}',
        request: request,
        cause: error,
        isTimeout: error.message.toLowerCase().contains('timed out'),
      );
    } on io.IOException catch (error) {
      throw HttpTransportException(
        'request failed: $error',
        request: request,
        cause: error,
      );
    }
  }

  static HttpHeaders _headers(io.HttpClientResponse incoming) {
    final headers = HttpHeaders();
    incoming.headers.forEach((name, values) {
      for (final value in values) {
        headers.add(name, value);
      }
    });
    return headers;
  }

  @override
  void close() => _client.close(force: true);
}

/// The read timeout of a request ran out: no data for [timeout].
final class _ReadTimeout implements Exception {
  _ReadTimeout(this.timeout);

  final Duration timeout;

  @override
  String toString() => 'no data within ${timeout.inMilliseconds} ms';
}
