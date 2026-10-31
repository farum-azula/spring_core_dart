/// WebSocket connections for `spring_boot_dart` applications, on both
/// sides: typed clients that keep a live connection to a server, and
/// server endpoints that accept such connections.
///
/// - **Clients**, on the VM, in Flutter and in the browser: describe the
///   socket as an abstract class with `@WebSocketClient`, a `Stream<T>`
///   method with `@OnMessage` for the incoming messages and a
///   `Future<void>` method with `@SendMessage`, and inject it like any
///   bean. The generator writes the implementation; messages are read and
///   written as JSON through the `ObjectMapper`. The connection opens on
///   demand and reconnects after a loss, configured by
///   `spring.websocket.client.config.<name>.*`.
/// - **Server endpoints**, with `spring_boot_starter_web` as a dependency:
///   a `@WebSocketEndpoint` bean with `@OnOpen`, `@OnMessage`, `@OnClose`
///   and `@OnError` methods, or a `WebSocketHandler` registered by a
///   `WebSocketConfigurer`.
///
/// ```dart
/// // A chat client: the server's address comes from a property.
/// @WebSocketClient('chat', url: r'${chat.url}')
/// abstract interface class ChatSocket {
///   @OnMessage()
///   Stream<ChatMessage> messages();
///
///   @SendMessage()
///   Future<void> send(ChatMessage message);
/// }
/// ```
///
/// Differs from Spring: Spring's WebSocket client is imperative
/// (`WebSocketClient.execute(handler, url)`, STOMP's
/// `WebSocketStompClient`); there is no declarative interface client.
/// STOMP is not supported here.
///
/// Re-exports `spring_web_dart` and `spring_boot_starter_logging` (and
/// through it `spring_boot_dart` and `spring_core_dart`): the starter is the
/// only dependency an application lists.
library;

// Logging and spring_boot_dart (re-exported by the logging starter), so
// this starter is the only dependency an application needs.
export 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
export 'package:spring_web_dart/spring_web_dart.dart';

export 'src/server/web_socket_endpoint.dart';
export 'src/server/web_socket_handler.dart';
export 'src/server/web_socket_handler_mapping.dart';
export 'src/web_socket_client.dart';
export 'src/web_socket_client_config.dart';
export 'src/web_socket_client_factory.dart';
export 'src/web_socket_connection_manager.dart' hide redactText, redactUrl;
export 'src/web_socket_handshake.dart';
export 'src/web_socket_invocation_handler.dart';
