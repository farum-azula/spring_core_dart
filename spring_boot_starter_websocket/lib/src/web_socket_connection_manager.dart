import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_client_config.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_handshake.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// Keeps the one connection of a `@WebSocketClient`: it opens it when
/// first needed, hands every message to all listeners, and opens it again
/// after a loss while someone listens.
///
/// Each client has one, created by its `WebSocketInvocationHandler`, and
/// the generated client calls it; applications reach it only through
/// `WebSocketInvocationHandler.connectionManager`. The open connection is
/// a `WebSocketSession` of `spring_web_dart`. How it reconnects is set by
/// the [WebSocketReconnectPolicy] of its [config]; every attempt goes
/// through the [interceptors].
///
/// Spring (Java): `WebSocketConnectionManager`, which connects a
/// `WebSocketHandler` through a `WebSocketClient` but does not reconnect.
final class WebSocketConnectionManager {
  /// A manager of the connection of client [clientName] to [url]; it
  /// does not connect until asked.
  WebSocketConnectionManager({
    required this.clientName,
    required this.url,
    required this.config,
    required this.transport,
    required this._log,
    this.protocols = const [],
    this.interceptors = const [],
  });

  /// The close codes after which the connection is opened again, as the
  /// cause may be temporary: none, going away (1001), no status (1005),
  /// lost (1006), the server's failures (1011 to 1014), and a connection
  /// this side dropped because the server took nothing of what was sent
  /// (4500, `CloseStatus.sessionNotReliable`). Any other code ends the
  /// message streams: 1000 normally, others with a `WebSocketException`.
  static final Set<int?> retryableCloseCodes = {
    null,
    CloseStatus.goingAway.code,
    CloseStatus.noStatusCode.code,
    CloseStatus.noCloseFrame.code,
    CloseStatus.serverError.code,
    CloseStatus.serviceRestarted.code,
    CloseStatus.serviceOverload.code,
    1014, // bad gateway
    CloseStatus.sessionNotReliable.code,
  };

  /// The name of the `@WebSocketClient`.
  final String clientName;

  /// The address, before the interceptors change it.
  final Uri url;

  /// The subprotocols offered in each handshake.
  final List<String> protocols;

  /// The client's settings: handshake timeout, reconnection and default
  /// headers.
  final WebSocketClientConfig config;

  /// Opens the connections: `dart:io`, the browser, or a mock in tests.
  final WebSocketTransport transport;

  /// Called on every handshake, in this order, before it is sent.
  final List<WebSocketHandshakeInterceptor> interceptors;

  final SpringLog _log;
  final _listeners = <StreamController<Object>>{};
  WebSocketSession? _connection;
  StreamSubscription<Object>? _subscription;
  Completer<WebSocketSession>? _pending;
  Timer? _retry;
  // Reconnection attempts since the last stable connection (for the
  // backoff and max-retries).
  var _retries = 0;
  // Resets _retries once a connection proved stable.
  Timer? _stable;
  // Sends (and connect()) waiting for the outcome of the next attempt.
  final _waiters = <Completer<WebSocketSession>>[];
  // Bumped by close(): attempts of an older generation are dropped.
  var _generation = 0;
  var _disposed = false;

  /// Whether a connection is open now; `false` before the first use,
  /// during a reconnection and after [close].
  bool get isConnected => _connection != null;

  /// The incoming messages as they arrive, a `String` or a `Uint8List`
  /// each. Listening opens the connection; the stream is done when the
  /// connection ends for good: closed by [close], closed normally by the
  /// server, or given up. After [dispose] the stream gives a [StateError].
  Stream<Object> messages() {
    late final StreamController<Object> controller;
    controller = StreamController<Object>(
      onListen: () {
        if (_disposed) {
          controller.addError(_disposedError());
          unawaited(controller.close());
          return;
        }
        _listeners.add(controller);
        _ensure().ignore();
      },
      onCancel: () {
        _listeners.remove(controller);
        _stopRetrying();
      },
    );
    return controller.stream;
  }

  // The last listener left while a reconnect waited: no attempt is made
  // (unless a send waits for it); the next listener starts afresh.
  void _stopRetrying() {
    final retry = _retry;
    if (_listeners.isNotEmpty || retry == null || _waiters.isNotEmpty) {
      return;
    }
    retry.cancel();
    _retry = null;
    _retries = 0;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        WebSocketException(
          'no listener is left to reconnect for',
          url: redactUrl(url),
        ),
      );
    }
  }

  /// Sends a text (`String`) or binary (`List<int>`) message, opening the
  /// connection first when needed. Without a connection the send waits for
  /// the next attempt only, so at most the reconnect delay and the connect
  /// timeout. If that attempt fails, so does the send, while the client
  /// goes on reconnecting for its listeners.
  Future<void> sendMessage(Object message) async {
    final connection = await _awaitConnection();
    try {
      connection.sendMessage(message);
    } on WebSocketException catch (error) {
      throw _redactedException(error);
    }
  }

  /// Opens the connection now, if it is not open, instead of on first
  /// use; fails when the next attempt fails, like [sendMessage].
  Future<void> connect() => _awaitConnection();

  Future<WebSocketSession> _awaitConnection() {
    final connection = _connection;
    if (connection != null) {
      return Future.value(connection);
    }
    final waiter = Completer<WebSocketSession>();
    _waiters.add(waiter);
    unawaited(_ensure().then(_resolveWaiters, onError: _failWaiters));
    return waiter.future;
  }

  void _resolveWaiters(WebSocketSession connection) {
    final waiters = [..._waiters];
    _waiters.clear();
    for (final waiter in waiters) {
      waiter.complete(connection);
    }
  }

  void _failWaiters(Object error, [StackTrace? stackTrace]) {
    final waiters = [..._waiters];
    _waiters.clear();
    for (final waiter in waiters) {
      waiter.completeError(error, stackTrace);
    }
  }

  /// Closes the connection with a normal closure (1000) and ends every
  /// message stream; a reconnection that was waiting is dropped. Using the
  /// client again opens a new connection.
  Future<void> close() async {
    final connection = _connection;
    _reset(WebSocketException('closed by the client', url: redactUrl(url)));
    for (final listener in [..._listeners]) {
      unawaited(listener.close());
    }
    _listeners.clear();
    if (connection != null) {
      _log.debug('closing ${redactUrl(url)}', fields: {'client': clientName});
      await connection.close();
    }
  }

  /// Closes for good, when the application stops: like [close], and
  /// every later use fails with a [StateError].
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await close();
  }

  // Forgets the current connection and any attempt in progress.
  void _reset(Object pendingError) {
    _generation++;
    _retry?.cancel();
    _retry = null;
    _stable?.cancel();
    _stable = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _connection = null;
    _retries = 0;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(pendingError);
    }
    _failWaiters(pendingError);
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
      headers: HttpHeaders.fromEntries([
        for (final MapEntry(key: name, value: values)
            in config.defaultRequestHeaders.entries)
          for (final value in values) MapEntry(name, value),
      ]),
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
    _log.debug(
      'connected to ${redactUrl(handshake.url)}',
      fields: {'client': clientName},
    );
    // The retries count on until the connection proves stable (a message,
    // or open for the longest reconnect delay): a server that accepts and
    // closes at once still reaches max-retries.
    _stable?.cancel();
    _stable = Timer(config.reconnect.maxDelay, () {
      _stable = null;
      if (_connection == connection) {
        _retries = 0;
      }
    });
    _connection = connection;
    _subscription = connection.messages.listen(
      (message) {
        _retries = 0;
        for (final listener in [..._listeners]) {
          listener.add(message);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _log.debug(
          'connection error: ${redactText('$error')}',
          fields: {'client': clientName},
        );
      },
      onDone: () => _closed(connection),
    );
    final pending = _pending;
    _pending = null;
    pending?.complete(connection);
  }

  // A connection attempt failed.
  void _failed(Object failure, StackTrace stackTrace) {
    final error = _redacted(failure);
    _log.debug(
      'connection failed: ${redactText('$error')}',
      fields: {'client': clientName},
    );
    _failWaiters(error, stackTrace);
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
    _stable?.cancel();
    _stable = null;
    final status = connection.closeStatus;
    final code = status?.code;
    final reason = status?.reason;
    final why = reason == null || reason.isEmpty ? '' : ' $reason';
    // By the server, or by this side's session (a message too big, a
    // server that reads nothing), or the connection broke.
    _log.debug(
      'connection closed ($code$why)',
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
    // Given up (or nobody listens): the next listener starts afresh.
    _retries = 0;
    if (code == CloseStatus.normal.code) {
      _end();
    } else {
      _end(
        WebSocketException(
          'the connection closed with code $code'
          '${reason == null || reason.isEmpty ? '' : ': $reason'}',
          url: redactUrl(url),
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

// The transport's exceptions carry the address, with a token an
// interceptor put in the query, in their text: redacted before they reach
// the application's streams and logs. The cause stays as it was.
Object _redacted(Object error) =>
    error is WebSocketException ? _redactedException(error) : error;

WebSocketException _redactedException(WebSocketException error) =>
    WebSocketException(
      redactText(error.message),
      url: switch (error.url) {
        final url? => redactUrl(url),
        null => null,
      },
      cause: error.cause,
      isTimeout: error.isTimeout,
    );

/// [url] as it may be logged or shown in an error: every query value and
/// the user information replaced by `***` (`ws://chat.test/ws?token=***`),
/// as browsers' WebSocket clients pass tokens in the query. Internal to
/// the starter (not exported).
Uri redactUrl(Uri url) {
  if (!url.hasQuery && url.userInfo.isEmpty) {
    return url;
  }
  return url.replace(
    userInfo: url.userInfo.isEmpty ? null : '***',
    query: url.hasQuery ? _redactQuery(url.query) : null,
  );
}

/// [text] with the query values and user information of the URLs in it
/// replaced by `***`, as [redactUrl] does; for error texts that quote an
/// address, such as `dart:io`'s "Connection to 'http://...' was not
/// upgraded". Internal to the starter (not exported).
String redactText(String text) => text
    .replaceAllMapped(
      _urlQuery,
      (match) => '${match[1]}?${_redactQuery(match[2]!)}',
    )
    .replaceAllMapped(_userInfo, (match) => '${match[1]}***@');

// The query ends at a space, a quote, `#`, or a closing `)` / `>` / `]`
// around the address.
final _urlQuery = RegExp(
  r"""([a-zA-Z][\w+.-]*://[^\s'"?#]*)\?([^\s'"#)>\]]*)""",
);
final _userInfo = RegExp(r"""([a-zA-Z][\w+.-]*://)[^\s'"/?#@]+@""");

String _redactQuery(String query) => [
  for (final part in query.split('&'))
    if (part.isEmpty)
      part
    else if (part.indexOf('=') case final eq when eq > 0)
      '${part.substring(0, eq)}=***'
    else
      '***',
].join('&');
