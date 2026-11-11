import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:supabase_example_server/spring_gen/src/app.spring.dart';

/// Every bean under `lib/src/`; `bin/main.dart`'s `@SpringBootApplication`
/// imports it.
@ComponentScan()
final BeanModule appBeans = $appBeans;
