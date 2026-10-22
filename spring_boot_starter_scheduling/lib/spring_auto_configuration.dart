/// Discovered by the generator of every application that depends on
/// `spring_boot_starter_scheduling` (see `AutoConfigurationModule`).
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_scheduling/src/scheduling_auto_configuration.dart';

/// Runs `@Scheduled` methods and exposes a `TaskScheduler`.
@AutoConfigurationModule()
final BeanModule springBootStarterSchedulingAutoConfiguration = BeanModule(
  'springBootStarterSchedulingAutoConfiguration',
  [...schedulingAutoConfiguration],
);
