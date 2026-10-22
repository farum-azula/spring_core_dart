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
/// Re-exports `spring_boot_dart` and `spring_web_dart`.
library;

export 'package:spring_boot_dart/spring_boot_dart.dart';
export 'package:spring_web_dart/spring_web_dart.dart';

export 'src/web_socket_client.dart';
export 'src/web_socket_client_config.dart';
export 'src/web_socket_client_factory.dart';
export 'src/web_socket_handshake.dart';
export 'src/web_socket_invocation_handler.dart';
export 'src/web_socket_session.dart';
