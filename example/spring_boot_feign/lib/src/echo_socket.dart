// A declarative WebSocket client against a real public echo server
// (Postman's, wss://ws.postman-echo.com/raw): what is sent comes back.
// The generator writes the implementation; messages are JSON through the
// ObjectMapper; the connection opens on first use and is closed when the
// application stops.
//
// Spring (Java): no declarative WebSocket client — Spring uses
// WebSocketClient.execute(handler, url) or STOMP. @WebSocketClient is
// this project's own, in the style of @FeignClient.
import 'package:spring_boot_feign_example/src/models.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';

@WebSocketClient('echo', url: r'${echo.url}')
abstract interface class EchoSocket {
  /// Incoming messages, JSON → ChatMessage.
  @OnMessage()
  Stream<ChatMessage> messages();

  /// ChatMessage → JSON.
  @SendMessage()
  Future<void> send(ChatMessage message);
}
