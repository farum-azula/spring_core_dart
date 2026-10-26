import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';

class ChatMessage {
  const ChatMessage({required this.user, required this.text});

  final String user;
  final String text;
}

class Ack {
  const Ack({required this.room, required this.received});

  final String room;
  final String received;
}

@Service()
class ChatLog {
  final opened = <String>[];
  final closed = <int>[];
  final errors = <Object>[];
}

@WebSocketEndpoint('/ws/rooms/{room}', allowedOrigins: ['https://chat.example'])
class ChatEndpoint {
  ChatEndpoint(this.log, this.sessions);

  final ChatLog log;
  final WebSocketSessionRegistry sessions;

  @OnOpen()
  void open(ServerWebSocketSession session, @PathVariable() String room) {
    log.opened.add(room);
    session.attributes['room'] = room;
  }

  @OnMessage()
  Ack message(
    @PathVariable() String room,
    ChatMessage message,
    ServerWebSocketSession session,
  ) {
    if (message.text == 'fail') {
      throw StateError('failing on purpose');
    }
    sessions.broadcast('/ws/rooms/{room}', message);
    return Ack(room: room, received: message.text);
  }

  @OnClose()
  void close(CloseStatus status) => log.closed.add(status.code);

  @OnError()
  void error(ServerWebSocketSession session, Object error) {
    log.errors.add(error);
    session.sendMessage('error: $error');
  }
}

final class EchoHandler extends TextWebSocketHandler {
  @override
  void handleTextMessage(ServerWebSocketSession session, String message) {
    session.sendMessage('echo: $message (${session.attributes['token']})');
  }
}

final class TokenInterceptor with HandshakeInterceptor {
  @override
  bool beforeHandshake(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Map<String, Object?> attributes,
  ) {
    final token = request.queryParameters['token']?.firstOrNull;
    if (token == null) {
      return false;
    }
    attributes['token'] = token;
    return true;
  }
}

@Configuration()
class WsConfig implements WebSocketConfigurer {
  @override
  void registerWebSocketHandlers(WebSocketHandlerRegistry registry) => registry
      .addHandler(EchoHandler(), ['/ws/echo'])
      .addInterceptors([TokenInterceptor()]);
}
