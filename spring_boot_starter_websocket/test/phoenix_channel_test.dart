import 'dart:async';

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_websocket/spring_auto_configuration.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:test/test.dart';

import 'chat.dart';
import 'phoenix_room.dart';
import 'phoenix_support.dart';

const _config = 'spring.websocket.client.config';

final class TokenJoinInterceptor implements PhoenixJoinInterceptor {
  int calls = 0;
  final joins = <String>[];

  @override
  Future<void> apply(PhoenixJoin join) async {
    joins.add('${join.clientName} ${join.topic}');
    join.payload['token'] = 't${++calls}';
  }
}

void main() {
  late MockWebSocketTransport sockets;
  late ApplicationContextRunner runner;

  setUp(() {
    sockets = MockWebSocketTransport();
    runner = const ApplicationContextRunner()
        .withUserConfiguration(roomModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration)
        .withPropertyValues([
          'chat.url=ws://chat.test/socket/websocket',
          'lobby.topic=lobby',
          '$_config.chat.reconnect.delay=10ms',
          '$_config.chat.reconnect.max-delay=40ms',
          '$_config.chat.phoenix.push-timeout=150ms',
        ])
        .withBean<WebSocketTransport>(() => sockets);
  });

  test('events: decoded to the declared type, the topic from the '
      'parameter, one connection for every topic', () async {
    await runner.runAsync((context) async {
      final room = context.getBean<Room>();
      final lobby = context.getBean<Lobby>();
      await pump();
      expect(sockets.connections, isEmpty, reason: 'nothing used yet');

      final messages = <ChatMessage>[];
      final errors = <Object>[];
      final raw = <Map<String, Object?>>[];
      final other = <ChatMessage>[];
      final ticks = <int>[];
      expect(room.messages('42'), isA<Stream<ChatMessage>>());
      room.messages('42').listen(messages.add, onError: errors.add);
      room.raw('42').listen(raw.add);
      room.messages('7').listen(other.add);
      lobby.ticks().listen(ticks.add);

      final server = await PhoenixServer.next(sockets);
      expect(server.socket.uri.queryParameters, {'vsn': '2.0.0'});
      final joins = [
        await server.acceptJoin(),
        await server.acceptJoin(),
        await server.acceptJoin(),
      ];
      expect(
        [for (final join in joins) join[2]],
        [
          'room:42',
          'room:7',
          'lobby',
        ],
      );
      expect(joins.first[4], isEmpty);
      server
        ..send('room:42', 'new_msg', {'from': 'ann', 'text': 'hi'})
        ..send('room:42', 'new_msg', {'nope': true})
        ..send('room:42', 'user_left', {'from': 'bob'})
        ..send('room:7', 'new_msg', {'from': 'bob', 'text': 'yo'})
        ..send('lobby', 'tick', 3);
      await pump();
      expect([for (final m in messages) '${m.from}: ${m.text}'], ['ann: hi']);
      expect(errors.single, isA<MessageConversionException>());
      expect(
        (errors.single as MessageConversionException).message,
        '{"nope":true}',
      );
      expect(raw, [
        {'from': 'ann', 'text': 'hi'},
        {'nope': true},
      ]);
      expect([for (final m in other) m.text], ['yo']);
      expect(ticks, [3]);
      expect(sockets.connections, hasLength(1), reason: 'one shared socket');
      expect(server.framesOf('phx_join'), hasLength(3));
    });
  });

  test('push: the payload as JSON, the reply read as the declared '
      'type', () async {
    await runner.runAsync((context) async {
      final room = context.getBean<Room>();
      final lobby = context.getBean<Lobby>();

      final sent = room.send('42', const ChatMessage(from: 'me', text: 'hi'));
      final server = await PhoenixServer.next(sockets);
      final join = await server.acceptJoin();
      expect(join[2], 'room:42');
      final push = await server.take('new_msg');
      expect(push[0], join[1]);
      expect(push[4], {'from': 'me', 'text': 'hi'});
      server.reply(push, response: {'id': 9});
      final ack = await sent;
      expect(ack, isA<Ack>());
      expect(ack.id, 9);

      // Future<void>: the reply is awaited, its response ignored.
      var seen = false;
      unawaited(room.seen('42', {'upTo': 9}).then((_) => seen = true));
      final seenPush = await server.take('seen');
      expect(seenPush[4], {'upTo': 9});
      await pump();
      expect(seen, isFalse);
      server.reply(seenPush, response: {'ignored': true});
      await pump();
      expect(seen, isTrue);
      expect(server.framesOf('phx_join'), hasLength(1), reason: 'joined once');

      // reply: false completes when sent.
      await room.typing('42');
      expect((await server.take('typing'))[4], isEmpty);

      // A list of objects, and a plain string.
      final history = room.history('42');
      server.reply(
        await server.take('history'),
        response: [
          {'from': 'ann', 'text': 'one'},
          {'from': 'bob', 'text': 'two'},
        ],
      );
      expect(await history, isA<List<ChatMessage>>());
      expect([for (final m in await history) m.text], ['one', 'two']);
      final ping = lobby.ping();
      final lobbyJoin = await server.acceptJoin();
      expect(lobbyJoin[2], 'lobby');
      server.reply(await server.take('ping'), response: 'pong');
      expect(await ping, 'pong');
    });
  });

  test('push failures: an error reply, no reply, a refused join, a '
      'payload that is no JSON', () async {
    await runner.runAsync((context) async {
      final room = context.getBean<Room>();
      final failed = room.send('42', const ChatMessage(from: 'me', text: ''));
      final server = await PhoenixServer.next(sockets);
      await server.acceptJoin();
      server.reply(
        await server.take('new_msg'),
        status: 'error',
        response: {'text': 'empty'},
      );
      await expectLater(
        failed,
        throwsA(
          isA<PhoenixPushException>().having(
            (e) => e.reply!.response,
            'response',
            {'text': 'empty'},
          ),
        ),
      );
      await expectLater(
        room.seen('42', {'upTo': 1}),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        room.seen('42', {'when': Object()}),
        throwsA(isA<MessageConversionException>()),
      );
      // The reply cannot be read as an Ack.
      final unread = room.send('42', const ChatMessage(from: 'a', text: 'b'));
      server.reply(await server.take('new_msg'), response: 'what');
      await expectLater(unread, throwsA(isA<MessageConversionException>()));

      final refused = room.send('7', const ChatMessage(from: 'a', text: 'b'));
      server.reply(
        await server.take('phx_join'),
        status: 'error',
        response: {'reason': 'unauthorized'},
      );
      await expectLater(refused, throwsA(isA<PhoenixJoinException>()));
    });
  });

  test('a topic is left when its last listener cancels, and by '
      'leave()', () async {
    await runner.runAsync((context) async {
      final room = context.getBean<Room>();
      final first = room.messages('42').listen(null);
      final second = room.raw('42').listen(null);
      var done = false;
      room.messages('7').listen(null, onDone: () => done = true);
      final server = await PhoenixServer.next(sockets);
      final join42 = await server.acceptJoin();
      await server.acceptJoin();

      await first.cancel();
      await pump();
      expect(server.framesOf('phx_leave'), isEmpty, reason: 'one listens');
      await second.cancel();
      final leave = await server.take('phx_leave');
      expect(leave[2], 'room:42');
      expect(leave[0], join42[1]);
      server.reply(leave);
      await pump();
      expect(server.socket.isClosed, isFalse, reason: 'room:7 is open');

      // Listening again joins again.
      final again = room.messages('42').listen(null);
      final rejoin = await server.acceptJoin();
      expect(rejoin[2], 'room:42');
      expect(rejoin[1], isNot(join42[1]));
      await again.cancel();
      server.reply(await server.take('phx_leave'));

      final left = room.leave('7');
      final leave7 = await server.take('phx_leave');
      expect(leave7[2], 'room:7');
      server.reply(leave7);
      await left;
      await pump();
      expect(done, isTrue, reason: 'leave() ends the streams');
      expect(server.socket.isClosed, isTrue);
      expect(server.socket.closedByClient, isTrue);
      await room.leave('nowhere'); // harmless
    });
  });

  test('@JoinPayload and the interceptors make the join payload, fresh '
      'on every join', () async {
    final interceptor = TokenJoinInterceptor();
    await runner.withBean<PhoenixJoinInterceptor>(() => interceptor).runAsync((
      context,
    ) async {
      final room = context.getBean<Room>();
      final lobby = context.getBean<Lobby>();
      final messages = <String>[];
      room
          .messagesSince('42', const RoomJoin(since: 100))
          .listen((message) => messages.add(message.text));
      final first = await PhoenixServer.next(sockets);
      final join = await first.acceptJoin();
      expect(join[2], 'room:42');
      expect(join[4], {'since': 100, 'token': 't1'});
      lobby.ticks().listen(null);
      expect((await first.acceptJoin())[4], {'token': 't2'});
      first.send('room:42', 'new_msg', {'from': 'ann', 'text': 'one'});
      await pump();

      await first.socket.drop();
      final second = await PhoenixServer.next(sockets);
      final rejoins = [
        await second.acceptJoin(),
        await second.acceptJoin(),
      ];
      final rejoin = rejoins.firstWhere((frame) => frame[2] == 'room:42');
      expect(rejoin[4], {
        'since': 100,
        'token': isIn(['t3', 't4']),
      });
      expect(rejoin[1], isNot(join[1]));
      second.send('room:42', 'new_msg', {'from': 'ann', 'text': 'two'});
      await pump();
      expect(messages, ['one', 'two']);
      expect(interceptor.joins.toSet(), {'chat room:42', 'chat lobby'});
      expect(interceptor.calls, 4);
    });
  });

  test('a refused join is an error event; the stream goes on and is '
      'joined later', () async {
    await runner.runAsync((context) async {
      final room = context.getBean<Room>();
      final messages = <String>[];
      final errors = <Object>[];
      room
          .messages('42')
          .listen((m) => messages.add(m.text), onError: errors.add);
      final server = await PhoenixServer.next(sockets);
      server.reply(
        await server.take('phx_join'),
        status: 'error',
        response: {'reason': 'busy'},
      );
      await pump();
      expect(errors.single, isA<PhoenixJoinException>());
      await server.acceptJoin();
      server.send('room:42', 'new_msg', {'from': 'ann', 'text': 'in'});
      await pump();
      expect(messages, ['in']);
    });
  });

  test('closing the context ends the streams and closes the '
      'connection', () async {
    late MockWebSocket server;
    var done = false;
    await runner.runAsync((context) async {
      final room = context.getBean<Room>();
      room.messages('42').listen(null, onDone: () => done = true);
      final phoenix = await PhoenixServer.next(sockets);
      await phoenix.acceptJoin();
      server = phoenix.socket;
    });
    await pump();
    expect(done, isTrue);
    expect(server.isClosed, isTrue);
    expect(server.closeStatus, CloseStatus.normal);
  });

  test('an invalid channel stops the application with every '
      'reason', () {
    const ApplicationContextRunner()
        .withUserConfiguration(brokenRoomModule(brokenRoomHandler))
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration)
        .withBean<WebSocketTransport>(() => sockets)
        .run((context) {
          final failure = '${context.startupFailure}';
          expect(failure, contains('Invalid Phoenix channel BrokenRoom'));
          expect(failure, contains('must start with ws:// or wss://'));
          expect(
            failure,
            contains('BrokenRoom.notAStream: an @OnEvent method'),
          );
          expect(
            failure,
            contains(
              'BrokenRoom.noTopicParameter: the topic "room:{id}" needs a '
              'parameter named id',
            ),
          );
          expect(failure, contains('BrokenRoom.twoPayloads: a @Push method'));
          expect(
            failure,
            contains('BrokenRoom.noReply: a @Push(reply: false) method'),
          );
          expect(
            failure,
            contains('BrokenRoom.both has both @OnEvent and @Push'),
          );
          expect(failure, contains('BrokenRoom.other: mark it @OnEvent'));
          expect(
            failure,
            contains('BrokenRoom.leave: leave takes only the parameters'),
          );
        });
  });

  test('an unknown vsn, a missing URL and an unresolved topic are '
      'reported', () {
    const ApplicationContextRunner()
        .withUserConfiguration(brokenRoomModule(oddLobbyHandler))
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration)
        .withBean<WebSocketTransport>(() => sockets)
        .run((context) {
          final failure = '${context.startupFailure}';
          expect(failure, contains('Invalid Phoenix channel OddLobby'));
          expect(failure, contains('no PhoenixSerializer for vsn "9.9.9"'));
          expect(failure, contains('known: 2.0.0, 1.0.0'));
        });
    const ApplicationContextRunner()
        .withUserConfiguration(roomModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration)
        .withBean<WebSocketTransport>(() => sockets)
        .run((context) {
          final failure = '${context.startupFailure}';
          expect(failure, contains('Invalid Phoenix channel'));
          expect(failure, contains('chat.url'));
        });
    const ApplicationContextRunner()
        .withUserConfiguration(roomModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration)
        .withPropertyValues(['chat.url=ws://chat.test/socket/websocket'])
        .withBean<WebSocketTransport>(() => sockets)
        .run((context) {
          final failure = '${context.startupFailure}';
          expect(failure, contains('Invalid Phoenix channel Lobby'));
          expect(failure, contains('cannot resolve the topic'));
        });
  });

  test('the vsn and the url of the properties are used when the '
      'annotation has none', () async {
    await runner
        .withPropertyValues(['$_config.chat.phoenix.vsn=1.0.0'])
        .runAsync((context) async {
          final lobby = context.getBean<Lobby>();
          lobby.ticks().listen(null);
          final server = await sockets.nextConnection;
          expect(server.uri.queryParameters['vsn'], '1.0.0');
          await pump();
          expect((server.sentJson.single! as Map)['event'], 'phx_join');
        });
  });
}
