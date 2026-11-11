@Tags(['supabase'])
library;

import 'dart:convert';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app_support.dart';

Map<String, Object?> _row(
  int id,
  String title, {
  bool done = false,
  int version = 1,
}) => {
  'id': id,
  'title': title,
  'list_id': 'l1',
  'done': done,
  'priority': 'low',
  'created_at': '2026-11-10T08:00:00Z',
  'version': version,
};

void main() {
  late MockHttpTransport transport;

  setUp(() => transport = MockHttpTransport());

  Future<void> withTodos(Future<void> Function(Todos todos) body) =>
      appRunner(transport).runAsync((context) async {
        expect(context.startupFailure, isNull);
        await body(context.getBean<Todos>());
      });

  String query(int request) => Uri.decodeFull(
    transport.requests[request].url.query,
  );

  Object? sent(int request) =>
      jsonDecode(utf8.decode(transport.requests[request].body!));

  group('derived queries become filters of the REST API', () {
    setUp(() {
      transport
          .when(HttpMethod.get, '/rest/v1/todos')
          .respond(
            200,
            json: [_row(1, 'Buy milk')],
          );
    });

    test('equality and an order', () async {
      await withTodos((todos) async {
        final found = await todos.findByDoneOrderByCreatedAtDesc(false);
        expect(found.single.title, 'Buy milk');
        expect(found.single.listId, 'l1');
        expect(found.single.priority, Priority.low);
        expect(found.single.createdAt, DateTime.utc(2026, 11, 10, 8));
      });
      expect(query(0), 'done=eq.false&order=created_at.desc');
      final request = transport.requests.single;
      expect(request.headers['apikey'], 'anon-key');
      expect(request.headers['Authorization'], 'Bearer anon-key');
    });

    test(
      'text patterns are anchored expressions with the text escaped',
      () async {
        await withTodos(
          (todos) => todos.findByTitleStartingWithIgnoreCase(
            'a*b(c',
          ),
        );
        expect(
          transport.requests.single.url.queryParameters['title'],
          r'imatch.^a\*b\(c',
        );
      },
    );

    test('an Or is one parameter, its text values quoted', () async {
      await withTodos(
        (todos) => todos.findByListIdAndDoneOrPriority(
          'a,b)"c',
          true,
          Priority.high,
        ),
      );
      expect(
        transport.requests.single.url.queryParameters['or'],
        r'(and(list_id.eq."a,b)\"c",done.eq.true),priority.eq."high")',
      );
    });

    test('In, Between and the first of an order', () async {
      await withTodos((todos) async {
        await todos.findByIdIn([1, 2]);
        await todos.findByCreatedAtBetween(
          DateTime.utc(2026),
          DateTime.utc(2027),
        );
        await todos.findFirstByListIdOrderByIdDesc('l1');
      });
      expect(query(0), 'id=in.(1,2)');
      expect(
        transport.requests[1].url.queryParametersAll['created_at'],
        ['gte.2026-01-01T00:00:00.000Z', 'lte.2027-01-01T00:00:00.000Z'],
      );
      expect(query(2), 'list_id=eq.l1&order=id.desc&limit=1');
    });
  });

  test('a page asks for its window and for the count', () async {
    transport
        .when(HttpMethod.get, '/rest/v1/todos')
        .respond(200, json: [_row(3, 'c'), _row(4, 'd')]);
    transport
        .when(HttpMethod.get, '/rest/v1/todos')
        .respond(200, json: [], headers: {'Content-Range': '*/7'});
    await withTodos((todos) async {
      final page = await todos.findByListId('l1', PageRequest.of(1, 2));
      expect(page.content.map((t) => t.id), [3, 4]);
      expect(page.totalElements, 7);
      expect(page.totalPages, 4);
    });
    expect(query(0), 'list_id=eq.l1&order=id&offset=2&limit=2');
    expect(transport.requests[1].headers['Prefer'], 'count=exact');
    expect(query(1), 'list_id=eq.l1&select=id&limit=0');
  });

  test('count, exists and delete by a condition', () async {
    transport
        .when(HttpMethod.get, '/rest/v1/todos')
        .respond(200, json: [], headers: {'Content-Range': '*/0'});
    transport
        .when(HttpMethod.get, '/rest/v1/todos')
        .respond(
          200,
          json: [
            {'id': 1},
          ],
        );
    transport
        .when(HttpMethod.delete, '/rest/v1/todos')
        .respond(
          200,
          json: [
            {'id': 1},
            {'id': 2},
          ],
        );
    await withTodos((todos) async {
      expect(await todos.countByDone(true), 0);
      expect(await todos.existsByTitle('x'), isTrue);
      expect(await todos.deleteByDone(true), 2);
      await todos.deleteAll();
    });
    expect(query(1), 'title=eq.x&select=id&limit=1');
    expect(query(2), 'done=eq.true&select=id');
    expect(transport.requests[2].headers['Prefer'], 'return=representation');
    // Every row, as a condition every row meets: a project's database
    // refuses a DELETE without a WHERE.
    expect(query(3), 'id=not.is.null&select=id');
  });

  group('saving', () {
    test(
      'a new entity: the database gives the id, the version starts at 1',
      () async {
        transport
            .when(HttpMethod.post, '/rest/v1/todos')
            .respond(201, json: [_row(9, 'New')]);
        await withTodos((todos) async {
          final saved = await todos.save(Todo(title: 'New', listId: 'l1'));
          expect(saved.id, 9);
          expect(saved.version, 1);
        });
        expect(sent(0), {
          'title': 'New',
          'list_id': 'l1',
          'done': false,
          'priority': 'low',
          'created_at': null,
          'version': 1,
        });
        expect(
          transport.requests.single.headers['Prefer'],
          'return=representation',
        );
      },
    );

    test('an update names the version it read and raises it', () async {
      transport
          .when(HttpMethod.patch, '/rest/v1/todos')
          .respond(200, json: [_row(9, 'Changed', version: 3)]);
      await withTodos((todos) async {
        final saved = await todos.save(
          Todo(title: 'Changed', listId: 'l1', id: 9, version: 2),
        );
        expect(saved.version, 3);
      });
      expect(query(0), 'id=eq.9&version=eq.2');
      final body = sent(0)! as Map<String, Object?>;
      expect(body['version'], 3);
      expect(body.containsKey('id'), isFalse);
    });

    test('no row updated: someone else changed it', () async {
      transport.when(HttpMethod.patch, '/rest/v1/todos').respond(200, json: []);
      await withTodos((todos) async {
        await expectLater(
          todos.save(Todo(title: 'x', listId: 'l1', id: 9, version: 2)),
          throwsA(isA<OptimisticLockingFailureException>()),
        );
      });
    });

    test('without a version, no row updated is a wrong update', () async {
      transport
          .when(HttpMethod.get, '/rest/v1/notes')
          .respond(
            200,
            json: [
              {'id': 'n1', 'text': 'old'},
            ],
          );
      transport.when(HttpMethod.patch, '/rest/v1/notes').respond(200, json: []);
      await appRunner(transport).runAsync((context) async {
        await expectLater(
          context.getBean<Notes>().save(Note(text: 'x', id: 'n1')),
          throwsA(isA<IncorrectUpdateSemanticsDataAccessException>()),
        );
      });
    });
  });

  group('@Json properties', () {
    Map<String, Object?> parcel({Object? packaging}) => {
      'id': 7,
      'label': 'books',
      'packaging':
          packaging ??
          {
            'box': 'L',
            'fragile': true,
            'size': {'width': 30, 'height': 20},
          },
      'stops': [
        {'city': 'Ely', 'day': 1},
        {'city': 'Hull', 'day': null},
      ],
    };

    test(
      'the body sent is nested JSON, the answer is read into the classes',
      () async {
        transport
            .when(HttpMethod.post, '/rest/v1/parcels')
            .respond(201, json: [parcel()]);
        await appRunner(transport).runAsync((context) async {
          expect(context.startupFailure, isNull);
          final saved = await context.getBean<Parcels>().save(
            Parcel(
              label: 'books',
              packaging: Packaging(
                box: 'L',
                fragile: true,
                size: BoxSize(width: 30, height: 20),
              ),
              stops: [
                Stop(city: 'Ely', day: 1),
                Stop(city: 'Hull'),
              ],
            ),
          );
          expect(saved.id, 7);
          expect(saved.packaging.box, 'L');
          expect(saved.packaging.fragile, isTrue);
          expect(saved.packaging.size!.height, 20);
          expect([for (final stop in saved.stops) stop.city], ['Ely', 'Hull']);
          expect(saved.stops.last.day, isNull);
        });
        final body = sent(0)! as Map<String, Object?>;
        expect(body['label'], 'books');
        // An object and an array, not their text.
        expect(body['packaging'], {
          'box': 'L',
          'fragile': true,
          'size': {'width': 30, 'height': 20},
        });
        expect(body['stops'], [
          {'city': 'Ely', 'day': 1},
          {'city': 'Hull', 'day': null},
        ]);
      },
    );

    test('an answer that does not fit the class names the property', () async {
      transport
          .when(HttpMethod.get, '/rest/v1/parcels')
          .respond(
            200,
            json: [
              parcel(packaging: ['secret-4711']),
            ],
          );
      await appRunner(transport).runAsync((context) async {
        await expectLater(
          context.getBean<Parcels>().findByLabel('books'),
          throwsA(
            isA<MappingException>()
                .having(
                  (e) => e.message,
                  'message',
                  contains('Parcel.packaging: the stored JSON cannot be read'),
                )
                .having((e) => e.message, 'message', isNot(contains('4711'))),
          ),
        );
      });
    });
  });

  group("the database's errors are the data starter's exceptions", () {
    for (final (status, body, matcher) in [
      (
        409,
        {'code': '23505', 'message': 'duplicate key value'},
        isA<DuplicateKeyException>(),
      ),
      (
        409,
        {'code': '23503', 'message': 'violates foreign key'},
        isA<DataIntegrityViolationException>(),
      ),
      (
        403,
        {'code': '42501', 'message': 'new row violates row-level security'},
        isA<PermissionDeniedDataAccessException>(),
      ),
      (
        401,
        {'code': 'PGRST301', 'message': 'JWT expired'},
        isA<PermissionDeniedDataAccessException>(),
      ),
      (
        404,
        {'code': 'PGRST205', 'message': 'Could not find the table'},
        isA<InvalidDataAccessResourceUsageException>(),
      ),
      (
        400,
        {'code': 'PGRST100', 'message': 'failed to parse filter'},
        isA<InvalidDataAccessApiUsageException>(),
      ),
      (
        503,
        {'code': 'PGRST002', 'message': 'schema cache'},
        isA<DataAccessResourceFailureException>(),
      ),
    ]) {
      test('$status ${body['code']}', () async {
        transport
            .when(HttpMethod.post, '/rest/v1/todos')
            .respond(status, json: body);
        await withTodos((todos) async {
          await expectLater(
            todos.save(Todo(title: 'x', listId: 'l1')),
            throwsA(matcher),
          );
        });
      });
    }

    test('no answer is a resource failure', () async {
      transport
          .when(HttpMethod.get, '/rest/v1/todos')
          .fail(HttpTransportException('connection refused'));
      await withTodos((todos) async {
        await expectLater(
          todos.findAll(),
          throwsA(isA<DataAccessResourceFailureException>()),
        );
      });
    });
  });

  test('the calls are made as the caller says', () async {
    transport.when(HttpMethod.get, '/rest/v1/todos').respond(200, json: []);
    await appRunner(transport).runAsync((context) async {
      await context.getBean<SupabaseCredentials>().asServiceRole(
        () => context.getBean<Todos>().findAll(),
      );
    });
    expect(transport.requests.single.headers['apikey'], 'service-key');
    expect(
      transport.requests.single.headers['Authorization'],
      'Bearer service-key',
    );
  });

  test('the schema of the configuration is asked for', () async {
    transport.when(HttpMethod.get, '/rest/v1/todos').respond(200, json: []);
    transport
        .when(HttpMethod.post, '/rest/v1/todos')
        .respond(201, json: [_row(1, 'x')]);
    await appRunner(transport, ['spring.supabase.db.schema=app']).runAsync((
      context,
    ) async {
      final todos = context.getBean<Todos>();
      await todos.findAll();
      await todos.save(Todo(title: 'x', listId: 'l1'));
    });
    expect(transport.requests[0].headers['Accept-Profile'], 'app');
    expect(transport.requests[1].headers['Content-Profile'], 'app');
  });
}
