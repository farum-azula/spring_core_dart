// The glue the generator wrote into the test application: one driver bean
// although two modules (the application's and shared/) both carry the glue.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app/shared/shared.dart';
import 'app/sqlite_app.dart';
import 'app/sqlite_app.spring.dart';

void main() {
  test('the glue makes one SQLite driver bean', () async {
    await const ApplicationContextRunner()
        .withUserConfiguration($application)
        .runAsync((context) async {
          expect(context.startupFailure, isNull);
          expect(context, hasSingleBean<JdbcDriver>());
          expect(context, hasBeanNamed('sqlite3JdbcDriver'));
          final driver = context.getBean<JdbcDriver>();
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
          expect(context, hasSingleBean<JdbcDriver>());
        });
    // And both modules given one after the other still make one driver.
    await const ApplicationContextRunner()
        .withUserConfiguration(sharedBeans)
        .withUserConfiguration($application)
        .runAsync((context) async {
          expect(context.startupFailure, isNull);
          expect(context, hasSingleBean<JdbcDriver>());
        });
  });
}
