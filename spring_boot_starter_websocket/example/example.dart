// In an application the starter is picked up automatically: add the
// dependency, describe the socket as below and run the generator (it
// writes the implementation of ChatSocket). main() talks to a WebSocket
// server through the transport the starter uses, without generated code.
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:spring_web_dart/io.dart';

@WebSocketClient('chat', url: r'${chat.url}')
abstract interface class ChatSocket {
  @OnMessage()
  Stream<ChatMessage> messages();

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

  void start() =>
      socket.messages().listen((m) => print('${m.from}: ${m.text}'));

  Future<void> say(String text) =>
      socket.send(ChatMessage(from: 'me', text: text));
}

Future<void> main() async {
  // A local echo server.
  final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final socket = await io.WebSocketTransformer.upgrade(request);
    socket.listen((message) => socket.add('echo: $message'));
  });

  final session = await IoWebSocketTransport().connect(
    Uri.parse('ws://127.0.0.1:${server.port}/ws'),
  );
  final reply = session.messages.first;
  session.sendMessage(jsonEncode({'from': 'me', 'text': 'hello'}));
  print(await reply); // echo: {"from":"me","text":"hello"}
  await session.close(CloseStatus.normal);
  await server.close(force: true);
}
