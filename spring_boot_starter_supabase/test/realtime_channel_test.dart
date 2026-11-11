@Tags(['supabase'])
library;

import 'dart:async';

import 'package:spring_boot_starter_supabase/spring_auto_configuration.dart';
import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'realtime_room.dart';
import 'realtime_support.dart';
import 'support.dart';

/// Runs [body] as the signed-in user [name].
Future<T> _asUser<T>(String name, FutureOr<T> Function() body) =>
    SecurityContextHolder.runWithContext(() async {
      SecurityContextHolder.getContext().authentication =
          TestingAuthenticationToken(name, null);
      return await body();
    });

void main() {
  late MockWebSocketTransport sockets;
  late ApplicationContextRunner runner;

  setUp(() {
    sockets = MockWebSocketTransport();
    // The Realtime beans by hand until the starter's module has them.
    final wired = springBootStarterSupabaseAutoConfiguration.definitions.any(
      (definition) => definition.name == 'supabaseRealtime',
    );
    runner = const ApplicationContextRunner()
        .withUserConfiguration(roomModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springSecurityCoreAutoConfiguration)
        .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
        .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration)
        .withAutoConfiguration(springBootStarterDataAutoConfiguration)
        .withAutoConfiguration(springBootStarterCacheAutoConfiguration)
        .withAutoConfiguration(springBootStarterSupabaseAutoConfiguration)
        .withAutoConfiguration(
          BeanModule('supabaseRealtimeTest', [
            if (!wired) ...supabaseRealtimeAutoConfiguration,
          ]),
        )
        .withPropertyValues([
          'spring.supabase.url=$projectUrl',
          'spring.supabase.anon-key=anon-key',
          'spring.supabase.realtime.timeout=150ms',
          'spring.websocket.client.config.default.reconnect.delay=10ms',
          'spring.websocket.client.config.default.reconnect.max-delay=40ms',
        ])
        .withBean<HttpTransport>(MockHttpTransport.new)
        .withBean<WebSocketTransport>(() => sockets);
  });

  test('broadcasts: read as the declared type, on the channel the '
      'parameter names', () async {
    await runner.runAsync((context) async {
      expect(context.startupFailure, isNull);
      final room = context.getBean<Room>();
      await pump();
      expect(sockets.connections, isEmpty, reason: 'nothing used yet');

      final cursors = <Cursor>[];
      final errors = <Object>[];
      final raw = <Map<String, Object?>>[];
      final other = <Cursor>[];
      expect(room.cursors('42'), isA<Stream<Cursor>>());
      room.cursors('42').listen(cursors.add, onError: errors.add);
      room.rawCursors('42').listen(raw.add);
      room.cursors('7').listen(other.add);

      final server = await RealtimeServer.next(sockets);
      expect(
        '${server.socket.uri}',
        '$realtimeAddress?vsn=1.0.0&apikey=anon-key',
      );
      final joins = [await server.acceptJoin(), await server.acceptJoin()];
      expect(
        [for (final join in joins) join['topic']],
        [
          'realtime:room:42',
          'realtime:room:7',
        ],
      );
      expect(RealtimeServer.configOf(joins.first)['broadcast'], {
        'ack': false,
        'self': true,
      });
      server
        ..broadcast('room:42', 'cursor', {'x': 1, 'y': 2})
        ..broadcast('room:42', 'cursor', {'nope': true})
        ..broadcast('room:42', 'other', {'x': 8, 'y': 8})
        ..broadcast('room:7', 'cursor', {'x': 3, 'y': 4});
      await pump();
      expect(
        [for (final cursor in cursors) '${cursor.x},${cursor.y}'],
        [
          '1,2',
        ],
      );
      expect(errors.single, isA<MessageConversionException>());
      expect('${errors.single}', contains('Room.cursors'));
      expect(raw, [
        {'x': 1, 'y': 2},
        {'nope': true},
      ]);
      expect([for (final cursor in other) cursor.x], [3]);
      expect(sockets.connections, hasLength(1), reason: 'one connection');
    });
  });

  test('sending: the payload is the parameter the name does not use, '
      'as JSON', () async {
    await runner
        .withPropertyValues(['rooms.prefix=hall', 'rooms.ping=knock'])
        .runAsync((context) async {
          final room = context.getBean<Room>();
          final moved = room.moveCursor('42', const Cursor(x: 3, y: 4));
          final server = await RealtimeServer.next(sockets);
          final join = await server.acceptJoin();
          // The prefix of the name comes from the configuration.
          expect(join['topic'], 'realtime:hall:42');
          await moved;
          await room.ping('42');
          expect(
            [
              for (final frame in server.framesOf('broadcast'))
                frame['payload'],
            ],
            [
              {
                'type': 'broadcast',
                'event': 'cursor',
                'payload': {'x': 3, 'y': 4},
              },
              {
                'type': 'broadcast',
                'event': 'knock',
                'payload': <String, Object?>{},
              },
            ],
          );
          expect(server.framesOf('phx_join'), hasLength(1));
        });
  });

  test('presence: who is there as the declared type; a payload '
      'tracks, none ends the presence', () async {
    await runner.runAsync((context) async {
      final room = context.getBean<Room>();
      final members = <List<Member>>[];
      final presences = <List<RealtimePresence>>[];
      expect(room.members('42'), isA<Stream<List<Member>>>());
      room.members('42').listen(members.add);
      room.presences('42').listen(presences.add);
      final server = await RealtimeServer.next(sockets);
      final join = await server.acceptJoin();
      expect(RealtimeServer.configOf(join)['presence'], {
        'key': '',
        'enabled': true,
      });

      final joined = room.join('42', const Member(name: 'Ann'));
      final track = await server.accept('presence');
      await joined;
      expect(track['payload'], {
        'type': 'presence',
        'event': 'track',
        'payload': {'name': 'Ann', 'typing': false},
      });
      server.send('room:42', 'presence_state', {
        'k1': metas({
          'a1': {'name': 'Ann', 'typing': false},
        }),
        'k2': metas({
          'b1': {'name': 'Bob', 'typing': true},
        }),
      });
      await pump();
      expect(
        [
          for (final member in members.single)
            '${member.name} ${member.typing}',
        ],
        ['Ann false', 'Bob true'],
      );
      expect(refs(presences.single), ['k1/a1', 'k2/b1']);

      final left = room.leave('42');
      final untrack = await server.accept('presence');
      await left;
      expect(untrack['payload'], {'type': 'presence', 'event': 'untrack'});
      expect(server.framesOf('phx_join'), hasLength(1));
    });
  });

  test('database changes: the table, the kind and a filter filled '
      'from the parameters', () async {
    await runner.withPropertyValues(['rooms.table=notes']).runAsync((
      context,
    ) async {
      final room = context.getBean<Room>();
      final messages = <RealtimeRowChange>[];
      final mine = <RealtimeRowChange>[];
      room.messages('42').listen(messages.add);
      // Values are values: one with a comma is quoted, a list is the
      // values of the `in`.
      room.messagesOf('42', ['ann', 'b,ob']).listen(mine.add);
      final server = await RealtimeServer.next(sockets);
      final join = await server.acceptJoin(ids: [1, 2]);
      expect(join['topic'], 'realtime:room:42');
      expect(RealtimeServer.configOf(join)['postgres_changes'], [
        {
          'event': '*',
          'schema': 'public',
          'table': 'messages',
          'filter': 'room_id=eq.42',
        },
        {
          'event': 'INSERT',
          'schema': 'app',
          'table': 'notes',
          'filter': 'room_id=eq.42,author=in.(ann,"b,ob")',
        },
      ]);
      server
        ..change('room:42', [1], 'UPDATE', record: {'id': 1})
        ..change('room:42', [2], 'INSERT', record: {'id': 2});
      await pump();
      expect([for (final change in messages) change.record['id']], [1]);
      expect([for (final change in mine) change.record['id']], [2]);
    });
  });

  test('one channel per name: joined on its first use, with everything '
      'used at once; left when its last stream is cancelled and nothing '
      'is tracked', () async {
    await runner.runAsync((context) async {
      final room = context.getBean<Room>();
      final cursors = room.cursors('42').listen(null);
      final members = room.members('42').listen(null);
      final messages = room.messages('42').listen(null);
      final joining = room.join('42', const Member(name: 'Ann'));
      final server = await RealtimeServer.next(sockets);
      final join = await server.acceptJoin(ids: [1]);
      await server.accept('presence');
      await joining;
      final config = RealtimeServer.configOf(join);
      expect(config['postgres_changes'], hasLength(1));
      expect((config['presence']! as Map)['enabled'], isTrue);
      expect(server.framesOf('phx_join'), hasLength(1));

      await cursors.cancel();
      await members.cancel();
      await pump(10);
      expect(server.framesOf('phx_leave'), isEmpty);
      // The subscription to the changes ends: joined again without it.
      await messages.cancel();
      await server.accept('phx_leave');
      final again = await server.acceptJoin();
      expect(RealtimeServer.configOf(again)['postgres_changes'], isEmpty);
      await server.accept('presence');
      await pump(10);
      expect(server.socket.isClosed, isFalse, reason: 'Ann is tracked');

      final leaving = room.leave('42');
      await server.accept('presence');
      await leaving;
      final leave = await server.accept('phx_leave');
      expect(leave['topic'], 'realtime:room:42');
      await pump();
      expect(server.socket.closedByClient, isTrue);
      expect(context.getBean<SupabaseRealtime>().channels, isEmpty);
    });
  });

  test('a name and a presence key from an expression: the user of the '
      'call; the options of the annotation; a marked payload', () async {
    await runner.runAsync((context) async {
      final desk = context.getBean<Desk>();
      final notes = <String>[];
      await _asUser('ada', () => desk.notes().listen(notes.add));
      final server = await RealtimeServer.next(sockets);
      final join = await server.acceptJoin();
      expect(join['topic'], 'realtime:desk:ada');
      expect(RealtimeServer.configOf(join), {
        'postgres_changes': <Object?>[],
        'broadcast': {'ack': true, 'self': false},
        'presence': {'key': 'ada', 'enabled': false},
        'private': true,
      });
      // Not a token of Supabase: the channel is the application's.
      expect(RealtimeServer.tokenOf(join), 'anon-key');

      // ack: the call waits for the server.
      var sent = false;
      final note = _asUser('ada', () => desk.note('hi')).then((_) {
        sent = true;
      });
      final frame = await server.take('broadcast');
      await pump();
      expect(sent, isFalse);
      server.reply(frame);
      await note;
      expect((frame['payload']! as Map)['payload'], 'hi');
      server.broadcast('desk:ada', 'note', 'welcome');
      await pump();
      expect(notes, ['welcome']);

      // The application's own kind of method.
      final typing = _asUser('ada', desk.typing);
      final typed = await server.accept('broadcast');
      await typing;
      expect((typed['payload']! as Map)['event'], 'typing');

      // Presence on a joined channel: joined again with it.
      final sitting = _asUser('ada', () => desk.sit({'seat': 3}));
      await server.accept('phx_leave');
      final again = await server.acceptJoin();
      expect(RealtimeServer.configOf(again)['presence'], {
        'key': 'ada',
        'enabled': true,
      });
      final track = await server.accept('presence');
      await sitting;
      expect((track['payload']! as Map)['payload'], {'seat': 3});
    });
  });

  test('a value that gives no name is refused before anything is '
      'joined', () async {
    await runner.runAsync((context) async {
      final room = context.getBean<Room>();
      final desk = context.getBean<Desk>();
      // Nobody is signed in: #{authentication.name} has no value.
      await expectLater(desk.note('hi'), throwsArgumentError);
      expect(desk.notes, throwsArgumentError);
      await expectLater(
        room.moveCursor('', const Cursor(x: 1, y: 1)),
        throwsArgumentError,
      );
      expect(() => room.cursors('a\nb'), throwsArgumentError);
      expect(() => room.messagesOf('1', ['a\tb']), throwsArgumentError);
      await pump();
      expect(sockets.connections, isEmpty);
    });
  });

  test('an interface that is declared wrongly stops the start, with '
      'every problem in one message', () {
    runner.withUserConfiguration(brokenRoomModule).run((context) {
      expect(context, hasFailed());
      final message = '${context.startupFailure}';
      expect(message, contains('Invalid @RealtimeChannel interface'));
      for (final problem in [
        'BrokenRoom.wrongReturn: a @Broadcast method returns Stream<T> ',
        'BrokenRoom.extraParameter: a @Broadcast method that returns a ',
        'BrokenRoom.twoPayloads: takes one payload at most',
        'BrokenRoom.noId: "room:{id}": {id} is not a parameter of noId()',
        r'BrokenRoom.noProperty: "${no.such.event}"',
        'BrokenRoom.notAList: a @Presence method that returns a Stream ',
        'BrokenRoom.wrongPresence: a @Presence method returns ',
        'BrokenRoom.wrongStream: a @PostgresChanges method returns ',
        'BrokenRoom.badFilter: "a=eq.{nope}": {nope} is not a parameter ',
        'BrokenRoom.unmarked: needs @Broadcast, @Presence or ',
      ]) {
        expect(message, contains(problem));
      }
      // One line per problem, none twice.
      expect('  - BrokenRoom.'.allMatches(message), hasLength(10));
    });
  });

  test('the values of a filter cannot change it', () {
    const encoder = PostgresFilterEncoder();
    String value(Object? value) => encoder.value(value, '{v}');
    expect(encoder.literal('id=eq.'), 'id=eq.');
    expect(value(42), '42');
    expect(value('plain text'), 'plain text');
    expect(value(RealtimeChangeKind.insert), 'insert');
    expect(value('a,b'), '"a,b"');
    expect(value('1),id=gt.(0'), '"1),id=gt.(0"');
    expect(value(r'say "hi" \ bye'), r'"say \"hi\" \\ bye"');
    expect(value(' padded'), '" padded"');
    // In a list Realtime reads an array of PostgreSQL: a brace would end
    // it, and the word null would be no value.
    expect(value('a}b'), '"a}b"');
    expect(value('{a}'), '"{a}"');
    expect(value(['x', 'NULL', 'null']), 'x,"NULL","null"');
    expect(value('nullable'), 'nullable');
    // Nothing a filter of Realtime can say.
    expect(() => value(''), throwsArgumentError);
    expect(() => value(['ok', '']), throwsArgumentError);
    expect(value([1, 2, 3]), '1,2,3');
    expect(value(['a', 'b,c']), 'a,"b,c"');
    expect(() => value(null), throwsArgumentError);
    expect(() => value('a\nb'), throwsArgumentError);
    expect(() => value(['ok', null]), throwsArgumentError);
  });

  test('the beans: Realtime stops with the application, and gives way '
      "to the application's own", () async {
    late MockWebSocket connection;
    final done = Completer<void>();
    await runner.runAsync((context) async {
      final realtime = context.getBean<SupabaseRealtime>();
      expect(context.getBean<RealtimeChannelFactory>().realtime, realtime);
      context
          .getBean<Room>()
          .cursors('1')
          .listen(
            null,
            onDone: done.complete,
          );
      final server = await RealtimeServer.next(sockets);
      await server.acceptJoin();
      connection = server.socket;
    });
    await done.future;
    expect(connection.closedByClient, isTrue);

    late SupabaseRealtime own;
    await runner
        .withBean<SupabaseRealtime>(() => own = realtimeOf(sockets))
        .runAsync((context) async {
          expect(context.getBean<SupabaseRealtime>(), same(own));
          expect(context.getBean<RealtimeChannelFactory>().realtime, same(own));
        });
  });
}
