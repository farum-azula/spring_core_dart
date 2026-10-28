import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/client/http_response.dart';
import 'package:spring_web_dart/src/client/http_transport.dart';
import 'package:spring_web_dart/src/client/streamed_http_response.dart';
import 'package:spring_web_dart/src/http_headers.dart';

/// The [HttpTransport] for platforms with `dart:io` (the Dart VM, Flutter
/// on mobile and desktop), built on `dart:io`'s `HttpClient`.
///
/// `platformHttpTransport()` returns one on these platforms, so you create
/// it yourself only to configure the `HttpClient`: a proxy, trusted
/// certificates, a user agent. Declare it as an `HttpTransport` bean and
/// the Feign starter uses it.
///
/// How it treats an [HttpRequest]:
///
/// - Its headers replace the `HttpClient` defaults of the same name
///   (`User-Agent`, `Accept-Encoding`); `Content-Length` is always taken
///   from the body.
/// - Redirects are followed when `followRedirects` is set, as far as
///   `HttpClient` follows them: for `GET` and `HEAD`, and a `303` after a
///   `POST`.
/// - `readTimeout` limits each wait for data (the response, then every
///   chunk of the body) and `timeout` the whole exchange. When one runs
///   out the request is aborted and an [HttpTransportException] with
///   `isTimeout` is thrown.
/// - Socket and other I/O errors become an [HttpTransportException]
///   whose `cause` is the original error.
///
/// ```dart
/// import 'dart:io';
///
/// import 'package:spring_web_dart/io.dart';
///
/// // Feign calls go through the company proxy.
/// @Configuration()
/// class HttpSetup {
///   @Bean()
///   HttpTransport httpTransport() => IoHttpTransport(
///     connectTimeout: const Duration(seconds: 3),
///     client: HttpClient()
///       ..findProxy = (_) => 'PROXY proxy.neon.books:3128',
///   );
/// }
/// ```
///
/// Spring (Java): `JdkClientHttpRequestFactory`, on the JDK's
/// `HttpClient`:
/// ```java
/// var factory = new JdkClientHttpRequestFactory(HttpClient.newHttpClient());
/// factory.setReadTimeout(Duration.ofSeconds(5));
/// ```
class IoHttpTransport implements HttpTransport {
  /// A transport that sends through [client], or through a new
  /// `HttpClient` when none is given. [connectTimeout], when set, becomes
  /// the client's `connectionTimeout`: the longest wait for a connection
  /// to open. [close] closes the client, also one passed in.
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
      final outgoing = (pending = await _client.openUrl(
        request.method.value,
        request.url,
      ))..followRedirects = request.followRedirects;
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
      return await read(incoming, outgoing);
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
