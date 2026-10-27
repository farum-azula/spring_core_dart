// Chapter 5, the support chat: a @WebSocketEndpoint opened in memory with
// MockMvc.webSocket, through the same filters (the security chain checks
// the handshake) as a real connection.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:neon_books_server/src/orders/order_service.dart';
import 'package:spring_boot_starter_security/testing.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

import 'support/app.dart';

/// The client's end of a chat, reading JSON messages one by one.
final class Chat {
  Chat._(this.session) : _messages = StreamIterator(session.messages);

  final WebSocketSession session;
  final StreamIterator<Object> _messages;

  static Future<Chat> open(
    MockMvc mvc,
    String name, {
    List<String> roles = const ['USER'],
    Map<String, String> headers = const {},
  }) async => Chat._(
    await mvc.webSocket(
      '/ws/support',
      headers: headers,
      postProcessors: [user(name).roles(roles)],
    ),
  );

  void say(String text) => session.sendMessage(jsonEncode({'text': text}));

  Future<Map<String, Object?>> next() async {
    if (!await _messages.moveNext().timeout(const Duration(seconds: 5))) {
      throw StateError('the chat closed');
    }
    return jsonDecode(_messages.current as String) as Map<String, Object?>;
  }

  Future<void> close() => session.close();
}

void main() {
  final app = neonBooks();

  test('the bot greets and answers, in the language asked for', () async {
    final ada = await Chat.open(app.mockMvc, 'ada');
    expect(await ada.next(), containsPair('from', 'NEON Books'));
    ada.say('How long does delivery take?');
    final answer = await ada.next();
    expect(answer['text'], 'Books are delivered within 2 days.');
    expect(DateTime.parse(answer['at']! as String), isA<DateTime>());
    await ada.close();

    final japanese = await Chat.open(
      app.mockMvc,
      'ada',
      headers: {'Accept-Language': 'ja'},
    );
    expect((await japanese.next())['text'], startsWith('adaさん、こんにちは。'));
    await japanese.close();
  });

  test('admins see what customers write and answer with @name', () async {
    final root = await Chat.open(app.mockMvc, 'root', roles: ['USER', 'ADMIN']);
    await root.next(); // the greeting
    final ada = await Chat.open(app.mockMvc, 'ada');
    await ada.next();

    ada.say('Is Dune in stock?');
    // The session registry broadcast: the user of the handshake is the
    // sender, whatever the client says.
    expect(await root.next(), containsPair('from', 'ada'));
    expect(await ada.next(), containsPair('from', 'NEON Books')); // the bot

    root.say('@ada Yes, 5 copies.');
    expect(await ada.next(), {
      'from': 'root',
      'text': 'Yes, 5 copies.',
      'at': isA<String>(),
    });
    await ada.close();
    await root.close();
  });

  test('@OnError: a message that is not JSON, the chat goes on', () async {
    final ada = await Chat.open(app.mockMvc, 'ada');
    await ada.next();
    ada.session.sendMessage('not json');
    expect((await ada.next())['text'], contains('could not be read'));
    ada.say('hours?');
    expect((await ada.next())['text'], 'We are open from 9:00 to 21:00.');
    await ada.close();
  });

  test('the handshake needs a login (the security chain)', () async {
    await expectLater(
      app.mockMvc.webSocket('/ws/support'),
      throwsA(isA<WebSocketException>()),
    );
  });

  test("a shipped order is announced in the customer's chat", () async {
    final ada = await Chat.open(app.mockMvc, 'ada');
    await ada.next();
    await withMockUser(
      () => app.getBean<OrderService>().place('ada', {'9780547928227': 1}),
      username: 'ada',
    );
    // neon.orders.shipping-delay=50ms in the test profile.
    expect((await ada.next())['text'], matches(r'Your order \d+ has shipped'));
    await ada.close();
  });
}
