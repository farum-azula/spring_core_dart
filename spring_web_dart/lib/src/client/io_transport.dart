import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/client/http_response.dart';
import 'package:spring_web_dart/src/client/http_transport.dart';
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
  Future<HttpResponse> send(HttpRequest request) async {
    io.HttpClientRequest? pending;
    Future<HttpResponse> exchange() async {
      final outgoing = pending = await _client.openUrl(
        request.method.value,
        request.url,
      );
      outgoing.followRedirects =
          request.method == HttpMethod.get || request.method == HttpMethod.head;
      request.headers.forEach((name, value) {
        if (name.toLowerCase() != 'content-length') {
          outgoing.headers.add(name, value, preserveHeaderCase: true);
        }
      });
      final body = request.body;
      if (body != null) {
        outgoing
          ..contentLength = body.length
          ..add(body);
      }
      final incoming = await outgoing.close();
      final bytes = await incoming.fold<BytesBuilder>(
        BytesBuilder(copy: false),
        (builder, chunk) => builder..add(chunk),
      );
      final headers = HttpHeaders();
      incoming.headers.forEach((name, values) {
        for (final value in values) {
          headers.add(name, value);
        }
      });
      return HttpResponse(
        incoming.statusCode,
        headers: headers,
        body: bytes.takeBytes(),
        request: request,
      );
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

  @override
  void close() => _client.close(force: true);
}
