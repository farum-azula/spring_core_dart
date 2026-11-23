// Where the WebSocket annotations go: an endpoint's handlers in a @WebSocketEndpoint, a client's methods in its interface; elsewhere the build fails, naming what to change.
import 'package:test/test.dart';

import '../support/placements.dart';

void main() {
  group('misplaced', () {
    misplacedCases({
      '@OnMessage in a component': (
        '@Component() class Chat { @OnMessage() Stream<String> m() => '
            'Stream.empty(); }',
        ['@OnMessage on Chat.m: Chat is no @WebSocketEndpoint'],
      ),
      '@OnOpen in a controller': (
        '@RestController() class C { @OnOpen() void o(WebSocketSession s) {} }',
        ['@OnOpen on C.o: C is no @WebSocketEndpoint'],
      ),
      '@SendMessage in a class': (
        '@Component() class C { @SendMessage() void s(String m) {} }',
        ['@SendMessage on C.s: C is no @WebSocketClient or @PhoenixChannel'],
      ),
    });
  });

  group('@JoinPayload', () {
    misplacedCases({
      'on a parameter of a component method': (
        '@Component() class A { void m(@JoinPayload() String x) {} }',
        ['@JoinPayload on parameter x of A.m'],
      ),
    });
  });
}
