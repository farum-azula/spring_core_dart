import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The `spring.task.scheduling.*` properties.
///
/// Spring Boot (Java): `TaskSchedulingProperties`.
@ConfigurationProperties('spring.task.scheduling')
class SchedulingProperties {
  /// `false`: no `@Scheduled` method runs, which keeps tests predictable.
  bool enabled = true;

  /// What closing the context does with the runs going on.
  SchedulingShutdown shutdown = SchedulingShutdown();
}

/// The `spring.task.scheduling.shutdown.*` properties.
@Introspected()
class SchedulingShutdown {
  /// Closing the context with `closeAsync()` waits for the runs going on.
  bool awaitTermination = false;

  /// The longest such wait. Default: no limit.
  Duration? awaitTerminationPeriod;
}
