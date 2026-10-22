import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/client/http_response.dart';
import 'package:spring_web_dart/src/client/http_transport.dart';
import 'package:spring_web_dart/src/client/streamed_http_response.dart';
import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_method.dart';

/// An [HttpTransport] on `dart:io`'s `HttpClient`: the VM, Flutter mobile
/// and desktop. Follows redirects for `GET` and `HEAD`; the request's
/// timeout covers the whole exchange (the request is aborted when it runs
/// out). Like Spring's `JdkClientHttpRequestFactory`.
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
        final bytes = await incoming.fold<BytesBuilder>(
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
  // covers both, and failures become HttpTransportException.
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
      outgoing.followRedirects =
          request.method == HttpMethod.get || request.method == HttpMethod.head;
      // The request's headers replace HttpClient's defaults (User-Agent,
      // Accept-Encoding); further values of the same name are added.
      final seen = <String>{};
      request.headers.forEach((name, value) {
        final key = name.toLowerCase();
        if (key == 'content-length') {
          return;
        }
        if (seen.add(key)) {
          outgoing.headers.set(name, value, preserveHeaderCase: true);
        } else {
          outgoing.headers.add(name, value, preserveHeaderCase: true);
        }
      });
      final body = request.body;
      if (body != null) {
        outgoing
          ..contentLength = body.length
          ..add(body);
      }
      return read(await outgoing.close(), outgoing);
    }

    final timeout = request.timeout;
    try {
      return timeout == null
          ? await exchange()
          : await exchange().timeout(timeout);
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
