# spring_boot_starter_websocket

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

WebSocket for
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
applications, both sides:

- **Clients:** describe a socket as an abstract class with `@OnMessage`
  and `@SendMessage` methods and inject it like any bean. Works on the VM,
  in Flutter (mobile, desktop, web) and in the browser.
- **Server endpoints:** a `@WebSocketEndpoint` bean with `@OnOpen`,
  `@OnMessage`, `@OnClose` methods, or Spring's `WebSocketHandler` with a
  `WebSocketConfigurer`, served by
  [`spring_boot_starter_web`](https://pub.dev/packages/spring_boot_starter_web)
  (see [Server endpoints](#server-endpoints)).

The generator writes the code (no reflection), messages go through the
`ObjectMapper` of `spring_core_dart` as JSON.

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

*In the guides:* [server, 5. WebSocket](https://github.com/farum-azula/spring_core_dart/tree/main/example/server_guide#5-websocket), [app, 6. Server access](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_guide#6-server-access).

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
supported yet. The connection is kept by a `WebSocketConnectionManager`
like Spring's, but unlike Spring's it reconnects (`reconnect.*`, named
after Spring 7's `RetryPolicy`).

## Setup

```yaml
dependencies:
  spring_boot_starter_websocket: ^0.4.1

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.1   # required: writes the client implementations
```

```bash
dart run build_runner build
```

The starter is found automatically: every abstract class with
`@WebSocketClient` in the scanned package becomes a bean, named after the
interface (`chatSocket`). One import is enough:
`package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart`
re-exports `spring_boot_dart`, `spring_web_dart` and
`spring_boot_starter_logging`. The starter is the only dependency an
application needs: it brings the others, logging included, like every
Spring Boot starter.

For server endpoints, list `spring_boot_starter_web` as well (it brings
the server; see [Server endpoints](#server-endpoints)). This starter does
not depend on it, so a Flutter app with clients only starts no server.

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
  after `reconnect.delay`, multiplied by `reconnect.multiplier` after each
  failure up to `reconnect.max-delay`, give or take `reconnect.jitter`;
  listeners stay subscribed. A send (or `connect()`) during the outage
  waits for the next attempt only and fails if it fails, so it never waits
  longer than the delay plus `connect-timeout`. The retries count on
  until a connection proves stable (it delivers a message, or stays open
  for `reconnect.max-delay`), so a server that accepts and closes at once
  still reaches `reconnect.max-retries`; after giving up, the next
  listener starts with every retry again, and once the last listener
  cancels no further attempt is made. A normal close by the server (1000) ends the streams; other
  codes (1008 policy violation, ...) end them with a `WebSocketException`.
  The connection is managed by a `WebSocketConnectionManager` (Spring's
  name), the open connection is a `WebSocketSession` of `spring_web_dart`.
- **Without listeners** a failed attempt fails the send at once.
- **Shutdown.** Connections are closed when the application stops;
  `closeAsync()` waits until they are.

## Configuration

`spring.websocket.client.config.<name>.*`, falling back to
`spring.websocket.client.config.default.*`:

| Property | Default | Meaning |
|---|---|---|
| `url` | — | The address when `@WebSocketClient` has no `url` |
| `connect-timeout` | `10s` | The longest a handshake may take |
| `reconnect.enabled` | `true` | Open lost connections again while someone listens (`true` / `false` in any case; other values fail the start) |
| `reconnect.delay` | `1s` | The wait before the first attempt |
| `reconnect.multiplier` | `2` | What each further wait is multiplied by (`1`: a fixed delay) |
| `reconnect.max-delay` | `30s` | The longest wait |
| `reconnect.jitter` | `0` | A random part added to or taken from each wait (scaled by the multiplier too; never below `delay` nor above `max-delay`) |
| `reconnect.max-retries` | none | Attempts in a row before giving up |
| `default-request-headers.<Name>` | — | Headers sent with every handshake (not in browsers); `a,b` or a YAML list gives several values; a client's header replaces `default`'s of the same name in any case |

```properties
spring.websocket.client.config.default.connect-timeout=5s
spring.websocket.client.config.chat.reconnect.delay=500ms
spring.websocket.client.config.chat.reconnect.jitter=100ms
spring.websocket.client.config.chat.reconnect.max-retries=10
```

The `reconnect.*` names are those of Spring Framework 7's `RetryPolicy`
(`delay`, `multiplier`, `maxDelay`, `jitter`, `maxRetries`), checked like
its builder (`delay` and `jitter` not negative, `multiplier` at least 1,
`max-delay` positive, `max-retries` not negative; a `delay` above
`max-delay` is allowed and waits `max-delay`;
otherwise the start fails), and the
waits are computed like its `ExponentialBackOff`; the defaults suit
reconnecting (a doubling delay, no limit) rather than `RetryPolicy`'s (a
fixed 1 s delay, 3 retries). The policy is `WebSocketClientConfig.reconnect`
(a `WebSocketReconnectPolicy`).

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

## Server endpoints

With [`spring_boot_starter_web`](../spring_boot_starter_web/README.md) in
the application's dependencies, the same starter serves WebSocket
endpoints on the web server's port. The handshake is an ordinary request:
it passes the web starter's filters (so a security filter authenticates
it like any other) before the endpoint takes it.

```yaml
dependencies:
  spring_boot_starter_web: ^0.4.1
  spring_boot_starter_websocket: ^0.4.1
```

### `@WebSocketEndpoint`

A bean whose methods handle the connections to a path, like Jakarta's
`@ServerEndpoint`:

```dart
@WebSocketEndpoint('/ws/rooms/{room}', allowedOrigins: ['https://chat.example'])
class ChatEndpoint {
  ChatEndpoint(this.sessions);
  final WebSocketSessionRegistry sessions;

  @OnOpen()
  void open(ServerWebSocketSession session, @PathVariable() String room) =>
      session.attributes['room'] = room;

  @OnMessage()
  Ack message(@PathVariable() String room, ChatMessage message) {
    sessions.broadcast('/ws/rooms/{room}', message);   // to every open session
    return Ack(room: room, received: message.text);     // sent back as JSON
  }

  @OnClose()
  void close(ServerWebSocketSession session, CloseStatus status) =>
      print('${session.id} left: ${status.code}');

  @OnError()
  void error(ServerWebSocketSession session, Object error) =>
      session.sendMessage('error: $error');
}
```

The methods take what they need, in any order:

| Parameter | Value |
|---|---|
| `ServerWebSocketSession` (or `WebSocketSession`) | the connection |
| `@PathVariable() String room` | a `{room}` of the path (`@PathVariable('id')` for another name) |
| `Principal?` | the user of the handshake (`null` when anonymous) |
| the message, in `@OnMessage` | `String` (text), `Uint8List` (binary), any other type read as JSON through the `ObjectMapper` |
| `CloseStatus`, in `@OnClose` | why the connection closed |
| the error, in `@OnError` | what a method threw, or the connection's error |

- What `@OnMessage` returns (a `Future` is awaited) is sent back: a
  `String` as text, bytes as binary, anything else as JSON; `void` and
  `null` send nothing. `@OnMessage` is the annotation the clients use;
  on a `@WebSocketEndpoint` class it marks the method handling each
  message.
- The messages of one connection are handled one after the other, in
  order.
- An exception goes to `@OnError` and the connection stays open; without
  an `@OnError` method it is logged and the connection is closed with
  1011 (server error).
- The path is a path pattern (`{room}`, `{*rest}`, like the controllers').
  A request to it that is not a WebSocket handshake is a 400.
- `protocols: ['chat.v2']` lists the sub-protocols the endpoint speaks;
  the first one the client offers (`Sec-WebSocket-Protocol`) is chosen.
- Checked at startup: two handlers for one path, an `@PathVariable` that
  is not in the path, a parameter that is none of the above, several
  `@OnMessage` methods, an endpoint without `@OnOpen`, `@OnMessage` or
  `@OnClose` stop the application with the list.

**Differs from Spring.** Spring has no annotated endpoint of its own: it
registers a `WebSocketHandler` (below), or Jakarta's `@ServerEndpoint`
classes through a `ServerEndpointExporter`. `@WebSocketEndpoint`,
`@OnOpen`, `@OnClose` and `@OnError` follow Jakarta's names, but the
endpoint is a singleton bean (Jakarta creates one per connection) with
constructor injection, and `@PathVariable` replaces `@PathParam`.

### `WebSocketHandler` and `WebSocketConfigurer`

Spring's style works too: a handler registered by a `WebSocketConfigurer`
bean, with handshake interceptors.

```dart
@Configuration()
class WsConfig implements WebSocketConfigurer {
  @override
  void registerWebSocketHandlers(WebSocketHandlerRegistry registry) => registry
      .addHandler(EchoHandler(), ['/ws/echo'])
      .setAllowedOrigins(['https://shop.example'])
      .setSupportedProtocols(['echo.v1'])
      .addInterceptors([TokenInterceptor()]);
}

final class EchoHandler extends TextWebSocketHandler {
  @override
  void handleTextMessage(ServerWebSocketSession session, String text) =>
      session.sendMessage('echo: $text (${session.attributes['token']})');
}

final class TokenInterceptor with HandshakeInterceptor {
  @override
  bool beforeHandshake(request, response, attributes) {
    final token = request.queryParameters['token']?.firstOrNull;
    if (token == null) return false;                  // 403
    attributes['token'] = token;                      // session.attributes
    return true;
  }
}
```

| Type | Spring | What |
|---|---|---|
| `WebSocketHandler` | `WebSocketHandler` | `afterConnectionEstablished`, `handleMessage` (`String` or `Uint8List`), `handleTransportError`, `afterConnectionClosed` |
| `AbstractWebSocketHandler`, `TextWebSocketHandler` | the same | text and binary apart; a binary message closes a `TextWebSocketHandler`'s connection (1003) |
| `WebSocketConfigurer`, `WebSocketHandlerRegistry` | the same | `addHandler(handler, paths)` then `setAllowedOrigins`, `setAllowedOriginPatterns`, `setSupportedProtocols`, `addInterceptors` |
| `HandshakeInterceptor` | the same | `beforeHandshake(request, response, attributes)`: `false` refuses (403 unless it answered); `afterHandshake(request, error)` |
| `ServerWebSocketSession` | server-side `WebSocketSession` | `id`, `handshakeHeaders`, `attributes`, `principal`, `pathVariables`, `sendMessage`, `sendJson`, `close`, `messages` |
| `WebSocketSessionRegistry` | (none) | the open sessions: `sessions([pattern])`, `broadcast(pattern, message)` (`null`: every endpoint) |
| `WebSocketHandlerMapping` | `WebSocketHandlerMapping` | maps the handshakes; the web starter's dispatcher asks it after the controllers |

### Origins

Like Spring: a browser connecting from the server's own origin is
accepted, one from another origin only when it is in `allowedOrigins`
(`'*'` for any) or matches `allowedOriginPatterns`
(`'https://*.example'`); others get a 403. A client that sends no
`Origin` (not a browser: an app, a server) is accepted. Authenticate
those with a filter or a `HandshakeInterceptor`.

### Broadcasting

`WebSocketSessionRegistry` (a bean) holds the open sessions per endpoint
path, as written on the endpoint; a session leaves it when it closes:

```dart
@Service()
class Announcer {
  Announcer(this.sessions);
  final WebSocketSessionRegistry sessions;

  void announce(Object news) => sessions.broadcast('/ws/news', news);  // JSON
}
```

## Testing

`MockWebSocketTransport` (from `spring_boot_starter_test`, the dev
dependency of the tests) plays the server:

```dart
final sockets = MockWebSocketTransport();
await const ApplicationContextRunner()
    .withUserConfiguration(appModule)
    .withAutoConfiguration(springBootAutoConfiguration)
    .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration)
    .withPropertyValues(['chat.url=ws://chat.test/ws'])
    .withBean<WebSocketTransport>(() => sockets)
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

### Server endpoints

`MockMvc.webSocket(path)` opens a connection to an endpoint in memory, through
the same filters and handshake, and returns the client's end:

```dart
final app = springBootTest(springApplication);

test('echoes', () async {
  final session = await app.mockMvc.webSocket('/ws/rooms/neon',
      headers: {'Origin': 'https://chat.example'});
  final replies = StreamIterator(session.messages);
  session.sendMessage('{"user": "ann", "text": "hi"}');
  expect(await replies.moveNext(), isTrue);
  expect(jsonDecode(replies.current as String), {'room': 'neon', 'received': 'hi'});
  await session.close();
});
```

A refused handshake (an origin, an interceptor) throws a
`WebSocketException` with the status. Over a real socket, start the server
on a free port and connect with the client transport:

```dart
final app = springBootTest(springApplication, webEnvironment: WebEnvironment.randomPort);

test('over a socket', () async {
  final session = await platformWebSocketTransport()
      .connect(Uri.parse('ws://127.0.0.1:${app.localServerPort}/ws/rooms/neon'));
  ...
});
```
