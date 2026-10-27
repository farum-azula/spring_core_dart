import 'package:spring_boot_dart/spring_boot_dart.dart';

/// A WebSocket endpoint of the application's server (with
/// `spring_boot_starter_web`): a bean whose `@OnOpen`, `@OnMessage`,
/// `@OnClose` and `@OnError` methods handle the connections to [path],
/// like Jakarta's `@ServerEndpoint` (Spring registers a `WebSocketHandler`
/// for the same; `WebSocketConfigurer` does that here too).
///
/// The methods take what they need, in any order:
///
/// - `ServerWebSocketSession` / `WebSocketSession`: the connection;
/// - `@PathVariable() String room`: a `{room}` of [path];
/// - `Principal`: the user of the handshake (null when anonymous and
///   nullable);
/// - the message (`@OnMessage`): `String` (text), `Uint8List` (binary), any
///   other type read as JSON;
/// - `CloseStatus` (`@OnClose`): why it closed;
/// - the error (`@OnError`): what a handler threw, or the transport error.
///
/// What an `@OnMessage` method returns (a `Future` is awaited) is sent
/// back: a `String` as text, bytes as binary, anything else as JSON.
///
/// ```dart
/// @WebSocketEndpoint('/ws/rooms/{room}')
/// class ChatEndpoint {
///   ChatEndpoint(this.rooms);
///   final ChatRooms rooms;
///
///   @OnOpen()
///   void open(ServerWebSocketSession session, @PathVariable() String room) =>
///       rooms.join(room, session);
///
///   @OnMessage()
///   void message(@PathVariable() String room, ChatMessage message) =>
///       rooms.broadcast(room, message);
///
///   @OnClose()
///   void close(ServerWebSocketSession session, @PathVariable() String room) =>
///       rooms.leave(room, session);
/// }
/// ```
///
/// Origins: like Spring, a browser connecting from another origin is
/// refused unless it is in [allowedOrigins] (or [allowedOriginPatterns]);
/// clients sending no `Origin` (not browsers) are accepted.
class WebSocketEndpoint extends Component {
  /// An endpoint at [path] (a path pattern: `{variables}` allowed).
  const WebSocketEndpoint(
    this.path, {
    this.allowedOrigins = const [],
    this.allowedOriginPatterns = const [],
    this.protocols = const [],
    String? name,
  }) : super(name);

  /// The path pattern, e.g. `/ws/chat` or `/ws/rooms/{room}`.
  final String path;

  /// Origins allowed besides the server's own (`*` for any).
  final List<String> allowedOrigins;

  /// Origin patterns allowed (`https://*.example`).
  final List<String> allowedOriginPatterns;

  /// Sub-protocols the endpoint speaks (`Sec-WebSocket-Protocol`); the
  /// first one the client offers is chosen.
  final List<String> protocols;
}

/// Marks the method of a [WebSocketEndpoint] called when a connection
/// opens, like Jakarta's `@OnOpen`.
@BeanMethodAnnotation()
class OnOpen {
  /// Marks the method.
  const OnOpen();
}

/// Marks the method of a [WebSocketEndpoint] called when a connection
/// closed (it may take the `CloseStatus`), like Jakarta's `@OnClose`.
@BeanMethodAnnotation()
class OnClose {
  /// Marks the method.
  const OnClose();
}

/// Marks the method of a [WebSocketEndpoint] called with an error a
/// handler threw or the connection broke with, like Jakarta's `@OnError`.
/// Without one, the error is logged and the connection closed (1011).
@BeanMethodAnnotation()
class OnError {
  /// Marks the method.
  const OnError();
}
