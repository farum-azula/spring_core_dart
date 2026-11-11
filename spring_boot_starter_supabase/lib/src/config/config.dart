/// The module of the starter's `@ConfigurationProperties` classes.
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_supabase/spring_gen/src/config/config.spring.dart';

/// The `spring.supabase.*` properties as beans (generated).
@ComponentScan()
final BeanModule supabaseConfigBeans = $supabaseConfigBeans;
