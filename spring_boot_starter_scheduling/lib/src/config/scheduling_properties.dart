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

  /// Which isolates run the `@Scheduled` methods when the web server has
  /// a pool of them (`server.isolates.count`): `primary` (the default),
  /// so a job runs once for the application, or `all`, once in every
  /// isolate, for what each isolate must do for itself (refreshing what
  /// it keeps in memory).
  SchedulingIsolates isolates = SchedulingIsolates.primary;
}

/// Which isolates run `@Scheduled` methods
/// (`spring.task.scheduling.isolates`).
enum SchedulingIsolates {
  /// The application's first isolate only.
  primary,

  /// Every isolate.
  all,
}

/// The `spring.task.scheduling.shutdown.*` properties.
@Introspected()
class SchedulingShutdown {
  /// Closing the context with `closeAsync()` waits for the runs going on.
  bool awaitTermination = false;

  /// The longest such wait. Default: no limit.
  Duration? awaitTerminationPeriod;
}
