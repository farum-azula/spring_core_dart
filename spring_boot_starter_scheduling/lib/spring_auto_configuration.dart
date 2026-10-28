/// The starter's auto-configuration. Applications never import it: the
/// generator finds this file in every dependency and adds its module to
/// the generated application, which is what makes the dependency alone
/// enough. A test that builds a context by hand can name it.
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_scheduling/src/scheduling_auto_configuration.dart';

// The auto-configurations this starter builds on (logging, and through it
// spring_boot_dart's), so a test of an application that lists only this starter
// can name them.
export 'package:spring_boot_starter_logging/spring_auto_configuration.dart';

/// The beans that run `@Scheduled` methods: the default `TaskScheduler`,
/// the processor that finds the methods, and the `TaskExecutor` behind
/// `@Async` listeners.
@AutoConfigurationModule()
final BeanModule springBootStarterSchedulingAutoConfiguration = BeanModule(
  'springBootStarterSchedulingAutoConfiguration',
  [...schedulingAutoConfiguration],
);
