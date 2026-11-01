// A @DataTest on an application with a SQLite database and no migrations:
// the in-memory database gets the tables of the entities. The generator
// writes spring/data_test/create_schema.test.spring.dart.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../spring/data_test/create_schema.test.spring.dart';
import 'create_app/create_app.dart';

@DataTest(application: 'test/data_test/create_app/create_app.dart')
class CreateSchemaTest {
  @Autowired()
  late TaskRepository tasks;

  @Autowired()
  late JdbcClient jdbc;

  @Autowired()
  late Environment environment;

  @Test()
  Future<void> createsTheTablesFromTheEntities() async {
    expect(environment.getProperty('spring.data.jdbc.schema'), 'create');
    final tables = await jdbc
        .sql("select name from sqlite_master where name = 'tasks'")
        .query<String>()
        .list();
    expect(tables, ['tasks']);
  }

  @Test()
  Future<void> savesATask() async {
    await tasks.save(Task(title: 'write the docs'));
    await tasks.save(Task(title: 'run the tests', done: true));
    expect(await tasks.findByDone(true), hasLength(1));
  }

  @Test()
  Future<void> theTasksAreGone() async {
    expect(await tasks.count(), 0);
  }
}

void main() => runSpringTests();
