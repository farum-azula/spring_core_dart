# spring_boot_starter_websocket

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

Declarative WebSocket clients for
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
applications: describe a socket as an abstract class with `@OnMessage` and
`@SendMessage` methods and inject it like any bean. The generator writes
the implementation (no reflection), messages go through the `ObjectMapper`
of `spring_core_dart` as JSON. Works on the VM, in Flutter (mobile,
desktop, web) and in the browser.

```dart
@WebSocketClient('chat', url: r'${chat.url}')
abstract interface class ChatSocket {
  @OnMessage()
  Stream<ChatMessage> messages();       // incoming messages, JSON → ChatMessage

  @SendMessage()
  Future<void> send(ChatMessage message); // ChatMessage → JSON
}

@Introspected()                          // JSON without fromJson / toJson
class ChatMessage {
  const ChatMessage({required this.from, required this.text});
  final String from;
  final String text;
}

@Service()
class Chat {
  Chat(this.socket);                     // injected like any bean
  final ChatSocket socket;

  void start() => socket.messages().listen((m) => print('${m.from}: ${m.text}'));

  Future<void> say(String text) => socket.send(ChatMessage(from: 'me', text: text));
}
```

```properties
# lib/resources/application.properties
chat.url=wss://chat.neon.books/ws
```

## Differs from Spring

Spring has **no declarative WebSocket client**. In Spring you write a
handler and hand it to the imperative client, or use STOMP:

```java
WebSocketClient client = new StandardWebSocketClient();
client.execute(new TextWebSocketHandler() {
  @Override
  protected void handleTextMessage(WebSocketSession session, TextMessage message) {
    ChatMessage chat = objectMapper.readValue(message.getPayload(), ChatMessage.class);
  }
}, "wss://chat.neon.books/ws");

// or STOMP
WebSocketStompClient stomp = new WebSocketStompClient(client);
stomp.connectAsync(url, new StompSessionHandlerAdapter() { ... });
```

This starter follows the style of `@FeignClient` instead: the socket is an
interface with typed streams, created and configured by the container.
`@WebSocketClient`, `@OnMessage`, `@SendMessage`, `WebSocketHandshakeInterceptor`
and the `spring.websocket.client.config.*` properties are this project's
own; they have no Spring counterpart with the same names. STOMP is not
supported yet.

## Setup

```yaml
dependencies:
  spring_boot_dart: ^0.1.0
  spring_boot_starter_websocket: ^0.1.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.1.0   # required: writes the client implementations
```

```bash
dart run build_runner build
```

The starter is found automatically: every abstract class with
`@WebSocketClient` in the scanned package becomes a bean, named after the
interface (`chatSocket`). One import is enough:
`package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart`
re-exports `spring_boot_dart` and `spring_web_dart`.

## Methods

| Method | What it does |
|---|---|
| `@OnMessage() Stream<T> name()` | The incoming messages. `String`: text messages as they are; `Uint8List`: binary messages; any other type: text messages read as JSON. A message that cannot be read is an error event (`MessageConversionException`) and the stream goes on. Every call gives a new stream; all streams see every message. |
| `@SendMessage() Future<void> name(T message)` | Sends a message: `String` as text, `Uint8List` (or a `List<int>` parameter) as binary, anything else as JSON text. Waits while the connection opens. |
| `Future<void> connect()` | Opens the connection now (optional: it opens on demand). |
| `Future<void> close()` | Optional. Closes the connection early (code 1000), e.g. on logout or when a screen goes away; the streams are done, using the client again opens a new connection. Not needed for shutdown: the application closes every connection when it stops. |

Any other method stops the application at startup with the reason, as do
a missing URL or one that does not start with `ws://` / `wss://`.

## The connection

- **One per client.** All streams and sends of a client share one
  connection.
- **On demand.** It opens on the first listener of an `@OnMessage` stream
  or the first message sent (or `connect()`).
- **Reconnection.** While someone listens, a lost connection (close codes
  none, 1001, 1005, 1006, 1011–1014) or a failed attempt is opened again
  after `reconnect-delay`, doubled after each failure up to
  `max-reconnect-delay`; listeners stay subscribed. Sends during the
  outage wait for the new connection. A normal close by the server (1000)
  ends the streams; other codes (1008 policy violation, ...) end them with
  a `WebSocketException`.
- **Without listeners** a failed attempt fails the send at once.
- **Shutdown.** Connections are closed when the application stops.

## Configuration

`spring.websocket.client.config.<name>.*`, falling back to
`spring.websocket.client.config.default.*`:

| Property | Default | Meaning |
|---|---|---|
| `url` | — | The address when `@WebSocketClient` has no `url` |
| `connect-timeout` | `10s` | The longest a handshake may take |
| `reconnect` | `true` | Open lost connections again while someone listens |
| `reconnect-delay` | `1s` | The first wait before reconnecting (doubled after each failure) |
| `max-reconnect-delay` | `30s` | The longest wait |
| `max-attempts` | none | Failed attempts in a row before giving up |
| `default-request-headers.<Name>` | — | Headers sent with every handshake (not in browsers) |

```properties
spring.websocket.client.config.default.connect-timeout=5s
spring.websocket.client.config.chat.reconnect-delay=500ms
spring.websocket.client.config.chat.max-attempts=10
```

## Tokens: handshake interceptors

A `WebSocketHandshakeInterceptor` bean changes every handshake — each
connection and reconnection, so a fresh token is used:

```dart
@Component()
class ChatAuth implements WebSocketHandshakeInterceptor {
  ChatAuth(this.tokens);
  final TokenStore tokens;

  @override
  Future<void> apply(WebSocketHandshake handshake) async {
    if (handshake.clientName == 'chat') {
      handshake.queryParameter('token', await tokens.current());
      // VM and mobile only: handshake.headers.set('Authorization', 'Bearer ...');
    }
  }
}
```

**Flutter web and browsers** cannot send headers with a WebSocket
handshake (a header there fails with a `WebSocketException`): put tokens
in the URL (`queryParameter`) or a protocol (`handshake.protocols`).

## Transport

The `webSocketTransport` bean is `platformWebSocketTransport()`:
`IoWebSocketTransport` (`dart:io`) on the VM and in Flutter mobile and
desktop, `BrowserWebSocketTransport` on the web. Declare your own
`WebSocketTransport` bean to replace it.

## Testing

`MockWebSocketTransport` (`package:spring_web_dart/testing.dart`) plays
the server:

```dart
final sockets = MockWebSocketTransport();
await const ApplicationContextRunner()
    .withUserConfiguration(appModule)
    .withAutoConfiguration(springBootAutoConfiguration)
    .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration)
    .withPropertyValues(['chat.url=ws://chat.test/ws'])
    .withBean<WebSocketTransport>(sockets)
    .runAsync((context) async {
      final chat = context.getBean<ChatSocket>();
      final messages = <ChatMessage>[];
      chat.messages().listen(messages.add);

      final server = await sockets.nextConnection;
      server.pushJson({'from': 'ann', 'text': 'hi'}); // server → client
      await chat.send(const ChatMessage(from: 'me', text: 'hello'));
      expect(server.sentJson, [{'from': 'me', 'text': 'hello'}]);

      await server.drop();                            // the client reconnects
      await sockets.nextConnection;
    });
```

With `springBootTest`, override the bean with
`BeanOverride<WebSocketTransport>(sockets)`.
