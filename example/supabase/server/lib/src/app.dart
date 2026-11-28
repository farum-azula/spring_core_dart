import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:supabase_example_server/spring_gen/src/app.spring.dart';
import 'package:supabase_example_server/src/project/functions.dart';

/// Every bean under `lib/src/`, with the Edge Functions interface in its
/// group; `bin/main.dart`'s `@SpringBootApplication` imports it.
@ComponentScan()
@ImportHttpServices(group: EdgeFunctions.group, types: [Functions])
final BeanModule appBeans = $appBeans;
