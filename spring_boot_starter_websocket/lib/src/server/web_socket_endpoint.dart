import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Marks a bean that accepts WebSocket connections on [path] of the
/// application's own server: its `@OnOpen`, `@OnMessage`, `@OnClose` and
/// `@OnError` methods handle each connection.
///
/// Use it to push live data to apps and browsers, or to let them talk to
/// each other, as in a chat. It needs `spring_boot_starter_web` as a
/// dependency, which runs the server. The handshake is an ordinary
/// request: it passes the web starter's filters, so a security filter
/// authenticates it like any other. The class is a singleton bean with
/// constructor injection, shared by all connections; keep per-connection
/// state in `session.attributes`.
///
/// The methods take what they need, in any order:
///
/// - `ServerWebSocketSession` or `WebSocketSession`: the connection;
/// - `@PathVariable() String room`: the `{room}` of [path];
/// - `Principal?`: the user of the handshake, `null` when anonymous;
/// - the message, in `@OnMessage`: `String` (text), `Uint8List` (binary),
///   or any other type, read as JSON through the `ObjectMapper`;
/// - `CloseStatus`, in `@OnClose`: why it closed;
/// - the error, in `@OnError`: what a method threw, or the connection's
///   error.
///
/// What an `@OnMessage` method returns is sent back, after awaiting a
/// `Future`: a `String` as text, bytes as binary, anything else as JSON;
/// `void` and `null` send nothing. The messages of one connection are
/// handled one after the other, in order. An endpoint must have an
/// `@OnOpen`, `@OnMessage` or `@OnClose` method, and at most one of each;
/// a wrong endpoint stops the start with the list of problems.
///
/// ```dart
/// // A chat with one room per path: /ws/rooms/neon, /ws/rooms/dart, ...
/// @WebSocketEndpoint('/ws/rooms/{room}')
/// class ChatEndpoint {
///   ChatEndpoint(this.rooms); // the application's own bean
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
/// Origins: as in Spring, a browser connecting from the server's own
/// origin is accepted, one from another origin only when it is in
/// [allowedOrigins] or matches [allowedOriginPatterns]; others get a 403.
/// Clients that send no `Origin` (not browsers: apps, servers) are
/// accepted, so authenticate them with a filter.
///
/// Spring (Java): Spring has no annotated endpoint of its own; it
/// registers a `WebSocketHandler` (here too, with a `WebSocketConfigurer`)
/// or Jakarta's `@ServerEndpoint` classes. This annotation follows
/// Jakarta's names, but the endpoint is a singleton bean (Jakarta creates
/// one per connection), and `@PathVariable` replaces `@PathParam`.
class WebSocketEndpoint extends Component {
  /// An endpoint at [path], accepting the origins and offering the
  /// [protocols] given. [name] is the bean name; by default it is derived
  /// from the class name.
  const WebSocketEndpoint(
    this.path, {
    this.allowedOrigins = const [],
    this.allowedOriginPatterns = const [],
    this.protocols = const [],
    String? name,
  }) : super(name);

  /// The path the endpoint answers, a path pattern as on controllers:
  /// `/ws/chat`, `/ws/rooms/{room}`, `/ws/{*rest}`. A request to it that
  /// is not a WebSocket handshake gets a 400.
  final String path;

  /// The browser origins allowed besides the server's own, such as
  /// `https://chat.example`, compared in any case; `*` allows any.
  final List<String> allowedOrigins;

  /// Origin patterns allowed besides [allowedOrigins], where `*` stands
  /// for any text: `https://*.example`.
  final List<String> allowedOriginPatterns;

  /// The subprotocols the endpoint speaks (`Sec-WebSocket-Protocol`):
  /// the first one the client offers that is in this list is chosen. A
  /// client offering none of them still connects, without a protocol.
  final List<String> protocols;
}

/// Marks the method of a [WebSocketEndpoint] called when a connection has
/// opened, before its first message: to greet the client, to note who
/// joined, or to keep values in `session.attributes`. Jakarta's
/// `@OnOpen`.
@BeanMethodAnnotation()
class OnOpen {
  /// Marks the method called when a connection opens.
  const OnOpen();
}

/// Marks the method of a [WebSocketEndpoint] called when a connection has
/// closed, from either side, after its last message was handled: to clean
/// up what `@OnOpen` set up. It may take the `CloseStatus`. Jakarta's
/// `@OnClose`.
@BeanMethodAnnotation()
class OnClose {
  /// Marks the method called when a connection closes.
  const OnClose();
}

/// Marks the method of a [WebSocketEndpoint] called with an error that
/// another method threw or the connection broke with; the connection stays
/// open. Jakarta's `@OnError`.
///
/// Without such a method, the error is logged and the connection is closed
/// with 1011 (server error).
@BeanMethodAnnotation()
class OnError {
  /// Marks the method called with the errors of a connection.
  const OnError();
}
