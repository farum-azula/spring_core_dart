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
/// final session = await transport.connect(Uri.parse('wss://chat.neon.books/ws'));
/// session.messages.listen(print);
/// session.sendMessage('hello');
/// await session.close();
/// ```
///
/// Spring (Java):
/// ```java
/// WebSocketClient client = new StandardWebSocketClient();
/// WebSocketSession session = client.execute(handler, "wss://chat.neon.books/ws").get();
/// ```
abstract interface class WebSocketTransport {
  /// Opens a session with [url] (`ws:` or `wss:`), sending [headers] and
  /// asking for one of [protocols]; [timeout] limits the handshake. Fails
  /// with [WebSocketException].
  ///
  /// Browsers cannot send headers with the handshake: on the web a
  /// non-empty [headers] fails — pass a token as a query parameter or a
  /// protocol instead.
  Future<WebSocketSession> connect(
    Uri url, {
    HttpHeaders? headers,
    List<String> protocols = const [],
    Duration? timeout,
  });
}

/// One open WebSocket connection, like Spring's `WebSocketSession`. The
/// incoming messages are a stream (Spring calls a `WebSocketHandler`).
///
/// ```dart
/// session.messages.listen((message) {
///   if (message is String) { ... } // a text frame
///   if (message is Uint8List) { ... } // a binary frame
/// });
/// session.sendMessage('{"text":"hi"}');
/// await session.close(CloseStatus.goingAway);
/// ```
///
/// Spring (Java):
/// ```java
/// session.sendMessage(new TextMessage("{\"text\":\"hi\"}"));
/// session.close(CloseStatus.GOING_AWAY);
/// ```
abstract interface class WebSocketSession {
  /// The address of the session.
  Uri get uri;

  /// The incoming messages: `String` for text frames, `Uint8List` for
  /// binary ones. Single subscription; done when the session closes.
  Stream<Object> get messages;

  /// The subprotocol the server accepted, if any.
  String? get acceptedProtocol;

  /// Whether the session is open.
  bool get isOpen;

  /// Sends a text message (`String`) or a binary one (`List<int>`); throws
  /// [WebSocketException] when the session is closed.
  void sendMessage(Object message);

  /// Closes the session with [status] ([CloseStatus.normal] by default).
  Future<void> close([CloseStatus status = CloseStatus.normal]);

  /// How the session was closed (by either side), once it is closed;
  /// `null` while it is open.
  CloseStatus? get closeStatus;
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

/// The code and optional reason of a WebSocket close frame (RFC 6455),
/// like Spring's `CloseStatus`, with its constants.
///
/// ```dart
/// await session.close(CloseStatus.policyViolation.withReason('no token'));
/// if (session.closeStatus?.equalsCode(CloseStatus.normal) ?? false) { ... }
/// ```
///
/// Spring (Java):
/// ```java
/// session.close(CloseStatus.POLICY_VIOLATION.withReason("no token"));
/// ```
final class CloseStatus {
  /// A status with [code] (1000–4999) and an optional [reason].
  const CloseStatus(this.code, [this.reason])
    : assert(code >= 1000 && code < 5000, 'Invalid status code');

  /// 1000: the purpose of the connection was fulfilled.
  static const normal = CloseStatus(1000);

  /// 1001: the endpoint is going away (a server going down, a page
  /// leaving).
  static const goingAway = CloseStatus(1001);

  /// 1002: a protocol error.
  static const protocolError = CloseStatus(1002);

  /// 1003: a kind of data the endpoint cannot accept.
  static const notAcceptable = CloseStatus(1003);

  /// 1005: closed without a status code (never sent in a close frame).
  static const noStatusCode = CloseStatus(1005);

  /// 1006: the connection was lost without a close frame (never sent).
  static const noCloseFrame = CloseStatus(1006);

  /// 1007: data that does not fit the message type.
  static const badData = CloseStatus(1007);

  /// 1008: a policy violation (often: not authorized).
  static const policyViolation = CloseStatus(1008);

  /// 1009: a message too big to process.
  static const tooBigToProcess = CloseStatus(1009);

  /// 1010: the client expected an extension the server did not offer.
  static const requiredExtension = CloseStatus(1010);

  /// 1011: the server failed.
  static const serverError = CloseStatus(1011);

  /// 1012: the server is restarting.
  static const serviceRestarted = CloseStatus(1012);

  /// 1013: the server is overloaded; try again later.
  static const serviceOverload = CloseStatus(1013);

  /// 1015: the TLS handshake failed (never sent).
  static const tlsHandshakeFailure = CloseStatus(1015);

  /// 4500: Spring's code for a session that cannot be relied on any more
  /// (e.g. a send timed out).
  static const sessionNotReliable = CloseStatus(4500);

  /// The status code.
  final int code;

  /// The reason, if any.
  final String? reason;

  /// This code with [reason].
  CloseStatus withReason(String reason) => CloseStatus(code, reason);

  /// Whether [other] has the same code (the reason may differ).
  bool equalsCode(CloseStatus other) => code == other.code;

  @override
  bool operator ==(Object other) =>
      other is CloseStatus && other.code == code && other.reason == reason;

  @override
  int get hashCode => Object.hash(code, reason);

  @override
  String toString() => 'CloseStatus[code=$code, reason=$reason]';
}
