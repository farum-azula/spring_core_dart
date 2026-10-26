/// Declarative WebSocket clients for `spring_boot_dart`: annotate an
/// abstract class with `@WebSocketClient`, a `Stream<T>` method with
/// `@OnMessage` and a `Future<void>` method with `@SendMessage`; inject it
/// like any bean. The generator writes the implementation; messages go
/// through the `ObjectMapper` as JSON.
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
/// ```
///
/// Differs from Spring: Spring's WebSocket client is imperative
/// (`WebSocketClient.execute(handler, url)`, STOMP's
/// `WebSocketStompClient`); there is no declarative interface client.
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
export 'src/web_socket_connection_manager.dart';
export 'src/web_socket_handshake.dart';
export 'src/web_socket_invocation_handler.dart';
