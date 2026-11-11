// What a repository on the store over the REST API has beyond its
// queries: database functions (`@Procedure`) and the streams that follow the
// rows (`watch…By`, `changes…By`), which Realtime feeds.
@Tags(['supabase'])
library;

import 'dart:convert';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app_support.dart';
import 'realtime_support.dart';

Map<String, Object?> _row(
  int id,
  String title, {
  bool done = false,
  String list = 'l1',
}) => {
  'id': id,
  'title': title,
  'list_id': list,
  'done': done,
  'priority': 'low',
  'created_at': '2026-11-10T08:00:00Z',
  'version': 1,
};

// The channel Realtime joins for the changes of the table, whatever the
// condition: a filter of Realtime would hide deletes and rows that leave
// it.
const _channel = 'db-changes:public:todos:*';

// What is asked of Realtime: the whole table.
const _wholeTable = [
  {'event': '*', 'schema': 'public', 'table': 'todos'},
];

void main() {
  late MockHttpTransport transport;
  late MockWebSocketTransport sockets;

  setUp(() {
    transport = MockHttpTransport();
    sockets = MockWebSocketTransport();
  });

  Future<void> withTodos(Future<void> Function(Todos todos) body) =>
      appRunner(transport, [
        'spring.supabase.realtime.timeout=150ms',
        'spring.websocket.client.config.default.reconnect.delay=10ms',
        'spring.websocket.client.config.default.reconnect.max-delay=40ms',
      ]).withBean<WebSocketTransport>(() => sockets).runAsync((context) async {
        expect(context.startupFailure, isNull);
        await body(context.getBean<Todos>());
      });

  test('the store says what it has: functions and changes, nothing of '
      'SQL', () async {
    await appRunner(transport).runAsync((context) async {
      expect(context.startupFailure, isNull);
      final store = context.getBean<PostgrestDataStore>();
      expect(store.name, 'supabase');
      expect(store.capabilities.functions, isTrue);
      expect(store.capabilities.changes, isTrue);
      expect(store.capabilities.transactions, isFalse);
      expect(store.capabilities.locks, isFalse);
      expect(store.capabilities.queries, isFalse);
    });
  });

  group('@Procedure', () {
    test('posts the arguments in snake case to the function and reads its '
        'result', () async {
      transport
          .when(HttpMethod.post, '/rest/v1/rpc/close_all')
          .respond(200, json: 2);
      await withTodos((todos) async {
        expect(await todos.closeAll('l1'), 2);
      });
      final request = transport.requests.single;
      expect(request.method, HttpMethod.post);
      expect(request.url.path, '/rest/v1/rpc/close_all');
      expect(jsonDecode(utf8.decode(request.body!)), {'list_id': 'l1'});
      expect(request.headers['apikey'], 'anon-key');
      expect(sockets.connections, isEmpty);
    });

    test('a function the API refuses is a data access failure', () async {
      transport
          .when(HttpMethod.post, '/rest/v1/rpc/close_all')
          .respond(
            403,
            json: {
              'code': '42501',
              'message': 'permission denied for function close_all',
            },
          );
      await withTodos((todos) async {
        await expectLater(
          todos.closeAll('l1'),
          throwsA(isA<PermissionDeniedDataAccessException>()),
        );
      });
    });
  });

  group('changes…By', () {
    test('subscribes to the whole table, without a filter of Realtime, and '
        'gives every change as a RowChange of the entity', () async {
      await withTodos((todos) async {
        final changes = <RowChange<Todo>>[];
        final subscription = todos.changesByListId('l1').listen(changes.add);
        final server = await RealtimeServer.next(sockets);
        final join = await server.acceptJoin(ids: [7]);
        expect(join['topic'], 'realtime:$_channel');
        expect(RealtimeServer.configOf(join)['postgres_changes'], _wholeTable);

        server
          ..change(_channel, [7], 'INSERT', record: _row(1, 'Buy milk'))
          ..change(
            _channel,
            [7],
            'UPDATE',
            record: _row(1, 'Buy milk', done: true),
            old: {'id': 1},
          )
          ..change(_channel, [7], 'DELETE', old: {'id': 1});
        await pump();

        expect(
          [for (final change in changes) change.kind],
          [RowChangeKind.insert, RowChangeKind.update, RowChangeKind.delete],
        );
        expect([for (final change in changes) change.id], [1, 1, 1]);
        expect(changes[0].row!.title, 'Buy milk');
        expect(changes[0].row!.listId, 'l1');
        expect(changes[0].previous, isNull);
        expect(changes[1].row!.done, isTrue);
        // Only the key of the old row: no entity.
        expect(changes[1].previous, isNull);
        expect(changes[2].row, isNull);
        await subscription.cancel();
      });
      // No query: the changes are the stream.
      expect(transport.requests, isEmpty);
    });

    test('the condition is applied here: a row of another list is left '
        'out, and what may have left the list is not', () async {
      await withTodos((todos) async {
        final changes = <RowChange<Todo>>[];
        final subscription = todos.changesByListId('l1').listen(changes.add);
        final server = await RealtimeServer.next(sockets);
        await server.acceptJoin(ids: [7]);

        server
          // Never of the list.
          ..change(
            _channel,
            [7],
            'INSERT',
            record: _row(2, 'Elsewhere', list: 'l2'),
          )
          // Only the key of the old row: it may have been of the list.
          ..change(
            _channel,
            [7],
            'UPDATE',
            record: _row(3, 'Moved', list: 'l2'),
            old: {'id': 3},
          )
          // A delete has only the key, whatever the list.
          ..change(_channel, [7], 'DELETE', old: {'id': 4});
        await pump();

        expect(
          [for (final change in changes) (change.kind, change.id)],
          [(RowChangeKind.update, 3), (RowChangeKind.delete, 4)],
        );
        expect(changes[0].row!.listId, 'l2');
        expect(changes[0].previous, isNull);
        expect(changes[1].row, isNull);
        expect(changes[1].previous, isNull);
        await subscription.cancel();
      });
    });

    test('with the whole old row (replica identity full) only the rows '
        'that were or are of the list are left', () async {
      await withTodos((todos) async {
        final changes = <RowChange<Todo>>[];
        final subscription = todos.changesByListId('l1').listen(changes.add);
        final server = await RealtimeServer.next(sockets);
        await server.acceptJoin(ids: [7]);

        server
          ..change(
            _channel,
            [7],
            'UPDATE',
            record: _row(2, 'Elsewhere', list: 'l2', done: true),
            old: _row(2, 'Elsewhere', list: 'l2'),
          )
          ..change(
            _channel,
            [7],
            'UPDATE',
            record: _row(3, 'Moved', list: 'l2'),
            old: _row(3, 'Moved'),
          )
          ..change(
            _channel,
            [7],
            'DELETE',
            old: _row(4, 'Elsewhere', list: 'l2'),
          )
          ..change(_channel, [7], 'DELETE', old: _row(5, 'Gone'));
        await pump();

        expect(
          [for (final change in changes) (change.kind, change.id)],
          [(RowChangeKind.update, 3), (RowChangeKind.delete, 5)],
        );
        expect(changes[0].previous!.listId, 'l1');
        expect(changes[1].previous!.title, 'Gone');
        await subscription.cancel();
      });
    });
  });

  group('watch…By', () {
    test('gives the result of its query on listen and again after every '
        'change', () async {
      transport
          .when(HttpMethod.get, '/rest/v1/todos')
          .respond(200, json: [_row(1, 'Buy milk')]);
      await withTodos((todos) async {
        final lists = <List<Todo>>[];
        final subscription = todos.watchByListId('l1').listen(lists.add);
        final server = await RealtimeServer.next(sockets);
        final join = await server.acceptJoin(ids: [7]);
        expect(RealtimeServer.configOf(join)['postgres_changes'], _wholeTable);
        await pump();
        expect(lists, hasLength(1));
        expect(lists.single.single.title, 'Buy milk');

        transport.reset();
        transport
            .when(HttpMethod.get, '/rest/v1/todos')
            .respond(200, json: [_row(1, 'Buy milk'), _row(2, 'Bread')]);
        server.change(_channel, [7], 'INSERT', record: _row(2, 'Bread'));
        await pump();
        expect(lists, hasLength(2));
        expect(
          [for (final todo in lists.last) todo.title],
          [
            'Buy milk',
            'Bread',
          ],
        );
        expect(
          Uri.decodeFull(transport.requests.single.url.query),
          'list_id=eq.l1',
        );
        await subscription.cancel();
      });
    });

    test('queries again after a delete and after an update that takes a '
        'row out of the condition, once per burst; not after an insert '
        'elsewhere', () async {
      transport
          .when(HttpMethod.get, '/rest/v1/todos')
          .respond(200, json: [_row(1, 'Buy milk'), _row(2, 'Bread')]);
      await withTodos((todos) async {
        final lists = <List<Todo>>[];
        final subscription = todos.watchByListId('l1').listen(lists.add);
        final server = await RealtimeServer.next(sockets);
        await server.acceptJoin(ids: [7]);
        await pump();
        expect(lists, hasLength(1));

        transport.reset();
        transport
            .when(HttpMethod.get, '/rest/v1/todos')
            .respond(200, json: [_row(1, 'Buy milk')]);
        server.change(
          _channel,
          [7],
          'INSERT',
          record: _row(9, 'Elsewhere', list: 'l2'),
        );
        await pump();
        expect(lists, hasLength(1));
        expect(transport.requests, isEmpty);

        // The row moves to another list: only the key of the old row.
        server.change(
          _channel,
          [7],
          'UPDATE',
          record: _row(2, 'Bread', list: 'l2'),
          old: {'id': 2},
        );
        await pump();
        expect(lists, hasLength(2));
        expect([for (final todo in lists.last) todo.title], ['Buy milk']);

        transport.reset();
        transport
            .when(HttpMethod.get, '/rest/v1/todos')
            .respond(200, json: <Object?>[]);
        // A burst of deletes: the keys only.
        server
          ..change(_channel, [7], 'DELETE', old: {'id': 1})
          ..change(_channel, [7], 'DELETE', old: {'id': 5})
          ..change(_channel, [7], 'DELETE', old: {'id': 6});
        await pump();
        expect(lists.last, isEmpty);
        expect(transport.requests.length, lessThanOrEqualTo(2));
        await subscription.cancel();
      });
    });

    test('two watched queries of one table share one channel', () async {
      transport
          .when(HttpMethod.get, '/rest/v1/todos')
          .respond(200, json: <Object?>[]);
      await withTodos((todos) async {
        final first = todos.watchByListId('l1').listen(null);
        final second = todos.watchByListId('l2').listen(null);
        final server = await RealtimeServer.next(sockets);
        final join = await server.acceptJoin(ids: [7]);
        expect(join['topic'], 'realtime:$_channel');
        expect(RealtimeServer.configOf(join)['postgres_changes'], _wholeTable);
        await pump();
        expect(server.framesOf('phx_join'), hasLength(1));
        await first.cancel();
        await second.cancel();
      });
    });
  });
}
