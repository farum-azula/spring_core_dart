import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Marks an abstract class as a WebSocket client: the application gets a
/// bean that implements it over one live connection to a server.
///
/// Use it when an app or a service talks to a WebSocket server, such as
/// a chat, live prices or notifications. Instead of handling raw frames,
/// you declare what you receive and what you send: methods marked
/// [OnMessage] give the incoming messages as a typed `Stream`, methods
/// marked [SendMessage] send one. An optional `Future<void> connect()`
/// opens the connection early and `Future<void> close()` closes it before
/// the application stops; any other method fails the start. The generator
/// writes the implementation (no reflection); messages that are not text
/// or bytes are read and written as JSON through the `ObjectMapper`. The
/// bean is named after the class (`chatSocket`).
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
/// @Log()
/// class Chat {
///   Chat(this.socket); // the generated client bean
///   final ChatSocket socket;
///
///   // Listening opens the connection; it reconnects while we listen.
///   void start() => socket.messages().listen(log.info);
///
///   Future<void> say(String text) =>
///       socket.send(ChatMessage(from: 'me', text: text));
/// }
/// ```
///
/// A client has one connection, shared by every stream and send. It opens
/// on the first listener, the first message sent or `connect()`. A lost
/// connection is opened again, with a growing wait, while someone
/// listens (`reconnect.*`). The application closes every connection when
/// it stops.
///
/// Differs from Spring: Spring has no declarative WebSocket client. In
/// Spring you write a handler and run it with the imperative client:
/// ```java
/// WebSocketClient client = new StandardWebSocketClient();
/// client.execute(new TextWebSocketHandler() {
///   protected void handleTextMessage(
///       WebSocketSession session, TextMessage message) { ... }
/// }, "wss://chat.neon.books/ws");
/// // or STOMP: new WebSocketStompClient(client).connectAsync(url, new StompSessionHandlerAdapter() { ... });
/// ```
/// This starter follows the `@FeignClient` style instead, so a socket is
/// an injectable interface with typed streams.
@InterfaceProxy(primary: true)
class WebSocketClient {
  /// A client named [name], connecting to [url] (or to the configured
  /// `url`) and offering [protocols].
  const WebSocketClient(this.name, {this.url, this.protocols = const []});

  /// The name of the client: its properties are
  /// `spring.websocket.client.config.<name>.*`, and a
  /// `WebSocketHandshakeInterceptor` sees it as
  /// `WebSocketHandshake.clientName`.
  final String name;

  /// The server's address, starting with `ws://` or `wss://`, such as
  /// `wss://chat.neon.books/ws`; `${...}` placeholders are resolved, as in
  /// `r'${chat.url}'`. When given, it wins over the configured `url`;
  /// without both, the start fails.
  final String? url;

  /// The subprotocols offered to the server in the handshake
  /// (`Sec-WebSocket-Protocol`); none by default.
  final List<String> protocols;
}

/// Marks the method that receives messages: on a [WebSocketClient], the
/// stream of incoming messages; on a server `@WebSocketEndpoint`, the
/// method called with each message of a connection.
///
/// On a client the method takes no parameters and returns `Stream<T>`.
/// `T` decides what the stream gives: `String` gives the text messages as
/// they are, `Uint8List` the binary messages, and any other type the text
/// messages read as JSON. Messages of the other kind are skipped. A
/// message that cannot be read is an error event (a
/// `MessageConversionException`) and the stream goes on. Every call gives
/// a new stream; all of them see every message. Listening opens the
/// connection.
///
/// ```dart
/// // In a @WebSocketClient: each server message as a ChatMessage.
/// @OnMessage()
/// Stream<ChatMessage> messages();
/// ```
///
/// On a server endpoint, see `WebSocketEndpoint` for the parameters and
/// the reply.
///
/// Spring (Java): no declarative counterpart; the closest is
/// `WebSocketHandler.handleMessage` or STOMP's `@SubscribeMapping`.
@BeanMethodAnnotation()
class OnMessage {
  /// Marks the method that receives messages.
  const OnMessage();
}

/// Marks a method of a [WebSocketClient] that sends its argument to the
/// server.
///
/// The method takes one parameter and returns `Future<void>`. A `String`
/// is sent as a text message, a `Uint8List` (or any value of a
/// `List<int>` parameter) as a binary one, anything else as JSON text.
/// When the connection is not open, the send opens it and waits; during
/// an outage it waits for the next reconnection attempt only and fails
/// if that attempt fails. A value that cannot be written as JSON throws a
/// `MessageConversionException`.
///
/// ```dart
/// // In a @WebSocketClient: a ChatMessage goes out as JSON.
/// @SendMessage()
/// Future<void> send(ChatMessage message);
/// ```
///
/// Spring (Java): no declarative counterpart; the closest is
/// `WebSocketSession.sendMessage` or STOMP's `StompSession.send`.
class SendMessage {
  /// Marks the method that sends its argument.
  const SendMessage();
}
