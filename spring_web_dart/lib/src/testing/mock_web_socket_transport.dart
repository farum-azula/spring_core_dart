import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/websocket/web_socket_transport.dart';

/// A fake WebSocket connection for tests: every connection the client
/// opens is kept in memory, and the test plays the server on it.
///
/// It replaces the real [WebSocketTransport] under a WebSocket client
/// (for example one of the WebSocket starter), so a test can read what
/// the client sent, push messages to it, close or drop the connection,
/// and make the next connection attempt fail, all without a server.
/// Each `connect` succeeds at once and gives a [MockWebSocket]; wait for
/// it with [nextConnection].
///
/// ```dart
/// // A chat client under test talks to the mock instead of a server.
/// final sockets = MockWebSocketTransport();
/// runner = runner.withBean<WebSocketTransport>(() => sockets);
///
/// final server = await sockets.nextConnection;
/// server.pushJson({'from': 'ann', 'text': 'hi'}); // the client receives
/// expect(server.sentJson, [{'from': 'me', 'text': 'hello'}]);
///
/// sockets.failNextConnect(); // the first reconnection attempt fails
/// await server.drop(); // the connection is lost: the client reconnects
/// ```
///
/// Spring (Java): no equivalent; tests start a server or mock
/// `WebSocketSession`.
class MockWebSocketTransport implements WebSocketTransport {
  /// A transport that accepts every connection, until [failNextConnect]
  /// says otherwise.
  MockWebSocketTransport();

  final _connections = <MockWebSocket>[];
  final _failures = Queue<Object>();
  final _waiting = Queue<Completer<MockWebSocket>>();
  var _taken = 0;

  /// Every connection opened so far, in order, closed ones included.
  List<MockWebSocket> get connections => List.unmodifiable(_connections);

  /// The connection opened last; throws a `StateError` when none was
  /// opened.
  MockWebSocket get lastConnection => _connections.isEmpty
      ? throw StateError('No WebSocket was opened')
      : _connections.last;

  /// The next connection this getter has not returned yet: the first
  /// call gives the first connection, the second call the second, and so
  /// on. When the client has not opened it yet, the future completes when
  /// it does. This is how a test waits for a (re)connection.
  Future<MockWebSocket> get nextConnection {
    if (_taken < _connections.length) {
      return Future.value(_connections[_taken++]);
    }
    final waiting = Completer<MockWebSocket>();
    _waiting.add(waiting);
    return waiting.future;
  }

  /// Makes the next `connect` throw [error] (by default a
  /// [WebSocketException] "connection refused"), to test how the client
  /// handles a refused connection. Each call fails one more attempt.
  void failNextConnect([Object? error]) =>
      _failures.add(error ?? WebSocketException('connection refused'));

  @override
  Future<WebSocketSession> connect(
    Uri url, {
    HttpHeaders? headers,
    List<String> protocols = const [],
    Duration? timeout,
  }) async {
    await Future<void>.delayed(Duration.zero);
    if (_failures.isNotEmpty) {
      // Any object can be prepared as the failure (failNextConnect).
      // ignore: only_throw_errors
      throw _failures.removeFirst();
    }
    final socket = MockWebSocket._(
      url,
      headers?.copy() ?? HttpHeaders(),
      List.unmodifiable(protocols),
    );
    _connections.add(socket);
    if (_waiting.isNotEmpty) {
      _taken++;
      _waiting.removeFirst().complete(socket);
    }
    return socket;
  }
}

/// One connection opened through a [MockWebSocketTransport]: the client
/// uses it as its [WebSocketSession], and the test plays the server with
/// the other members.
///
/// The test reads what the client sent ([sent], [sentJson], [onSent]),
/// sends it messages ([push], [pushJson]) and ends the connection
/// cleanly ([closeFromServer]) or abruptly ([drop]).
///
/// ```dart
/// final server = await sockets.nextConnection;
/// expect(server.headers['Authorization'], 'Bearer t0k3n');
/// server.push('welcome');
/// await server.closeFromServer(CloseStatus.goingAway);
/// ```
final class MockWebSocket implements WebSocketSession {
  MockWebSocket._(this.uri, this.headers, this.protocols);

  /// The URL the client connected to.
  @override
  final Uri uri;

  /// The headers the client sent with the handshake (a copy).
  final HttpHeaders headers;

  /// The sub-protocols the client offered, in order; the first one is
  /// taken as the [acceptedProtocol].
  final List<String> protocols;

  final _incoming = StreamController<Object>();
  final _sent = <Object>[];
  final _sentEvents = StreamController<Object>.broadcast();
  CloseStatus? _closeStatus;
  bool _closedByClient = false;

  /// Every message the client sent, in order: a `String` for a text
  /// message, a `Uint8List` for a binary one.
  List<Object> get sent => List.unmodifiable(_sent);

  /// The text messages the client sent that are JSON, decoded. Other text
  /// and binary messages are left out (see [sent]), and so is a message
  /// that is the JSON `null`.
  List<Object?> get sentJson => [
    for (final message in _sent)
      if (message is String) ?_tryJson(message),
  ];

  static Object? _tryJson(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  /// Each message the client sends from now on, as it is sent; ends when
  /// the connection closes. Use it to wait for a message.
  Stream<Object> get onSent => _sentEvents.stream;

  /// Whether the connection is closed, by either side.
  bool get isClosed => _closeStatus != null;

  /// Whether the client closed it (rather than the test, with
  /// [closeFromServer] or [drop]).
  bool get closedByClient => _closedByClient;

  /// Sends the client a text (`String`) or binary (`List<int>`) message,
  /// as the server would. Throws a `StateError` once the connection is
  /// closed.
  void push(Object message) {
    if (isClosed) {
      throw StateError('The connection is closed');
    }
    _incoming.add(
      message is List<int> && message is! Uint8List
          ? Uint8List.fromList(message)
          : message,
    );
  }

  /// Sends the client [json], encoded, as a text message.
  void pushJson(Object? json) => push(jsonEncode(json));

  /// Closes the connection as the server would, with [status] (1000,
  /// normal, by default); the client sees it as a clean close.
  Future<void> closeFromServer([CloseStatus status = CloseStatus.normal]) =>
      _end(status);

  /// Loses the connection without a close handshake, as a network
  /// failure does: the close status is [CloseStatus.noCloseFrame] (1006).
  /// Use it to test that the client reconnects.
  Future<void> drop() => _end(CloseStatus.noCloseFrame);

  Future<void> _end(CloseStatus status) async {
    if (isClosed) {
      return;
    }
    _closeStatus = status;
    unawaited(_incoming.close());
    unawaited(_sentEvents.close());
  }

  @override
  Stream<Object> get messages => _incoming.stream;

  @override
  String? get acceptedProtocol => protocols.firstOrNull;

  @override
  bool get isOpen => !isClosed;

  @override
  void sendMessage(Object message) {
    if (isClosed) {
      throw WebSocketException('the connection is closed', url: uri);
    }
    final value = switch (message) {
      String() => message,
      Uint8List() => message,
      List<int>() => Uint8List.fromList(message),
      _ => throw ArgumentError.value(
        message,
        'message',
        'a String or a List<int>',
      ),
    };
    _sent.add(value);
    _sentEvents.add(value);
  }

  @override
  Future<void> close([CloseStatus status = CloseStatus.normal]) {
    if (!isClosed) {
      _closedByClient = true;
    }
    return _end(status);
  }

  @override
  CloseStatus? get closeStatus => _closeStatus;

  @override
  String toString() => 'MockWebSocket($uri)';
}
