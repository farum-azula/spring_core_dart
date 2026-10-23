import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_client_config.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_handshake.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// Manages the one connection (a `WebSocketSession`) of a
/// `@WebSocketClient`, shared by its streams and sends: opened on demand,
/// handed to every listener, opened again after a loss while someone
/// listens (see [WebSocketReconnectPolicy]). Created by
/// `WebSocketInvocationHandler`.
///
/// Spring (Java): `WebSocketConnectionManager`, which connects a
/// `WebSocketHandler` through a `WebSocketClient` (without reconnecting).
final class WebSocketConnectionManager {
  /// A manager of client [clientName]'s connection to [url].
  WebSocketConnectionManager({
    required this.clientName,
    required this.url,
    required this.config,
    required this.transport,
    required this._log,
    this.protocols = const [],
    this.interceptors = const [],
  });

  /// Close codes after which the connection is opened again: none, going
  /// away, no status, lost, and the server's temporary failures.
  static final retryableCloseCodes = {
    null,
    CloseStatus.goingAway.code,
    CloseStatus.noStatusCode.code,
    CloseStatus.noCloseFrame.code,
    CloseStatus.serverError.code,
    CloseStatus.serviceRestarted.code,
    CloseStatus.serviceOverload.code,
    1014, // bad gateway
  };

  /// The `@WebSocketClient` name.
  final String clientName;

  /// The address (before interceptors).
  final Uri url;

  /// The offered subprotocols.
  final List<String> protocols;

  /// Timeouts, reconnection and default headers.
  final WebSocketClientConfig config;

  /// Opens the connections.
  final WebSocketTransport transport;

  /// Applied to every handshake.
  final List<WebSocketHandshakeInterceptor> interceptors;

  final SpringLog _log;
  final _listeners = <StreamController<Object>>{};
  WebSocketSession? _connection;
  StreamSubscription<Object>? _subscription;
  Completer<WebSocketSession>? _pending;
  Timer? _retry;
  // Reconnection attempts since the last connection (for the backoff and
  // max-retries).
  var _retries = 0;
  // Bumped by close(): attempts of an older generation are dropped.
  var _generation = 0;
  var _disposed = false;

  /// Whether a connection is open, like Spring's `isConnected()`.
  bool get isConnected => _connection != null;

  /// The incoming messages (`String` or `Uint8List`); listening opens the
  /// connection. Done when the connection ends for good.
  Stream<Object> messages() {
    late final StreamController<Object> controller;
    controller = StreamController<Object>(
      onListen: () {
        if (_disposed) {
          controller
            ..addError(_disposedError())
            ..close();
          return;
        }
        _listeners.add(controller);
        _ensure().ignore();
      },
      onCancel: () => _listeners.remove(controller),
    );
    return controller.stream;
  }

  /// Sends a text (`String`) or binary (`List<int>`) message, opening the
  /// connection first when needed.
  Future<void> sendMessage(Object message) async {
    final connection = await _ensure();
    connection.sendMessage(message);
  }

  /// Opens the connection now (if it is not open).
  Future<void> connect() => _ensure();

  /// Closes the connection (normal closure); listeners are done. Using the
  /// client again opens a new connection.
  Future<void> close() async {
    final connection = _connection;
    _reset(WebSocketException('closed by the client', url: url));
    for (final listener in [..._listeners]) {
      unawaited(listener.close());
    }
    _listeners.clear();
    if (connection != null) {
      _log.debug('closing $url', fields: {'client': clientName});
      await connection.close();
    }
  }

  /// Closes for good (the application stops).
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    await close();
    _disposed = true;
  }

  // Forgets the current connection and any attempt in progress.
  void _reset(Object pendingError) {
    _generation++;
    _retry?.cancel();
    _retry = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _connection = null;
    _retries = 0;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(pendingError);
    }
  }

  StateError _disposedError() => StateError(
    'The WebSocket client $clientName is closed: the application stopped',
  );

  Future<WebSocketSession> _ensure() {
    if (_disposed) {
      return Future.error(_disposedError());
    }
    final connection = _connection;
    if (connection != null) {
      return Future.value(connection);
    }
    final pending = _pending;
    if (pending != null) {
      return pending.future;
    }
    final created = _pending = Completer<WebSocketSession>();
    created.future.ignore();
    unawaited(_attempt(_generation));
    return created.future;
  }

  Future<void> _attempt(int generation) async {
    final handshake = WebSocketHandshake(
      clientName: clientName,
      url: url,
      headers: HttpHeaders(config.defaultRequestHeaders),
      protocols: protocols,
    );
    final WebSocketSession connection;
    try {
      for (final interceptor in interceptors) {
        await interceptor.apply(handshake);
      }
      connection = await transport.connect(
        handshake.url,
        headers: handshake.headers.isEmpty ? null : handshake.headers,
        protocols: handshake.protocols,
        timeout: config.connectTimeout,
      );
    } on Object catch (error, stackTrace) {
      if (generation == _generation) {
        _failed(error, stackTrace);
      }
      return;
    }
    if (generation != _generation) {
      unawaited(connection.close());
      return;
    }
    _log.debug('connected to ${handshake.url}', fields: {'client': clientName});
    _retries = 0;
    _connection = connection;
    _subscription = connection.messages.listen(
      (message) {
        for (final listener in [..._listeners]) {
          listener.add(message);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _log.debug('connection error: $error', fields: {'client': clientName});
      },
      onDone: () => _closed(connection),
    );
    final pending = _pending;
    _pending = null;
    pending?.complete(connection);
  }

  // A connection attempt failed.
  void _failed(Object error, StackTrace stackTrace) {
    _log.debug('connection failed: $error', fields: {'client': clientName});
    if (_listeners.isNotEmpty && _schedule()) {
      return;
    }
    final pending = _pending;
    _pending = null;
    _retries = 0;
    _end(error, stackTrace);
    if (pending != null && !pending.isCompleted) {
      pending.completeError(error, stackTrace);
    }
  }

  // The connection ended without close() from this side.
  void _closed(WebSocketSession connection) {
    if (_connection != connection) {
      return;
    }
    _connection = null;
    _subscription = null;
    final status = connection.closeStatus;
    final code = status?.code;
    final reason = status?.reason;
    _log.debug(
      'closed by the server ($code${reason == null || reason.isEmpty ? '' : ' $reason'})',
      fields: {'client': clientName},
    );
    if (_listeners.isNotEmpty && retryableCloseCodes.contains(code)) {
      final pending = _pending = Completer<WebSocketSession>();
      pending.future.ignore();
      if (_schedule()) {
        return;
      }
      _pending = null;
    }
    if (code == CloseStatus.normal.code) {
      _end();
    } else {
      _end(
        WebSocketException(
          'closed by the server with code $code'
          '${reason == null || reason.isEmpty ? '' : ': $reason'}',
          url: url,
        ),
      );
    }
  }

  // Schedules the next attempt, unless reconnecting is off or max-retries
  // is reached (false then).
  bool _schedule() {
    final policy = config.reconnect;
    final max = policy.maxRetries;
    if (!policy.enabled || (max != null && _retries >= max)) {
      return false;
    }
    _retries++;
    final delay = policy.delayFor(_retries);
    _log.debug(
      'reconnecting in ${delay.inMilliseconds} ms (attempt $_retries)',
      fields: {'client': clientName},
    );
    final generation = _generation;
    _retry = Timer(delay, () {
      _retry = null;
      if (generation == _generation) {
        unawaited(_attempt(generation));
      }
    });
    return true;
  }

  // Ends every listener, after [error] when given.
  void _end([Object? error, StackTrace? stackTrace]) {
    for (final listener in [..._listeners]) {
      if (error != null) {
        listener.addError(error, stackTrace);
      }
      unawaited(listener.close());
    }
    _listeners.clear();
  }
}
