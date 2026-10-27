// WebSocket handshakes pass the security chain (docs/security.md, "What is
// protected"): an anonymous or unauthorized handshake is refused before the
// endpoint is opened, and an accepted connection keeps the handshake's user
// for its messages.
import 'dart:async';

import 'package:spring_boot_starter_security/spring_auto_configuration.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_security/testing.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_websocket/spring_auto_configuration.dart';
import 'package:test/test.dart';

import 'app/socket/socket.dart';
import 'support.dart';

Future<void> _withSocketApp(Future<void> Function(MockMvc mvc) body) =>
    const ApplicationContextRunner()
        .withUserConfiguration(socketSecurityBeans)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterLoggingAutoConfiguration)
        .withAutoConfiguration(springBootStarterWebAutoConfiguration)
        .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration)
        .withAutoConfiguration(springSecurityCoreAutoConfiguration)
        .withAutoConfiguration(springBootStarterSecurityAutoConfiguration)
        .withPropertyValues([
          'spring.test.web-environment=mock',
          'logging.level.root=warn',
        ])
        .runAsync((started) async {
          final failure = started.startupFailure;
          if (failure != null) {
            fail('The application failed to start: $failure');
          }
          await body(MockMvc.of(started.context));
        });

Future<String> _ask(WebSocketSession session) async {
  final replies = StreamIterator(session.messages);
  session.sendMessage('who?');
  expect(await replies.moveNext(), isTrue);
  await session.close();
  return replies.current as String;
}

void main() {
  test('an anonymous handshake is refused with 401', () async {
    await _withSocketApp((mvc) async {
      await expectLater(
        mvc.webSocket('/ws/whoami'),
        throwsA(isA<Object>().having((e) => '$e', 'error', contains('401'))),
      );
    });
  });

  test('a handshake without the role is refused with 403', () async {
    await _withSocketApp((mvc) async {
      await expectLater(
        mvc.webSocket('/ws/whoami', headers: basic('bob', 'bob-pw')),
        throwsA(isA<Object>().having((e) => '$e', 'error', contains('403'))),
      );
    });
  });

  test('wrong credentials are refused with 401', () async {
    await _withSocketApp((mvc) async {
      await expectLater(
        mvc.webSocket('/ws/whoami', headers: basic('ada', 'wrong')),
        throwsA(isA<Object>().having((e) => '$e', 'error', contains('401'))),
      );
    });
  });

  test("an accepted connection keeps the handshake's user", () async {
    await _withSocketApp((mvc) async {
      final session = await mvc.webSocket(
        '/ws/whoami',
        headers: basic('ada', 'ada-pw'),
      );
      expect(await _ask(session), 'ada / ada');
    });
  });

  test('user() from the test support works for handshakes', () async {
    await _withSocketApp((mvc) async {
      final session = await mvc.webSocket(
        '/ws/whoami',
        postProcessors: [user('ada')],
      );
      expect(await _ask(session), 'ada / ada');
    });
  });
}
