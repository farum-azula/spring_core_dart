import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/client/http_response.dart';
import 'package:spring_web_dart/src/client/http_transport.dart';
import 'package:spring_web_dart/src/client/streamed_http_response.dart';
import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_method.dart';
import 'package:spring_web_dart/src/http_secrets.dart';

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
///   `POST` (then a `GET`), at most [maxRedirects]. A redirect to another
///   origin drops the headers that carry a credential
///   (`HttpSecrets.isSensitiveHeader` and the request's
///   `sensitiveHeaders`), as browsers drop `Authorization`; a redirect
///   from `https` to `http` is not followed (the `3xx` is returned).
/// - `readTimeout` limits each wait for data (the response, then every
///   chunk of the body) and `timeout` the whole exchange. When one runs
///   out the request is aborted and an [HttpTransportException] with
///   `isTimeout` is thrown.
/// - When `abort` completes before the status and headers arrive, the
///   request is aborted, which closes its connection, and an
///   [HttpTransportException] is thrown.
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
    // The caller gave the request up (HttpRequest.abort): aborting closes
    // the connection instead of leaving it open until the server answers.
    // Once the response is there, the body's subscription does that.
    var aborted = false;
    var answered = false;
    unawaited(
      request.abort?.then((_) {
        aborted = true;
        if (!answered) {
          pending?.abort(const _Aborted());
        }
      }),
    );
    Future<T> exchange() async {
      var method = request.method;
      var url = request.url;
      var body = request.body;
      final headers = HttpHeaders()..addHeaders(request.headers);
      for (var redirects = 0; ; redirects++) {
        // Redirects are followed here, not by HttpClient: a hop to another
        // origin must drop the credentials.
        final outgoing = (pending = await _client.openUrl(method.value, url))
          ..followRedirects = false;
        if (aborted) {
          // Given up while the connection was opening: nothing is sent.
          outgoing.abort(const _Aborted());
          await outgoing.close();
        }
        // The request's headers replace HttpClient's defaults (User-Agent,
        // Accept-Encoding); further values of the same name are added.
        headers.forEach((name, values) {
          if (name.toLowerCase() == 'content-length') {
            return;
          }
          outgoing.headers.set(name, values.first, preserveHeaderCase: true);
          for (final value in values.skip(1)) {
            outgoing.headers.add(name, value, preserveHeaderCase: true);
          }
        });
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
        final next = request.followRedirects && redirects < maxRedirects
            ? _redirect(method, url, incoming)
            : null;
        if (next == null) {
          final result = await read(incoming, outgoing);
          answered = true;
          return result;
        }
        await incoming.drain<void>();
        if (!_sameOrigin(url, next.url)) {
          [
            for (final name in headers.names)
              if (HttpSecrets.isSensitiveHeader(name) ||
                  request.sensitiveHeaders.contains(name.toLowerCase()))
                name,
          ].forEach(headers.remove);
        }
        if (next.method != method) {
          body = null;
          headers.remove('content-type');
        }
        method = next.method;
        url = next.url;
      }
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
    } on _Aborted catch (error) {
      throw HttpTransportException(
        'request aborted',
        request: request,
        cause: error,
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

  /// The most redirects one request follows, as `HttpClient`'s default.
  static const int maxRedirects = 5;

  // Where a redirect leads, as HttpClient follows them (GET and HEAD, and a
  // 303 after any method, which becomes a GET); null when it is not one to
  // follow, or leads from https to http (the 3xx is then the answer).
  static ({HttpMethod method, Uri url})? _redirect(
    HttpMethod method,
    Uri url,
    io.HttpClientResponse incoming,
  ) {
    const redirects = {301, 302, 303, 307, 308};
    final location = incoming.headers.value('location');
    if (!redirects.contains(incoming.statusCode) || location == null) {
      return null;
    }
    final safe = method == HttpMethod.get || method == HttpMethod.head;
    if (!safe && incoming.statusCode != 303) {
      return null;
    }
    final Uri target;
    try {
      target = url.resolve(location);
    } on FormatException {
      return null;
    }
    if (url.scheme == 'https' && target.scheme != 'https') {
      return null;
    }
    if (target.scheme != 'http' && target.scheme != 'https') {
      return null;
    }
    return (
      method: incoming.statusCode == 303 && method != HttpMethod.head
          ? HttpMethod.get
          : method,
      url: target,
    );
  }

  static bool _sameOrigin(Uri a, Uri b) =>
      a.scheme == b.scheme && a.host == b.host && a.port == b.port;
}

/// The caller gave the request up before the response arrived.
final class _Aborted implements Exception {
  const _Aborted();

  @override
  String toString() => 'the request was aborted by its caller';
}

/// The read timeout of a request ran out: no data for [timeout].
final class _ReadTimeout implements Exception {
  _ReadTimeout(this.timeout);

  final Duration timeout;

  @override
  String toString() => 'no data within ${timeout.inMilliseconds} ms';
}
