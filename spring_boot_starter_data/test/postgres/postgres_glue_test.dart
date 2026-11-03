// The glue the generator wrote into the test application: a PostgreSQL
// driver bean over the `postgres` package, next to the SQLite one (the
// starter lists both packages), without a server.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../spring_gen/postgres/app/postgres_app.spring.dart';
import 'app/postgres_app.dart';

void main() {
  test('the glue makes the PostgreSQL driver bean', () async {
    await const ApplicationContextRunner()
        .withUserConfiguration($application)
        .runAsync((context) async {
          expect(context.startupFailure, isNull);
          expect(context, hasBeanNamed('postgresJdbcDriver'));
          expect(context.getBean<Marker>(), isNotNull);
          final driver = context.getBean<JdbcDriver>(
            qualifier: 'postgresJdbcDriver',
          );
          expect(driver, isA<PostgresJdbcDriver>());
          expect(driver.name, 'postgres');
          expect(driver.schemes, ['postgresql', 'postgres']);
          expect(driver.dialect, isA<PostgresDialect>());
        });
  });

  test('both drivers are there, each for its own scheme', () async {
    await const ApplicationContextRunner()
        .withUserConfiguration($application)
        .runAsync((context) async {
          final names = context.getBeanNamesForType<JdbcDriver>()..sort();
          expect(names, ['postgresJdbcDriver', 'sqlite3JdbcDriver']);
        });
  });

  test('a connection that cannot be made is a SqlError, with no password '
      'in it', () async {
    await const ApplicationContextRunner()
        .withUserConfiguration($application)
        .runAsync((context) async {
          final driver = context.getBean<JdbcDriver>(
            qualifier: 'postgresJdbcDriver',
          );
          // Nothing listens on port 1.
          Object? error;
          try {
            await driver.connect(
              ConnectionSettings(
                url: Uri.parse('postgresql://ann:hunter2@127.0.0.1:1/db'),
                properties: const {'sslmode': 'disable'},
              ),
            );
          } on Object catch (e) {
            error = e;
          }
          expect(error, isA<SqlError>());
          expect((error! as SqlError).connectionLost, isTrue);
          expect('$error', isNot(contains('hunter2')));
          expect(
            driver.dialect.translate(error as SqlError),
            isA<DataAccessResourceFailureException>(),
          );
        });
  });
}
