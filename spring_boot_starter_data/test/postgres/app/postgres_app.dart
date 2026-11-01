// The application the PostgreSQL tests start: the generator sees `postgres`
// among the starter's dev dependencies and writes the glue (a
// PostgresBinding over the `postgres` package and the `postgresJdbcDriver`
// bean) into postgres_app.spring.dart. The tests take the driver from the
// context.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

import 'postgres_app.spring.dart';

/// A bean of the application's own module.
@Component()
class Marker {}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final context = await springApplication.runAsync(args);
  context.close();
}
