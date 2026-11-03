// The application the SQLite tests start: the generator sees `sqlite3`
// among the starter's dev dependencies and writes the glue (a SqliteBinding
// over the `sqlite3` package and the `sqlite3JdbcDriver` bean) into
// sqlite_app.spring.dart. The tests take the driver from the context.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

import '../../spring_gen/sqlite/app/sqlite_app.spring.dart';

/// A bean of the application's own module.
@Component()
class Marker {}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final context = await springApplication.runAsync(args);
  context.close();
}
