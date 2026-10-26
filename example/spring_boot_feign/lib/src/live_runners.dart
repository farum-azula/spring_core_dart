// Read a few events of a real event stream and talk to a real WebSocket
// echo server, through the injected clients. Runners go one after another,
// as in Spring Boot: each starts when the previous one's Future completes
// (BlogRunner first, see @Order).
import 'dart:async';

import 'package:spring_boot_feign_example/src/app.spring.dart';
import 'package:spring_boot_feign_example/src/echo_socket.dart';
import 'package:spring_boot_feign_example/src/models.dart';
import 'package:spring_boot_feign_example/src/wikimedia_client.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

/// Prints the next 5 edits on Wikimedia wikis, then stops listening (the
/// connection is closed).
@Component()
@Order(2)
@Log(topic: 'wikipedia')
class WikipediaRunner implements ApplicationRunner {
  WikipediaRunner(this.streams);

  final WikimediaStreams streams;

  @override
  Future<void> run(ApplicationArguments args) async {
    try {
      var count = 0;
      await for (final change in streams.recentChanges().timeout(
        const Duration(seconds: 30),
      )) {
        log.info(
          '${change.wiki} ${change.type}: "${change.title}" by ${change.user}'
          '${change.bot ? ' (bot)' : ''}',
        );
        if (++count == 5) {
          break; // cancels the subscription: the connection is closed
        }
      }
    } on TimeoutException {
      log.error('Wikimedia sent no event within 30 s');
    } on FeignException catch (error) {
      log.error('Wikimedia answered with an error: $error');
    }
  }
}

/// Sends two messages to the echo server and prints what comes back.
@Component()
@Order(3)
@Log(topic: 'echo')
class EchoRunner implements ApplicationRunner {
  EchoRunner(this.socket);

  final EchoSocket socket;

  @override
  Future<void> run(ApplicationArguments args) async {
    // Listen first (this opens the connection), then send. When the server
    // cannot be reached, this fails before the first send does: ignore()
    // keeps that from being an uncaught error (it is reported below).
    final replies = socket.messages().take(2).toList()..ignore();
    try {
      await socket.send(const ChatMessage(from: 'dart', text: 'hello'));
      await socket.send(const ChatMessage(from: 'dart', text: 'spring'));
      for (final reply in await replies.timeout(const Duration(seconds: 15))) {
        log.info('echo: ${reply.from} says "${reply.text}"');
      }
    } on TimeoutException {
      log.error('the echo server did not answer within 15 s');
    } on WebSocketException catch (error) {
      log.error('the echo server is not reachable: ${error.message}');
    }
  }
}
