@Tags(['docker'])
library;

// A @DataTest on a PostgreSQL the test starts: a @Container with
// @ServiceConnection puts the container's URL and user into spring.datasource.*
// (replaceDatabase: false keeps it from being swapped for SQLite), the
// migrations run on it, and each test still rolls back. Skipped without Docker
// (a failure with CONTAINERS_REQUIRED=true). The generator writes
// spring/data_test/container_postgres.test.spring.dart.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/containers.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../spring/data_test/container_postgres.test.spring.dart';
import 'postgres_app/postgres_data_app.dart';

@DataTest(
  application: 'test/data_test/postgres_app/postgres_data_app.dart',
  replaceDatabase: false,
)
@Testcontainers()
class ContainerPostgresTest {
  @Container()
  @ServiceConnection()
  static final postgres = PostgresContainer('postgres:17');

  @Autowired()
  late BookRepository books;

  @Autowired()
  late DataSource dataSource;

  @Autowired()
  late JdbcClient jdbc;

  @Test()
  Future<void> runsOnTheContainersPostgres() async {
    expect(dataSource.settings.url.toString(), postgres.jdbcUrl);
    final version = await jdbc.sql('select version()').query<String>().single();
    expect(version, startsWith('PostgreSQL 17'));
  }

  @Test()
  Future<void> appliesTheMigrations() async {
    final scripts = await jdbc
        .sql('select script from schema_history order by installed_rank')
        .query<String>()
        .list();
    expect(scripts, hasLength(2));
    expect(scripts.first, contains('V1__books'));
  }

  @Test()
  Future<void> savesABook() async {
    final saved = await books.save(Book(title: 'Dune', year: 1965));
    expect(saved.id, isNotNull); // the key the server generated
    await books.save(Book(title: 'Neuromancer', year: 1984));
    expect(await books.count(), 2);
    expect(
      (await books.findByYearGreaterThan(1970)).single.title,
      'Neuromancer',
    );
  }

  // Rolled back at the end of the test before: the table is empty again.
  @Test()
  Future<void> startsEmptyAgain() async {
    expect(await books.count(), 0);
  }

  @Test()
  Future<void> theConstraintsOfTheMigrationsHold() async {
    await books.save(Book(title: 'Dune', year: 1965));
    await expectLater(
      books.save(Book(title: 'Dune', year: 1965)),
      throwsA(isA<DuplicateKeyException>()),
    );
  }
}

void main() => runSpringTests();
