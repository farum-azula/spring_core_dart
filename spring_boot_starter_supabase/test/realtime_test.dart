@Tags(['supabase'])
library;

import 'dart:async';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'realtime_support.dart';
import 'support.dart';

const _ms = Duration(milliseconds: 1);

void main() {
  late MockWebSocketTransport sockets;
  late TestLogin login;
  late SupabaseRealtime realtime;

  setUp(() {
    sockets = MockWebSocketTransport();
    login = TestLogin();
    realtime = realtimeOf(sockets, login: login);
  });

  tearDown(() async {
    await realtime.destroy();
  });

  group('the connection', () {
    test('opens with the first channel that is used, at the '
        "project's address with the apikey, and reads large "
        'messages', () async {
      final room = realtime.channel('room:1');
      final stream = room.broadcast('cursor');
      await pump();
      expect(sockets.connections, isEmpty, reason: 'nothing listens yet');
      expect(realtime.isConnected, isFalse);
      expect(realtime.channels, isEmpty);

      final received = <Object?>[];
      stream.listen(received.add);
      final server = await RealtimeServer.next(sockets);
      expect(
        '${server.socket.uri}',
        '$realtimeAddress?vsn=1.0.0&apikey=anon-key',
      );
      expect('${realtime.url}', realtimeAddress);
      // Realtime sends up to 3,000 KB: more than the 8 KB of a client.
      expect(server.socket.maxTextMessageSize, 4 * 1024 * 1024);
      expect(server.socket.maxBinaryMessageSize, isNull);
      final join = await server.acceptJoin();
      expect(join['topic'], 'realtime:room:1');
      expect(realtime.isConnected, isTrue);
      expect(room.isJoined, isTrue);
      expect(
        [for (final channel in realtime.channels) channel.name],
        [
          'room:1',
        ],
      );

      final large = 'a' * 100000;
      server.broadcast('room:1', 'cursor', {'text': large});
      await pump();
      expect(received, [
        {'text': large},
      ]);
      expect(server.socket.isClosed, isFalse);
    });

    test('closes when the last channel is left, and opens again with '
        'the next use', () async {
      final first = realtime.channel('a').broadcast('x').listen(null);
      final second = realtime.channel('b').broadcast('x').listen(null);
      final server = await RealtimeServer.next(sockets);
      await server.acceptJoin();
      await server.acceptJoin();

      await first.cancel();
      final leave = await server.accept('phx_leave');
      expect(leave['topic'], 'realtime:a');
      expect(server.socket.isClosed, isFalse, reason: 'b is still used');
      expect([for (final channel in realtime.channels) channel.name], ['b']);

      await second.cancel();
      await server.accept('phx_leave');
      await pump();
      expect(server.socket.closedByClient, isTrue);
      expect(realtime.channels, isEmpty);
      expect(realtime.isConnected, isFalse);

      realtime.channel('a').broadcast('x').listen(null);
      final again = await RealtimeServer.next(sockets);
      await again.acceptJoin();
      expect(sockets.connections, hasLength(2));
    });

    test('the apikey is asked at each connection, and is never the '
        'service role key', () async {
      final keys = _Keys();
      realtime = realtimeOf(sockets, credentials: keys);
      // Used inside asServiceRole: the join is the service role's, the
      // address of the shared connection is not.
      await keys.asServiceRole(() async {
        realtime.channel('admin').broadcast('x').listen(null);
        await pump();
      });
      final first = await RealtimeServer.next(sockets);
      expect(first.socket.uri.queryParameters['apikey'], 'anon-1');
      final join = await first.acceptJoin();
      expect(RealtimeServer.tokenOf(join), 'service-token');

      keys.anon = 'anon-2';
      await first.socket.drop();
      final second = await RealtimeServer.next(sockets);
      expect(second.socket.uri.queryParameters['apikey'], 'anon-2');
      expect(
        RealtimeServer.tokenOf(await second.acceptJoin()),
        'service-token',
      );
    });

    test("the application's settings of the client supabase-realtime "
        "win over the starter's", () async {
      realtime = realtimeOf(
        sockets,
        heartbeat: _ms * 30,
        settings: {
          'default': WebSocketClientSettings()
            // Of every client: not Realtime's limit, wire format or
            // heartbeat.
            ..maxTextMessageSize = DataSize.ofKilobytes(16)
            ..maxBinaryMessageSize = DataSize.ofKilobytes(32)
            ..phoenix = (WebSocketPhoenixSettings()
              ..vsn = '2.0.0'
              ..heartbeatInterval = const Duration(hours: 1)),
        },
      );
      realtime.channel('a').broadcast('x').listen(null);
      final server = await RealtimeServer.next(sockets);
      expect(server.socket.uri.queryParameters['vsn'], '1.0.0');
      expect(server.socket.maxTextMessageSize, 4 * 1024 * 1024);
      expect(server.socket.maxBinaryMessageSize, 32 * 1024);
      await server.acceptJoin();
      // spring.supabase.realtime.heartbeat-interval: 30 ms.
      final beat = await server.take('heartbeat');
      expect(beat['topic'], 'phoenix');
      await realtime.destroy();

      sockets = MockWebSocketTransport();
      realtime = realtimeOf(
        sockets,
        settings: {
          'Supabase-Realtime': WebSocketClientSettings()
            ..url = 'wss://elsewhere.test/socket/websocket'
            ..maxTextMessageSize = DataSize.ofKilobytes(64)
            ..defaultRequestHeaders = {
              'X-Shop': ['neon'],
            }
            ..phoenix = (WebSocketPhoenixSettings()..vsn = '2.0.0'),
        },
      );
      realtime.channel('a').broadcast('x').listen(null);
      final other = await sockets.nextConnection;
      // A key is only ever sent to spring.supabase.url.
      expect(other.uri.host, 'abcd.supabase.co');
      expect(other.uri.queryParameters['vsn'], '2.0.0');
      expect(other.maxTextMessageSize, 64 * 1024);
      expect(other.headers['X-Shop'], 'neon');
      await pump(20);
      // The second wire format: arrays.
      expect((other.sentJson.single! as List<Object?>)[3], 'phx_join');
    });

    test('a wire format nobody speaks fails the use, not the '
        'start', () async {
      realtime = realtimeOf(
        sockets,
        settings: {
          'supabase-realtime': WebSocketClientSettings()
            ..phoenix = (WebSocketPhoenixSettings()..vsn = '9.9.9'),
        },
      );
      final errors = <Object>[];
      final done = Completer<void>();
      realtime
          .channel('a')
          .broadcast('x')
          .listen(null, onError: errors.add, onDone: done.complete);
      await done.future;
      expect('${errors.single}', contains('no PhoenixSerializer for vsn'));
      await expectLater(
        realtime.channel('a').send('x'),
        throwsA(isA<StateError>()),
      );
      expect(sockets.connections, isEmpty);
    });
  });

  group('secrets', () {
    final logs = captureLogs(level: SpringLogLevel.trace);

    test('no log line and no exception shows the key or a token', () async {
      const secrets = ['anon-key', 'user-token-1', 'user-token-2'];
      login.token = 'user-token-1';
      final shown = <String>[];
      void show(Object error, [StackTrace? stackTrace]) => shown.add('$error');

      // The first attempt fails with the address in its text, as a
      // transport reports it.
      final address = Uri.parse(
        '$realtimeAddress?vsn=1.0.0&apikey=anon-key',
      );
      final refusal = WebSocketException(
        "Connection to '$address' was not upgraded to websocket",
        url: address,
      );
      sockets.failNextConnect(refusal);
      final room = realtime.channel('room:1', ack: true);
      room.broadcast('x').listen(null, onError: show);
      room
          .postgresChanges(table: 'todos', filter: 'id=nope.1')
          .listen(null, onError: show);

      final server = await RealtimeServer.next(sockets);
      // Refused once, as a server does for a token it does not take.
      final refused = await server.take('phx_join');
      expect(RealtimeServer.tokenOf(refused), 'user-token-1');
      server.reply(
        refused,
        status: 'error',
        response: {'reason': 'InvalidJWTExpiration: Token has expired'},
      );
      await server.acceptJoin(ids: [1]);
      server.send('room:1', 'system', {
        'extension': 'postgres_changes',
        'status': 'error',
        'message': 'invalid filter',
        'channel': 'room:1',
      });
      final sent = room.send('x', {'n': 1}).then((_) {}, onError: show);
      server.reply(
        await server.take('broadcast'),
        status: 'error',
        response: {'error': 'payload_size_exceeded'},
      );
      await sent;
      login.signIn('user-token-2');
      await server.take('access_token');
      server.socket.push('not json');
      await server.socket.drop();
      final again = await RealtimeServer.next(sockets);
      expect(
        RealtimeServer.tokenOf(await again.acceptJoin(ids: [2])),
        'user-token-2',
      );
      await realtime.destroy();

      // A connection that is given up: its error reaches the streams.
      realtime = realtimeOf(
        sockets,
        login: login,
        settings: {
          'supabase-realtime': WebSocketClientSettings()
            ..reconnect = (WebSocketReconnectSettings()..maxRetries = 0),
        },
      );
      sockets.failNextConnect(refusal);
      final done = Completer<void>();
      realtime
          .channel('room:2')
          .broadcast('x')
          .listen(null, onError: show, onDone: done.complete);
      await done.future;

      expect(shown, [
        // Each stream of the channel is told about the refused join.
        startsWith('PhoenixJoinException: realtime:room:1: the server'),
        startsWith('PhoenixJoinException: realtime:room:1: the server'),
        'RealtimeException: invalid filter',
        startsWith('PhoenixPushException: realtime:room:1 broadcast'),
        allOf(
          startsWith('WebSocketException: Connection to'),
          contains('apikey=***'),
        ),
      ]);
      final lines = [
        for (final record in logs.records)
          '$record ${record.fields} ${record.error}',
        ...shown,
        '$realtime',
        '$room',
      ];
      for (final secret in secrets) {
        expect(
          lines.where((line) => line.contains(secret)),
          isEmpty,
          reason: 'shows $secret',
        );
      }
      // The log does say where it connected, without the query values.
      expect(logs.text, contains('abcd.supabase.co'));
      expect(logs.text, contains('apikey=***'));
    });
  });

  group('the join', () {
    test('a channel that is only listened to for broadcasts: nothing '
        'else is asked, and the token is the anon key', () async {
      realtime.channel('room:1').broadcast('cursor').listen(null);
      final server = await RealtimeServer.next(sockets);
      final join = await server.acceptJoin();
      expect(join['topic'], 'realtime:room:1');
      expect(join['payload'], {
        'config': {
          'postgres_changes': <Object?>[],
          'broadcast': {'ack': false, 'self': false},
          'presence': {'key': '', 'enabled': false},
          'private': false,
        },
        'access_token': 'anon-key',
      });
    });

    test('the options of the channel, and everything that is listened '
        'to at once, in one join', () async {
      login.token = 'user-token-1';
      final room = realtime.channel(
        'room:1',
        private: true,
        self: true,
        ack: true,
        presenceKey: 'ann',
      );
      room.broadcast('cursor').listen(null);
      room.presence().listen(null);
      room.postgresChanges(table: 'todos').listen(null);
      room
          .postgresChanges(
            schema: 'app',
            table: 'messages',
            filter: 'room_id=eq.1',
            kind: RealtimeChangeKind.insert,
          )
          .listen(null);
      final server = await RealtimeServer.next(sockets);
      final join = await server.acceptJoin(ids: [1, 2]);
      expect(join['payload'], {
        'config': {
          'postgres_changes': [
            {'event': '*', 'schema': 'public', 'table': 'todos'},
            {
              'event': 'INSERT',
              'schema': 'app',
              'table': 'messages',
              'filter': 'room_id=eq.1',
            },
          ],
          'broadcast': {'ack': true, 'self': true},
          'presence': {'key': 'ann', 'enabled': true},
          'private': true,
        },
        'access_token': 'user-token-1',
      });
      await pump();
      expect(server.framesOf('phx_join'), hasLength(1));
    });

    test('the access token is asked at every join, also the one after '
        'a reconnection', () async {
      login.token = 'user-token-1';
      realtime.channel('room:1').broadcast('x').listen(null);
      final first = await RealtimeServer.next(sockets);
      expect(RealtimeServer.tokenOf(await first.acceptJoin()), 'user-token-1');
      login.token = 'user-token-2';
      await first.socket.drop();
      final second = await RealtimeServer.next(sockets);
      expect(
        RealtimeServer.tokenOf(await second.acceptJoin()),
        'user-token-2',
      );
    });

    test('a join the server refuses is an error event, and is tried '
        'again', () async {
      final errors = <Object>[];
      final received = <Object?>[];
      realtime
          .channel('room:1', private: true)
          .broadcast('x')
          .listen(received.add, onError: errors.add);
      final server = await RealtimeServer.next(sockets);
      server.reply(
        await server.take('phx_join'),
        status: 'error',
        response: {'reason': 'Unauthorized: no policy'},
      );
      await pump();
      expect(errors.single, isA<PhoenixJoinException>());
      expect('${errors.single}', contains('Unauthorized'));
      await server.acceptJoin();
      server.broadcast('room:1', 'x', {'n': 1});
      await pump();
      expect(received, [
        {'n': 1},
      ]);
    });

    test('one name is one channel: every call gives it, with the same '
        'options only', () async {
      final received = <String>[];
      realtime
          .channel('room:1', self: true)
          .broadcast('a')
          .listen((_) => received.add('a'));
      realtime
          .channel('room:1', self: true)
          .broadcast('b')
          .listen((_) => received.add('b'));
      final server = await RealtimeServer.next(sockets);
      await server.acceptJoin();
      server
        ..broadcast('room:1', 'a', const <String, Object?>{})
        ..broadcast('room:1', 'b', const <String, Object?>{});
      await pump();
      expect(received, ['a', 'b']);
      expect(server.framesOf('phx_join'), hasLength(1));
      expect(realtime.channels, hasLength(1));

      final errors = <Object>[];
      final done = Completer<void>();
      realtime
          .channel('room:1')
          .broadcast('a')
          .listen(null, onError: errors.add, onDone: done.complete);
      await done.future;
      expect(errors.single, isA<StateError>());
      expect('${errors.single}', contains('room:1 is in use as'));
      await expectLater(
        realtime.channel('room:1', presenceKey: 'ann').track(const {}),
        throwsA(isA<StateError>()),
      );
    });

    test('a channel asked inside asServiceRole is the service '
        "role's, whenever it is used; not with another caller's "
        'at once', () async {
      login.token = 'user-token-1';
      final credentials = realtime.credentials;
      final admin = await credentials.asServiceRole(
        () => realtime.channel('admin'),
      );
      // Used outside: still the service role.
      admin.broadcast('x').listen(null);
      realtime.channel('mine').broadcast('x').listen(null);
      final server = await RealtimeServer.next(sockets);
      expect(server.socket.uri.queryParameters['apikey'], 'anon-key');
      final joins = [await server.acceptJoin(), await server.acceptJoin()];
      expect(
        {
          for (final join in joins) join['topic']: RealtimeServer.tokenOf(join),
        },
        {'realtime:admin': 'service-key', 'realtime:mine': 'user-token-1'},
      );

      // The same name as the user while the service role has it: no.
      await expectLater(
        realtime.channel('admin').send('x'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('as the service role'),
          ),
        ),
      );
    });
  });

  group('database changes', () {
    test('are told apart by the ids of the join, and each kind goes '
        'to who asked for it', () async {
      final room = realtime.channel('db');
      final all = <RealtimeRowChange>[];
      final inserts = <RealtimeRowChange>[];
      final messages = <RealtimeRowChange>[];
      room.postgresChanges(table: 'todos').listen(all.add);
      room
          .postgresChanges(table: 'todos', kind: RealtimeChangeKind.insert)
          .listen(inserts.add);
      room
          .postgresChanges(table: 'messages', filter: 'room_id=eq.1')
          .listen(messages.add);
      final server = await RealtimeServer.next(sockets);
      await server.acceptJoin(ids: [11, 22, 33]);

      server
        ..change('db', [11, 22], 'INSERT', record: {'id': 1, 'title': 'a'})
        ..change(
          'db',
          [11],
          'UPDATE',
          record: {'id': 1, 'title': 'b'},
          old: {'id': 1},
        )
        // The id of the inserts with another kind: not theirs.
        ..change('db', [22], 'DELETE', old: {'id': 1})
        ..change('db', [11], 'DELETE', old: {'id': 1})
        ..change(
          'db',
          [33],
          'INSERT',
          record: {'id': 7},
          table: 'messages',
          errors: ['Error 413: Payload Too Large'],
        )
        // Ids nobody has, and what is no change.
        ..change('db', [99], 'INSERT', record: {'id': 9})
        ..change('db', [11], 'TRUNCATE')
        ..send('db', 'postgres_changes', 'nope');
      await pump();

      expect(
        [for (final change in all) change.kind],
        [
          RealtimeChangeKind.insert,
          RealtimeChangeKind.update,
          RealtimeChangeKind.delete,
        ],
      );
      expect(
        [for (final change in inserts) change.record],
        [
          {'id': 1, 'title': 'a'},
        ],
      );
      final insert = all.first;
      expect(insert.schema, 'public');
      expect(insert.table, 'todos');
      expect(insert.record, {'id': 1, 'title': 'a'});
      expect(insert.oldRecord, isEmpty);
      expect(insert.commitTime, DateTime.utc(2026, 11, 10, 8, 30));
      expect(insert.columns, {'id': 'int8', 'title': 'text'});
      expect(insert.errors, isEmpty);
      expect(all[1].record, {'id': 1, 'title': 'b'});
      expect(all[1].oldRecord, {'id': 1});
      expect(all[2].record, isEmpty);
      expect(all[2].oldRecord, {'id': 1});
      expect(messages.single.table, 'messages');
      expect(messages.single.errors, ['Error 413: Payload Too Large']);
    });

    test('equal subscriptions are one for the server, and every '
        'listener gets the change', () async {
      final room = realtime.channel('db');
      final first = <RealtimeRowChange>[];
      final second = <RealtimeRowChange>[];
      room.postgresChanges(table: 'todos').listen(first.add);
      room.postgresChanges(table: 'todos').listen(second.add);
      final server = await RealtimeServer.next(sockets);
      final join = await server.acceptJoin(ids: [5]);
      expect(RealtimeServer.configOf(join)['postgres_changes'], hasLength(1));
      server.change('db', [5], 'INSERT', record: {'id': 1});
      await pump();
      expect(first, hasLength(1));
      expect(second, hasLength(1));
    });

    test('after a rejoin the new ids count', () async {
      final changes = <RealtimeRowChange>[];
      realtime
          .channel('db')
          .postgresChanges(table: 'todos')
          .listen(changes.add);
      final first = await RealtimeServer.next(sockets);
      await first.acceptJoin(ids: [11]);
      first.change('db', [11], 'INSERT', record: {'id': 1});
      await pump();

      await first.socket.drop();
      final second = await RealtimeServer.next(sockets);
      await second.acceptJoin(ids: [44]);
      second
        ..change('db', [11], 'INSERT', record: {'id': 2})
        ..change('db', [44], 'INSERT', record: {'id': 3});
      await pump();
      expect([for (final change in changes) change.record['id']], [1, 3]);

      // The channel crashed on the server: joined again, new ids again.
      second.send('db', 'phx_error', const <String, Object?>{});
      await second.acceptJoin(ids: [55]);
      second
        ..change('db', [44], 'INSERT', record: {'id': 4})
        ..change('db', [55], 'INSERT', record: {'id': 5});
      await pump();
      expect([for (final change in changes) change.record['id']], [1, 3, 5]);
    });

    test('a change that comes right behind the reply of the join is '
        'not lost', () async {
      final changes = <RealtimeRowChange>[];
      realtime
          .channel('db')
          .postgresChanges(table: 'todos')
          .listen(changes.add);
      final server = await RealtimeServer.next(sockets);
      final join = await server.take('phx_join');
      server
        ..reply(
          join,
          response: {
            'postgres_changes': [
              {'id': 7, 'event': '*', 'schema': 'public', 'table': 'todos'},
            ],
          },
        )
        ..change('db', [7], 'INSERT', record: {'id': 1});
      await pump(10);
      expect(changes, hasLength(1));
    });

    test('a subscription the server could not make is an error event, '
        'and the channel goes on', () async {
      final room = realtime.channel('db');
      final changes = <RealtimeRowChange>[];
      final errors = <Object>[];
      final broadcasts = <Object?>[];
      final broadcastErrors = <Object>[];
      room
          .postgresChanges(table: 'todos', filter: 'id=nope.1')
          .listen(changes.add, onError: errors.add);
      room.broadcast('x').listen(broadcasts.add, onError: broadcastErrors.add);
      final server = await RealtimeServer.next(sockets);
      await server.acceptJoin(ids: [1]);
      server
        ..send('db', 'system', {
          'extension': 'postgres_changes',
          'status': 'ok',
          'message': 'Subscribed to PostgreSQL',
          'channel': 'db',
        })
        ..send('db', 'system', {
          'extension': 'postgres_changes',
          'status': 'error',
          'message': 'Error parsing `filter` params: ["nope", "1"]',
          'channel': 'db',
        })
        ..change('db', [1], 'INSERT', record: {'id': 1})
        ..broadcast('db', 'x', {'n': 1});
      await pump();
      final error = errors.single as RealtimeException;
      expect(error.message, contains('Error parsing `filter`'));
      expect(error.extension, 'postgres_changes');
      expect(error.status, 'error');
      expect(error.topic, 'realtime:db');
      expect('$error', startsWith('RealtimeException: Error parsing'));
      expect(changes, hasLength(1), reason: 'the stream stays open');
      expect(broadcasts, hasLength(1));
      expect(broadcastErrors, isEmpty, reason: 'not its problem');
    });

    test('a reply with other subscriptions than asked is an error '
        'event: no change is routed', () async {
      final changes = <RealtimeRowChange>[];
      final errors = <Object>[];
      realtime
          .channel('db')
          .postgresChanges(table: 'todos')
          .listen(changes.add, onError: errors.add);
      final server = await RealtimeServer.next(sockets);
      server
        ..reply(
          await server.take('phx_join'),
          response: {
            'postgres_changes': [
              {'id': 7, 'event': '*', 'schema': 'public', 'table': 'other'},
            ],
          },
        )
        ..change('db', [7], 'INSERT', record: {'id': 1});
      await pump(10);
      expect(errors.single, isA<RealtimeException>());
      expect('${errors.single}', contains('other subscriptions'));
      expect(changes, isEmpty);
    });

    test("the server's subscription ends with its last listener: the "
        'channel is joined again without it while something else '
        'listens', () async {
      final room = realtime.channel('room:1');
      final broadcasts = <Object?>[];
      room.broadcast('x').listen(broadcasts.add);
      final first = room.postgresChanges(table: 'todos').listen(null);
      final second = room.postgresChanges(table: 'todos').listen(null);
      final server = await RealtimeServer.next(sockets);
      await server.acceptJoin(ids: [1]);

      await first.cancel();
      await pump();
      expect(server.events, ['phx_join'], reason: 'one listener is left');

      await second.cancel();
      // Left first, then joined with the new configuration.
      final leave = await server.accept('phx_leave');
      final join = await server.acceptJoin();
      expect(leave['join_ref'], isNot(join['join_ref']));
      expect(RealtimeServer.configOf(join)['postgres_changes'], isEmpty);
      expect(server.events, ['phx_join', 'phx_leave', 'phx_join']);
      expect(server.socket.isClosed, isFalse);
      server.broadcast('room:1', 'x', {'n': 1});
      await pump();
      expect(broadcasts, hasLength(1), reason: 'the other stream goes on');
    });

    test('a subscription added to a joined channel joins it again '
        'with both', () async {
      final room = realtime.channel('db');
      final todos = <RealtimeRowChange>[];
      final messages = <RealtimeRowChange>[];
      room.postgresChanges(table: 'todos').listen(todos.add);
      final server = await RealtimeServer.next(sockets);
      await server.acceptJoin(ids: [1]);

      room.postgresChanges(table: 'messages').listen(messages.add);
      await server.accept('phx_leave');
      final join = await server.acceptJoin(ids: [2, 3]);
      expect(RealtimeServer.configOf(join)['postgres_changes'], [
        {'event': '*', 'schema': 'public', 'table': 'todos'},
        {'event': '*', 'schema': 'public', 'table': 'messages'},
      ]);
      server
        // An id of the join that was left.
        ..change('db', [1], 'INSERT', record: {'id': 1})
        ..change('db', [2], 'INSERT', record: {'id': 2})
        ..change('db', [3], 'INSERT', record: {'id': 3}, table: 'messages');
      await pump();
      expect([for (final change in todos) change.record['id']], [2]);
      expect([for (final change in messages) change.record['id']], [3]);
    });

    test('SupabaseRealtime.postgresChanges: a channel of its own, '
        'left with its last listener', () async {
      final changes = <RealtimeRowChange>[];
      final first = realtime
          .postgresChanges(table: 'todos', filter: 'list_id=eq.7')
          .listen(changes.add);
      final second = realtime
          .postgresChanges(table: 'todos', filter: 'list_id=eq.7')
          .listen(null);
      final other = realtime
          .postgresChanges(table: 'todos', kind: RealtimeChangeKind.delete)
          .listen(null);
      final server = await RealtimeServer.next(sockets);
      final joins = [
        await server.acceptJoin(ids: [1]),
        await server.acceptJoin(ids: [2]),
      ];
      expect(
        [for (final join in joins) join['topic']],
        [
          'realtime:db-changes:public:todos:*:list_id=eq.7',
          'realtime:db-changes:public:todos:DELETE',
        ],
      );
      expect(RealtimeServer.configOf(joins.first)['postgres_changes'], [
        {
          'event': '*',
          'schema': 'public',
          'table': 'todos',
          'filter': 'list_id=eq.7',
        },
      ]);
      server.change(
        'db-changes:public:todos:*:list_id=eq.7',
        [1],
        'INSERT',
        record: {'id': 1},
      );
      await pump();
      expect(changes, hasLength(1));

      await first.cancel();
      await pump();
      expect(server.framesOf('phx_leave'), isEmpty);
      await second.cancel();
      final leave = await server.accept('phx_leave');
      expect(leave['topic'], joins.first['topic']);
      expect(server.socket.isClosed, isFalse);
      await other.cancel();
      await server.accept('phx_leave');
      await pump();
      expect(server.socket.closedByClient, isTrue);
    });
  });

  group('broadcast', () {
    test('each event goes to its listeners, as JSON', () async {
      final room = realtime.channel('room:1');
      final cursors = <Map<String, Object?>>[];
      final ticks = <Object?>[];
      final objects = <Map<String, Object?>>[];
      final errors = <Object>[];
      room.broadcast('cursor').listen(cursors.add);
      room.events('tick').listen(ticks.add);
      room.broadcast('tick').listen(objects.add, onError: errors.add);
      final server = await RealtimeServer.next(sockets);
      await server.acceptJoin();
      server
        ..broadcast('room:1', 'cursor', {'x': 1, 'y': 2})
        ..broadcast('room:1', 'tick', 3)
        ..broadcast('room:1', 'tick', {'n': 4})
        ..broadcast('room:1', 'other', {'n': 5})
        ..broadcast('room:2', 'cursor', {'x': 9})
        ..send('room:1', 'broadcast', 'nope');
      await pump();
      expect(cursors, [
        {'x': 1, 'y': 2},
      ]);
      expect(ticks, [
        3,
        {'n': 4},
      ]);
      expect(objects, [
        {'n': 4},
      ]);
      expect(errors.single, isA<FormatException>());
    });

    test('send: the event and its payload, handed over without '
        'waiting for the server', () async {
      final room = realtime.channel('room:1');
      room.broadcast('cursor').listen(null);
      final server = await RealtimeServer.next(sockets);
      final join = await server.acceptJoin();
      await room.send('cursor', {'x': 3, 'y': 4});
      await room.send('ping');
      final frames = server.framesOf('broadcast');
      expect(frames.first['topic'], 'realtime:room:1');
      expect(frames.first['join_ref'], join['ref']);
      expect(frames.first['payload'], {
        'type': 'broadcast',
        'event': 'cursor',
        'payload': {'x': 3, 'y': 4},
      });
      expect(frames.last['payload'], {
        'type': 'broadcast',
        'event': 'ping',
        'payload': <String, Object?>{},
      });
    });

    test('ack: send waits for the server, and fails when it '
        'refuses', () async {
      final room = realtime.channel('room:1', ack: true);
      room.broadcast('cursor').listen(null);
      final server = await RealtimeServer.next(sockets);
      final join = await server.acceptJoin();
      expect(RealtimeServer.configOf(join)['broadcast'], {
        'ack': true,
        'self': false,
      });

      var taken = false;
      final sent = room.send('cursor', {'x': 1}).then((_) => taken = true);
      final frame = await server.take('broadcast');
      await pump();
      expect(taken, isFalse, reason: 'no reply yet');
      server.reply(frame);
      await sent;
      expect(taken, isTrue);

      final refused = room.send('cursor', {'x': 2});
      server.reply(
        await server.take('broadcast'),
        status: 'error',
        response: {'error': 'payload_size_exceeded'},
      );
      await expectLater(
        refused,
        throwsA(
          isA<PhoenixPushException>().having(
            (error) => error.reply?.response,
            'response',
            {'error': 'payload_size_exceeded'},
          ),
        ),
      );

      // No answer at all.
      await expectLater(
        room.send('cursor', {'x': 3}),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('self: asked in the join, and the own broadcast comes '
        'back', () async {
      final room = realtime.channel('room:1', self: true);
      final received = <Object?>[];
      room.broadcast('cursor').listen(received.add);
      final server = await RealtimeServer.next(sockets);
      final join = await server.acceptJoin();
      expect(RealtimeServer.configOf(join)['broadcast'], {
        'ack': false,
        'self': true,
      });
      await room.send('cursor', {'x': 1});
      final frame = await server.take('broadcast');
      // The server sends it to everyone, the sender included.
      server.send('room:1', 'broadcast', frame['payload']);
      await pump();
      expect(received, [
        {'x': 1},
      ]);
    });

    test('send joins a channel nothing listens to; it stays joined '
        'until it is left', () async {
      final room = realtime.channel('room:1');
      final sent = room.send('cursor', {'x': 1});
      final server = await RealtimeServer.next(sockets);
      await server.acceptJoin();
      await sent;
      expect(server.framesOf('broadcast'), hasLength(1));
      await pump(10);
      expect(server.framesOf('phx_leave'), isEmpty);
      expect(room.isJoined, isTrue);

      await room.send('cursor', {'x': 2});
      expect(server.framesOf('phx_join'), hasLength(1));
      expect(server.framesOf('broadcast'), hasLength(2));

      final left = room.leave();
      await server.accept('phx_leave');
      await left;
      expect(room.isJoined, isFalse);
      expect(server.socket.closedByClient, isTrue);
    });

    test('send fails when the channel cannot be joined', () async {
      final room = realtime.channel('room:1', private: true);
      final sent = room.send('cursor', {'x': 1});
      final server = await RealtimeServer.next(sockets);
      server.reply(
        await server.take('phx_join'),
        status: 'error',
        response: {'reason': 'Unauthorized'},
      );
      await expectLater(sent, throwsA(isA<PhoenixJoinException>()));
      // Joined for the send only: not tried again for nobody.
      await pump(10);
      expect(realtime.channels, isEmpty);
      expect(server.framesOf('phx_join'), hasLength(1));
      expect(server.socket.closedByClient, isTrue);
    });
  });

  group('presence', () {
    test('the list after the state of the join, and again after '
        'every diff', () async {
      final room = realtime.channel('room:1');
      final lists = <List<String>>[];
      room.presence().listen((present) => lists.add(refs(present)));
      final server = await RealtimeServer.next(sockets);
      final join = await server.acceptJoin();
      expect(RealtimeServer.configOf(join)['presence'], {
        'key': '',
        'enabled': true,
      });
      await pump();
      expect(lists, isEmpty, reason: 'nothing known before the state');

      server.send('room:1', 'presence_state', {
        'ann': metas({
          'a1': {'name': 'Ann'},
        }),
        'bob': metas({
          'b1': {'name': 'Bob'},
        }),
      });
      await pump();
      server.send('room:1', 'presence_diff', {
        'joins': {
          'cid': metas({'c1': {}}),
          // A second device of ann.
          'ann': metas({'a2': {}}),
        },
        'leaves': {
          'bob': metas({'b1': {}}),
        },
      });
      await pump();
      server.send('room:1', 'presence_diff', {
        'joins': <String, Object?>{},
        'leaves': {
          'ann': metas({'a1': {}}),
        },
      });
      await pump();
      expect(lists, [
        ['ann/a1', 'bob/b1'],
        ['ann/a1', 'ann/a2', 'cid/c1'],
        ['ann/a2', 'cid/c1'],
      ]);
    });

    test('a listener that comes later gets the list at once, with '
        'what each tracked', () async {
      final room = realtime.channel('room:1');
      room.presence().listen(null);
      final server = await RealtimeServer.next(sockets);
      await server.acceptJoin();
      server.send('room:1', 'presence_state', {
        'ann': metas({
          'a1': {'name': 'Ann', 'phx_ref_prev': 'a0'},
        }),
      });
      await pump();
      final present = await room.presence().first;
      expect(present.single.key, 'ann');
      expect(present.single.ref, 'a1');
      expect(present.single.state, {'name': 'Ann'});
      await pump();
      expect(server.framesOf('phx_join'), hasLength(1));
    });

    test('after a rejoin: diffs wait for the new state, which says '
        'who left meanwhile', () async {
      final lists = <List<String>>[];
      realtime
          .channel('room:1')
          .presence()
          .listen((present) => lists.add(refs(present)));
      final first = await RealtimeServer.next(sockets);
      await first.acceptJoin();
      first.send('room:1', 'presence_state', {
        'ann': metas({'a1': {}}),
        'bob': metas({'b1': {}}),
      });
      await pump();

      await first.socket.drop();
      final second = await RealtimeServer.next(sockets);
      await second.acceptJoin();
      // A diff of the new join before its state: kept for after it.
      second.send('room:1', 'presence_diff', {
        'joins': {
          'dan': metas({'d1': {}}),
        },
        'leaves': <String, Object?>{},
      });
      await pump();
      expect(lists, hasLength(1), reason: 'the diff waits');
      second.send('room:1', 'presence_state', {
        'ann': metas({'a1': {}}),
        'cid': metas({'c1': {}}),
      });
      await pump();
      expect(lists, [
        ['ann/a1', 'bob/b1'],
        ['ann/a1', 'cid/c1', 'dan/d1'],
      ]);
    });

    test('track: the state is pushed and answered; tracking again '
        'replaces it; untrack ends it', () async {
      final room = realtime.channel('room:1', presenceKey: 'ann');
      room.presence().listen(null);
      final server = await RealtimeServer.next(sockets);
      final join = await server.acceptJoin();
      expect(RealtimeServer.configOf(join)['presence'], {
        'key': 'ann',
        'enabled': true,
      });

      var tracked = false;
      final track = room.track({'name': 'Ann'}).then((_) => tracked = true);
      final frame = await server.take('presence');
      expect(frame['topic'], 'realtime:room:1');
      expect(frame['payload'], {
        'type': 'presence',
        'event': 'track',
        'payload': {'name': 'Ann'},
      });
      await pump();
      expect(tracked, isFalse, reason: 'no reply yet');
      server.reply(frame);
      await track;

      final again = room.track({'name': 'Ann', 'typing': true});
      final second = await server.accept('presence');
      await again;
      expect((second['payload']! as Map)['payload'], {
        'name': 'Ann',
        'typing': true,
      });

      final untrack = room.untrack();
      final last = await server.accept('presence');
      await untrack;
      expect(last['payload'], {'type': 'presence', 'event': 'untrack'});
      await room.untrack();
      await pump();
      expect(server.framesOf('presence'), hasLength(3));
      expect(server.framesOf('phx_join'), hasLength(1));
    });

    test('track fails when the server refuses the state', () async {
      final room = realtime.channel('room:1');
      final track = room.track({'name': 'Ann'});
      final server = await RealtimeServer.next(sockets);
      await server.acceptJoin();
      server.reply(
        await server.take('presence'),
        status: 'error',
        response: {'reason': 'Presence track payload must be a map'},
      );
      await expectLater(track, throwsA(isA<PhoenixPushException>()));
      // Not present, so nothing keeps the channel: it is left, and a
      // later join would not track behind the caller's back.
      await server.accept('phx_leave');
      await pump();
      expect(realtime.channels, isEmpty);
    });

    test('what is tracked keeps the channel joined, and is tracked '
        'again after a rejoin', () async {
      final room = realtime.channel('room:1');
      final track = room.track({'name': 'Ann'});
      final first = await RealtimeServer.next(sockets);
      final join = await first.acceptJoin();
      expect(
        (RealtimeServer.configOf(join)['presence']! as Map)['enabled'],
        isTrue,
      );
      await first.accept('presence');
      await track;
      await pump(10);
      expect(first.framesOf('phx_leave'), isEmpty);
      expect(first.framesOf('presence'), hasLength(1));

      await first.socket.drop();
      final second = await RealtimeServer.next(sockets);
      await second.acceptJoin();
      final again = await second.accept('presence');
      expect(again['payload'], {
        'type': 'presence',
        'event': 'track',
        'payload': {'name': 'Ann'},
      });
      await pump(10);
      expect(second.framesOf('presence'), hasLength(1));

      // Nothing listens and nothing is tracked any more: left.
      final untrack = room.untrack();
      await second.accept('presence');
      await untrack;
      await second.accept('phx_leave');
      await pump();
      expect(second.socket.closedByClient, isTrue);
    });

    test('presence first used on a joined channel joins it again '
        'with presence on, and it stays on', () async {
      final room = realtime.channel('room:1');
      final broadcasts = <Object?>[];
      room.broadcast('x').listen(broadcasts.add);
      final server = await RealtimeServer.next(sockets);
      final first = await server.acceptJoin();
      expect(
        (RealtimeServer.configOf(first)['presence']! as Map)['enabled'],
        isFalse,
      );

      final track = room.track({'name': 'Ann'});
      await server.accept('phx_leave');
      final second = await server.acceptJoin();
      expect(
        (RealtimeServer.configOf(second)['presence']! as Map)['enabled'],
        isTrue,
      );
      final frame = await server.accept('presence');
      expect(frame['join_ref'], second['ref']);
      await track;

      final untrack = room.untrack();
      await server.accept('presence');
      await untrack;
      await pump(10);
      // Still used by the broadcast listener, and not joined a third
      // time to turn presence off.
      expect(server.framesOf('phx_join'), hasLength(2));
      server.broadcast('room:1', 'x', {'n': 1});
      await pump();
      expect(broadcasts, hasLength(1));
    });
  });

  group('the access token', () {
    test('a new token of the same user is sent to every joined '
        'channel, without joining again', () async {
      final tokens = [
        for (var n = 1; n <= 2; n++) unsignedToken({'sub': 'ann', 'iat': n}),
      ];
      login.token = tokens.first;
      realtime.channel('a').broadcast('x').listen(null);
      realtime.channel('b').broadcast('x').listen(null);
      final server = await RealtimeServer.next(sockets);
      final joins = [await server.acceptJoin(), await server.acceptJoin()];
      expect(RealtimeServer.tokenOf(joins.first), tokens.first);

      login.signIn(tokens.last);
      final first = [
        await server.take('access_token'),
        await server.take('access_token'),
      ];
      expect(
        [for (final frame in first) frame['topic']],
        [
          'realtime:a',
          'realtime:b',
        ],
      );
      expect(
        [for (final frame in first) frame['payload']],
        [
          {'access_token': tokens.last},
          {'access_token': tokens.last},
        ],
      );
      expect(first.first['join_ref'], joins.first['ref']);

      // The same token again: nothing to send.
      login.signIn(tokens.last);
      await pump(10);
      expect(server.framesOf('access_token'), hasLength(2));
      expect(server.framesOf('phx_join'), hasLength(2));
      expect(server.framesOf('phx_leave'), isEmpty);
    });

    test('another user, and nobody after a logout: the channel is joined '
        "again with the new token, and nothing of the user before's "
        'arrives', () async {
      final ann = unsignedToken({'sub': 'ann'});
      final bob = unsignedToken({'sub': 'bob'});
      void accept(RealtimeServer server, Map<String, Object?> join) {
        final asked =
            RealtimeServer.configOf(join)['postgres_changes']! as List<Object?>;
        server.reply(
          join,
          response: {
            'postgres_changes': [
              for (final subscription in asked)
                {...subscription! as Map<String, Object?>, 'id': 7},
            ],
          },
        );
      }

      final rows = <Object?>[];
      login.token = ann;
      realtime
          .channel('db')
          .postgresChanges(table: 'todos')
          .listen((change) => rows.add(change.record['id']));
      final server = await RealtimeServer.next(sockets);
      expect(RealtimeServer.tokenOf(await server.acceptJoin(ids: [7])), ann);
      server.change('db', [7], 'INSERT', record: {'id': 'of ann'});
      await pump();

      login.signIn(bob, name: 'bob');
      // The leave first: the server ends what it sends for Ann.
      await server.take('phx_leave');
      final asBob = await server.take('phx_join');
      expect(RealtimeServer.tokenOf(asBob), bob);
      // Still on its way when the join arrives: a row Ann may read.
      server.change('db', [7], 'INSERT', record: {'id': 'of ann, late'});
      await pump();
      accept(server, asBob);
      await pump();
      server.change('db', [7], 'INSERT', record: {'id': 'of bob'});
      await pump();
      expect(rows, ['of ann', 'of bob']);

      login.signOut();
      await server.take('phx_leave');
      final asNobody = await server.take('phx_join');
      expect(RealtimeServer.tokenOf(asNobody), 'anon-key');
      server.change('db', [7], 'INSERT', record: {'id': 'of bob, late'});
      await pump();
      accept(server, asNobody);
      await pump();
      server.change('db', [7], 'INSERT', record: {'id': 'public'});
      await pump();
      expect(rows, ['of ann', 'of bob', 'public']);
      // A token is never sent to a channel joined as someone else.
      expect(server.framesOf('access_token'), isEmpty);
      expect(server.framesOf('phx_join'), hasLength(3));
    });

    test('a login that changes while a channel is being joined reaches '
        'it right after the join: the same user as a token, another as a '
        'new join', () async {
      final ann = [
        for (var n = 1; n <= 2; n++) unsignedToken({'sub': 'ann', 'iat': n}),
      ];
      final bob = unsignedToken({'sub': 'bob'});
      login.token = ann.first;
      realtime.channel('a').broadcast('x').listen(null);
      final server = await RealtimeServer.next(sockets);
      final join = await server.take('phx_join');
      login.signIn(ann.last);
      await pump(10);
      // The join was sent with the old token: the new one follows it.
      expect(server.framesOf('access_token'), isEmpty);
      expect(RealtimeServer.tokenOf(join), ann.first);
      server.reply(
        join,
        response: {'postgres_changes': <Object?>[]},
      );
      final frame = await server.take('access_token');
      expect(frame['payload'], {'access_token': ann.last});
      await pump(10);
      expect(server.framesOf('access_token'), hasLength(1));

      // Bob signs in while the channel is joined again after a crash.
      server.send('a', 'phx_error', const <String, Object?>{});
      final again = await server.take('phx_join');
      expect(RealtimeServer.tokenOf(again), ann.last);
      login.signIn(bob, name: 'bob');
      await pump(10);
      server.reply(
        again,
        response: {'postgres_changes': <Object?>[]},
      );
      await server.take('phx_leave');
      expect(RealtimeServer.tokenOf(await server.acceptJoin()), bob);
      await pump(10);
      expect(server.framesOf('access_token'), hasLength(1));
      expect(server.framesOf('phx_join'), hasLength(3));
    });

    test('a token that was refreshed reaches the channels at the next '
        'heartbeat', () async {
      await realtime.destroy();
      login.token = 'user-token-1';
      realtime = realtimeOf(sockets, login: login, heartbeat: _ms * 30);
      realtime.channel('a').broadcast('x').listen(null);
      final server = await RealtimeServer.next(sockets);
      await server.acceptJoin();
      // Refreshed: no change of the login is told.
      login.token = 'user-token-2';
      final frame = await server.take('access_token');
      expect(frame['payload'], {'access_token': 'user-token-2'});
    });

    test('service role channels keep the service role key', () async {
      final admin = await realtime.credentials.asServiceRole(
        () => realtime.channel('admin'),
      );
      admin.broadcast('x').listen(null);
      final server = await RealtimeServer.next(sockets);
      expect(RealtimeServer.tokenOf(await server.acceptJoin()), 'service-key');
      login.signIn('user-token-1');
      await realtime.refreshAuth();
      await pump(10);
      expect(server.framesOf('access_token'), isEmpty);
    });
  });

  group('the end', () {
    test('a problem of the channel itself is an error event of every '
        'stream; the server then closes it and the streams are '
        'done', () async {
      final room = realtime.channel('room:1');
      final events = <String>[];
      void follow(Stream<Object?> stream, String name) => stream.listen(
        null,
        onError: (Object error) => events.add('$name: $error'),
        onDone: () => events.add('$name done'),
      );
      follow(room.broadcast('x'), 'broadcast');
      follow(room.presence(), 'presence');
      follow(room.postgresChanges(table: 'todos'), 'changes');
      await room.track({'name': 'Ann'}).timeout(_ms * 20, onTimeout: () {});
      final server = await RealtimeServer.next(sockets);
      final join = await server.acceptJoin(ids: [1]);
      await server.accept('presence');
      server
        ..send('room:1', 'system', {
          'extension': 'system',
          'status': 'error',
          'message': 'Too many messages per second',
          'channel': 'room:1',
        })
        ..socket.pushJson({
          'topic': 'realtime:room:1',
          'event': 'phx_close',
          'payload': <String, Object?>{},
          'ref': join['ref'],
        });
      await pump(10);
      expect(events, [
        'changes: RealtimeException: Too many messages per second',
        'broadcast: RealtimeException: Too many messages per second',
        'presence: RealtimeException: Too many messages per second',
        'changes done',
        'broadcast done',
        'presence done',
      ]);
      expect(realtime.channels, isEmpty);
      expect(server.socket.closedByClient, isTrue);

      // Used again: joined again, and nothing is tracked any more.
      room.broadcast('x').listen(null);
      final again = await RealtimeServer.next(sockets);
      final rejoin = await again.acceptJoin();
      expect(
        (RealtimeServer.configOf(rejoin)['presence']! as Map)['enabled'],
        isFalse,
      );
      await pump(10);
      expect(again.framesOf('presence'), isEmpty);
    });

    test('leave: the streams are done, and using the channel joins it '
        'again', () async {
      final room = realtime.channel('room:1');
      final done = Completer<void>();
      room.broadcast('x').listen(null, onDone: done.complete);
      final server = await RealtimeServer.next(sockets);
      await server.acceptJoin();
      final left = room.leave();
      await server.accept('phx_leave');
      await left;
      await done.future;
      expect(realtime.channels, isEmpty);
      await room.leave();

      final received = <Object?>[];
      room.broadcast('x').listen(received.add);
      final again = await RealtimeServer.next(sockets);
      await again.acceptJoin();
      again.broadcast('room:1', 'x', {'n': 1});
      await pump();
      expect(received, hasLength(1));
    });

    test('a connection that ends for good ends the streams with its '
        'error', () async {
      final errors = <Object>[];
      final done = Completer<void>();
      realtime
          .channel('room:1')
          .broadcast('x')
          .listen(null, onError: errors.add, onDone: done.complete);
      final server = await RealtimeServer.next(sockets);
      await server.acceptJoin();
      await server.socket.closeFromServer(CloseStatus.policyViolation);
      await done.future;
      expect(errors.single, isA<WebSocketException>());
      expect(realtime.channels, isEmpty);
    });

    test('the application stops: every stream is done, the connection '
        'closes, and later use fails', () async {
      final room = realtime.channel('room:1');
      final done = <String>[];
      room.broadcast('x').listen(null, onDone: () => done.add('broadcast'));
      room.presence().listen(null, onDone: () => done.add('presence'));
      realtime
          .postgresChanges(table: 'todos')
          .listen(null, onDone: () => done.add('changes'));
      final server = await RealtimeServer.next(sockets);
      await server.acceptJoin();
      await server.acceptJoin(ids: [1]);

      await realtime.destroy();
      await pump();
      expect(done, unorderedEquals(['broadcast', 'presence', 'changes']));
      expect(server.socket.closedByClient, isTrue);
      expect(realtime.channels, isEmpty);
      expect(realtime.isConnected, isFalse);

      final errors = <Object>[];
      final ended = Completer<void>();
      room
          .broadcast('x')
          .listen(null, onError: errors.add, onDone: ended.complete);
      await ended.future;
      expect(errors.single, isA<StateError>());
      expect('${errors.single}', contains('the application stopped'));
      await expectLater(room.send('x'), throwsA(isA<StateError>()));
      await expectLater(room.track(const {}), throwsA(isA<StateError>()));
      await room.untrack();
      await room.leave();
      await realtime.destroy();
      expect(sockets.connections, hasLength(1));
    });

    test('stopped before anything was used: nothing was opened', () async {
      await realtime.destroy();
      expect(sockets.connections, isEmpty);
    });
  });
}

/// Credentials whose keys the test changes; the service role inside
/// [asServiceRole].
final class _Keys implements SupabaseCredentials {
  static final _service = Object();

  /// The anon key now.
  String anon = 'anon-1';

  bool get _isService => Zone.current[_service] == true;

  @override
  String get apiKey => _isService ? 'service-key' : anon;

  @override
  Future<String> accessToken() async =>
      _isService ? 'service-token' : 'anon-token';

  @override
  SupabaseCaller get caller =>
      _isService ? const SupabaseCaller.service() : const SupabaseCaller.anon();

  @override
  Future<T> asServiceRole<T>(FutureOr<T> Function() body) =>
      runZoned(() async => await body(), zoneValues: {_service: true});
}
