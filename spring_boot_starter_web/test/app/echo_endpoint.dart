import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';

class Shout {
  const Shout(this.text);

  final String text;
}

@WebSocketEndpoint('/ws/echo/{name}')
class EchoEndpoint {
  @OnMessage()
  Shout echo(@PathVariable() String name, String text, Principal? user) =>
      Shout('$name: ${text.toUpperCase()}');
}
