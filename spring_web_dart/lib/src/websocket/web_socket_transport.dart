import 'dart:async';

import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/websocket/platform_web_socket_stub.dart'
    if (dart.library.io) 'package:spring_web_dart/src/websocket/platform_web_socket_io.dart'
    if (dart.library.js_interop) 'package:spring_web_dart/src/websocket/platform_web_socket_web.dart'
    as platform;

/// Opens WebSocket connections: what `@WebSocketClient` interfaces
/// (`spring_boot_starter_websocket`) talk to. Implementations:
/// `IoWebSocketTransport` (VM, Flutter mobile and desktop;
/// `package:spring_web_dart/io.dart`), `BrowserWebSocketTransport` (web;
/// `package:spring_web_dart/browser.dart`), `MockWebSocketTransport`
/// (tests; `package:spring_web_dart/testing.dart`).
///
/// ```dart
/// final transport = platformWebSocketTransport();
/// final socket = await transport.connect(Uri.parse('wss://chat.neon.books/ws'));
/// socket.messages.listen(print);
/// socket.send('hello');
/// await socket.close();
/// ```
///
/// Spring (Java):
/// ```java
/// WebSocketClient client = new StandardWebSocketClient();
/// client.execute(handler, "wss://chat.neon.books/ws");
/// ```
abstract interface class WebSocketTransport {
  /// Opens a connection to [url] (`ws:` or `wss:`), sending [headers] and
  /// asking for one of [protocols]; [timeout] limits the handshake. Fails
  /// with [WebSocketException].
  ///
  /// Browsers cannot send headers with the handshake: on the web a
  /// non-empty [headers] fails — pass a token as a query parameter or a
  /// protocol instead.
  Future<WebSocketConnection> connect(
    Uri url, {
    HttpHeaders? headers,
    List<String> protocols = const [],
    Duration? timeout,
  });
}

/// One open WebSocket connection.
///
/// ```dart
/// socket.messages.listen((message) {
///   if (message is String) { ... } // a text frame
///   if (message is Uint8List) { ... } // a binary frame
/// });
/// socket.send('{"text":"hi"}');
/// await socket.close(1000, 'bye');
/// ```
///
/// Spring (Java): `WebSocketSession`.
abstract interface class WebSocketConnection {
  /// The incoming messages: `String` for text frames, `Uint8List` for
  /// binary ones. Single subscription; done when the connection closes.
  Stream<Object> get messages;

  /// The protocol the server picked, if any.
  String? get protocol;

  /// Sends a text frame (`String`) or a binary frame (`List<int>`); throws
  /// [WebSocketException] when the connection is closed.
  void send(Object message);

  /// Closes the connection with [code] and [reason].
  Future<void> close([int? code, String? reason]);

  /// The close code, once closed (e.g. 1000 normal, 1006 lost).
  int? get closeCode;

  /// The close reason, once closed.
  String? get closeReason;
}

/// The WebSocket transport of the current platform:
/// `IoWebSocketTransport` with `dart:io`, `BrowserWebSocketTransport` on
/// the web.
///
/// Spring (Java): picking a `WebSocketClient` implementation
/// (`StandardWebSocketClient`, `ReactorNettyWebSocketClient`).
WebSocketTransport platformWebSocketTransport() =>
    platform.createWebSocketTransport();

/// A WebSocket that could not be opened or used.
///
/// ```dart
/// try {
///   await transport.connect(url);
/// } on WebSocketException catch (error) {
///   print(error.message);
/// }
/// ```
///
/// Spring (Java): `WebSocketException` / a failed `CompletableFuture`
/// from `WebSocketClient.execute`.
class WebSocketException implements Exception {
  /// A failure described by [message].
  WebSocketException(
    this.message, {
    this.url,
    this.cause,
    this.isTimeout = false,
  });

  /// What went wrong.
  final String message;

  /// The address, when known.
  final Uri? url;

  /// The underlying error, if any.
  final Object? cause;

  /// Whether the handshake ran out of time.
  final bool isTimeout;

  @override
  String toString() =>
      'WebSocketException: $message${url == null ? '' : ' ($url)'}';
}

/// WebSocket close codes (RFC 6455).
abstract final class WebSocketStatus {
  /// 1000: done.
  static const normalClosure = 1000;

  /// 1001: the server is going down or the page is leaving.
  static const goingAway = 1001;

  /// 1002: a protocol error.
  static const protocolError = 1002;

  /// 1003: a kind of data the endpoint does not accept.
  static const unsupportedData = 1003;

  /// 1005: closed without a code.
  static const noStatusReceived = 1005;

  /// 1006: the connection was lost without a close frame.
  static const abnormalClosure = 1006;

  /// 1007: data that does not fit the message type.
  static const invalidPayload = 1007;

  /// 1008: a policy violation (often: not authorized).
  static const policyViolation = 1008;

  /// 1009: a message too big.
  static const messageTooBig = 1009;

  /// 1011: the server failed.
  static const internalError = 1011;

  /// 1012: the server is restarting.
  static const serviceRestart = 1012;

  /// 1013: try again later.
  static const tryAgainLater = 1013;
}
