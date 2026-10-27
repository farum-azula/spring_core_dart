import 'package:neon_books_app/src/api/models.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';

/// The support chat, a WebSocket (`/ws/support`) described like a Feign
/// client: incoming messages as a stream, sending as a method. One
/// connection for both; it opens on the first listener and reconnects.
/// The server lets only logged-in users in: `SupportHandshake` adds the
/// session cookie to every handshake.
@WebSocketClient('support', url: r'${api.ws-url}/ws/support')
abstract interface class SupportSocket {
  @OnMessage()
  Stream<ChatMessage> messages();

  @SendMessage()
  Future<void> send(ChatMessage message);

  /// Closes the connection (on logout).
  Future<void> close();
}
