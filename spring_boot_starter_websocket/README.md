# spring_boot_starter_websocket

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

WebSocket connections for
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
applications, on both sides of the connection.

A WebSocket is a connection that stays open, so the server can push
messages the moment something happens: a chat message, a price, a
notification. Handling one by hand means opening it, encoding and decoding
every frame, and opening it again when the network drops. This starter
does that work:

- **Clients:** describe a socket as an abstract class, with a method for
  the incoming messages (`@OnMessage`) and one for sending
  (`@SendMessage`), and inject it like any bean. The connection opens when
  first needed and reconnects after a loss. Works on the VM, in Flutter
  (mobile, desktop, web) and in the browser.
- **Server endpoints:** a `@WebSocketEndpoint` bean with `@OnOpen`,
  `@OnMessage` and `@OnClose` methods, or Spring's `WebSocketHandler` with
  a `WebSocketConfigurer`, served by
  [`spring_boot_starter_web`](https://pub.dev/packages/spring_boot_starter_web)
  (see [Server endpoints](#server-endpoints)).

The generator writes the code at build time, without reflection. Messages
are read and written as JSON through the `ObjectMapper` of
`spring_core_dart`.

## Install

```yaml
dependencies:
  spring_boot_starter_websocket: ^0.4.3

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.3   # required: writes the client implementations
```

```bash
dart run build_runner build
```

Listing the starter is enough: every abstract class with
`@WebSocketClient` in the scanned package becomes a bean, named after the
interface (`ChatSocket` → `chatSocket`).

One import is enough:
`package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart`
re-exports `spring_boot_dart`, `spring_web_dart` and
`spring_boot_starter_logging`. The starter is the only dependency an
application needs: it brings the others, logging included, as every
Spring Boot starter does.

For server endpoints, list `spring_boot_starter_web` as well; it brings
the server (see [Server endpoints](#server-endpoints)). This starter does
not depend on it, so a Flutter app that only has clients starts no
server.

## A first client

A chat app receives and sends chat messages:

```dart
@WebSocketClient('chat', url: r'${chat.url}')
abstract interface class ChatSocket {
  @OnMessage()
  Stream<ChatMessage> messages();         // incoming messages, read from JSON

  @SendMessage()
  Future<void> send(ChatMessage message); // sent as JSON
}

@Introspected()                            // read and written as JSON without fromJson / toJson
class ChatMessage {
  const ChatMessage({required this.from, required this.text});
  final String from;
  final String text;
}

@Service()
@Log()
class Chat {
  Chat(this.socket);                       // the generated client, injected like any bean
  final ChatSocket socket;

  // Listening opens the connection; it reconnects while someone listens.
  void start() => socket.messages().listen((m) => log.info('${m.from}: ${m.text}'));

  Future<void> say(String text) => socket.send(ChatMessage(from: 'me', text: text));
}
```

```properties
# lib/resources/application.properties
chat.url=wss://chat.neon.books/ws
```

*In the guides:* [server, 5. WebSocket](https://github.com/farum-azula/spring_core_dart/tree/main/example/server_guide#5-websocket), [app, 6. Server access](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_guide#6-server-access).

### Compared with Spring

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
`@WebSocketClient`, `@OnMessage`, `@SendMessage`,
`WebSocketHandshakeInterceptor`, the `spring.websocket.client.config.*`
properties and `spring.websocket.client.max-text-message-size` /
`max-binary-message-size` are this project's own; Spring has nothing with
these names.
STOMP is not supported yet. The connection is kept by a
`WebSocketConnectionManager`, as in Spring, but unlike Spring's it
reconnects (`reconnect.*`, named after Spring 7's `RetryPolicy`).

## Client methods

A client interface has these kinds of methods:

| Method | What it does |
|---|---|
| `@OnMessage() Stream<T> name()` | The incoming messages. `T` decides what the stream gives: `String` gives the text messages as they are, `Uint8List` the binary messages, any other type the text messages read as JSON. Messages of the other kind are skipped. A message that cannot be read arrives as an error event (`MessageConversionException`), and the stream goes on. Every call gives a new stream; all streams see every message. |
| `@SendMessage() Future<void> name(T message)` | Sends a message: a `String` as text, a `Uint8List` (or the value of a `List<int>` parameter) as binary, anything else as JSON text. Waits while the connection opens. |
| `Future<void> connect()` | Optional. Opens the connection now instead of on first use. |
| `Future<void> close()` | Optional. Closes the connection early (code 1000), for example on logout or when a screen goes away. The streams are done; using the client again opens a new connection. Not needed for shutdown: the application closes every connection when it stops. |

Any other method stops the application at startup with the reason. So
does a missing URL, or one that does not start with `ws://` or `wss://`.

A value a `@SendMessage` method cannot write as JSON throws a
`MessageConversionException` from the call itself, before a `Future` is
returned, rather than failing the returned `Future`.

## The connection

- **One per client.** All streams and sends of a client share one
  connection.
- **On demand.** It opens on the first listener of an `@OnMessage`
  stream, on the first message sent, or on `connect()`.
- **Reconnection while someone listens.** A connection that was lost
  (closed with no code, 1001, 1005, 1006 or 1011–1014, or dropped by the
  client with 4500, see [Transport](#transport)), or an attempt that
  failed, is opened again after a wait. The first wait is
  `reconnect.delay`; each further one is multiplied by
  `reconnect.multiplier`, up to `reconnect.max-delay`, give or take
  `reconnect.jitter`. Listeners stay subscribed meanwhile.
- **Sends during an outage.** A send (or `connect()`) waits for the next
  attempt only, and fails if that attempt fails, so it never waits longer
  than the delay plus `connect-timeout`. With listeners, reconnecting goes
  on after such a failure; without any, nothing more is tried.
- **When it gives up.** The retries keep counting until a connection
  proves stable, meaning it delivers a message or stays open for
  `reconnect.max-delay`. So a server that accepts and closes at once still
  reaches `reconnect.max-retries`. After giving up, the streams end with
  the last error; the next listener starts again with every retry. Once
  the last listener cancels, no further attempt is made.
- **Closed by the server.** A normal close (1000) ends the streams. Other
  codes (1008 policy violation, ...) end them with a
  `WebSocketException`.
- **Shutdown.** Connections are closed when the application stops;
  `closeAsync()` waits until they are.

The connection is managed by a `WebSocketConnectionManager`; the open
connection is a `WebSocketSession` of `spring_web_dart`.

## Configuration

Each client is configured under `spring.websocket.client.config.<name>.*`,
where `<name>` is the client's name. What a client does not set falls back
to `spring.websocket.client.config.default.*`.

```properties
spring.websocket.client.config.default.connect-timeout=5s
spring.websocket.client.config.chat.reconnect.delay=500ms
spring.websocket.client.config.chat.reconnect.jitter=100ms
spring.websocket.client.config.chat.reconnect.max-retries=10
```

| Property | Default | Meaning |
|---|---|---|
| `url` | — | the address when `@WebSocketClient` has no `url` (`${...}` placeholders allowed) |
| `connect-timeout` | `10s` | the longest a handshake may take |
| `reconnect.enabled` | `true` | open lost connections again while someone listens. `true` / `false` in any case (also `on` / `off`, `yes` / `no`, `1` / `0`); another value fails the start |
| `reconnect.delay` | `1s` | the wait before the first attempt |
| `reconnect.multiplier` | `2` | what each further wait is multiplied by (`1`: a fixed delay) |
| `reconnect.max-delay` | `30s` | the longest wait |
| `reconnect.jitter` | `0` | a random part added to or taken from each wait. It grows with the multiplier like the wait does, and the wait never goes below `delay` nor above `max-delay` |
| `reconnect.max-retries` | none | how many attempts in a row before giving up |
| `default-request-headers.<Name>` | — | headers sent with every handshake (not possible in browsers). `a,b` or a YAML list gives several values. A client's header replaces the `default` one of the same name, in any case |

The `reconnect.*` names are those of Spring Framework 7's `RetryPolicy`
(`delay`, `multiplier`, `maxDelay`, `jitter`, `maxRetries`), and the
values are checked as its builder checks them: `delay` and `jitter` not
negative, `multiplier` at least 1, `max-delay` positive, `max-retries` not
negative. A `delay` above `max-delay` is allowed and waits `max-delay`.
Anything else fails the start with an error naming the property; a
`multiplier` or `max-retries` that is not a number fails with a plain
`FormatException` that does not name it. The waits are computed as by
Spring's `ExponentialBackOff`. The defaults suit reconnecting (a doubling
delay, no limit) rather than `RetryPolicy`'s (a fixed 1 s delay, 3
retries). In code, the policy is `WebSocketClientConfig.reconnect`, a
`WebSocketReconnectPolicy`.

## Tokens: handshake interceptors

Servers usually want to know who connects. A
`WebSocketHandshakeInterceptor` bean changes the handshake of every
connection and every reconnection before it is sent, so a token that
expired in the meantime is replaced by a fresh one:

```dart
// The chat server wants the user's current token.
@Component()
class ChatAuth implements WebSocketHandshakeInterceptor {
  ChatAuth(this.tokens);
  final TokenStore tokens;

  @override
  Future<void> apply(WebSocketHandshake handshake) async {
    if (handshake.clientName == 'chat') {   // other clients are left alone
      handshake.queryParameter('token', await tokens.current());
      // VM and mobile only: handshake.headers.set('Authorization', 'Bearer ...');
    }
  }
}
```

An interceptor that throws fails that connection attempt.

**Flutter web and browsers** cannot send headers with a WebSocket
handshake; a header there fails with a `WebSocketException`. Put tokens
in the URL (`queryParameter`) or in a subprotocol (`handshake.protocols`)
instead. The client's log lines and the messages of the exceptions it
passes on show every query value and user information as `***`
(`ws://chat.test/ws?token=***`); the original error stays in the
exception's `cause`.

## Transport

The `webSocketTransport` bean opens the connections. By default it is
`platformWebSocketTransport()`: `IoWebSocketTransport` (`dart:io`) on the
VM and in Flutter mobile and desktop, `BrowserWebSocketTransport` on the
web. Declare your own `WebSocketTransport` bean to replace it, as tests do
with a mock.

On `dart:io`, what a client sends waits in memory while the server does
not take it. As Spring's `ConcurrentWebSocketSessionDecorator` does, the
connection is dropped (4500) when more than 512 KB wait or what was sent
has not left within 10 seconds; the client then reconnects as after any
broken connection, such as a server that resets it (1006). Declare an
`IoWebSocketTransport(sendBufferSizeLimit: ..., sendTimeLimit: ...)`
bean for other limits. A `@SendMessage` method completes when the
message is queued, not when it has left.

A message from the server larger than 8 KB (text or binary, Tomcat's
default in Spring) is not read: the connection is closed with 1009
(message too big), and the streams end with a `WebSocketException`. The
text limit counts UTF-8 bytes, where Tomcat counts characters. Raise the
limits with these properties (`-1`: no limit; the browser has none),
this starter's own keys, since Spring sets the limits in code, on the
client's `WebSocketContainer` (`setDefaultMaxTextMessageBufferSize`):

```properties
spring.websocket.client.max-text-message-size=1MB
spring.websocket.client.max-binary-message-size=-1
```

No extension is offered (no permessage-deflate). A handshake answer that
picks a subprotocol the client did not offer, or any extension, fails
the connection (RFC 6455), and redirects are not followed, as in
browsers.

## Server endpoints

With [`spring_boot_starter_web`](../spring_boot_starter_web/README.md) in
the application's dependencies, the same starter serves WebSocket
endpoints on the web server's port. The handshake is an ordinary HTTP
request: it passes the web starter's filters, so a security filter
authenticates it like any other, before the endpoint takes it.

```yaml
dependencies:
  spring_boot_starter_web: ^0.4.3
  spring_boot_starter_websocket: ^0.4.3
```

### `@WebSocketEndpoint`

A `@WebSocketEndpoint` bean accepts the connections to a path. Its
methods are called when a connection opens, for each message, when it
closes, and on errors. The annotation follows the names of Jakarta's
`@ServerEndpoint`.

```dart
// A chat with one room per path: /ws/rooms/neon, /ws/rooms/dart, ...
@WebSocketEndpoint('/ws/rooms/{room}', allowedOrigins: ['https://chat.example'])
@Log()
class ChatEndpoint {
  ChatEndpoint(this.sessions);
  final WebSocketSessionRegistry sessions;

  // The endpoint is shared by all connections: per-connection state
  // goes in session.attributes.
  @OnOpen()
  void open(ServerWebSocketSession session, @PathVariable() String room) =>
      session.attributes['room'] = room;

  @OnMessage()
  Ack message(@PathVariable() String room, ChatMessage message) {
    sessions.broadcast('/ws/rooms/{room}', message);   // to every open session of the endpoint
    return Ack(room: room, received: message.text);     // the reply, sent back as JSON
  }

  @OnClose()
  void close(ServerWebSocketSession session, CloseStatus status) =>
      log.info('${session.id} left: ${status.code}');

  @OnError()
  void error(ServerWebSocketSession session, Object error) =>
      session.sendMessage('error: $error');
}

@Introspected()
class Ack {
  const Ack({required this.room, required this.received});
  final String room;
  final String received;
}
```

The methods take what they need, in any order:

| Parameter | Value |
|---|---|
| `ServerWebSocketSession` (or `WebSocketSession`) | the connection |
| `@PathVariable() String room` | a `{room}` of the path (`@PathVariable('id')` for another name); an `int`, `double`, `bool`, enum, ... is converted by the `ConversionService`, as on controllers, and a value that does not convert answers the handshake with 400 |
| `Principal?` | the user of the handshake (`null` when anonymous) |
| the message, in `@OnMessage` | `String` (text), `Uint8List` (binary), or any other type, read as JSON through the `ObjectMapper` |
| `CloseStatus`, in `@OnClose` | why the connection closed |
| the error, in `@OnError` | what a method threw, or the connection's error |

- What `@OnMessage` returns is sent back, after awaiting a `Future`: a
  `String` as text, bytes as binary, anything else as JSON. `void` and
  `null` send nothing. `@OnMessage` is the same annotation the clients
  use; on a `@WebSocketEndpoint` class it marks the method that handles
  each message.
- The messages of one connection are handled one after the other, in
  order. While one is handled the connection is not read, so a client
  that sends faster than the handler works is held back by the network
  instead of filling the server's memory. A message larger than the web
  starter's `server.websocket.max-text-message-size` or
  `max-binary-message-size` (8 KB by default, as Tomcat's) closes the
  connection with 1009 (message too big).
- What is sent to a client that reads slowly or not at all waits in
  memory up to the web starter's `server.websocket.send-buffer-size-limit`
  (512 KB) and `send-time-limit` (10 s); past either, the connection is
  dropped and `@OnClose` gets 4500 (`CloseStatus.sessionNotReliable`),
  as with Spring's `ConcurrentWebSocketSessionDecorator`. A client that
  goes away meanwhile (a reset) gets the session closed with 1006
  (`CloseStatus.noCloseFrame`) and the error as the reason, over TLS
  too; after `session.close(status)`, `@OnClose` gets that `status`.
  Either way the session leaves `WebSocketSessionRegistry`.
- An exception goes to the `@OnError` method, and the connection stays
  open. Without an `@OnError` method, it is logged and the connection is
  closed with 1011 (server error). This holds for `@OnOpen` too, and
  `@OnOpen` (or `afterConnectionEstablished`) may close the session
  itself to turn a client away: `@OnClose` then gets the status, once,
  and the session leaves `WebSocketSessionRegistry`. Messages the
  client sent before it saw the close may still reach `@OnMessage`;
  check `session.isOpen` there. Anything else that fails
  for a connection is logged to `spring.websocket.server` and closes it
  with 1011; it never ends the process.
- The path is a path pattern, as on controllers (`{room}`, `{*rest}`). A
  request to it that is not a WebSocket handshake gets a 400 in plain
  text, as from Spring's handshake handler; the web starter's server
  answers a repeated or malformed `Sec-WebSocket-Key` with a 400 problem
  and another `Sec-WebSocket-Version` with a 426.
- Each session has a random id in the form of a UUID
  (`session.id`), as in Spring.
- `protocols: ['chat.v2']` lists the subprotocols the endpoint speaks.
  The first one the client offers (`Sec-WebSocket-Protocol`) that is in
  the list is chosen; a client offering none of them still connects,
  without a protocol.
- Checked at startup: two handlers for one path, a `@PathVariable` that is
  not in the path or of a type nothing converts a String to, a parameter
  of none of the kinds above, several methods with the same annotation,
  or an endpoint without any of `@OnOpen`, `@OnMessage` and `@OnClose`
  stops the application with the list of problems.

**This differs from Spring.** Spring has no annotated endpoint of its
own: it registers a `WebSocketHandler` (below), or Jakarta's
`@ServerEndpoint` classes through a `ServerEndpointExporter`.
`@WebSocketEndpoint`, `@OnOpen`, `@OnClose` and `@OnError` follow
Jakarta's names, but the endpoint is a singleton bean with constructor
injection (Jakarta creates one per connection), and `@PathVariable`
replaces `@PathParam`.

### `WebSocketHandler` and `WebSocketConfigurer`

Spring's lower-level style works too: a handler object, registered for
paths by a `WebSocketConfigurer` bean, with handshake interceptors. Use it
when you port Spring code, or when one handler serves several paths.

```dart
// The echo handler answers on /ws/echo, for the shop's pages only.
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

// Only clients with a token connect; the handler finds it in
// session.attributes['token'].
final class TokenInterceptor with HandshakeInterceptor {
  @override
  bool beforeHandshake(request, response, attributes) {
    final token = request.queryParameters['token']?.firstOrNull;
    if (token == null) return false;                  // 403
    attributes['token'] = token;                      // becomes session.attributes
    return true;
  }
}
```

| Type | Spring | What |
|---|---|---|
| `WebSocketHandler` | `WebSocketHandler` | `afterConnectionEstablished`, `handleMessage` (`String` or `Uint8List`), `handleTransportError`, `afterConnectionClosed` |
| `AbstractWebSocketHandler`, `TextWebSocketHandler` | the same | text and binary messages in separate methods; a binary message closes a `TextWebSocketHandler`'s connection (1003) |
| `WebSocketConfigurer`, `WebSocketHandlerRegistry` | the same | `addHandler(handler, paths)`, then `setAllowedOrigins`, `setAllowedOriginPatterns`, `setSupportedProtocols`, `addInterceptors` |
| `HandshakeInterceptor` | the same | `beforeHandshake(request, response, attributes)`: `false` refuses (403, unless it answered itself); `afterHandshake(request, error)` |
| `ServerWebSocketSession` | server-side `WebSocketSession` | `id`, `handshakeHeaders`, `attributes`, `principal`, `pathVariables`, `sendMessage`, `sendJson`, `close`; its incoming messages go to `handleMessage` (the server reads its `messages` stream itself, which can be listened to only once) |
| `WebSocketSessionRegistry` | (none) | the open sessions: `sessions([pattern])`, `broadcast(pattern, message)` (`null`: every endpoint) |
| `WebSocketHandlerMapping` | `WebSocketHandlerMapping` | maps the handshakes; the web starter's dispatcher asks it after the controllers |

Differences from Spring:

- An error a handler method throws goes to `handleTransportError`, and
  the connection stays open unless the handler closes it. Spring closes
  the connection with 1011 (server error).
  `AbstractWebSocketHandler.handleTransportError` does nothing, so with
  it such errors are ignored: override it to log or close.
- `setAllowedOrigins`, `setAllowedOriginPatterns` and
  `setSupportedProtocols` add to the values set before; Spring's replace
  them.
- `HandshakeInterceptor`s apply to the handlers of a configurer only, not
  to `@WebSocketEndpoint`s; a web filter covers both.
- No `@EnableWebSocket` is needed.

### Origins

Browsers send an `Origin` header, and a page from another site must not
be able to open a connection with the user's cookies. As in Spring's
`OriginHandshakeInterceptor`, a browser connecting from the server's
own origin (the same scheme, host and port, a missing port being the
scheme's default) is accepted; one from another origin only when
Spring's `CorsConfiguration` rules allow it. Others get a 403. The rules
are those of the web starter's CORS (`AllowedOrigins` of
`spring_web_dart` decides for both):

- `allowedOrigins` / `setAllowedOrigins` are whole origins, compared
  without case (`'https://chat.example'`); `'*'` allows any.
- `allowedOriginPatterns` / `setAllowedOriginPatterns` are compared with
  case: `*` matches any text, as Spring's `.*`
  (`'https://*.chat.example'` takes `https://eu.chat.example`, not
  `https://chat.example`; `'*.chat.example'` takes any scheme), and a
  port list at the end takes the ports listed
  (`'http://localhost:[3000,3001]'`) or, with `[*]`, any port or none
  (`'http://localhost:[*]'` takes `http://localhost` too).
- A value may list several, separated by commas
  (`'https://a.example, https://b.example'`), and a trailing `/` is
  ignored, in the values and in the `Origin` header.

Differences from Spring, none for what browsers send: an `Origin`
longer than 1024 characters gets a 403 whatever the rules (a real one is
under 300, and the match takes time that grows with the length); the
server's own origin is
recognized whatever the case of its host (Spring compares hosts with
case; browsers send them in lower case); an `Origin` that is not a URL
(`http://localhost:3000.evil.example`) gets a 403 (Spring fails the
handshake with a 500). A client
that sends no `Origin` (not a browser: an app, a server) is accepted;
authenticate those with a filter or a `HandshakeInterceptor`.

The endpoint's origins alone decide: the web starter's `addCorsMappings`
rules and `@CrossOrigin` are the controllers', and do not apply to a
handshake, with or without the security starter (its CORS filter asks
the handler mappings in order, as Spring's `HandlerMappingIntrospector`,
and sees that this starter's mapping takes the handshake). Only a
`CorsConfigurationSource` bean named `corsConfigurationSource` with rules
for the endpoint's path is checked too, by the security starter's
filter, as Spring Security checks it.

### Broadcasting

`WebSocketSessionRegistry` is a bean that holds the open sessions per
endpoint path, written as on the endpoint (`/ws/rooms/{room}`, not
`/ws/rooms/neon`). A session joins when its handshake succeeds and leaves
when it closes. Spring has no counterpart; a Spring application keeps
such a list itself.

```dart
// Every client of /ws/news gets the announcement.
@Service()
class Announcer {
  Announcer(this.sessions);
  final WebSocketSessionRegistry sessions;

  void announce(Object news) => sessions.broadcast('/ws/news', news);  // as JSON
}
```

`broadcast` sends a `String` as text, bytes as binary and anything else as
JSON, and skips a session that closed meanwhile.

## Testing

### Clients

`MockWebSocketTransport` plays the server: the test reads what the client
sent, pushes messages, and drops the connection to check reconnection. It
comes with `spring_boot_starter_test`, the tests' dev dependency:

```dart
final sockets = MockWebSocketTransport();
final app = springBootTest(
  springApplication,
  overrides: [BeanOverride<WebSocketTransport>(sockets)],
  properties: {'chat.url': 'ws://chat.test/ws'},
);

test('chats', () async {
  final chat = app.getBean<ChatSocket>();
  final messages = <ChatMessage>[];
  chat.messages().listen(messages.add);              // opens the connection

  final server = await sockets.nextConnection;
  server.pushJson({'from': 'ann', 'text': 'hi'});    // server → client
  await chat.send(const ChatMessage(from: 'me', text: 'hello'));
  expect(server.sentJson, [{'from': 'me', 'text': 'hello'}]);

  await server.drop();                               // the connection is lost...
  await sockets.nextConnection;                      // ...and the client reconnects
});
```

With an `ApplicationContextRunner`, register the mock with
`.withBean<WebSocketTransport>(() => sockets)`.

### Server endpoints

`MockMvc.webSocket(path)` opens a connection to an endpoint in memory,
through the same filters and handshake, and returns the client's end:

```dart
final app = springBootTest(springApplication);

test('acknowledges a message', () async {
  final session = await app.mockMvc.webSocket('/ws/rooms/neon',
      headers: {'Origin': 'https://chat.example'});
  final replies = StreamIterator(session.messages);
  session.sendMessage('{"from": "ann", "text": "hi"}');
  // First the broadcast to the room, which includes this session...
  expect(await replies.moveNext(), isTrue);
  expect(jsonDecode(replies.current as String), {'from': 'ann', 'text': 'hi'});
  // ...then the reply of @OnMessage.
  expect(await replies.moveNext(), isTrue);
  expect(jsonDecode(replies.current as String), {'room': 'neon', 'received': 'hi'});
  await session.close();
});
```

A refused handshake (by the origin check or an interceptor) throws a
`WebSocketException` with the status. To test over a real socket, start
the server on a free port and connect with the client transport:

```dart
final app = springBootTest(springApplication, webEnvironment: WebEnvironment.randomPort);

test('over a socket', () async {
  final session = await platformWebSocketTransport()
      .connect(Uri.parse('ws://127.0.0.1:${app.localServerPort}/ws/rooms/neon'));
  ...
});
```
