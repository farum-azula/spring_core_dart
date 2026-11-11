@Tags(['postgres'])
library;

// The rate limiter's SQL store on a PostgreSQL server: the same checks as
// on SQLite, over pools of several connections.
import 'dart:io';
import 'dart:isolate';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../postgres/support.dart';
import 'support.dart';

void main() {
  group('on PostgreSQL', skip: postgresServerSkip, () {
    usePostgresServer();

    late String schema;
    setUp(() async => schema = await newSchema());

    rateLimitStoreContract(
      () => postgresSource(schema, maxSize: 8),
      ddlFile: _shipped('lib/sql/rate_limit/postgresql.sql').readAsStringSync(),
    );

    test('the table is unlogged', () async {
      final source = await postgresSource(schema);
      await JdbcRateLimitStore(
        source,
        createTable: true,
      ).tryAcquire('k', const RateLimit(5, Duration(minutes: 1)));
      final connection = await source.getConnection();
      try {
        final result = await connection.query(
          'select relpersistence::text as relpersistence from pg_class c '
          'join pg_namespace n on n.oid = c.relnamespace '
          "where c.relname = 'rate_limit' and n.nspname = ?",
          [schema],
        );
        expect('${result.rows.single['relpersistence']}', 'u');
      } finally {
        await source.releaseConnection(connection);
      }
    });
  });
}

// The file of this package, wherever the tests are run from.
File _shipped(String path) => File.fromUri(
  Isolate.resolvePackageUriSync(
    Uri.parse('package:spring_boot_starter_data/spring_boot_starter_data.dart'),
  )!.resolve('../$path'),
);
