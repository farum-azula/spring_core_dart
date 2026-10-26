import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Turns an abstract class into a WebSocket client bean: methods marked
/// [OnMessage] give the incoming messages as a typed `Stream`, methods
/// marked [SendMessage] send one; optional `connect()` and `close()`
/// open it eagerly or close it early (the application closes every
/// connection when it stops). The generator writes the implementation
/// (no reflection); messages go through the `ObjectMapper` as JSON.
///
/// ```dart
/// @WebSocketClient('chat', url: r'${chat.url}')
/// abstract interface class ChatSocket {
///   @OnMessage()
///   Stream<ChatMessage> messages();
///
///   @SendMessage()
///   Future<void> send(ChatMessage message);
/// }
///
/// @Service()
/// class Chat {
///   Chat(this.socket);
///   final ChatSocket socket;
///
///   void start() => socket.messages().listen(print);
///   Future<void> say(String text) => socket.send(ChatMessage('me', text));
/// }
/// ```
///
/// One connection per client, opened on the first listener or the first
/// message sent, shared by every stream; lost connections are opened again
/// with backoff while someone listens. [name] keys the configuration
/// (`spring.websocket.client.config.<name>.*`); [url] (`ws:` or `wss:`,
/// placeholders allowed) wins over the configured `url`; [protocols] are
/// the subprotocols offered in the handshake.
///
/// Differs from Spring: Spring has no declarative WebSocket client. In
/// Spring you write a handler and run it with the imperative client:
/// ```java
/// WebSocketClient client = new StandardWebSocketClient();
/// client.execute(new TextWebSocketHandler() {
///   protected void handleTextMessage(WebSocketSession session, TextMessage message) { ... }
/// }, "wss://chat.neon.books/ws");
/// // or STOMP: new WebSocketStompClient(client).connectAsync(url, new StompSessionHandlerAdapter() { ... });
/// ```
/// This starter follows the `@FeignClient` style instead, so a socket is
/// an injectable interface with typed streams.
@InterfaceProxy(primary: true)
class WebSocketClient {
  /// A client named [name].
  const WebSocketClient(this.name, {this.url, this.protocols = const []});

  /// The client name (configuration key, logger name).
  final String name;

  /// The address, e.g. `wss://chat.neon.books/ws` or `${chat.url}`.
  final String? url;

  /// Subprotocols offered in the handshake (`Sec-WebSocket-Protocol`).
  final List<String> protocols;
}

/// Marks the method of a [WebSocketClient] that gives the incoming
/// messages: no parameters, returns `Stream<T>`. `String` gives text
/// messages as they are, `Uint8List` binary messages, any other type text
/// messages read as JSON (a message that cannot be read is an error event
/// on the stream, which goes on). Every call gives a new stream; all of
/// them see every message.
///
/// ```dart
/// @OnMessage()
/// Stream<ChatMessage> messages();
/// ```
///
/// On a `@WebSocketEndpoint` (server) class it marks the method handling
/// each message of a connection instead (see `WebSocketEndpoint`).
///
/// Spring (Java): no declarative counterpart; the closest is
/// `WebSocketHandler.handleMessage` or STOMP's `@SubscribeMapping`.
@BeanMethodAnnotation()
class OnMessage {
  /// Marks a method returning the incoming messages.
  const OnMessage();
}

/// Marks a method of a [WebSocketClient] that sends a message: one
/// parameter, returns `Future<void>`. A `String` is sent as a text
/// message, a `Uint8List` (or a `List<int>` parameter) as a binary one,
/// anything else as JSON text. Waits while the connection opens.
///
/// ```dart
/// @SendMessage()
/// Future<void> send(ChatMessage message);
/// ```
///
/// Spring (Java): no declarative counterpart; the closest is
/// `WebSocketSession.sendMessage` or STOMP's `StompSession.send`.
class SendMessage {
  /// Marks a method sending its argument.
  const SendMessage();
}
