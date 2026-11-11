// The D1 store asked at startup: before the Worker's environment is there
// nothing can be asked; with it, a binding that is missing says what to
// declare, and one that is there gets its table.
import 'package:spring_boot_starter_edge/spring_boot_starter_edge.dart';
import 'package:test/test.dart';

final class _Database implements D1Database {
  final statements = <String>[];
  Object? failure;

  @override
  Future<int> execute(String sql, [List<Object?> parameters = const []]) async {
    if (failure case final failure?) {
      // The failure of the test, whatever it is.
      // ignore: only_throw_errors
      throw failure;
    }
    statements.add(sql.trim().split('\n').first);
    return 0;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) async => const [];
}

void main() {
  test('it is a store that is asked at startup', () {
    expect(
      D1RateLimitStore(_Database.new),
      isA<VerifiableRateLimitStore>(),
    );
  });

  test('before the environment is there nothing is asked', () async {
    var asked = 0;
    final store = D1RateLimitStore(
      () {
        asked++;
        throw StateError('no request has arrived yet');
      },
      environmentLoaded: () => false,
    );
    await store.verify();
    expect(asked, 0);
  });

  test('a binding the Worker does not have: what to declare', () async {
    final store = D1RateLimitStore(
      () => throw StateError('The Worker has no binding "LIMITS"'),
      environmentLoaded: () => true,
    );
    await expectLater(
      store.verify(),
      throwsA(
        isA<RateLimitStoreSetupException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('"LIMITS"'),
            contains('[[d1_databases]]'),
            contains('spring.edge.cloudflare.rate-limit.database'),
          ),
        ),
      ),
    );
  });

  test('the database is there: its table is created, once', () async {
    final database = _Database();
    final store = D1RateLimitStore(() => database, table: 'limits');
    await store.verify();
    await store.verify();
    expect(database.statements, [
      'create table if not exists limits (',
      'create index if not exists limits_expires_at on limits (expires_at)',
      startsWith('delete from limits'),
    ]);
  });

  test('a database that does not answer is no setup problem, and is asked '
      'again', () async {
    final database = _Database()..failure = StateError('D1 is down');
    final store = D1RateLimitStore(() => database);
    await expectLater(store.verify(), throwsStateError);
    database.failure = null;
    await store.verify();
    expect(database.statements, hasLength(3));
  });
}
