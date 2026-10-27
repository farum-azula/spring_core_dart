// A declarative WebSocket client in a Spring Boot application: describe the
// socket, the generator writes its implementation and picks the starter up
// (example.spring.dart, from `dart run build_runner build`). Messages are
// JSON through the ObjectMapper; the connection opens on first use and
// closes with the application.
//
//   dart run example/example.dart

// The example shows its result on the console: printing is the point.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io' as io;

import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';

import 'example.spring.dart';

@WebSocketClient('chat', url: r'${chat.url}')
abstract interface class ChatSocket {
  /// Incoming messages, JSON → ChatMessage.
  @OnMessage()
  Stream<ChatMessage> messages();

  /// ChatMessage → JSON.
  @SendMessage()
  Future<void> send(ChatMessage message);
}

@Introspected()
class ChatMessage {
  const ChatMessage({required this.from, required this.text});
  final String from;
  final String text;
}

@Service()
class Chat {
  Chat(this.socket);
  final ChatSocket socket;

  /// Sends [text] and waits for the first message back.
  Future<ChatMessage> ask(String text) async {
    final reply = socket.messages().first;
    await socket.send(ChatMessage(from: 'me', text: text));
    return await reply;
  }
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  // A local echo server standing in for a real chat server.
  final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final socket = await io.WebSocketTransformer.upgrade(request);
    socket.listen(socket.add); // sends every message back
  });

  final context = springApplication.run(
    args,
    properties: {'chat.url': 'ws://127.0.0.1:${server.port}/ws'},
  );
  final reply = await context.getBean<Chat>().ask('hello');
  print('${reply.from}: ${reply.text}'); // me: hello

  await context.closeAsync(); // closes the socket
  await server.close(force: true);
}
