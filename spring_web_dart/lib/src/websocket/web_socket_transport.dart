import 'dart:async';

import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/websocket/platform_web_socket_stub.dart'
    if (dart.library.io) 'package:spring_web_dart/src/websocket/platform_web_socket_io.dart'
    if (dart.library.js_interop) 'package:spring_web_dart/src/websocket/platform_web_socket_web.dart'
    as platform;

/// The low-level WebSocket client: it opens a connection to a `ws:` or
/// `wss:` URL and hands back the open [WebSocketSession].
///
/// It exists so that the clients built on it (the `@WebSocketClient`
/// interfaces of `spring_boot_starter_websocket`) do not depend on how a
/// platform does WebSockets. Three implementations come with this
/// package:
///
/// - `IoWebSocketTransport` on `dart:io` (the VM, Flutter on mobile and
///   desktop), from `package:spring_web_dart/io.dart`;
/// - `BrowserWebSocketTransport` on the browser's `WebSocket`, from
///   `package:spring_web_dart/browser.dart`;
/// - `MockWebSocketTransport` for tests, from
///   `package:spring_web_dart/testing.dart`.
///
/// Most applications never call it: the WebSocket starter declares a
/// `webSocketTransport` bean from [platformWebSocketTransport], and its
/// clients use it. Declare your own `WebSocketTransport` bean to replace
/// it, for example an `IoWebSocketTransport` with a configured
/// `HttpClient`.
///
/// ```dart
/// // A short exchange outside any @WebSocketClient interface.
/// final transport = platformWebSocketTransport();
/// final session =
///     await transport.connect(Uri.parse('wss://chat.neon.books/ws'));
/// session.messages.listen(log.info);
/// session.sendMessage('hello');
/// await session.close();
/// ```
///
/// Spring (Java): `WebSocketClient`, which runs a handler instead of
/// returning a stream:
/// ```java
/// WebSocketClient client = new StandardWebSocketClient();
/// WebSocketSession session =
///     client.execute(handler, "wss://chat.neon.books/ws").get();
/// ```
abstract interface class WebSocketTransport {
  /// Opens a connection to [url] (`ws:` or `wss:`) and completes once the
  /// handshake has succeeded.
  ///
  /// [headers] go with the handshake request, typically `Authorization`.
  /// [protocols] are the subprotocols offered to the server
  /// (`Sec-WebSocket-Protocol`); the one it picks is
  /// [WebSocketSession.acceptedProtocol]. [timeout] limits the handshake;
  /// `null` leaves it to the platform.
  ///
  /// Fails with a [WebSocketException] when the server cannot be reached,
  /// refuses the handshake, or does not answer within [timeout] (then
  /// `isTimeout` is set).
  ///
  /// Browsers cannot send headers with the handshake, so in the browser a
  /// non-empty [headers] fails at once. Pass a token as a query parameter
  /// or a protocol there instead.
  Future<WebSocketSession> connect(
    Uri url, {
    HttpHeaders? headers,
    List<String> protocols = const [],
    Duration? timeout,
  });
}

/// One open WebSocket connection: it receives messages as a stream, sends
/// messages, and closes.
///
/// A client gets it from [WebSocketTransport.connect]. A server gets it
/// when it accepts a connection (`ServerHttpRequest.upgradeToWebSocket`),
/// so the same type serves both sides. With the WebSocket starter you
/// rarely hold one: `@WebSocketClient` interfaces and
/// `@WebSocketEndpoint` classes hide it behind typed methods. You use it
/// directly with a bare transport, or in a server handler that needs the
/// connection itself.
///
/// ```dart
/// session.messages.listen((message) {
///   if (message is String) { ... } // A text frame.
///   if (message is Uint8List) { ... } // A binary frame.
/// });
/// session.sendMessage('{"text":"hi"}');
/// // Tell the server the client is leaving, not failing.
/// await session.close(CloseStatus.goingAway);
/// ```
///
/// Spring (Java): `WebSocketSession`; the incoming messages go to a
/// `WebSocketHandler` instead of a stream:
/// ```java
/// session.sendMessage(new TextMessage("{\"text\":\"hi\"}"));
/// session.close(CloseStatus.GOING_AWAY);
/// ```
abstract interface class WebSocketSession {
  /// The URL of the connection: the one a client connected to, or the
  /// `ws:` form of the request URL on a server.
  Uri get uri;

  /// The incoming messages: a `String` for each text frame, a `Uint8List`
  /// for each binary one. It can be listened to once, and it is done when
  /// the connection closes, whichever side closed it.
  Stream<Object> get messages;

  /// The subprotocol the two sides agreed on in the handshake, or `null`
  /// when none was asked for or accepted.
  String? get acceptedProtocol;

  /// Whether messages can still be sent: `false` once either side has
  /// started to close the connection.
  bool get isOpen;

  /// Sends [message] as a text frame when it is a `String`, or as a binary
  /// frame when it is a `List<int>`. Throws a [WebSocketException] when
  /// the session is no longer open, and an [ArgumentError] for any other
  /// type. It does not wait for the frame to leave: the message waits in
  /// memory until the network takes it. On `dart:io` a session whose
  /// other side takes nothing gives up past its limits (512 KB waiting,
  /// or 10 seconds) and drops the connection, and
  /// `IoWebSocketSession.flush` waits until what was sent has left; see
  /// `IoWebSocketSession`.
  void sendMessage(Object message);

  /// Closes the connection, sending [status] ([CloseStatus.normal] by
  /// default) to the other side. The future completes when the connection
  /// is closed.
  Future<void> close([CloseStatus status = CloseStatus.normal]);

  /// How the connection was closed, by either side: the code and reason
  /// of the close frame. `null` while it is open.
  CloseStatus? get closeStatus;
}

/// Creates the WebSocket transport that suits the platform the code runs
/// on: an `IoWebSocketTransport` where `dart:io` exists (the VM, Flutter
/// on mobile and desktop), a `BrowserWebSocketTransport` in the browser.
///
/// It lets code shared between Flutter mobile and Flutter web open
/// connections without conditional imports. The WebSocket starter calls
/// it for its default `webSocketTransport` bean. On a platform with
/// neither `dart:io` nor `dart:js_interop` it throws an
/// [UnsupportedError]: pass your own [WebSocketTransport] there.
///
/// [maxTextMessageSize] and [maxBinaryMessageSize] bound the messages a
/// session receives on `dart:io` (8 KB each when `null`, `-1` for no
/// limit; see `IoWebSocketTransport`). The browser assembles messages
/// itself and has no such limit, so it ignores them.
///
/// ```dart
/// final transport = platformWebSocketTransport(
///   maxTextMessageSize: 1024 * 1024, // the server sends large JSON
/// );
/// ```
///
/// Spring (Java): picking a `WebSocketClient` implementation by hand
/// (`StandardWebSocketClient`, `ReactorNettyWebSocketClient`).
WebSocketTransport platformWebSocketTransport({
  int? maxTextMessageSize,
  int? maxBinaryMessageSize,
}) => platform.createWebSocketTransport(
  maxTextMessageSize: maxTextMessageSize,
  maxBinaryMessageSize: maxBinaryMessageSize,
);

/// Thrown when a WebSocket connection cannot be opened or used: the server
/// is unreachable, refuses the handshake, does not answer in time, the
/// connection breaks, or a message is sent on a closed session.
///
/// Transports throw it from `connect`, and sessions from `sendMessage`
/// (on `dart:io`, also from `IoWebSocketSession.flush`). A connection
/// that breaks ends its message stream without one: its `closeStatus`
/// tells why (1006, `CloseStatus.noCloseFrame`, on `dart:io`). The
/// WebSocket starter reconnects after such failures, so you meet it
/// mostly when you use a transport directly.
///
/// ```dart
/// try {
///   await transport.connect(url, timeout: const Duration(seconds: 5));
/// } on WebSocketException catch (error) {
///   // Tell a slow server from one that refused.
///   log.warning(error.isTimeout ? 'chat is not answering' : error.message);
/// }
/// ```
///
/// Spring (Java): `WebSocketException`, or a failed `CompletableFuture`
/// from `WebSocketClient.execute`.
class WebSocketException implements Exception {
  /// A failure described by [message], for [url] when it is known.
  /// [cause] keeps the platform's own error; set [isTimeout] when the
  /// handshake ran out of time.
  WebSocketException(
    this.message, {
    this.url,
    this.cause,
    this.isTimeout = false,
  });

  /// What went wrong, for people, such as `cannot connect: ...` or
  /// `the connection is closed`.
  final String message;

  /// The URL of the connection, or `null` when it is not known.
  final Uri? url;

  /// The error the platform reported, or `null`.
  final Object? cause;

  /// Whether the handshake did not finish within the `timeout` given to
  /// `connect`.
  final bool isTimeout;

  @override
  String toString() =>
      'WebSocketException: $message${url == null ? '' : ' ($url)'}';
}

/// Why a WebSocket connection closed: the numeric code and optional
/// reason text of the close frame (RFC 6455).
///
/// A side that closes a connection says why, so the other side can react:
/// reconnect after a restart, ask for a new token after a policy
/// violation, stop after a normal close. You pass one to
/// [WebSocketSession.close] and read one from
/// [WebSocketSession.closeStatus]. The constants name the codes of the
/// RFC; codes 4000–4999 are free for applications.
///
/// ```dart
/// // A server endpoint turns away a client without a valid token.
/// await session.close(CloseStatus.policyViolation.withReason('no token'));
///
/// // A client compares codes only, since the reason text may vary.
/// if (session.closeStatus?.equalsCode(CloseStatus.normal) ?? false) { ... }
/// ```
///
/// Spring (Java): `CloseStatus`, with the same constants:
/// ```java
/// session.close(CloseStatus.POLICY_VIOLATION.withReason("no token"));
/// ```
final class CloseStatus {
  /// A status with [code] and an optional [reason]. The code must be in
  /// 1000–4999; this is only checked by an assertion in debug mode.
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

  /// 4500: a code Spring added for a session that can no longer be relied
  /// on, for example because a send timed out. An `IoWebSocketSession`
  /// reports it when it drops a connection whose other side takes
  /// nothing; it is never sent.
  static const sessionNotReliable = CloseStatus(4500);

  /// The numeric close code, such as 1000 for a normal close.
  final int code;

  /// The reason text sent with the code, or `null` for none. RFC 6455
  /// limits it to 123 bytes of UTF-8.
  final String? reason;

  /// A status with this code and [reason], for example
  /// `CloseStatus.policyViolation.withReason('no token')`.
  CloseStatus withReason(String reason) => CloseStatus(code, reason);

  /// Whether [other] has the same code, whatever the reasons. Use it
  /// instead of `==`, which compares the reasons too.
  bool equalsCode(CloseStatus other) => code == other.code;

  @override
  bool operator ==(Object other) =>
      other is CloseStatus && other.code == code && other.reason == reason;

  @override
  int get hashCode => Object.hash(code, reason);

  @override
  String toString() => 'CloseStatus[code=$code, reason=$reason]';
}
