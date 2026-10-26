import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/web_server.dart';
import 'package:spring_web_dart/io.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.web.server');

/// The default [WebServerFactory]: `dart:io`'s `HttpServer`, on the VM and
/// in Flutter apps on mobile and desktop. Spring Boot's
/// `TomcatServletWebServerFactory` in its place.
final class IoWebServerFactory implements ConfigurableWebServerFactory {
  /// A factory with [settings] (`server.*`).
  IoWebServerFactory([this.settings = const ServerProperties()]);

  @override
  ServerProperties settings;

  @override
  WebServer getWebServer(HttpHandler handler) => IoWebServer(handler, settings);
}

/// A [WebServer] on `dart:io`'s `HttpServer`.
final class IoWebServer implements WebServer {
  /// A server handing requests to [handler], with [settings].
  IoWebServer(this.handler, this.settings);

  /// Answers the requests.
  final HttpHandler handler;

  /// The `server.*` settings.
  final ServerProperties settings;

  io.HttpServer? _server;
  final _exchanges = <_Exchange>{};
  final _sockets = <io.WebSocket>{};

  @override
  int get port => _server?.port ?? -1;

  @override
  Future<void> start() => _starting ??= _bind();

  // The bind in progress: a stop() waits for it, so a server stopped while
  // its socket was still opening does not keep listening.
  Future<void>? _starting;

  Future<void> _bind() async {
    final address = await _address(settings.address);
    final ssl = settings.ssl;
    try {
      _server = ssl == null
          ? await io.HttpServer.bind(address, settings.port)
          : await io.HttpServer.bindSecure(
              address,
              settings.port,
              _securityContext(ssl),
              requestClientCertificate: ssl.clientAuth != ClientAuth.none,
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
    final server = _server!
      ..autoCompress = settings.compression
      ..serverHeader = null;
    // dart:io's defaults: X-Frame-Options: SAMEORIGIN and
    // X-Content-Type-Options: nosniff stay (Spring Boot without Spring
    // Security sends neither; the security starter will own these headers);
    // X-XSS-Protection is obsolete.
    server.defaultResponseHeaders.removeAll('x-xss-protection');
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
    // No new connections; open event streams and WebSockets end now
    // (they would never finish by themselves).
    final closing = server.close();
    for (final socket in _sockets.toList()) {
      unawaited(socket.close(io.WebSocketStatus.goingAway, 'Server stopping'));
    }
    for (final exchange in _exchanges.toList()) {
      if (exchange.isStreaming) {
        unawaited(exchange.abort());
      }
    }
    if (settings.shutdown == Shutdown.graceful) {
      final limit = timeout ?? const Duration(seconds: 30);
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

  Future<void> _serve(io.HttpRequest ioRequest) async {
    final exchange = _Exchange(this, ioRequest);
    _exchanges.add(exchange);
    try {
      final method = _method(ioRequest.method);
      if (method == null) {
        await exchange.response.send(
          501,
          'Unsupported method ${ioRequest.method}',
        );
        return;
      }
      if (settings.ssl?.clientAuth == ClientAuth.need &&
          ioRequest.certificate == null) {
        await exchange.response.send(403, 'A client certificate is required');
        return;
      }
      await handler.handle(exchange.request(method), exchange.response);
    } catch (error, stackTrace) {
      _log.error(
        'Request ${ioRequest.method} ${ioRequest.uri} failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!exchange.response.isCommitted && !exchange.upgraded) {
        await exchange.response.send(500, 'Internal Server Error');
      }
    } finally {
      if (!exchange.upgraded) {
        await exchange.response.close().catchError((_) {});
      }
      _exchanges.remove(exchange);
      exchange.finish();
    }
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

/// One request and its response.
final class _Exchange {
  _Exchange(this.server, this.ioRequest)
    : response = _IoResponse(ioRequest.response);

  final IoWebServer server;
  final io.HttpRequest ioRequest;
  final _IoResponse response;
  final _finished = Completer<void>();
  var upgraded = false;

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

  ServerHttpRequest request(HttpMethod method) => _IoRequest(this, method);
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
      '${host == null || host.isEmpty ? 'localhost:${_exchange.server.port}' : host}',
    );
    return base.replace(
      path: _io.uri.path,
      query: _io.uri.hasQuery ? _io.uri.query : null,
    );
  }();

  @override
  String get path => _io.uri.path;

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
    final limit = _exchange.server.settings.maxRequestBodySize;
    // Uploads have their own limits (spring.servlet.multipart.*).
    final multipart = (headers.contentType ?? '').toLowerCase().startsWith(
      'multipart/',
    );
    if (limit < 0 || multipart) {
      return _io;
    }
    if (_io.contentLength > limit) {
      return Stream.error(PayloadTooLargeException(limit));
    }
    var read = 0;
    return _io.transform(
      StreamTransformer<Uint8List, Uint8List>.fromHandlers(
        handleData: (chunk, sink) {
          read += chunk.length;
          if (read > limit) {
            sink.addError(PayloadTooLargeException(limit));
            sink.close();
          } else {
            sink.add(chunk);
          }
        },
      ),
    );
  }

  @override
  bool get isWebSocketUpgrade => io.WebSocketTransformer.isUpgradeRequest(_io);

  @override
  Future<WebSocketSession> upgradeToWebSocket({String? protocol}) async {
    if (!isWebSocketUpgrade) {
      throw StateError('Not a WebSocket handshake');
    }
    _exchange.upgraded = true;
    final socket = await io.WebSocketTransformer.upgrade(
      _io,
      protocolSelector: protocol == null ? null : (_) => protocol,
    );
    final sockets = _exchange.server._sockets..add(socket);
    unawaited(socket.done.whenComplete(() => sockets.remove(socket)));
    final wsUri = uri.replace(scheme: isSecure ? 'wss' : 'ws');
    return IoWebSocketSession(socket, wsUri);
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
  _IoResponse(this._io);

  final io.HttpResponse _io;

  @override
  int statusCode = 200;

  @override
  final HttpHeaders headers = HttpHeaders();

  final _cookies = <ResponseCookie>[];

  @override
  bool isCommitted = false;

  var _closed = false;

  /// An event stream or NDJSON: closed at shutdown instead of awaited.
  bool get isStreaming {
    final type = (headers.contentType ?? '').toLowerCase();
    return type.startsWith(MediaType.textEventStream) ||
        type.startsWith(MediaType.applicationNdjson);
  }

  @override
  void addCookie(ResponseCookie cookie) => _cookies.add(cookie);

  void _commit() {
    if (isCommitted) {
      return;
    }
    isCommitted = true;
    _io.statusCode = statusCode;
    final target = _io.headers;
    headers.forEach((name, values) {
      if (name.toLowerCase() == 'content-length') {
        target.contentLength = int.tryParse(values.first) ?? -1;
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
    if (isStreaming) {
      _io.bufferOutput = false;
    }
  }

  @override
  void add(List<int> bytes) {
    _commit();
    _io.add(bytes);
  }

  @override
  void write(String text) => add(utf8.encode(text));

  @override
  Future<void> flush() {
    _commit();
    return _io.flush();
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    _commit();
    return _io.addStream(stream);
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return _io.done.then((_) {}, onError: (_) {});
    }
    _closed = true;
    _commit();
    await _io.close();
  }

  @override
  Future<void> get done => _io.done.then((_) {}, onError: (_) {});
}
