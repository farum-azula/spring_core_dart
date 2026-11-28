import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:spring_web_dart/src/client/address/address_connector_io.dart';
import 'package:spring_web_dart/src/client/address/allowed_addresses.dart';
import 'package:spring_web_dart/src/client/http_redirects.dart';
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
/// the RestClient starter's clients use it (with your
/// `allowedAddresses`: the starter's check is then yours to keep).
///
/// How it treats an [HttpRequest]:
///
/// - Its headers replace the `HttpClient` defaults of the same name
///   (`User-Agent`, `Accept-Encoding`); `Content-Length` is always taken
///   from the body.
/// - A `streamingBody` is read while it is written to the connection, as
///   fast as the connection takes it, never gathered: with
///   `Content-Length` when its length is known, else chunked. It is opened
///   once the address is allowed, so a denied call reads nothing.
/// - Redirects are followed when `followRedirects` is set, as far as
///   `HttpClient` follows them: for `GET` and `HEAD`, and a `303` after a
///   `POST` (then a `GET`), at most [maxRedirects]. A redirect to another
///   origin drops the headers that carry a credential
///   (`HttpSecrets.isSensitiveHeader` and the request's
///   `sensitiveHeaders`), as browsers drop `Authorization`; a redirect
///   from `https` to `http` is not followed (the `3xx` is returned). A
///   hop that keeps the method sends the body again: a `streamingBody`
///   that cannot be opened again is not, and the `3xx` is returned, as
///   Apache HttpClient does for a body that is not repeatable.
/// - `readTimeout` limits each wait for data (the response, then every
///   chunk of the body) and `timeout` the whole exchange. When one runs
///   out the request is aborted and an [HttpTransportException] with
///   `isTimeout` is thrown.
/// - When `abort` completes before the status and headers arrive, the
///   request is aborted, which closes its connection, and an
///   [HttpTransportException] is thrown.
/// - Socket and other I/O errors become an [HttpTransportException]
///   whose `cause` is the original error.
/// - `connectTimeout` of the request limits how long opening its
///   connection may take, within the transport's own `connectTimeout`
///   (`HttpClient.connectionTimeout`), which still applies: a request
///   cannot wait longer than it.
/// - With [allowedAddresses], every URL (the request's and each
///   redirect's) is checked before anything is sent, and a host name is
///   resolved by the transport, checked address by address and connected
///   to at an address it checked (`HttpClient.connectionFactory`, so DNS
///   rebinding cannot swap the address). A denied call fails with a
///   `FilteredHostException`. The TLS handshake is then the transport's:
///   give it `securityContext` and `allowBadCertificates` rather than
///   setting them on the `HttpClient`.
///
/// ```dart
/// import 'dart:io';
///
/// import 'package:spring_web_dart/io.dart';
///
/// // The HTTP clients' calls go through the company proxy.
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
  ///
  /// [allowedAddresses] limits the hosts and addresses it calls (see
  /// [AllowedAddresses]); `null` (the default) calls any. It replaces the
  /// client's `connectionFactory`. [allowBadCertificates] accepts a
  /// certificate that is expired, self-signed or for another host: for
  /// development servers only, never for an API. [securityContext] is the
  /// TLS context of the connections the transport secures itself (with
  /// [allowedAddresses]). [lookup] resolves host names for
  /// [allowedAddresses] (`InternetAddress.lookup` by default): a resolver
  /// of your own, such as DNS over HTTPS, or a fixed table in a test.
  IoHttpTransport({
    Duration? connectTimeout,
    io.HttpClient? client,
    this.allowedAddresses,
    io.SecurityContext? securityContext,
    bool allowBadCertificates = false,
    Future<List<io.InternetAddress>> Function(String host)? lookup,
  }) : _client = client ?? io.HttpClient(context: securityContext) {
    if (connectTimeout != null) {
      _client.connectionTimeout = connectTimeout;
    }
    if (allowBadCertificates) {
      _client.badCertificateCallback = (_, _, _) => true;
    }
    if (allowedAddresses case final allowed?) {
      _client.connectionFactory = checkedConnectionFactory(
        allowed,
        context: securityContext,
        onBadCertificate: allowBadCertificates ? (_, _, _) => true : null,
        lookup: lookup,
      );
    }
  }

  final io.HttpClient _client;

  /// The hosts and addresses the transport may call, or `null` for any.
  final AllowedAddresses? allowedAddresses;

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
      final streaming = request.streamingBody;
      Stream<List<int>>? stream;
      final headers = HttpHeaders()..addHeaders(request.headers);
      for (var redirects = 0; ; redirects++) {
        // Redirects are followed here, not by HttpClient: a hop to another
        // origin must drop the credentials, and each hop is checked.
        allowedAddresses?.checkUrl(url);
        // Before connecting: a body that cannot be sent again fails here,
        // and a stream is only listened to when it is written.
        if (streaming != null && redirects == 0) {
          stream = streaming.open();
        }
        final opening = _client.openUrl(method.value, url);
        final connectTimeout = request.connectTimeout;
        final outgoing =
            (pending = connectTimeout == null
                  ? await opening
                  : await opening.timeout(
                      connectTimeout,
                      onTimeout: () => throw _ConnectTimeout(connectTimeout),
                    ))
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
        } else if (stream != null) {
          await _write(outgoing, stream, streaming!.length);
        }
        final readTimeout = request.readTimeout;
        final incoming = readTimeout == null
            ? await outgoing.close()
            : await outgoing.close().timeout(
                readTimeout,
                onTimeout: () => throw _ReadTimeout(readTimeout),
              );
        final next = request.followRedirects && redirects < maxRedirects
            ? HttpRedirects.next(
                method,
                url,
                incoming.statusCode,
                incoming.headers.value('location'),
              )
            : null;
        final keepsBody = next != null && next.method == method;
        // A stream read once cannot follow: the 3xx is the answer.
        if (next == null ||
            (keepsBody && stream != null && !streaming!.isRepeatable)) {
          final result = await read(incoming, outgoing);
          answered = true;
          return result;
        }
        await incoming.drain<void>();
        HttpRedirects.applyHop(headers, request, url, next.url);
        if (!keepsBody) {
          body = null;
          stream = null;
          headers.remove('content-type');
        } else if (stream != null) {
          stream = streaming!.open();
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
    } on _ConnectTimeout catch (error) {
      throw HttpTransportException(
        'no connection within ${error.timeout.inMilliseconds} ms '
        '(connect timeout)',
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

  // Writes [stream] as the body of [outgoing], at the pace of the
  // connection: with Content-Length when [length] is known, else chunked.
  static Future<void> _write(
    io.HttpClientRequest outgoing,
    Stream<List<int>> stream,
    int? length,
  ) async {
    if (length != null) {
      outgoing.contentLength = length;
    } else {
      outgoing.headers.chunkedTransferEncoding = true;
    }
    // Each chunk goes out as it comes: a stream produced slowly is not
    // held back to fill a buffer.
    outgoing.bufferOutput = false;
    try {
      await outgoing.addStream(stream);
    } on Object catch (error) {
      // A source that failed, or a connection that broke: nothing more is
      // sent on it.
      outgoing.abort(error);
      unawaited(outgoing.done.then<void>((_) {}, onError: (Object _) {}));
      rethrow;
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
  static const int maxRedirects = HttpRedirects.maxRedirects;
}

/// The caller gave the request up before the response arrived.
final class _Aborted implements Exception {
  const _Aborted();

  @override
  String toString() => 'the request was aborted by its caller';
}

/// The connect timeout of a request ran out: no connection within
/// [timeout].
final class _ConnectTimeout implements Exception {
  _ConnectTimeout(this.timeout);

  final Duration timeout;

  @override
  String toString() => 'no connection within ${timeout.inMilliseconds} ms';
}

/// The read timeout of a request ran out: no data for [timeout].
final class _ReadTimeout implements Exception {
  _ReadTimeout(this.timeout);

  final Duration timeout;

  @override
  String toString() => 'no data within ${timeout.inMilliseconds} ms';
}
