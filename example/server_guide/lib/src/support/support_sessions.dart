// The open support chats, for sending to one user or to the admins: the
// WebSocket starter's session registry holds the sessions per endpoint.
import 'package:neon_books_server/src/support/chat_message.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';

@Service()
class SupportSessions {
  SupportSessions(this._registry);

  final WebSocketSessionRegistry _registry;

  /// The path of `SupportEndpoint`.
  static const path = '/ws/support';

  /// Whether [user] (the user of a handshake) is an admin.
  static bool isAdmin(Principal? user) =>
      user is Authentication &&
      user.authorities.any((a) => a.authority == 'ROLE_ADMIN');

  /// Sends [message] to every chat of [user].
  void sendTo(String user, ChatMessage message) {
    for (final session in _registry.sessions(path)) {
      if (session.principal?.name == user) {
        session.sendJson(message);
      }
    }
  }

  /// Sends [message] to every admin's chat but [except].
  void sendToAdmins(ChatMessage message, {ServerWebSocketSession? except}) {
    for (final session in _registry.sessions(path)) {
      if (session != except && isAdmin(session.principal)) {
        session.sendJson(message);
      }
    }
  }

  /// Everyone in the chat.
  void broadcast(ChatMessage message) => _registry.broadcast(path, message);
}
