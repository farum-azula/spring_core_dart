/// The module of the starter's `@ConfigurationProperties` classes.
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_edge/spring_gen/src/config/config.spring.dart';

/// The `spring.edge.*` properties as beans (generated).
@ComponentScan()
final BeanModule edgeConfigBeans = $edgeConfigBeans;
