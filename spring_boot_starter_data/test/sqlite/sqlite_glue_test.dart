// The glue the generator wrote into the test application: one SQLite driver
// bean although two modules (the application's and shared/) both carry the
// glue (the application has the PostgreSQL driver beside it: the starter's
// dev dependencies list both packages).
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app/shared/shared.dart';
import 'app/sqlite_app.dart';
import 'app/sqlite_app.spring.dart';

// The SQLite driver beans: the names the glue gives its bean.
List<String> _sqliteDrivers(AssertableApplicationContext context) => [
  for (final name in context.getBeanNamesForType<JdbcDriver>())
    if (context.getBeanByName(name) is SqliteJdbcDriver) name,
];

void main() {
  test('the glue makes one SQLite driver bean', () async {
    await const ApplicationContextRunner()
        .withUserConfiguration($application)
        .runAsync((context) async {
          expect(context.startupFailure, isNull);
          expect(_sqliteDrivers(context), hasLength(1));
          expect(context, hasBeanNamed('sqlite3JdbcDriver'));
          final driver = context.getBean<JdbcDriver>(
            qualifier: 'sqlite3JdbcDriver',
          );
          expect(driver, isA<SqliteJdbcDriver>());
          expect(driver.schemes, ['sqlite']);
          expect(driver.dialect, isA<SqliteDialect>());
        });
  });

  test('both modules are loaded, each carrying the glue', () async {
    await const ApplicationContextRunner()
        .withUserConfiguration($application)
        .runAsync((context) async {
          expect(context.getBean<Marker>(), isNotNull);
          expect(context.getBean<SharedBean>(), isNotNull);
        });
    // The module of shared/ alone has the glue too.
    await const ApplicationContextRunner()
        .withUserConfiguration(sharedBeans)
        .runAsync((context) async {
          expect(_sqliteDrivers(context), hasLength(1));
        });
    // And both modules given one after the other still make one driver.
    await const ApplicationContextRunner()
        .withUserConfiguration(sharedBeans)
        .withUserConfiguration($application)
        .runAsync((context) async {
          expect(context.startupFailure, isNull);
          expect(_sqliteDrivers(context), hasLength(1));
        });
  });
}
