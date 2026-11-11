import 'dart:async';

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_websocket/spring_auto_configuration.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:test/test.dart';

import 'phoenix_support.dart';

const _ms = Duration(milliseconds: 1);
const _config = 'spring.websocket.client.config';

void main() {
  late MockWebSocketTransport sockets;
  final opened = <PhoenixSocket>[];

  PhoenixSocket socketOf({
    Duration heartbeat = Duration.zero,
    Duration pushTimeout = const Duration(milliseconds: 150),
    PhoenixSerializer serializer = const PhoenixSerializerV2(),
    PhoenixParameters? parameters,
  }) {
    final socket = PhoenixSocket(
      name: 'chat',
      url: Uri.parse('ws://chat.test/socket/websocket'),
      transport: sockets,
      serializer: serializer,
      parameters: parameters,
      config: WebSocketClientConfig(
        reconnect: WebSocketReconnectPolicy(
          delay: _ms * 10,
          maxDelay: _ms * 40,
        ),
        phoenix: PhoenixSocketConfig(
          heartbeatInterval: heartbeat,
          pushTimeout: pushTimeout,
        ),
      ),
    );
    opened.add(socket);
    return socket;
  }

  setUp(() => sockets = MockWebSocketTransport());

  tearDown(() async {
    for (final socket in opened) {
      await socket.dispose();
    }
    opened.clear();
  });

  group('serializers', () {
    const message = PhoenixMessage(
      topic: 'room:42',
      event: 'new_msg',
      payload: {
        'body': 'hi',
        'tags': [1, 2],
      },
      ref: '7',
      joinRef: '3',
    );

    void expectSame(PhoenixMessage actual, PhoenixMessage expected) {
      expect(actual.topic, expected.topic);
      expect(actual.event, expected.event);
      expect(actual.payload, expected.payload);
      expect(actual.ref, expected.ref);
      expect(actual.joinRef, expected.joinRef);
    }

    test('V1: a JSON object, vsn 1.0.0', () {
      const serializer = PhoenixSerializerV1();
      expect(serializer.vsn, '1.0.0');
      final frame = serializer.encode(message);
      expect(
        frame,
        '{"topic":"room:42","event":"new_msg",'
        '"payload":{"body":"hi","tags":[1,2]},"ref":"7","join_ref":"3"}',
      );
      expectSame(serializer.decode(frame), message);
      // A reply of a server: no join_ref at all.
      final reply = serializer.decode(
        '{"topic":"room:42","event":"phx_reply","ref":"7",'
        '"payload":{"status":"ok","response":{}}}',
      );
      expect(reply.joinRef, isNull);
      expect(reply.ref, '7');
      expect(() => serializer.decode('[1,2]'), throwsFormatException);
      expect(() => serializer.decode('nope'), throwsFormatException);
    });

    test('V2: a JSON array, vsn 2.0.0', () {
      const serializer = PhoenixSerializerV2();
      expect(serializer.vsn, '2.0.0');
      final frame = serializer.encode(message);
      expect(
        frame,
        '["3","7","room:42","new_msg",{"body":"hi","tags":[1,2]}]',
      );
      expectSame(serializer.decode(frame), message);
      const broadcast = PhoenixMessage(topic: 'lobby', event: 'tick');
      expect(serializer.encode(broadcast), '[null,null,"lobby","tick",null]');
      expectSame(
        serializer.decode(serializer.encode(broadcast)),
        broadcast,
      );
      expect(() => serializer.decode('{"topic":"x"}'), throwsFormatException);
      expect(() => serializer.decode('[1,2,3]'), throwsFormatException);
    });

    test('a reply payload is read as status and response', () {
      final ok = PhoenixReply.of({
        'status': 'ok',
        'response': {'id': 1},
      });
      expect(ok.isOk, isTrue);
      expect(ok.response, {'id': 1});
      final odd = PhoenixReply.of('what');
      expect(odd.isOk, isFalse);
      expect(odd.response, 'what');
    });
  });

  group('join', () {
    test('ok: connects with vsn and parameters, completes with the '
        'response', () async {
      final socket = socketOf(parameters: () => {'token': 't1'});
      final room = socket.channel('room:42', payload: () => {'since': 100});
      final states = <PhoenixChannelState>[];
      room.states.listen(states.add);
      expect(room.state, PhoenixChannelState.closed);
      await pump();
      expect(sockets.connections, isEmpty, reason: 'nothing joined yet');

      final joined = room.join();
      expect(room.state, PhoenixChannelState.joining);
      final server = await PhoenixServer.next(sockets);
      expect(server.socket.uri.path, '/socket/websocket');
      expect(server.socket.uri.queryParameters, {
        'vsn': '2.0.0',
        'token': 't1',
      });
      final join = await server.take('phx_join');
      expect(join, [
        '1',
        '1',
        'room:42',
        'phx_join',
        {'since': 100},
      ]);
      server.reply(join, response: {'welcome': true});
      expect(await joined, {'welcome': true});
      expect(room.state, PhoenixChannelState.joined);
      expect(room.joinRef, '1');
      expect(await room.join(), {'welcome': true}, reason: 'joined already');
      await pump();
      expect(states, [
        PhoenixChannelState.joining,
        PhoenixChannelState.joined,
      ]);
      expect(server.framesOf('phx_join'), hasLength(1));
      expect(socket.channels, [room]);
    });

    test('error: fails with the reply, then joins again with the '
        "socket's backoff", () async {
      final socket = socketOf();
      final room = socket.channel('room:42');
      final failure = room.join().then<Object?>(
        (_) => null,
        onError: (Object error) => error,
      );
      final server = await PhoenixServer.next(sockets);
      final first = await server.take('phx_join');
      server.reply(
        first,
        status: 'error',
        response: {'reason': 'unauthorized'},
      );
      final failed = await failure;
      expect(failed, isA<PhoenixJoinException>());
      final error = failed! as PhoenixJoinException;
      expect(error.topic, 'room:42');
      expect(error.isTimeout, isFalse);
      expect(error.reply!.response, {'reason': 'unauthorized'});
      expect(room.state, PhoenixChannelState.errored);

      // It goes on trying: the next join waits for that outcome.
      final again = room.join();
      final second = await server.take('phx_join');
      expect(second[1], isNot(first[1]), reason: 'a new ref');
      expect(second[0], second[1]);
      server.reply(second);
      expect(await again, isEmpty);
      expect(room.state, PhoenixChannelState.joined);
    });

    test('timeout: fails, tells the server to leave, joins again', () async {
      final socket = socketOf(pushTimeout: _ms * 30);
      final room = socket.channel('room:42');
      final failure = room.join().then<Object?>(
        (_) => null,
        onError: (Object error) => error,
      );
      final server = await PhoenixServer.next(sockets);
      final first = await server.take('phx_join');
      final error = await failure;
      expect(error, isA<PhoenixJoinException>());
      expect((error! as PhoenixJoinException).isTimeout, isTrue);
      final leave = await server.take('phx_leave');
      expect(leave[0], first[1], reason: 'the leave of the join timed out');
      final second = await server.take('phx_join');
      // A late reply to the first join is not taken for the second.
      server.reply(first);
      await pump();
      expect(room.state, PhoenixChannelState.joining);
      server.reply(second);
      await pump();
      expect(room.state, PhoenixChannelState.joined);
      expect(room.joinRef, second[1]);
    });

    test('a failing join payload fails the join, which is tried '
        'again', () async {
      final socket = socketOf();
      var calls = 0;
      final room = socket.channel(
        'room:42',
        payload: () => ++calls == 1 ? throw StateError('no token') : {'n': 2},
      );
      final failure = room.join().then<Object?>(
        (_) => null,
        onError: (Object error) => error,
      );
      final server = await PhoenixServer.next(sockets);
      final error = await failure;
      expect(error, isA<PhoenixJoinException>());
      expect((error! as PhoenixJoinException).cause, isA<StateError>());
      final join = await server.acceptJoin();
      expect(join[4], {'n': 2});
      expect(room.state, PhoenixChannelState.joined);
    });
  });

  test('join while the server cannot be reached: it times out, and joins '
      'once the connection opens', () async {
    final socket = socketOf(pushTimeout: _ms * 25);
    final room = socket.channel('room:42');
    sockets
      ..failNextConnect()
      ..failNextConnect()
      ..failNextConnect();
    final failure = await room.join().then<Object?>(
      (_) => null,
      onError: (Object error) => error,
    );
    expect(failure, isA<PhoenixJoinException>());
    expect((failure! as PhoenixJoinException).isTimeout, isTrue);
    expect(sockets.connections, isEmpty);
    expect(room.state, PhoenixChannelState.joining);
    final server = await PhoenixServer.next(sockets);
    await server.acceptJoin(response: {'late': true});
    expect(room.state, PhoenixChannelState.joined);
    expect(await room.join(), {'late': true});
    expect(server.framesOf('phx_join'), hasLength(1));
  });

  group('WebSocketConnectionManager', () {
    test('connectionChanges tells every open and loss; reconnect() drops '
        'the connection and opens a new one', () async {
      final manager = WebSocketConnectionManager(
        clientName: 'chat',
        url: Uri.parse('ws://chat.test/ws'),
        config: WebSocketClientConfig(
          reconnect: WebSocketReconnectPolicy(delay: _ms * 10),
        ),
        transport: sockets,
        log: const SpringLog('websocket.test'),
      );
      final changes = <bool>[];
      manager.connectionChanges.listen(changes.add);
      await pump();
      expect(sockets.connections, isEmpty, reason: 'listening opens nothing');
      manager.reconnect(); // nothing to drop
      final texts = <Object>[];
      manager.messages().listen(texts.add);
      final first = await sockets.nextConnection;
      await pump();
      expect(changes, [true]);

      manager.reconnect('no pong');
      expect(manager.isConnected, isFalse);
      expect(changes, [true, false]);
      expect(first.closeStatus!.code, CloseStatus.normal.code);
      expect(first.closeStatus!.reason, 'no pong');
      final second = await sockets.nextConnection;
      second.push('again');
      await pump();
      expect(texts, ['again'], reason: 'the listener is kept');
      expect(changes, [true, false, true]);

      await second.drop();
      await pump();
      expect(changes, [true, false, true, false]);
      await sockets.nextConnection;
      await pump();
      await manager.close();
      expect(changes, [true, false, true, false, true, false]);
      await manager.dispose();
    });

    test('reconnect() without a listener ends there', () async {
      final manager = WebSocketConnectionManager(
        clientName: 'chat',
        url: Uri.parse('ws://chat.test/ws'),
        config: const WebSocketClientConfig(),
        transport: sockets,
        log: const SpringLog('websocket.test'),
      );
      await manager.connect();
      manager.reconnect();
      await Future<void>.delayed(_ms * 20);
      expect(sockets.connections, hasLength(1));
      expect(manager.isConnected, isFalse);
      await manager.dispose();
    });
  });

  group('push', () {
    late PhoenixSocket socket;
    late PhoenixChannelSession room;
    late PhoenixServer server;
    late List<Object?> join;

    Future<void> joinRoom({
      Duration pushTimeout = const Duration(milliseconds: 150),
    }) async {
      socket = socketOf(pushTimeout: pushTimeout);
      room = socket.channel('room:42');
      final joined = room.join();
      server = await PhoenixServer.next(sockets);
      join = await server.acceptJoin();
      await joined;
    }

    test('ok: the reply matched by ref, with the join_ref', () async {
      await joinRoom();
      final first = room.push('new_msg', {'body': 'one'});
      final second = room.push('new_msg', {'body': 'two'});
      final one = await server.take('new_msg');
      final two = await server.take('new_msg');
      expect(one, [
        join[1],
        isNot(join[1]),
        'room:42',
        'new_msg',
        {'body': 'one'},
      ]);
      expect(two[1], isNot(one[1]));
      // Answered in the other order.
      server
        ..reply(two, response: {'id': 2})
        ..reply(one, response: {'id': 1});
      expect((await first).response, {'id': 1});
      final reply = await second;
      expect(reply.status, 'ok');
      expect(reply.response, {'id': 2});
    });

    test('error: a PhoenixPushException with the reply', () async {
      await joinRoom();
      final pushed = room.push('new_msg', {'body': ''});
      server.reply(
        await server.take('new_msg'),
        status: 'error',
        response: {'body': 'empty'},
      );
      await expectLater(
        pushed,
        throwsA(
          isA<PhoenixPushException>()
              .having((e) => e.event, 'event', 'new_msg')
              .having((e) => e.reply!.response, 'response', {'body': 'empty'}),
        ),
      );
    });

    test('timeout: a TimeoutException, by the socket or the call', () async {
      await joinRoom(pushTimeout: _ms * 30);
      final watch = Stopwatch()..start();
      await expectLater(
        room.push('slow', null),
        throwsA(isA<TimeoutException>()),
      );
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(25));
      await expectLater(
        room.push('slow', null, timeout: _ms * 5),
        throwsA(isA<TimeoutException>()),
      );
      // A null payload is sent as an empty object.
      expect((await server.take('slow'))[4], isEmpty);
      // The reply after the timeout is ignored.
      server.reply(await server.take('slow'));
      await pump();
    });

    test('made while joining: sent after the join succeeded', () async {
      socket = socketOf();
      room = socket.channel('room:42');
      final joined = room.join();
      final pushed = room.push('new_msg', {'body': 'early'});
      final sent = room.send('typing', {'user': 'ann'});
      server = await PhoenixServer.next(sockets);
      join = await server.take('phx_join');
      await pump(20);
      expect(server.frames, hasLength(1), reason: 'only the join so far');
      server.reply(join);
      await joined;
      final push = await server.take('new_msg');
      expect(push[0], join[1]);
      expect(push[4], {'body': 'early'});
      await sent;
      final typing = server.framesOf('typing').single;
      expect(typing[4], {'user': 'ann'});
      server.reply(push);
      expect((await pushed).isOk, isTrue);
    });

    test('before join and after leave: a StateError', () async {
      socket = socketOf();
      room = socket.channel('room:42');
      await expectLater(room.push('x', null), throwsStateError);
      await expectLater(room.send('x'), throwsStateError);
      await room.leave();
      await expectLater(room.push('x', null), throwsStateError);
      await expectLater(room.join(), throwsStateError);
      expect(sockets.connections, isEmpty);
    });
  });

  group('heartbeat', () {
    test('sent on the interval; replies keep the connection', () async {
      final socket = socketOf(heartbeat: _ms * 20);
      final joined = socket.channel('room:42').join();
      final server = await PhoenixServer.next(sockets);
      await server.acceptJoin();
      await joined;
      for (var i = 0; i < 3; i++) {
        final beat = await server.take('heartbeat');
        expect(beat, [null, isA<String>(), 'phoenix', 'heartbeat', isEmpty]);
        server.reply(beat);
      }
      expect(sockets.connections, hasLength(1));
      expect(server.socket.isClosed, isFalse);
      final refs = {for (final frame in server.frames) frame[1]};
      expect(refs, hasLength(server.frames.length), reason: 'one counter');
    });

    test('a missed heartbeat reconnects and the channel joins '
        'again', () async {
      final socket = socketOf(heartbeat: _ms * 20);
      final room = socket.channel('room:42');
      final joined = room.join();
      final first = await PhoenixServer.next(sockets);
      await first.acceptJoin();
      await joined;
      // No reply to the heartbeat.
      await first.take('heartbeat');
      final second = await PhoenixServer.next(sockets);
      expect(first.socket.isClosed, isTrue);
      expect(first.socket.closeStatus!.code, CloseStatus.normal.code);
      expect(first.socket.closeStatus!.reason, 'heartbeat timeout');
      expect(first.framesOf('heartbeat'), hasLength(1));
      await second.acceptJoin();
      expect(room.state, PhoenixChannelState.joined);
    });
  });

  group('reconnect', () {
    test('every channel joins again with a fresh payload and new refs; '
        'listeners keep receiving', () async {
      var tokens = 0;
      var joins = 0;
      final socket = socketOf(parameters: () => {'token': 't${++tokens}'});
      final room = socket.channel(
        'room:42',
        payload: () async => {'join': ++joins},
      );
      final lobby = socket.channel('lobby');
      final messages = <Object?>[];
      final states = <PhoenixChannelState>[];
      room.on('new_msg').listen(messages.add);
      room.states.listen(states.add);
      unawaited(room.join());
      unawaited(lobby.join());
      final first = await PhoenixServer.next(sockets);
      final roomJoin = await first.acceptJoin();
      final lobbyJoin = await first.acceptJoin();
      expect(roomJoin[4], {'join': 1});
      expect(lobbyJoin[2], 'lobby');
      first.send('room:42', 'new_msg', {'n': 1}, joinRef: roomJoin[1]);
      await pump();

      sockets.failNextConnect();
      await first.socket.drop();
      await pump();
      expect(room.state, PhoenixChannelState.errored);
      expect(lobby.state, PhoenixChannelState.errored);

      final second = await PhoenixServer.next(sockets);
      expect(second.socket.uri.queryParameters['token'], 't3');
      final rejoins = [
        await second.take('phx_join'),
        await second.take('phx_join'),
      ];
      expect({for (final join in rejoins) join[2]}, {'room:42', 'lobby'});
      final roomRejoin = rejoins.firstWhere((join) => join[2] == 'room:42');
      expect(roomRejoin[4], {'join': 2}, reason: 'a fresh payload');
      final oldRefs = {roomJoin[1], lobbyJoin[1]};
      for (final join in rejoins) {
        expect(oldRefs, isNot(contains(join[1])), reason: 'new refs');
        expect(join[0], join[1]);
        second.reply(join);
      }
      await pump();
      expect(room.state, PhoenixChannelState.joined);
      expect(lobby.state, PhoenixChannelState.joined);
      second.send('room:42', 'new_msg', {'n': 2}, joinRef: roomRejoin[1]);
      await pump();
      expect(messages, [
        {'n': 1},
        {'n': 2},
      ]);
      expect(states, [
        PhoenixChannelState.joining,
        PhoenixChannelState.joined,
        PhoenixChannelState.errored,
        PhoenixChannelState.joining,
        PhoenixChannelState.joined,
      ]);
    });

    test('a push made during the outage is sent after the join '
        'again', () async {
      final socket = socketOf();
      final room = socket.channel('room:42');
      unawaited(room.join());
      final first = await PhoenixServer.next(sockets);
      await first.acceptJoin();
      await first.socket.drop();
      await pump();
      final pushed = room.push('new_msg', {'body': 'queued'});
      final second = await PhoenixServer.next(sockets);
      final join = await second.acceptJoin();
      final push = await second.take('new_msg');
      expect(push[0], join[1]);
      second.reply(push);
      expect((await pushed).isOk, isTrue);
    });
  });

  group('events', () {
    late PhoenixSocket socket;
    late PhoenixChannelSession room;
    late PhoenixServer server;
    late List<Object?> join;

    setUp(() async {
      socket = socketOf();
      room = socket.channel('room:42');
      unawaited(room.join());
      server = await PhoenixServer.next(sockets);
      join = await server.acceptJoin();
    });

    test('messages and on(event): broadcasts and pushes of this '
        'join', () async {
      final all = <String>[];
      final texts = <Object?>[];
      room.messages.listen((message) => all.add(message.event));
      room.on('new_msg').listen(texts.add);
      server
        ..send('room:42', 'new_msg', {'body': 'a'})
        ..send('room:42', 'new_msg', {'body': 'b'}, joinRef: join[1])
        ..send('room:42', 'presence_diff', {'joins': <String, Object?>{}})
        ..send('room:7', 'new_msg', {'body': 'another topic'})
        ..socket.push('not a frame')
        ..socket.push([1, 2, 3]);
      await pump();
      expect(all, ['new_msg', 'new_msg', 'presence_diff']);
      expect(texts, [
        {'body': 'a'},
        {'body': 'b'},
      ]);
    });

    test('a message of an older join (join_ref mismatch) is '
        'dropped', () async {
      final texts = <Object?>[];
      room.on('new_msg').listen(texts.add);
      server
        ..send('room:42', 'new_msg', {'body': 'stale'}, joinRef: '999')
        ..send('room:42', 'phx_error', <String, Object?>{}, joinRef: '999')
        ..send('room:42', 'phx_close', <String, Object?>{}, joinRef: '999')
        ..send('room:42', 'new_msg', {'body': 'current'}, joinRef: join[1]);
      await pump();
      expect(texts, [
        {'body': 'current'},
      ]);
      expect(room.state, PhoenixChannelState.joined);
    });

    test('phx_error: errored, then joined again with backoff', () async {
      final states = <PhoenixChannelState>[];
      room.states.listen(states.add);
      final texts = <Object?>[];
      room.on('new_msg').listen(texts.add);
      server.send(
        'room:42',
        'phx_error',
        <String, Object?>{},
        joinRef: join[1],
      );
      await pump();
      expect(room.state, PhoenixChannelState.errored);
      expect(room.joinRef, isNull);
      final again = await server.acceptJoin();
      expect(again[1], isNot(join[1]));
      expect(sockets.connections, hasLength(1), reason: 'the same socket');
      expect(states, [
        PhoenixChannelState.errored,
        PhoenixChannelState.joining,
        PhoenixChannelState.joined,
      ]);
      server.send('room:42', 'new_msg', {'body': 'back'}, joinRef: again[1]);
      await pump();
      expect(texts, [
        {'body': 'back'},
      ]);
    });

    test('phx_close: the channel ends and the socket closes', () async {
      var done = false;
      room.messages.listen(null, onDone: () => done = true);
      final pushed = room.push('new_msg', null);
      await server.take('new_msg');
      server.send(
        'room:42',
        'phx_close',
        <String, Object?>{},
        joinRef: join[1],
      );
      await expectLater(pushed, throwsA(isA<PhoenixPushException>()));
      await room.done;
      await pump();
      expect(done, isTrue);
      expect(room.state, PhoenixChannelState.closed);
      expect(socket.channels, isEmpty);
      expect(server.socket.closedByClient, isTrue);
    });
  });

  group('leave', () {
    test('tells the server, ends the streams; the socket closes after '
        'the last channel', () async {
      final socket = socketOf();
      final room = socket.channel('room:42');
      final lobby = socket.channel('lobby');
      unawaited(room.join());
      unawaited(lobby.join());
      final server = await PhoenixServer.next(sockets);
      final roomJoin = await server.acceptJoin();
      await server.acceptJoin();
      var done = false;
      final states = <PhoenixChannelState>[];
      room.messages.listen(null, onDone: () => done = true);
      room.states.listen(states.add);

      final left = room.leave();
      expect(room.state, PhoenixChannelState.leaving);
      final leave = await server.take('phx_leave');
      expect(leave, [
        roomJoin[1],
        isA<String>(),
        'room:42',
        'phx_leave',
        isEmpty,
      ]);
      server.reply(leave);
      await left;
      await pump();
      expect(done, isTrue);
      expect(states, [
        PhoenixChannelState.leaving,
        PhoenixChannelState.closed,
      ]);
      expect(socket.channels, [lobby]);
      expect(server.socket.isClosed, isFalse, reason: 'the lobby is open');
      await room.leave(); // harmless

      final leftLobby = lobby.leave();
      server.reply(await server.take('phx_leave'));
      await leftLobby;
      expect(server.socket.isClosed, isTrue);
      expect(server.socket.closedByClient, isTrue);
      expect(server.socket.closeStatus, CloseStatus.normal);
      expect(socket.isConnected, isFalse);

      // A new channel opens a new connection.
      unawaited(socket.channel('room:7').join());
      final next = await PhoenixServer.next(sockets);
      expect((await next.acceptJoin())[2], 'room:7');
      expect(sockets.connections, hasLength(2));
    });

    test('without a reply it ends after the push timeout; while joining '
        'the join fails', () async {
      final socket = socketOf(pushTimeout: _ms * 30);
      final room = socket.channel('room:42');
      final joined = room.join();
      final server = await PhoenixServer.next(sockets);
      await server.take('phx_join');
      final failure = joined.then<Object?>(
        (_) => null,
        onError: (Object error) => error,
      );
      final left = room.leave();
      expect(await failure, isA<PhoenixJoinException>());
      await server.take('phx_leave');
      await left;
      expect(room.state, PhoenixChannelState.closed);
      expect(server.socket.closedByClient, isTrue);
    });
  });

  test('send: an event without a reply', () async {
    final socket = socketOf();
    final room = socket.channel('room:42');
    unawaited(room.join());
    final server = await PhoenixServer.next(sockets);
    final join = await server.acceptJoin();
    await room.send('typing', {'user': 'ann'});
    final typing = await server.take('typing');
    expect(typing[0], join[1]);
    expect(typing[4], {'user': 'ann'});
  });

  test('send while the channel cannot join: fails after the push timeout '
      'and is not sent later', () async {
    final socket = socketOf(pushTimeout: _ms * 40);
    final room = socket.channel('room:42');
    room.join().ignore();
    final server = await PhoenixServer.next(sockets);
    // The server does not answer the join.
    await server.take('phx_join');
    final watch = Stopwatch()..start();
    final dropped = [
      for (var n = 0; n < 3; n++) room.send('typing', {'n': n}),
    ];
    for (final sent in dropped) {
      await expectLater(
        sent,
        throwsA(
          isA<TimeoutException>().having(
            (e) => e.message,
            'message',
            '"typing" was not sent on room:42 in time',
          ),
        ),
      );
    }
    expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(35));
    expect(watch.elapsedMilliseconds, lessThan(1000));

    // The channel joins at last: only what is still waiting is sent.
    final join = await server.take('phx_join');
    final waiting = room.send('typing', {'n': 9});
    server.reply(join);
    await waiting;
    await pump();
    expect(
      [for (final frame in server.framesOf('typing')) frame[4]],
      [
        {'n': 9},
      ],
    );
    // Its time limit ended with the send.
    await Future<void>.delayed(_ms * 60);
    expect(room.state, PhoenixChannelState.joined);
  });

  test('the first wire format end to end', () async {
    final socket = socketOf(serializer: const PhoenixSerializerV1());
    final room = socket.channel('room:42');
    final texts = <Object?>[];
    room.on('new_msg').listen(texts.add);
    final joined = room.join();
    final server = await sockets.nextConnection;
    expect(server.uri.queryParameters['vsn'], '1.0.0');
    await pump();
    final join = server.sentJson.single! as Map<String, Object?>;
    expect(join, {
      'topic': 'room:42',
      'event': 'phx_join',
      'payload': <String, Object?>{},
      'ref': '1',
      'join_ref': '1',
    });
    server.pushJson({
      'topic': 'room:42',
      'event': 'phx_reply',
      'ref': '1',
      'payload': {'status': 'ok', 'response': <String, Object?>{}},
    });
    await joined;
    final pushed = room.push('new_msg', {'body': 'hi'});
    await pump();
    final push = server.sentJson.last! as Map<String, Object?>;
    expect(push['event'], 'new_msg');
    server
      ..pushJson({
        'topic': 'room:42',
        'event': 'phx_reply',
        'ref': push['ref'],
        'payload': {
          'status': 'ok',
          'response': {'id': 9},
        },
      })
      ..pushJson({
        'topic': 'room:42',
        'event': 'new_msg',
        'ref': null,
        'payload': {'body': 'yo'},
      });
    expect((await pushed).response, {'id': 9});
    await pump();
    expect(texts, [
      {'body': 'yo'},
    ]);
    // The close of an older join carries that join's ref.
    server.pushJson({
      'topic': 'room:42',
      'event': 'phx_close',
      'ref': '999',
      'payload': <String, Object?>{},
    });
    await pump();
    expect(room.state, PhoenixChannelState.joined);
    server.pushJson({
      'topic': 'room:42',
      'event': 'phx_close',
      'ref': '1',
      'payload': <String, Object?>{},
    });
    await room.done;
    expect(room.state, PhoenixChannelState.closed);
  });

  test('a connection the server ends for good ends the channels with '
      'the error', () async {
    final socket = socketOf();
    final room = socket.channel('room:42');
    unawaited(room.join());
    final server = await PhoenixServer.next(sockets);
    await server.acceptJoin();
    final errors = <Object>[];
    final done = Completer<void>();
    room.messages.listen(null, onError: errors.add, onDone: done.complete);
    await server.socket.closeFromServer(
      CloseStatus.policyViolation.withReason('no token'),
    );
    await done.future;
    expect(errors.single, isA<WebSocketException>());
    expect('${errors.single}', contains('1008: no token'));
    expect(room.state, PhoenixChannelState.closed);
    expect(socket.channels, isEmpty);
    await Future<void>.delayed(_ms * 30);
    expect(sockets.connections, hasLength(1));
  });

  group('PhoenixSocketFactory', () {
    late ApplicationContextRunner runner;

    setUp(() {
      runner = const ApplicationContextRunner()
          .withAutoConfiguration(springBootAutoConfiguration)
          .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration)
          .withPropertyValues([
            'chat.host=chat.test',
            '$_config.chat.url=ws://\${chat.host}/socket/websocket',
            '$_config.default.phoenix.push-timeout=3s',
            '$_config.chat.phoenix.heartbeat-interval=15s',
            '$_config.old.phoenix.vsn=1.0.0',
            '$_config.odd.phoenix.vsn=9.9.9',
          ])
          .withBean<WebSocketTransport>(() => sockets);
    });

    test('a socket per name and address, with the phoenix.* '
        'settings', () async {
      await runner.runAsync((context) async {
        final factory = context.getBean<PhoenixSocketFactory>();
        final chat = factory.socket('chat');
        expect('${chat.url}', 'ws://chat.test/socket/websocket');
        expect(chat.serializer, isA<PhoenixSerializerV2>());
        expect(chat.config.phoenix.heartbeatInterval, _ms * 15000);
        expect(chat.config.phoenix.pushTimeout, _ms * 3000);
        expect(factory.socket('chat'), same(chat));
        final other = Uri.parse('ws://other.test/socket/websocket');
        final old = factory.socket('old', url: other);
        expect(old, isNot(same(chat)));
        expect(old.serializer, isA<PhoenixSerializerV1>());
        expect(old.config.phoenix.heartbeatInterval, _ms * 30000);
        expect(factory.socket('old', url: other), same(old));
        expect(factory.socket('chat', url: other), isNot(same(old)));
        expect(
          () => factory.socket('old', url: other, vsn: '2.0.0'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('speaks vsn 1.0.0 already'),
            ),
          ),
        );
        expect(
          () => factory.socket('odd', url: other),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('no PhoenixSerializer for vsn "9.9.9"'),
            ),
          ),
        );
        expect(
          () => factory.socket('nowhere'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('spring.websocket.client.config.nowhere.url'),
            ),
          ),
        );
      });
    });

    test('closing the context closes the sockets', () async {
      late MockWebSocket server;
      late PhoenixChannelSession room;
      var done = false;
      await runner.runAsync((context) async {
        final factory = context.getBean<PhoenixSocketFactory>();
        room = factory.socket('chat').channel('room:42');
        room.messages.listen(null, onDone: () => done = true);
        unawaited(room.join());
        final phoenix = await PhoenixServer.next(sockets);
        await phoenix.acceptJoin();
        server = phoenix.socket;
      });
      await pump();
      expect(server.isClosed, isTrue);
      expect(server.closeStatus, CloseStatus.normal);
      expect(done, isTrue);
      expect(room.state, PhoenixChannelState.closed);
      await expectLater(room.join(), throwsStateError);
    });

    test('a value out of range fails naming the property', () async {
      await runner
          .withPropertyValues(['$_config.chat.phoenix.push-timeout=0s'])
          .runAsync((context) async {
            expect(
              () => context.getBean<PhoenixSocketFactory>().socket('chat'),
              throwsA(
                isA<ArgumentError>().having(
                  (e) => e.name,
                  'name',
                  '$_config.chat.phoenix.push-timeout',
                ),
              ),
            );
          });
    });
  });
}
