// @DataTest(replaceDatabase: false): the configured database is used, here
// a file in a temporary directory, and the tests still roll back. The
// generator writes spring_gen/data_test/replace_database.test.spring.dart.
import 'dart:io';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../spring_gen/data_test/replace_database.test.spring.dart';
import 'app/data_test_app.dart';

@DataTest(
  application: 'test/data_test/app/data_test_app.dart',
  replaceDatabase: false,
)
class ConfiguredDatabaseTest {
  static late Directory directory;

  @BeforeAll()
  static void createDirectory() {
    directory = Directory.systemTemp.createTempSync('data_test_kept');
  }

  // Known only when the tests run, as the temporary directory is.
  @DynamicPropertySource()
  static void database(DynamicPropertyRegistry registry) => registry.add(
    'spring.datasource.url',
    () => 'sqlite:file:${directory.path}/kept.db',
  );

  @AfterAll()
  static void deleteDirectory() => directory.deleteSync(recursive: true);

  @Autowired()
  late BookRepository books;

  @Autowired()
  late DataSource dataSource;

  @Test()
  void usesTheConfiguredDatabase() {
    expect(
      dataSource.settings.url.toString(),
      'sqlite:file:${directory.path}/kept.db',
    );
    expect(File('${directory.path}/kept.db').existsSync(), isTrue);
  }

  @Test()
  Future<void> savesABook() async {
    await books.save(Book(title: 'Dune', year: 1965));
    expect(await books.count(), 1);
  }

  @Test()
  Future<void> rollsItBackAnyway() async {
    expect(await books.count(), 0);
  }
}

void main() => runSpringTests();
