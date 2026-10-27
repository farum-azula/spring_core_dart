import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/websocket/web_socket_transport.dart';

/// A [WebSocketTransport] for tests: every `connect` gives a
/// [MockWebSocket] playing the server — read what the client sent, push
/// messages to it, close or drop the connection.
///
/// ```dart
/// final sockets = MockWebSocketTransport();
/// // In a Spring Boot test: withBean<WebSocketTransport>(sockets)
///
/// final server = await sockets.nextConnection;
/// server.pushJson({'from': 'ann', 'text': 'hi'});
/// expect(server.sentJson, [{'from': 'me', 'text': 'hello'}]);
/// server.drop(); // the client reconnects
/// sockets.failNextConnect(); // ... and fails once
/// ```
///
/// Spring (Java): no equivalent; tests start a server or mock
/// `WebSocketSession`.
class MockWebSocketTransport implements WebSocketTransport {
  /// A transport accepting every connection.
  MockWebSocketTransport();

  final _connections = <MockWebSocket>[];
  final _failures = Queue<Object>();
  final _waiting = Queue<Completer<MockWebSocket>>();
  var _taken = 0;

  /// Every connection opened so far, in order.
  List<MockWebSocket> get connections => List.unmodifiable(_connections);

  /// The last connection; throws `StateError` when there was none.
  MockWebSocket get lastConnection => _connections.isEmpty
      ? throw StateError('No WebSocket was opened')
      : _connections.last;

  /// The next connection not taken yet by this getter (the first call
  /// gives the first connection, and so on); waits until it is opened.
  Future<MockWebSocket> get nextConnection {
    if (_taken < _connections.length) {
      return Future.value(_connections[_taken++]);
    }
    final waiting = Completer<MockWebSocket>();
    _waiting.add(waiting);
    return waiting.future;
  }

  /// Makes the next `connect` fail with [error] (default: a
  /// [WebSocketException]).
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

/// The server side of one connection of a [MockWebSocketTransport] (and
/// the [WebSocketSession] the client uses).
final class MockWebSocket implements WebSocketSession {
  MockWebSocket._(this.uri, this.headers, this.protocols);

  /// The address the client connected to.
  @override
  final Uri uri;

  /// The handshake headers.
  final HttpHeaders headers;

  /// The protocols the client asked for.
  final List<String> protocols;

  final _incoming = StreamController<Object>();
  final _sent = <Object>[];
  final _sentEvents = StreamController<Object>.broadcast();
  CloseStatus? _closeStatus;
  bool _closedByClient = false;

  /// What the client sent, in order (`String` or `Uint8List`).
  List<Object> get sent => List.unmodifiable(_sent);

  /// The text messages the client sent that are JSON, decoded (other
  /// text and binary messages are left out; see [sent]).
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

  /// Each message the client sends, as it is sent.
  Stream<Object> get onSent => _sentEvents.stream;

  /// Whether the connection is closed.
  bool get isClosed => _closeStatus != null;

  /// Whether the client closed it.
  bool get closedByClient => _closedByClient;

  /// Sends the client a text (`String`) or binary (`List<int>`) message.
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

  /// Sends the client [json] encoded as a text message.
  void pushJson(Object? json) => push(jsonEncode(json));

  /// Closes from the server side with [status].
  Future<void> closeFromServer([CloseStatus status = CloseStatus.normal]) =>
      _end(status);

  /// Loses the connection ([CloseStatus.noCloseFrame], 1006), e.g. to test
  /// reconnection.
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
