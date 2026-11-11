import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/io_web_socket.dart';
import 'package:spring_boot_starter_web/src/request_target.dart';
import 'package:spring_boot_starter_web/src/web_server.dart';
import 'package:spring_web_dart/io.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.web.server');

/// Creates the HTTP server the starter uses by default: `dart:io`'s
/// `HttpServer`, on the VM and in Flutter apps on mobile and desktop.
///
/// The starter declares one as the `webServerFactory` bean, with
/// [settings] read from `server.*` and then passed to every
/// `WebServerFactoryCustomizer` bean. Applications rarely touch it: they
/// set properties, or change [settings] in a customizer. Import it from
/// `package:spring_boot_starter_web/io.dart` to wrap it in a factory of
/// your own, or to start a server outside the context, for example in a
/// tool.
///
/// ```dart
/// // A server for a test, on a free port, answering with a plain handler.
/// final server = IoWebServerFactory(const ServerProperties(port: 0))
///     .getWebServer(FunctionHttpHandler(
///       (request, response) => response.send(200, 'pong'),
///     ));
/// await server.start();
/// log.info('listening on ${server.port}');
/// ```
///
/// Spring Boot's default is Tomcat (`TomcatServletWebServerFactory`) in
/// its place.
final class IoWebServerFactory implements ConfigurableWebServerFactory {
  /// A factory whose servers use [settings]; Spring Boot's defaults when
  /// none are given (port 8080, all addresses).
  IoWebServerFactory([this.settings = const ServerProperties()]);

  @override
  ServerProperties settings;

  @override
  WebServer getWebServer(HttpHandler handler) => IoWebServer(handler, settings);
}

/// An HTTP server on `dart:io`'s `HttpServer`, made by
/// [IoWebServerFactory].
///
/// [start] binds the socket (with TLS when [settings] have `ssl`), and
/// every request goes to [handler] as a `ServerHttpRequest` and
/// `ServerHttpResponse`. A port in use is a [PortInUseException], any
/// other failure to listen a [WebServerException]. Some requests are
/// answered before the handler, with a problem
/// (`application/problem+json`):
///
/// - a method that `HttpMethod` does not list: 501;
/// - with `server.ssl.client-auth=need`, no client certificate: 403;
/// - a malformed `Host` header, an HTTP/1.1 request without one, or an
///   absolute target (`GET http://a.example/ HTTP/1.1`) whose host is not
///   the `Host` header's: 400, as Tomcat answers;
/// - an encoded `/`, `\` or NUL in the path (`%2F`, `%5C`, `%00`): 400,
///   as Tomcat answers by default, so `..%2F..%2Fsecret` never reaches a
///   path variable;
/// - a `.` or `..` segment that is left once matrix parameters are cut
///   off (`/files/..;x/secret`): 400, so `..` never reaches a path
///   variable either;
/// - a `%` escape in the path or the query that is malformed or not
///   UTF-8 (`/%FF`, `/%C0%AF`, `?id=%FF`): 400, as Tomcat answers.
///
/// `dart:io` keeps only the last of two `Host` headers, so a request with
/// two is served for the last one (Tomcat answers 400). It also parses
/// the request target before the server sees it, and keeps no raw form:
/// a raw `\` becomes `/`, so `..\` segments are resolved
/// (`/files/..\..\secret` arrives as `/secret`), and raw bytes past
/// ASCII are read as Latin-1 (Tomcat answers 400 to both). The router
/// and the security rules see the same path, but a proxy in front that
/// checks paths must refuse `\` itself.
///
/// A request body that sends nothing for `server.connection-timeout`
/// (60 s, Tomcat's `connectionTimeout`) while it is read fails with a
/// 408 problem, and the connection closes after the answer. A body
/// nobody reads is read and dropped after the answer: up to 2 MB, for at
/// most 5 seconds, so the connection can serve the next request (as
/// Tomcat's `max-swallow-size`); a longer or slower one closes the
/// connection. An idle connection closes after the same timeout. There
/// is no limit on the number of connections (Tomcat's
/// `max-connections`, 8192): put a proxy in front, or rely on the
/// system's limit of open files.
///
/// A response the client does not take is given up after the same
/// timeout: when none of its bytes leave for `server.connection-timeout`
/// the connection is dropped and the request is over, so a client that
/// asks and never reads cannot hold a place of
/// `server.max-concurrent-requests`, nor the body in memory, nor a
/// graceful stop. The time is counted per 64 KB of the body, and only
/// while bytes wait for the client: a download of any size that keeps
/// moving, however slowly, and a stream that is quiet between two
/// events are not cut.
///
/// When a handler fails after the response was committed (the status
/// and headers are out), the connection is dropped without finishing the
/// response (no final chunk), as Tomcat does, so the client sees a
/// broken response rather than a complete one.
///
/// A response header whose name or value `dart:io` cannot send (a
/// non-ASCII character, a line break) fails before anything is sent: the
/// header is dropped and the error answered as usual (a 500 problem).
/// [stop] follows `server.shutdown`: gracefully, running requests may
/// finish within the timeout; event streams and WebSocket sessions are
/// closed at once in both modes.
///
/// A request that shows both `Content-Length` and `Transfer-Encoding`
/// is answered 400 and its connection closed (RFC 9112 §6.3). `dart:io`
/// shows both only when the length comes first and the encoding is not
/// written exactly `chunked` (`Chunked`, `gzip, chunked`); in every
/// other case it drops the `Content-Length` before the server sees the
/// request, and reads the body as chunked, as the RFC allows. Such a
/// request cannot be told from a chunked one here and is served: behind
/// a proxy that reads it differently, requests can be smuggled. Put a
/// proxy in front that refuses them (most do).
///
/// The `Server` header is not sent, nor `X-XSS-Protection`; `dart:io`'s
/// `X-Frame-Options: SAMEORIGIN` and `X-Content-Type-Options: nosniff`
/// stay. `dart:io`'s default `Content-Type: text/plain; charset=utf-8` is
/// not sent either: an answer whose type the application did not set
/// has none, as with Tomcat. An answer that has no body by its status
/// (1xx, 204, 304) gets no `Content-Length` and no
/// `Transfer-Encoding` (RFC 9110 §8.6), a 304 or 1xx no `Content-Type`,
/// and what is written to it is dropped, as Tomcat does.
///
/// The starter's lifecycle bean starts and stops it with the context;
/// applications do not create one directly.
final class IoWebServer implements WebServer, WebServerActivity {
  /// A server that hands requests to [handler] and listens as [settings]
  /// say.
  IoWebServer(this.handler, this.settings);

  /// Answers every request; in the application, the `dispatcherHandler`.
  final HttpHandler handler;

  /// The `server.*` settings: address, port, TLS, compression, shutdown.
  final ServerProperties settings;

  io.HttpServer? _server;

  // The listening socket of a server without TLS (dart:io keeps the one
  // of a TLS server to itself).
  _Accepting? _accepting;

  // Stopping gracefully: every answer closes its connection.
  var _leaving = false;
  final _exchanges = <_Exchange>{};
  final _sessions = <IoWebSocketSession>{};

  @override
  int get port => _server?.port ?? -1;

  @override
  int get activeRequests => _exchanges.length;

  @override
  int get requestCount => _requests;
  var _requests = 0;

  @override
  int get refusedCount => _refused;
  var _refused = 0;

  // The connections open, counted at most every 100 ms: dart:io counts
  // them by going through them all.
  int _connections = 0;
  final _counted = Stopwatch();

  // Why the server takes no more now, when it is full; `null` when it
  // has room. A full server answers at once that it is: a request that
  // waits behind the others answers late or never, and takes memory
  // meanwhile.
  (String, {bool close})? _full(io.HttpServer server) {
    if (settings.maxConcurrentRequests case final max?
        when _exchanges.length > max) {
      var active = 0;
      for (final exchange in _exchanges) {
        if (!exchange.isStreaming) {
          active++;
        }
      }
      if (active > max) {
        return (
          'The server answers its most requests at a time ($max)',
          close: false,
        );
      }
    }
    if (settings.maxConnections case final max?) {
      if (!_counted.isRunning ||
          _counted.elapsedMilliseconds >= 100 ||
          _connections > max) {
        _connections = server.connectionsInfo().total;
        _counted
          ..reset()
          ..start();
      }
      if (_connections > max) {
        return (
          'The server has its most connections open ($max)',
          close: true,
        );
      }
    }
    return null;
  }

  @override
  Future<void> start() => _starting ??= _bind();

  // The bind in progress: a stop() waits for it, so a server stopped while
  // its socket was still opening does not keep listening.
  Future<void>? _starting;

  Future<void> _bind() async {
    _leaving = false;
    final address = await _address(settings.address);
    final ssl = settings.ssl;
    try {
      _server = ssl == null
          // The socket is this server's own, so that a stop can end
          // accepting first and let the open connections finish
          // ([_Accepting]); dart:io's bind does the same two steps.
          ? io.HttpServer.listenOn(
              _accepting = _Accepting(
                await io.ServerSocket.bind(
                  address,
                  settings.port,
                  shared: settings.shared,
                ),
              ),
            )
          : await io.HttpServer.bindSecure(
              address,
              settings.port,
              _securityContext(ssl),
              requestClientCertificate: ssl.clientAuth != ClientAuth.none,
              shared: settings.shared,
            );
    } on io.SocketException catch (error) {
      if (_isAddressInUse(error)) {
        throw PortInUseException(settings.port, error);
      }
      throw WebServerException(
        'cannot listen on ${settings.address ?? '*'}:${settings.port}',
        error,
      );
    }
    // Compression is done per response ([_IoResponse]), with Spring
    // Boot's media types and minimum size; dart:io's own only covers
    // bodies without a Content-Length.
    final server = _server!
      ..autoCompress = false
      ..serverHeader = null
      // Tomcat's keepAliveTimeout is its connectionTimeout.
      ..idleTimeout = settings.effectiveConnectionTimeout;
    // dart:io's defaults: X-Frame-Options: SAMEORIGIN and
    // X-Content-Type-Options: nosniff stay (Spring Boot without Spring
    // Security sends neither; the security starter will own these headers);
    // X-XSS-Protection is obsolete. Its Content-Type: text/plain would
    // label every answer whose type the application did not set: a 304
    // or 204, an empty answer; on a 304 a cache would even replace the
    // stored type with it (RFC 9111 §4.3.4), and with nosniff a browser
    // then refuses a revalidated script or style sheet.
    server.defaultResponseHeaders
      ..removeAll('x-xss-protection')
      ..removeAll(io.HttpHeaders.contentTypeHeader);
    server.listen(
      _serve,
      onError: (Object error, StackTrace stackTrace) {
        _log.warning('Server error', error: error, stackTrace: stackTrace);
      },
    );
  }

  @override
  Future<void> stop({Duration? timeout}) async {
    final starting = _starting;
    _starting = null;
    if (starting != null) {
      try {
        await starting;
      } on Object {
        // It did not start: nothing to stop.
      }
    }
    final server = _server;
    if (server == null) {
      return;
    }
    _server = null;
    final accepting = _accepting;
    _accepting = null;
    final graceful = settings.shutdown == Shutdown.graceful;
    if (graceful && accepting != null) {
      // No new connections, while the open ones still work: closing the
      // server at once would end every idle connection, and with it the
      // request a client has just sent on one (a keep-alive connection
      // looks idle until its next request is read).
      _leaving = true;
      await accepting.refuse();
    }
    // Open event streams and WebSockets end now (they would never finish
    // by themselves).
    for (final session in _sessions.toList()) {
      unawaited(
        session
            .close(CloseStatus.goingAway.withReason('Server stopping'))
            .catchError((Object _) {}),
      );
    }
    for (final exchange in _exchanges.toList()) {
      if (exchange.isStreaming) {
        unawaited(exchange.abort());
      }
    }
    final limit = timeout ?? const Duration(seconds: 30);
    if (_leaving) {
      await _letConnectionsLeave(server, limit);
    }
    final closing = server.close().whenComplete(
      () => accepting?.close() ?? Future<void>.value(),
    );
    if (graceful) {
      final active = _exchanges.isNotEmpty;
      if (active) {
        _log.info('Commencing graceful shutdown. Waiting for active requests');
      }
      // Running requests finish; then the non-forced close ends idle
      // connections once their responses are out (a forced close could
      // cut a response the client is still reading).
      final completed =
          await Future.wait([
                for (final exchange in _exchanges) exchange.finished,
              ])
              .then((_) => closing)
              .then((_) => true)
              .timeout(limit, onTimeout: () => false);
      if (active || !completed) {
        _log.info(
          completed
              ? 'Graceful shutdown complete'
              : 'Graceful shutdown aborted with one or more requests still '
                    'active',
        );
      }
      if (completed) {
        return;
      }
    }
    await server.close(force: true);
    await closing;
  }

  // Waits, while the server is leaving, for its connections to close: each
  // does with its next answer (`Connection: close`). One that sends nothing
  // would be waited for in vain, so a short while without any request ends
  // the wait, and [limit] (five seconds at most) does in any case.
  Future<void> _letConnectionsLeave(
    io.HttpServer server,
    Duration limit,
  ) async {
    const step = Duration(milliseconds: 5);
    const quiet = Duration(milliseconds: 30);
    const most = Duration(seconds: 5);
    final watch = Stopwatch()..start();
    final sinceRequest = Stopwatch()..start();
    var requests = _requests;
    while (watch.elapsed < limit && watch.elapsed < most) {
      if (server.connectionsInfo().total == 0) {
        return;
      }
      if (_requests != requests || _exchanges.isNotEmpty) {
        requests = _requests;
        sinceRequest.reset();
      } else if (sinceRequest.elapsed >= quiet) {
        return;
      }
      await Future<void>.delayed(step);
    }
  }

  Future<void> _serve(io.HttpRequest ioRequest) async {
    final exchange = _Exchange(this, ioRequest);
    _exchanges.add(exchange);
    _requests++;
    if (_leaving) {
      exchange.response.headers.set('Connection', 'close');
      ioRequest.response.persistentConnection = false;
    }
    try {
      final server = _server;
      if (server != null) {
        if (_full(server) case (final reason, :final close)?) {
          _refused++;
          final seconds = settings.retryAfter.inSeconds;
          exchange.response.headers.set(
            'Retry-After',
            '${seconds < 1 ? 1 : seconds}',
          );
          if (close) {
            // One connection too many: this one goes.
            exchange.response.headers.set('Connection', 'close');
            ioRequest.response.persistentConnection = false;
          }
          await exchange.response.problem(
            HttpStatus.serviceUnavailable,
            reason,
          );
          return;
        }
      }
      final method = _method(ioRequest.method);
      if (method == null) {
        await exchange.response.problem(
          HttpStatus.notImplemented,
          'Unsupported method',
        );
        return;
      }
      if (settings.ssl?.clientAuth == ClientAuth.need &&
          ioRequest.certificate == null) {
        await exchange.response.problem(
          HttpStatus.forbidden,
          'A client certificate is required',
        );
        return;
      }
      if (_hostProblem(ioRequest) case final problem?) {
        await exchange.response.problem(HttpStatus.badRequest, problem);
        return;
      }
      if (requestTargetProblem(ioRequest.uri) case final problem?) {
        await exchange.response.problem(HttpStatus.badRequest, problem);
        return;
      }
      if (_framingProblem(ioRequest) case final problem?) {
        // The two disagree about where the request ends: nothing after
        // it on this connection can be trusted (RFC 9112 §6.3).
        exchange.response.headers.set('Connection', 'close');
        ioRequest.response.persistentConnection = false;
        await exchange.response.problem(HttpStatus.badRequest, problem);
        return;
      }
      await handler.handle(exchange.request(method), exchange.response);
    } on Object catch (error, stackTrace) {
      _log.error(
        'Request ${ioRequest.method} ${ioRequest.uri} failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (exchange.response.isCommitted && !exchange.upgraded) {
        await exchange.response.abort();
      } else if (!exchange.upgraded) {
        await exchange.response.problem(
          HttpStatus.internalServerError,
          null,
        );
      }
    } finally {
      if (!exchange.upgraded) {
        await exchange.response.close().catchError((_) {});
        exchange.releaseBody();
      }
      _exchanges.remove(exchange);
      exchange.finish();
    }
  }

  // RFC 9110's Host: a host name, an IPv4 address or a bracketed IPv6
  // address, then an optional port.
  static final _host = RegExp(
    r'^(?:\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9._~-]+)(?::[0-9]{1,5})?$',
  );

  // As Tomcat: a malformed Host, none in HTTP/1.1 (RFC 9112 §3.2; HTTP/1.0
  // may omit it), or an absolute target naming another host is a 400.
  static String? _hostProblem(io.HttpRequest request) {
    final host = request.headers[io.HttpHeaders.hostHeader]?.lastOrNull;
    if (host == null || host.isEmpty) {
      return request.protocolVersion == '1.0'
          ? null
          : 'The Host header is missing';
    }
    if (!_host.hasMatch(host) || Uri.tryParse('http://$host') == null) {
      return 'Invalid Host header';
    }
    final target = request.uri;
    if (target.hasScheme && target.hasAuthority) {
      final named = Uri.parse('http://$host');
      int port(Uri uri, String scheme) => uri.hasPort
          ? uri.port
          : (scheme == 'https' || scheme == 'wss' ? 443 : 80);
      if (target.host.toLowerCase() != named.host.toLowerCase() ||
          port(target, target.scheme) != port(named, target.scheme)) {
        return 'The host of the request target is not the Host header';
      }
    }
    return null;
  }

  // A request with both Content-Length and Transfer-Encoding: two ways
  // to say where its body ends, which a proxy in front may read the other
  // way (request smuggling). dart:io reads the body as chunked and, for
  // the plain `Transfer-Encoding: chunked`, removes the Content-Length
  // itself; this sees the requests where it left both.
  static String? _framingProblem(io.HttpRequest request) {
    final headers = request.headers;
    return headers[io.HttpHeaders.transferEncodingHeader] != null &&
            headers[io.HttpHeaders.contentLengthHeader] != null
        ? 'A request cannot have both Content-Length and Transfer-Encoding'
        : null;
  }

  static HttpMethod? _method(String value) {
    for (final method in HttpMethod.values) {
      if (method.value == value) {
        return method;
      }
    }
    return null;
  }

  static Future<Object> _address(String? text) async {
    if (text == null || text.isEmpty) {
      return io.InternetAddress.anyIPv6;
    }
    if (io.InternetAddress.tryParse(text) case final address?) {
      return address;
    }
    if (text == 'localhost') {
      return io.InternetAddress.loopbackIPv4;
    }
    final found = await io.InternetAddress.lookup(text);
    return found.first;
  }

  static io.SecurityContext _securityContext(SslSettings ssl) {
    final context = io.SecurityContext()
      ..useCertificateChain(ssl.certificate)
      ..usePrivateKey(ssl.privateKey, password: ssl.privateKeyPassword);
    if (ssl.trustCertificate case final trust?) {
      context.setTrustedCertificates(trust);
    }
    return context;
  }

  static bool _isAddressInUse(io.SocketException error) {
    final code = error.osError?.errorCode;
    // EADDRINUSE: macOS 48, Linux 98, Windows WSAEADDRINUSE 10048.
    final message = error.toString().toLowerCase();
    return code == 48 ||
        code == 98 ||
        code == 10048 ||
        message.contains('address already in use') ||
        // The port is bound by this process already.
        message.contains('shared flag');
  }
}

/// One request in progress and its response, tracked so that a stop can
/// wait for it or end it.
final class _Exchange {
  _Exchange(this.server, this.ioRequest)
    : response = _IoResponse(
        ioRequest.response,
        server.settings,
        acceptsGzip: _acceptsGzip(ioRequest.headers),
      ) {
    response
      ..beforeCommit = _beforeCommit
      ..beforeClose = swallowRest
      ..failed = () => _request?.attributes[responseFailedAttribute] != null;
  }

  // `Accept-Encoding` lists gzip with a quality above 0.
  static bool _acceptsGzip(io.HttpHeaders headers) {
    for (final value
        in headers[io.HttpHeaders.acceptEncodingHeader] ?? const <String>[]) {
      for (final item in value.split(',')) {
        final parts = item.split(';');
        if (parts.first.trim().toLowerCase() != 'gzip') {
          continue;
        }
        final quality = parts
            .skip(1)
            .map((p) => p.trim().toLowerCase())
            .where((p) => p.startsWith('q='))
            .map((p) => double.tryParse(p.substring(2)) ?? 1)
            .firstOrNull;
        return quality == null || quality > 0;
      }
    }
    return false;
  }

  final IoWebServer server;
  final io.HttpRequest ioRequest;
  final _IoResponse response;
  _IoRequest? _request;
  final _finished = Completer<void>();
  bool upgraded = false;

  // The subscription to dart:io's request body, once someone listened
  // (or the body was held back unread).
  StreamSubscription<Uint8List>? _upstream;
  // Whether the rest of the body was given up (its reader stopped early,
  // or nobody read a large one), and whether it reached its end.
  var _abandoned = false;
  var _bodyDone = false;

  // Tomcat's server.tomcat.max-swallow-size: of a body nobody read, at
  // most this much is read and dropped after the answer ([swallowRest]),
  // so the connection can serve the next request; a larger one closes
  // the connection.
  static const int _maxSwallowSize = 2 * 1024 * 1024;

  /// The request body for [_IoRequest.body]. Its readers may stop early
  /// (a size limit, a multipart error): then dart:io's body subscription
  /// is paused, not cancelled, because a cancelled body makes dart:io drop
  /// the connection before the answer (a 413) is sent. The connection
  /// closes after the response instead, with the rest unread.
  ///
  /// While it is read, a body that sends nothing for
  /// `server.connection-timeout` ends with a 408 `ResponseStatusException`
  /// (the time a reader pauses it does not count).
  Stream<Uint8List> takeBody() {
    final controller = StreamController<Uint8List>(sync: true);
    final timeout = server.settings.effectiveConnectionTimeout;
    Timer? idle;
    void disarm() {
      idle?.cancel();
      idle = null;
    }

    void arm() {
      disarm();
      if (timeout == null || _bodyDone) {
        return;
      }
      idle = Timer(timeout, () {
        if (_bodyDone || controller.isClosed) {
          return;
        }
        _abandoned = true;
        _upstream?.pause();
        controller.addError(
          ResponseStatusException(
            HttpStatus.requestTimeout,
            'The request body did not arrive in time',
          ),
        );
        unawaited(controller.close());
      });
    }

    void data(Uint8List chunk) {
      if (controller.isClosed) {
        return; // timed out: the rest is not wanted
      }
      arm();
      controller.add(chunk);
    }

    void done() {
      _bodyDone = true;
      disarm();
      unawaited(controller.close());
    }

    void error(Object error, StackTrace stackTrace) {
      if (!controller.isClosed) {
        controller.addError(error, stackTrace);
      }
    }

    controller
      ..onListen = () {
        final held = _upstream;
        if (held != null) {
          _abandoned = false;
          held
            ..onData(data)
            ..onError(error)
            ..onDone(done)
            ..resume();
        } else {
          _upstream = ioRequest.listen(data, onError: error, onDone: done);
        }
        arm();
      }
      ..onPause = () {
        disarm();
        _upstream?.pause();
      }
      ..onResume = () {
        if (controller.isClosed) {
          return;
        }
        arm();
        _upstream?.resume();
      }
      ..onCancel = () {
        disarm();
        if (!_bodyDone) {
          _abandoned = true;
          _upstream?.pause();
        }
      };
    return controller.stream;
  }

  // Before the response goes out: dart:io reads a body nobody listened to
  // to its end before it sends the headers, so a 413 or 415 to a large
  // upload would wait for all of it, and a body that stalls would hold
  // the answer forever. An unread body is held back instead, and
  // [swallowRest] reads what it can of it after the answer.
  void _beforeCommit() {
    if (_upstream != null || upgraded) {
      return;
    }
    final length = ioRequest.contentLength;
    if (length > 0 ||
        (length < 0 && ioRequest.headers.chunkedTransferEncoding)) {
      _abandoned = true;
      _upstream = ioRequest.listen(null, onError: (Object _) {})..pause();
    }
  }

  /// When the rest of the body was given up, or never read: sends the
  /// response so far, then reads and drops up to 2 MB more, as Tomcat
  /// swallows it, so the client, still sending, reads the answer instead
  /// of a connection reset, and a connection whose body ends in time can
  /// serve the next request. A body still going after that, or after 5
  /// seconds in all, is left; the connection then closes after the
  /// response.
  Future<void> swallowRest() async {
    final upstream = _upstream;
    if (!_abandoned || _bodyDone || upstream == null || upgraded) {
      return;
    }
    try {
      await response.flush();
    } on Object {
      return; // the client went away
    }
    var swallowed = 0;
    final enough = Completer<void>();
    void stop() {
      if (!enough.isCompleted) {
        enough.complete();
      }
    }

    upstream
      ..onData((chunk) {
        swallowed += chunk.length;
        if (swallowed > _maxSwallowSize) {
          upstream.pause();
          stop();
        }
      })
      ..onError((Object _) => stop())
      ..onDone(() {
        _bodyDone = true;
        stop();
      })
      ..resume();
    await enough.future.timeout(const Duration(seconds: 5), onTimeout: () {});
  }

  /// Lets go of the body once the response is out.
  void releaseBody() {
    final upstream = _upstream;
    if (upstream != null && !_bodyDone) {
      upstream.cancel().ignore();
    }
  }

  Future<void> get finished => _finished.future;

  bool get isStreaming => response.isStreaming;

  void finish() {
    if (!_finished.isCompleted) {
      _finished.complete();
    }
  }

  Future<void> abort() async {
    try {
      await response.close();
    } on Object {
      // The client may be gone already.
    }
  }

  ServerHttpRequest request(HttpMethod method) =>
      _request = _IoRequest(this, method);
}

final class _IoRequest implements ServerHttpRequest {
  _IoRequest(this._exchange, this.method)
    : headers = HttpHeaders.readOnly(_headers(_exchange.ioRequest.headers));

  final _Exchange _exchange;

  io.HttpRequest get _io => _exchange.ioRequest;

  @override
  final HttpMethod method;

  @override
  final HttpHeaders headers;

  @override
  late final Uri uri = () {
    final secure = _exchange.server.settings.ssl != null;
    final host = headers[HttpHeaders.hostHeader];
    final base = Uri.parse(
      '${secure ? 'https' : 'http'}://'
      // The interpolation cannot be wrapped (dart format keeps it).
      // ignore: lines_longer_than_80_chars
      '${host == null || host.isEmpty ? 'localhost:${_exchange.server.port}' : host}',
    );
    return base.replace(
      path: path,
      query: _io.uri.hasQuery ? _io.uri.query : null,
    );
  }();

  /// The path of the request target. Dart reads a target starting with
  /// `//` (`//admin/api`, a path with an empty first segment in HTTP) as
  /// a host and a path; the full path is put back together, so the router
  /// and the security rules never take `/api` for it.
  @override
  late final String path = _io.uri.hasAuthority && !_io.uri.hasScheme
      ? '//${_io.uri.authority}${_io.uri.path}'
      : _io.uri.path;

  @override
  late final Map<String, List<String>> queryParameters = Map.unmodifiable(
    _io.uri.queryParametersAll,
  );

  @override
  late final Map<String, String> cookies = Map.unmodifiable(
    parseCookieHeader(headers.getAll(HttpHeaders.cookieHeader)),
  );

  @override
  String? get remoteAddress => _io.connectionInfo?.remoteAddress.address;

  @override
  bool get isSecure => _exchange.server.settings.ssl != null;

  @override
  final Map<String, Object?> attributes = {};

  @override
  Principal? principal;

  var _bodyRead = false;

  @override
  Stream<Uint8List> get body {
    if (_bodyRead) {
      throw StateError('The request body was read already');
    }
    _bodyRead = true;
    final source = _exchange.takeBody();
    // The server's limit for every body, whatever its type; the multipart
    // resolver reads uploads with its own (maxRequestBodySizeAttribute).
    final limit = switch (attributes[maxRequestBodySizeAttribute]) {
      final int own => own,
      _ => _exchange.server.settings.maxRequestBodySize,
    };
    if (limit < 0) {
      return source;
    }
    if (_io.contentLength > limit) {
      return Stream.error(PayloadTooLargeException(limit));
    }
    var read = 0;
    return source.transform(
      StreamTransformer<Uint8List, Uint8List>.fromHandlers(
        handleData: (chunk, sink) {
          read += chunk.length;
          if (read > limit) {
            sink
              ..addError(PayloadTooLargeException(limit))
              ..close();
          } else {
            sink.add(chunk);
          }
        },
      ),
    );
  }

  @override
  bool get isWebSocketUpgrade => asksForWebSocket(_io);

  /// Throws a [StateError] when the request does not ask for a WebSocket,
  /// and an [ErrorResponseException] (400, or 426 for another version)
  /// when its `Sec-WebSocket-Key` or `Sec-WebSocket-Version` is not valid.
  @override
  Future<WebSocketSession> upgradeToWebSocket({String? protocol}) async {
    if (!isWebSocketUpgrade) {
      throw StateError('Not a WebSocket handshake');
    }
    checkWebSocketHandshake(_io);
    _exchange.upgraded = true;
    final settings = _exchange.server.settings;
    final session = await upgradeWebSocket(
      _io,
      uri.replace(scheme: isSecure ? 'wss' : 'ws'),
      protocol: protocol,
      maxText: settings.webSocketMaxTextMessageSize,
      maxBinary: settings.webSocketMaxBinaryMessageSize,
      sendBufferSizeLimit: settings.webSocketSendBufferSizeLimit,
      sendTimeLimit: settings.webSocketSendTimeLimit,
    );
    final sessions = _exchange.server._sessions..add(session);
    unawaited(session.done.whenComplete(() => sessions.remove(session)));
    return session;
  }

  static HttpHeaders _headers(io.HttpHeaders source) {
    final headers = HttpHeaders();
    source.forEach((name, values) {
      for (final value in values) {
        headers.add(name, value);
      }
    });
    return headers;
  }
}

final class _IoResponse implements ServerHttpResponse {
  _IoResponse(this._io, this._settings, {required this.acceptsGzip});

  final io.HttpResponse _io;
  final ServerProperties _settings;

  /// Whether the client's `Accept-Encoding` takes gzip.
  final bool acceptsGzip;

  @override
  int statusCode = 200;

  @override
  final HttpHeaders headers = HttpHeaders();

  final _cookies = <ResponseCookie>[];

  @override
  bool isCommitted = false;

  var _closed = false;

  // The gzip encoder when the response is compressed.
  io.RawZLibFilter? _gzip;

  // Whether the status, once committed, allows no body: 1xx, 204, 304.
  var _bodiless = false;

  // How much of a body is handed to dart:io at a time when the client
  // is watched ([_watched]): the client has `server.connection-timeout`
  // for each slice, so 64 KB in a minute is the slowest download that
  // is still served.
  static const int _sliceSize = 64 * 1024;

  // What dart:io has taken since it last said that everything was with
  // the socket: at most a slice, so a small answer goes out as before,
  // without a flush of its own, and [close] has one slice to wait for.
  var _handed = 0;

  // The rest of a body larger than that, and what is written while
  // dart:io is busy: sent in slices by [flush], [addStream] and [close].
  // dart:io itself would take it all at once and then never tell how
  // much of it the client took.
  final _queue = Queue<List<int>>();

  // Set while a flush, a stream or the queue is on its way to the
  // socket: dart:io takes nothing else meanwhile.
  Completer<void>? _busy;

  // Whether the connection was dropped because the client stopped
  // reading ([_drop]); [_gone] completes then, for whoever waits for
  // dart:io, which may never answer for a connection it destroyed.
  var _dropped = false;
  final _gone = Completer<void>();

  Duration? get _timeout => _settings.effectiveConnectionTimeout;

  /// Called once, just before the status and headers go out.
  void Function()? beforeCommit;

  /// Called once, when everything is written but before the response is
  /// finished.
  Future<void> Function()? beforeClose;

  /// Whether the request failed after the response was committed
  /// ([responseFailedAttribute]): then [close] drops the connection.
  bool Function()? failed;

  /// Whether the response is an event stream or NDJSON, which never ends
  /// by itself: a stop closes it instead of waiting for it.
  bool get isStreaming {
    final type = (headers.contentType ?? '').toLowerCase();
    return type.startsWith(MediaType.textEventStream) ||
        type.startsWith(MediaType.applicationNdjson);
  }

  @override
  void addCookie(ResponseCookie cookie) => _cookies.add(cookie);

  /// Sends [status] with a problem body ([detail] when given) and closes;
  /// for the answers the server gives before the handler.
  Future<void> problem(int status, String? detail) {
    final problem = detail == null
        ? ProblemDetail.forStatus(status)
        : ProblemDetail.forStatusAndDetail(status, detail);
    final bytes = utf8.encode(jsonEncode(problem.toJson()));
    statusCode = status;
    headers
      ..contentType = MediaType.applicationProblemJson
      ..contentLength = bytes.length;
    add(bytes);
    return close();
  }

  // A header dart:io cannot send fails here, before anything is sent: the
  // header is dropped, so the error answer that follows can be written.
  void _checkHeaders() {
    for (final name in headers.names.toList()) {
      if (!_isToken(name)) {
        headers.remove(name);
        throw FormatException('Invalid response header name "$name"');
      }
      for (final value in headers.getAll(name)) {
        if (!_isFieldValue(value)) {
          headers.remove(name);
          // The value is not shown: it may be a secret.
          throw FormatException(
            'Invalid value of the response header "$name": only visible '
            'US-ASCII characters, spaces and tabs can be sent',
          );
        }
      }
    }
    for (final cookie in _cookies.toList()) {
      if (!_isFieldValue(cookie.toString())) {
        _cookies.remove(cookie);
        throw FormatException('Invalid cookie "${cookie.name}"');
      }
    }
  }

  static bool _isToken(String name) =>
      name.isNotEmpty &&
      name.codeUnits.every(
        (c) =>
            c > 0x20 && c < 0x7F && !r'"(),/:;<=>?@[\]{}'.codeUnits.contains(c),
      );

  // dart:io's rule for header values.
  static bool _isFieldValue(String value) =>
      value.codeUnits.every((c) => (c >= 0x20 && c < 0x7F) || c == 0x09);

  void _commit() {
    if (isCommitted) {
      return;
    }
    _checkHeaders();
    isCommitted = true;
    beforeCommit?.call();
    final compressible = _compressible();
    final compress = compressible && acceptsGzip;
    _io.statusCode = statusCode;
    _bodiless =
        statusCode < 200 ||
        statusCode == HttpStatus.noContent ||
        statusCode == HttpStatus.notModified;
    final target = _io.headers;
    if (_bodiless) {
      // Neither Content-Length nor Transfer-Encoding: chunked (dart:io's
      // default for HTTP/1.1); [close] keeps dart:io from adding its
      // Content-Length: 0.
      target.chunkedTransferEncoding = false;
    }
    // A 304 or 1xx carries no Content-Type either, as with Tomcat (only an
    // answer with a body, or a 204, has one): RFC 9110 §15.4.5.
    final typed = !_bodiless || statusCode == HttpStatus.noContent;
    headers.forEach((name, values) {
      if (!typed && name.toLowerCase() == 'content-type') {
        return;
      }
      if (name.toLowerCase() == 'content-length') {
        if (!_bodiless) {
          target.contentLength = compress
              ? -1
              : int.tryParse(values.first) ?? -1;
        }
        return;
      }
      target.removeAll(name);
      for (final value in values) {
        target.add(name, value, preserveHeaderCase: true);
      }
    });
    for (final cookie in _cookies) {
      target.add(HttpHeaders.setCookieHeader, cookie.toString());
    }
    if (compressible) {
      // Whether or not this client takes gzip, the answer depends on
      // Accept-Encoding, as Tomcat says: added once, and a `*` among the
      // names becomes the whole Vary.
      final vary = {
        for (final value in target[HttpHeaders.varyHeader] ?? const <String>[])
          for (final name in value.split(',')) name.trim().toLowerCase(),
      };
      if (vary.contains('*')) {
        target.set(HttpHeaders.varyHeader, '*');
      } else if (!vary.contains('accept-encoding')) {
        target.add(HttpHeaders.varyHeader, 'Accept-Encoding');
      }
    }
    if (compress) {
      target.set(HttpHeaders.contentEncodingHeader, 'gzip');
      _gzip = io.RawZLibFilter.deflateFilter(gzip: true);
    }
    if (isStreaming) {
      _io.bufferOutput = false;
    }
  }

  // Whether the answer would be compressed for a client that takes gzip,
  // by Spring Boot's (Tomcat's) rules: compression on, a body (not 1xx,
  // 204, 205, 304), not partial content, no encoding yet, no strong ETag
  // (it promises these very bytes), a media type of
  // server.compression.mime-types, at least min-response-size bytes (or
  // a length not known yet).
  bool _compressible() {
    if (!_settings.compression) {
      return false;
    }
    if (statusCode < 200 ||
        statusCode == HttpStatus.noContent ||
        statusCode == HttpStatus.resetContent ||
        statusCode == HttpStatus.partialContent ||
        statusCode == HttpStatus.notModified ||
        headers.contains(HttpHeaders.contentEncodingHeader) ||
        headers.contains(HttpHeaders.contentRangeHeader)) {
      return false;
    }
    final eTag = headers.eTag;
    if (eTag != null && !eTag.trim().startsWith('W/')) {
      return false;
    }
    final type = headers.contentType?.split(';').first.trim().toLowerCase();
    if (type == null ||
        !_settings.compressionMimeTypes.any((m) => _typeMatches(m, type))) {
      return false;
    }
    final length = int.tryParse(
      headers[HttpHeaders.contentLengthHeader] ?? '',
    );
    return length == null || length >= _settings.compressionMinResponseSize;
  }

  static bool _typeMatches(String pattern, String type) {
    final wanted = pattern.split(';').first.trim().toLowerCase();
    return wanted == type ||
        (wanted.endsWith('/*') &&
            type.startsWith(wanted.substring(0, wanted.length - 1)));
  }

  // The compressed bytes of [bytes] so far; with [flush], everything
  // written up to now (a sync flush), with [end] the gzip trailer.
  List<int> _compressed(
    List<int> bytes, {
    bool flush = false,
    bool end = false,
  }) {
    final gzip = _gzip!;
    if (bytes.isNotEmpty) {
      gzip.process(bytes, 0, bytes.length);
    }
    final out = BytesBuilder(copy: false);
    for (
      var chunk = gzip.processed(flush: flush || end, end: end);
      chunk != null;
      chunk = gzip.processed(flush: flush || end, end: end)
    ) {
      out.add(chunk);
    }
    return out.takeBytes();
  }

  void _send(List<int> bytes) {
    if (_bodiless) {
      return;
    }
    if (_gzip == null) {
      _out(bytes);
    } else {
      final out = _compressed(bytes);
      if (out.isNotEmpty) {
        _out(out);
      }
    }
  }

  // The bytes as they go on the wire: to dart:io at once while they fit
  // in a slice (the usual answer), else to the queue.
  void _out(List<int> bytes) {
    if (_dropped) {
      return;
    }
    if (_busy == null &&
        _queue.isEmpty &&
        _handed + bytes.length <= _sliceSize) {
      _handed += bytes.length;
      _io.add(bytes);
    } else {
      _queue.add(bytes);
    }
  }

  @override
  void add(List<int> bytes) {
    _commit();
    _send(bytes);
  }

  @override
  void write(String text) => add(utf8.encode(text));

  @override
  Future<void> flush() {
    _commit();
    if (_gzip != null) {
      final out = _compressed(const [], flush: true);
      if (out.isNotEmpty) {
        _out(out);
      }
    }
    return _exclusive(() async {
      // Nothing is awaited before dart:io is asked when there is no
      // queue, as for every small answer: a turn later it may never
      // complete the flush of a connection whose client just went away.
      if (_queue.isNotEmpty) {
        await _sendQueued();
      }
      if (!_dropped) {
        await _within(_io.flush());
        _handed = 0;
      }
    });
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    _commit();
    if (_bodiless) {
      return stream.drain<void>();
    }
    // After a drop there is no encoder, and nobody to send to.
    List<int> encoded(List<int> chunk) =>
        _gzip == null ? const [] : _compressed(chunk);
    final source = _gzip == null
        ? stream
        : stream.map(encoded).where((chunk) => chunk.isNotEmpty);
    return _exclusive(() async {
      if (_queue.isNotEmpty) {
        await _sendQueued();
      }
      if (!_dropped && _handed > 0) {
        await _within(_io.flush());
        _handed = 0;
      }
      await _pipe(source);
    });
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return await done;
    }
    if (isCommitted && (failed?.call() ?? false)) {
      return await abort();
    }
    _closed = true;
    _commit();
    if (_gzip != null) {
      _out(_compressed(const [], end: true));
      _gzip = null;
    }
    await beforeClose?.call();
    if (_busy != null || _queue.isNotEmpty) {
      await _exclusive(_sendQueued);
    }
    if (_dropped) {
      return;
    }
    if (_bodiless) {
      // dart:io adds Content-Length: 0 to an answer whose headers are
      // still unwritten at close (except to a HEAD request); an empty
      // stream writes them first.
      await _io.addStream(const Stream<List<int>>.empty());
    }
    await _within(_io.close());
  }

  @override
  Future<void> get done =>
      _unlessDropped(_io.done.then((_) {}, onError: (_) {}));

  /// Drops the connection without finishing the response: no final chunk
  /// (nor gzip trailer), so the client sees that the response broke off.
  /// For an error after the response was committed, as Tomcat does.
  Future<void> abort() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _gzip = null;
    _queue.clear();
    if (_busy != null) {
      // dart:io is in the middle of a stream or a flush and takes
      // neither an error nor a close: the connection goes directly.
      _destroy();
      return;
    }
    try {
      // An error added to dart:io's response destroys the connection.
      _io.addError(const _Aborted());
    } on StateError {
      // A stream is being added: its own failure ends the connection.
    }
    await _io.close().then((_) {}, onError: (Object _) {});
  }

  // One sender at a time: dart:io refuses a write, a flush or a stream
  // while another flush or stream is under way. What is written meanwhile
  // waits in the queue.
  Future<void> _exclusive(Future<void> Function() send) async {
    for (var busy = _busy; busy != null; busy = _busy) {
      await busy.future;
    }
    final mine = _busy = Completer<void>();
    try {
      await send();
    } finally {
      _busy = null;
      mine.complete();
    }
  }

  // Sends the queue, after what dart:io took before it.
  Future<void> _sendQueued() async {
    if (_queue.isEmpty || _dropped) {
      return;
    }
    if (_handed > 0) {
      await _within(_io.flush());
      _handed = 0;
    }
    await _pipe(Stream.fromIterable(_queued()));
  }

  // The queue, emptied as it is read: a chunk is let go once dart:io has
  // it, and what is written meanwhile follows.
  Iterable<List<int>> _queued() sync* {
    while (_queue.isNotEmpty) {
      yield _queue.removeFirst();
    }
  }

  // Hands [source] to dart:io, watched.
  Future<void> _pipe(Stream<List<int>> source) {
    if (_dropped) {
      source.listen(null).cancel().ignore();
      return Future.value();
    }
    return _unlessDropped(_io.addStream(_watched(source)));
  }

  /// [source] in slices of at most [_sliceSize], with the client watched:
  /// `dart:io` pauses the stream while a slice waits for room in the
  /// socket, that is, for the client to read. A pause longer than
  /// `server.connection-timeout` means a client that takes nothing, and
  /// the connection is dropped. Only that time counts: neither how long
  /// the whole body takes, nor how long [source] is quiet between two
  /// chunks (an event stream).
  Stream<List<int>> _watched(Stream<List<int>> source) {
    final timeout = _timeout;
    late final StreamSubscription<List<int>> upstream;
    late final StreamController<List<int>> controller;
    // The chunk being sliced and how far it went.
    List<int>? chunk;
    var offset = 0;
    var held = false;
    var pumping = false;
    Timer? stall;

    // The source waits while its last chunk is not all taken.
    void hold() {
      final wanted = chunk != null || controller.isPaused;
      if (wanted && !held) {
        held = true;
        upstream.pause();
      } else if (!wanted && held) {
        held = false;
        upstream.resume();
      }
    }

    void pump() {
      if (pumping) {
        return;
      }
      pumping = true;
      while (!controller.isPaused && !controller.isClosed) {
        final bytes = chunk;
        if (bytes == null) {
          break;
        }
        final end = offset + _sliceSize < bytes.length
            ? offset + _sliceSize
            : bytes.length;
        final List<int> slice;
        if (offset == 0 && end == bytes.length) {
          slice = bytes;
        } else if (bytes is Uint8List) {
          slice = Uint8List.sublistView(bytes, offset, end);
        } else {
          slice = bytes.sublist(offset, end);
        }
        if (end == bytes.length) {
          chunk = null;
        }
        offset = end;
        controller.add(slice);
      }
      pumping = false;
      hold();
    }

    controller = StreamController<List<int>>(
      sync: true,
      onListen: () {
        upstream = source.listen(
          (bytes) {
            chunk = bytes;
            offset = 0;
            pump();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!controller.isClosed) {
              controller.addError(error, stackTrace);
            }
          },
          onDone: () {
            if (!controller.isClosed) {
              unawaited(controller.close());
            }
          },
        );
      },
      onPause: () {
        hold();
        if (timeout != null) {
          stall ??= Timer(timeout, () {
            chunk = null;
            upstream.cancel().ignore();
            _drop();
          });
        }
      },
      onResume: () {
        stall?.cancel();
        stall = null;
        // Not from within the resume: dart:io's own subscription is
        // still in its callback then and would keep every slice added
        // now as a pending event, all of them at once, with no pause to
        // tell that the client took none.
        scheduleMicrotask(pump);
      },
      onCancel: () {
        stall?.cancel();
        stall = null;
        chunk = null;
        return upstream.cancel();
      },
    );
    return controller.stream;
  }

  // [sending] (a flush or the close of at most a slice), given up when
  // the client does not take it in `server.connection-timeout`.
  Future<void> _within(Future<void> sending) {
    final timeout = _timeout;
    if (timeout == null) {
      return sending;
    }
    final result = Completer<void>();
    final stall = Timer(timeout, () {
      _drop();
      if (!result.isCompleted) {
        result.complete();
      }
    });
    unawaited(
      sending.then(
        (_) {
          stall.cancel();
          if (!result.isCompleted) {
            result.complete();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          stall.cancel();
          if (!result.isCompleted) {
            result.completeError(error, stackTrace);
          }
        },
      ),
    );
    return result.future;
  }

  // [sending], or nothing more once the connection was dropped: dart:io
  // may never complete what it was doing for a connection it destroyed.
  Future<void> _unlessDropped(Future<void> sending) =>
      _dropped ? Future.value() : Future.any([sending, _gone.future]);

  // The client took nothing for `server.connection-timeout`: the
  // connection goes, and with it the rest of the response. Whoever
  // writes afterwards writes to nobody, as to a client that went away
  // (dart:io reports no error then either); [done] completes.
  void _drop() {
    if (_dropped) {
      return;
    }
    _log.debug(
      'A response was given up: its client read nothing of it for '
      '${_timeout?.inMilliseconds} ms (server.connection-timeout)',
    );
    _destroy();
  }

  void _destroy() {
    _dropped = true;
    _closed = true;
    _gzip = null;
    _queue.clear();
    // The one way dart:io gives to destroy the connection of a response
    // whose headers are out: a deadline that is over.
    _io.deadline = Duration.zero;
    if (!_gone.isCompleted) {
      _gone.complete();
    }
  }
}

/// The error that makes `dart:io` drop a response's connection.
final class _Aborted implements Exception {
  const _Aborted();

  @override
  String toString() => 'The response was aborted after an error';
}

/// The listening socket of a server, which can stop accepting without
/// closing: dart:io's `HttpServer.close()` ends every idle connection with
/// the socket, and a keep-alive connection is idle until its next request
/// is read. [refuse] ends the accepting only; the stream never ends by
/// itself, since the HTTP server stops delivering requests when it does.
final class _Accepting extends Stream<io.Socket> implements io.ServerSocket {
  _Accepting(this._socket);

  final io.ServerSocket _socket;
  late final StreamController<io.Socket> _sockets = StreamController(
    onListen: () => _accepted = _socket.listen(
      _sockets.add,
      onError: _sockets.addError,
    ),
    onPause: () => _accepted?.pause(),
    onResume: () => _accepted?.resume(),
    onCancel: refuse,
  );
  StreamSubscription<io.Socket>? _accepted;
  Future<void>? _refused;

  @override
  int get port => _socket.port;

  @override
  io.InternetAddress get address => _socket.address;

  /// Accepts no connection more; those accepted go on.
  Future<void> refuse() => _refused ??= () async {
    await _accepted?.cancel();
    await _socket.close();
  }();

  @override
  Future<io.ServerSocket> close() async {
    await refuse();
    if (!_sockets.isClosed) {
      unawaited(_sockets.close());
    }
    return this;
  }

  @override
  StreamSubscription<io.Socket> listen(
    void Function(io.Socket socket)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _sockets.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}
