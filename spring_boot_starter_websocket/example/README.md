# spring_boot_starter_websocket: examples

This starter turns an abstract class annotated with `@WebSocketClient`
into a WebSocket client bean of a
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
application: one method gives the incoming messages as a typed stream,
another sends. You write the interface; the generator writes the
implementation.

[`example.dart`](example.dart) is a small Spring Boot application with a
chat client and a service using it. It starts a local echo server that
sends every message back, asks the service to send `hello`, and logs
the first message that comes back.

## Run it

```yaml
dependencies:
  spring_boot_starter_websocket: ^0.4.3

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.3   # required: writes the client implementations
```

From the package directory, generate the code, then run the example:

```bash
dart run build_runner build   # writes the ChatSocket implementation
dart run example/example.dart
```

After the startup log lines it logs, through the `example` logger:

```text
... example : me: hello
```

## What it shows

The socket is an interface. `@OnMessage` gives the incoming messages,
read from JSON; `@SendMessage` sends one, written as JSON:

```dart
@WebSocketClient('chat', url: r'${chat.url}')
abstract interface class ChatSocket {
  @OnMessage()
  Stream<ChatMessage> messages();

  @SendMessage()
  Future<void> send(ChatMessage message);
}

@Introspected()                       // read and written as JSON without fromJson / toJson
class ChatMessage {
  const ChatMessage({required this.from, required this.text});
  final String from;
  final String text;
}
```

The service gets the generated client injected. Listening to the
messages opens the connection; the send waits until it is open:

```dart
@Service()
class Chat {
  Chat(this.socket);
  final ChatSocket socket;

  // Sends text and waits for the first message back.
  Future<ChatMessage> ask(String text) async {
    final reply = socket.messages().first;   // listen before sending, so no message is missed
    await socket.send(ChatMessage(from: 'me', text: text));
    return await reply;
  }
}
```

The URL comes from the `chat.url` property; the example sets it at startup
to the address of its local server:

```dart
final context = springApplication.run(
  args,
  properties: {'chat.url': 'ws://127.0.0.1:${server.port}/ws'},
);
```

`await context.closeAsync()` at the end closes the socket along with the
application.

Reconnection, configuration, handshake tokens, server endpoints and
testing are in the package
[README](https://pub.dev/packages/spring_boot_starter_websocket).
