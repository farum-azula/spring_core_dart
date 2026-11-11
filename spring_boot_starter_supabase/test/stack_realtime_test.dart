@Tags(['supabase', 'supabase-stack'])
library;

// Level 4, Realtime: the changes of the rows of a published table as the
// server sends them (filtered by row-level security and by a filter),
// the streams of a repository on them (deletes and rows that leave a
// condition, which a filter of Realtime does not send), broadcast and
// presence between two clients, a refreshed token on an open channel,
// and the join after a lost connection.
import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:test/test.dart';

import 'stack_support.dart';

void main() {
  group('Realtime of the stack', skip: Stack.skip, () {
    late StackApp ada;
    late StackApp bob;

    setUpAll(() async {
      Stack.require();
      ada = await StackApp.start(recordSockets: true);
      bob = await StackApp.start();
      await ada.signInAsNewUser();
      await bob.signInAsNewUser();
    });

    tearDownAll(() async {
      // Whatever a failed test left behind.
      for (final app in [ada, bob]) {
        await app.credentials.asServiceRole(() async {
          for (final table in ['/todos', '/messages']) {
            await app.rest(
              HttpMethod.delete,
              table,
              query: {'owner': 'eq.${app.userId}'},
            );
          }
        });
        await app.close();
      }
    });

    bool sameId(Object? a, Object? b) => '$a' == '$b';

    Future<Todo> save(StackApp app, Todo todo) =>
        app.run(() => app.todos.save(todo));

    Future<void> delete(StackApp app, Iterable<Todo> todos) => app.run(
      () => app.todos.deleteAllById([for (final todo in todos) todo.id!]),
    );

    // The server starts to send the changes of a table some time after
    // the join: rows are saved until the first of them is reported.
    Future<void> subscribed(
      Recorder<RealtimeRowChange> changes,
      StackApp app, {
      String? listId,
    }) async {
      final list = listId ?? Stack.unique('probe');
      final probes = <Todo>[];
      await changes.provoke(
        (n) async =>
            probes.add(await save(app, Todo(title: 'probe $n', listId: list))),
        (change) =>
            change.kind == RealtimeChangeKind.insert &&
            change.record['list_id'] == list,
        what:
            'the first change of todos (is the table in the publication '
            'supabase_realtime?)',
      );
      await delete(app, probes);
    }

    group('the changes of rows', () {
      test('an insert, an update and a delete of a published table '
          'arrive, as the server writes them', () async {
        final listId = Stack.unique('l');
        final changes = Recorder(ada.realtime.postgresChanges(table: 'todos'));
        try {
          await subscribed(changes, ada);

          final saved = await save(
            ada,
            Todo(title: 'first', listId: listId, priority: Priority.high),
          );
          final insert = await changes.next(
            (c) =>
                c.kind == RealtimeChangeKind.insert &&
                sameId(c.record['id'], saved.id),
            what: 'the insert',
          );
          expect(insert.schema, 'public');
          expect(insert.table, 'todos');
          expect(insert.record['title'], 'first');
          expect(insert.record['list_id'], listId);
          expect(insert.record['priority'], 'high');
          expect(insert.record['owner'], ada.userId);
          expect(insert.oldRecord, isEmpty);
          expect(insert.commitTime, isNotNull);
          expect(insert.columns.keys, containsAll(['id', 'title', 'done']));
          expect(insert.errors, isEmpty);

          await save(ada, saved..done = true);
          final update = await changes.next(
            (c) =>
                c.kind == RealtimeChangeKind.update &&
                sameId(c.record['id'], saved.id),
            what: 'the update',
          );
          expect(update.record['done'], isTrue);
          expect(update.record['version'], 2);
          // Without `replica identity full`: the key of the old row.
          expect(sameId(update.oldRecord['id'], saved.id), isTrue);

          await delete(ada, [saved]);
          final deleted = await changes.next(
            (c) =>
                c.kind == RealtimeChangeKind.delete &&
                sameId(c.oldRecord['id'], saved.id),
            what: 'the delete',
          );
          expect(deleted.record, isEmpty);
          expect(changes.errors, isEmpty);
        } finally {
          await changes.cancel();
        }
      });

      test('row-level security: the rows of another user do not '
          'arrive, the key of a row he deletes does', () async {
        final listId = Stack.unique('l');
        final changes = Recorder(ada.realtime.postgresChanges(table: 'todos'));
        final rows = <Todo>[];
        Todo? his;
        try {
          await subscribed(changes, ada);

          his = await save(bob, Todo(title: "Bob's", listId: listId));
          await save(bob, his..done = true);
          // Changes arrive in the order of their commits: when this one
          // is here, Bob's would have been.
          rows.add(await save(ada, Todo(title: "Ada's", listId: listId)));
          await changes.next(
            (c) => sameId(c.record['id'], rows.single.id),
            what: "the insert of Ada's row",
          );

          expect(
            changes.events.where(
              (c) =>
                  c.record['owner'] == bob.userId ||
                  sameId(c.record['id'], his!.id),
            ),
            isEmpty,
          );

          // A delete is not checked against the policies (the row is
          // gone, only its key is known): it arrives, as the key.
          final hisId = his.id;
          await delete(bob, [his]);
          his = null;
          final deleted = await changes.next(
            (c) =>
                c.kind == RealtimeChangeKind.delete &&
                sameId(c.oldRecord['id'], hisId),
            what: "the delete of Bob's row",
          );
          expect(deleted.oldRecord.keys, ['id']);
          expect(deleted.record, isEmpty);
          expect(changes.errors, isEmpty);
        } finally {
          await changes.cancel();
          await delete(ada, rows);
          if (his != null) {
            await delete(bob, [his]);
          }
        }
      });

      test('a filter of Realtime sends no delete and no update that takes '
          'a row out of it (why a repository does not use one)', () async {
        final listId = Stack.unique('l');
        final other = Stack.unique('l');
        final filtered = Recorder(
          ada.realtime.postgresChanges(
            table: 'todos',
            filter: 'list_id=eq.$listId',
          ),
        );
        final whole = Recorder(ada.realtime.postgresChanges(table: 'todos'));
        final rows = <Todo>[];
        try {
          await subscribed(filtered, ada, listId: listId);
          await subscribed(whole, ada);

          final moved = await save(ada, Todo(title: 'moved', listId: listId));
          final gone = await save(ada, Todo(title: 'gone', listId: listId));
          rows.addAll([moved, gone]);
          await filtered.next(
            (c) => sameId(c.record['id'], gone.id),
            what: 'the insert, with the filter',
          );

          await save(ada, moved..listId = other);
          await whole.next(
            (c) =>
                c.kind == RealtimeChangeKind.update &&
                sameId(c.record['id'], moved.id),
            what: 'the update, without a filter',
          );
          await delete(ada, [gone]);
          rows.remove(gone);
          final deleted = await whole.next(
            (c) =>
                c.kind == RealtimeChangeKind.delete &&
                sameId(c.oldRecord['id'], gone.id),
            what: 'the delete, without a filter',
          );
          // The key only: nothing a filter could test.
          expect(deleted.oldRecord.keys, ['id']);

          // In the order of the commits: when this one is here, the
          // update and the delete would have been.
          rows.add(await save(ada, Todo(title: 'marker', listId: listId)));
          await filtered.next(
            (c) => c.record['title'] == 'marker',
            what: 'the marker, with the filter',
          );
          expect(
            filtered.events.where(
              (c) =>
                  c.kind == RealtimeChangeKind.delete ||
                  sameId(c.record['id'], moved.id) &&
                      c.kind == RealtimeChangeKind.update,
            ),
            isEmpty,
          );
          expect(filtered.errors, isEmpty);
          expect(whole.errors, isEmpty);
        } finally {
          await filtered.cancel();
          await whole.cancel();
          await delete(ada, rows);
        }
      });

      test('the changes of a repository (changesBy...) are narrowed by its '
          'condition, the rows come as entities, a delete as its id', () async {
        final listId = Stack.unique('l');
        final other = Stack.unique('l');
        final changes = Recorder(ada.todos.changesByListId(listId));
        final rows = <Todo>[];
        try {
          await changes.provoke(
            (n) async => rows.add(
              await save(ada, Todo(title: 'probe $n', listId: listId)),
            ),
            (change) => change.kind == RowChangeKind.insert,
            what: 'the first change of the list',
          );

          rows.add(await save(ada, Todo(title: 'elsewhere', listId: other)));
          final wanted = await save(
            ada,
            Todo(
              title: 'wanted',
              listId: listId,
              priority: Priority.high,
              createdAt: DateTime.utc(2026, 3, 4, 5, 6, 7),
            ),
          );
          rows.add(wanted);
          final insert = await changes.next(
            (c) => c.kind == RowChangeKind.insert && c.row?.title == 'wanted',
            what: 'the insert of the list',
          );
          expect(insert.id, wanted.id);
          expect(insert.row?.id, wanted.id);
          expect(insert.row?.priority, Priority.high);
          expect(insert.row?.done, isFalse);
          expect(insert.row?.version, 1);
          expect(
            insert.row?.createdAt?.toUtc(),
            DateTime.utc(2026, 3, 4, 5, 6, 7),
          );

          final closed = await save(ada, wanted..done = true);
          final update = await changes.next(
            (c) => c.kind == RowChangeKind.update && c.id == wanted.id,
            what: 'the update of the list',
          );
          expect(update.row?.done, isTrue);

          expect(
            changes.events
                .where((c) => c.row != null)
                .map((c) => c.row!.listId),
            everyElement(listId),
          );

          // The row leaves the list: reported, with the row as it is now
          // (the table's replica identity is the key: no previous row).
          await save(ada, closed..listId = other);
          final left = await changes.next(
            (c) =>
                c.kind == RowChangeKind.update &&
                c.id == wanted.id &&
                c.row?.listId == other,
            what: 'the update that takes the row out of the list',
          );
          expect(left.previous, isNull);

          await delete(ada, [wanted]);
          rows.remove(wanted);
          final deleted = await changes.next(
            (c) => c.kind == RowChangeKind.delete && c.id == wanted.id,
            what: 'the delete',
          );
          expect(deleted.row, isNull);
          expect(deleted.previous, isNull);
          expect(changes.errors, isEmpty);
        } finally {
          await changes.cancel();
          await delete(ada, rows);
        }
      });

      test('a watched query (watchBy...) follows the rows', () async {
        final listId = Stack.unique('l');
        final lists = Recorder(ada.todos.watchByListId(listId));
        final rows = <Todo>[];
        try {
          // What is there now, first.
          expect(
            await lists.next((_) => true, what: 'the first list'),
            isEmpty,
          );

          await lists.provoke(
            (n) async => rows.add(
              await save(ada, Todo(title: 'probe $n', listId: listId)),
            ),
            (list) => list.isNotEmpty,
            what: 'a list with a row',
          );
          final last = await save(ada, Todo(title: 'last', listId: listId));
          rows.add(last);
          final all = await lists.next(
            (list) => list.any((todo) => todo.title == 'last'),
            what: 'the list with the last row',
          );
          expect(all.map((todo) => todo.id).toSet(), {
            for (final row in rows) row.id,
          });

          // A row that leaves the condition leaves the list.
          final moved = lists.events.length;
          await save(ada, last..listId = Stack.unique('l'));
          final without = await lists.next(
            (list) => list.every((todo) => todo.id != last.id),
            from: moved,
            what: 'the list without the row that moved',
          );
          expect(without, hasLength(rows.length - 1));

          final from = lists.events.length;
          await delete(ada, rows);
          rows.clear();
          expect(
            await lists.next(
              (list) => list.isEmpty,
              from: from,
              what: 'the empty list',
            ),
            isEmpty,
          );
          expect(lists.errors, isEmpty);
        } finally {
          await lists.cancel();
          await delete(ada, rows);
        }
      });

      test('a declared channel with a filter (@PostgresChanges) gets the '
          'rows of its room from every user who may be read', () async {
        final room = Stack.unique('room');
        final elsewhere = Stack.unique('room');
        Future<void> post(StackApp app, String roomId, String body) async {
          final response = await app.run(
            () => app.rest(
              HttpMethod.post,
              '/messages',
              json: {'room_id': roomId, 'body': body},
            ),
          );
          expect(response.isSuccess, isTrue, reason: response.bodyText);
        }

        final messages = Recorder(ada.room.messages(room));
        try {
          await messages.provoke(
            (n) => post(ada, room, 'probe $n'),
            (change) => change.kind == RealtimeChangeKind.insert,
            what:
                'the first change of messages (is the table in the '
                'publication supabase_realtime?)',
          );
          await post(bob, elsewhere, 'not for this room');
          await post(bob, room, 'hello from Bob');
          final hello = await messages.next(
            (c) => c.record['body'] == 'hello from Bob',
            what: "Bob's message",
          );
          expect(hello.table, 'messages');
          expect(hello.record['owner'], bob.userId);
          expect(
            messages.events.map((c) => c.record['room_id']),
            everyElement(room),
          );
          expect(messages.errors, isEmpty);
        } finally {
          await messages.cancel();
        }
      });
    });

    group('between two clients', () {
      test('a broadcast of one arrives at the other, not at its '
          'sender', () async {
        final id = Stack.unique('r');
        final atAda = Recorder(ada.room.cursors(id));
        final atBob = Recorder(bob.room.cursors(id));
        try {
          // Until both have joined: a broadcast is not kept for a client
          // that joins later.
          final first = await atAda.provoke(
            (n) => bob.run(() => bob.room.moveCursor(id, Cursor(x: n, y: 7))),
            (cursor) => cursor.y == 7,
            what: "Bob's broadcast",
          );
          expect(first.x, isNonNegative);
          expect(atBob.events, isEmpty);

          await atBob.provoke(
            (n) => ada.run(() => ada.room.moveCursor(id, Cursor(x: n, y: 9))),
            (cursor) => cursor.y == 9,
            what: "Ada's broadcast",
          );
          expect(atAda.events.where((cursor) => cursor.y == 9), isEmpty);
          expect(atAda.errors, isEmpty);
          expect(atBob.errors, isEmpty);
        } finally {
          await atAda.cancel();
          await atBob.cancel();
        }
      });

      test('presence: two clients see each other, and one leave', () async {
        final id = Stack.unique('r');
        final atAda = Recorder(ada.room.members(id));
        final atBob = Recorder(bob.room.members(id));
        Set<String> names(List<Member> members) => {
          for (final member in members) member.name,
        };
        try {
          await ada.run(() => ada.room.join(id, Member(name: 'ada')));
          await bob.run(
            () => bob.room.join(id, Member(name: 'bob', typing: true)),
          );
          bool both(List<Member> members) =>
              names(members).length == 2 &&
              names(members).containsAll({'ada', 'bob'});
          await atAda.next(both, what: 'both members, at Ada');
          final seen = await atBob.next(both, what: 'both members, at Bob');
          expect(seen.firstWhere((m) => m.name == 'bob').typing, isTrue);
          expect(seen.firstWhere((m) => m.name == 'ada').typing, isFalse);

          // Bob ends his presence (the channel of the interface, asked of
          // the bean: `Room` declares no method that leaves).
          final from = atAda.events.length;
          await bob.realtime.channels
              .firstWhere((channel) => channel.name == 'room:$id')
              .untrack();
          final left = await atAda.next(
            (members) => !names(members).contains('bob'),
            from: from,
            what: "Bob's leave",
          );
          expect(names(left), {'ada'});
          expect(atAda.errors, isEmpty);
        } finally {
          await atAda.cancel();
          await atBob.cancel();
          for (final app in [ada, bob]) {
            for (final channel in app.realtime.channels) {
              if (channel.name == 'room:$id') {
                await channel.leave();
              }
            }
          }
        }
      });
    });

    group('the connection', () {
      test('a refreshed token is pushed on the open channel, which goes '
          'on without a new join', () async {
        final listId = Stack.unique('l');
        final changes = Recorder(
          ada.realtime.postgresChanges(
            table: 'todos',
            filter: 'list_id=eq.$listId',
          ),
        );
        final rows = <Todo>[];
        int joins() => ada.sockets!.sent
            .where(
              (frame) =>
                  frame.event == 'phx_join' &&
                  (frame.topic ?? '').contains(listId),
            )
            .length;
        try {
          await subscribed(changes, ada, listId: listId);
          final joined = joins();
          expect(joined, greaterThanOrEqualTo(1));

          final before = (await ada.session())!.accessToken;
          // A token says when it was made, to the second.
          await Future<void>.delayed(const Duration(milliseconds: 1100));
          await ada.run(() => ada.auth.refreshSession());
          final after = (await ada.session())!.accessToken;
          expect(after, isNot(before));
          // The change of the login does it by itself; awaited here.
          await ada.realtime.refreshAuth();

          // Handed to the connection by now, on the wire a moment later.
          await ada.sockets!.next(
            (frame) =>
                frame.event == 'access_token' &&
                (frame.topic ?? '').contains(listId) &&
                frame.payload is Map &&
                (frame.payload! as Map)['access_token'] == after,
            what: 'the new token on the channel',
          );

          rows.add(await save(ada, Todo(title: 'after', listId: listId)));
          await changes.next(
            (c) => c.record['title'] == 'after',
            what: 'a change after the refresh',
          );
          expect(joins(), joined);
          expect(changes.errors, isEmpty);
          expect(changes.isDone, isFalse);
        } finally {
          await changes.cancel();
          await delete(ada, rows);
        }
      });

      // Last: it drops the connection every channel of Ada is on.
      test('after a lost connection the channel is joined again and the '
          'changes go on', () async {
        final listId = Stack.unique('l');
        final changes = Recorder(
          ada.realtime.postgresChanges(
            table: 'todos',
            filter: 'list_id=eq.$listId',
          ),
        );
        try {
          await subscribed(changes, ada, listId: listId);
          final connections = ada.sockets!.sessions.length;
          expect(ada.realtime.isConnected, isTrue);

          await ada.sockets!.drop();
          await subscribed(changes, ada, listId: listId);

          expect(ada.sockets!.sessions.length, greaterThan(connections));
          expect(ada.realtime.isConnected, isTrue);
          expect(changes.isDone, isFalse);
        } finally {
          await changes.cancel();
        }
      });
    });
  });
}
