/// Recurring work for `spring_boot_dart` applications: add the dependency,
/// put `@Scheduled(...)` on a bean method, and the method runs every few
/// minutes, after each run with a pause, or at cron times, until the
/// application context closes.
///
/// What it contains:
///
/// - `Scheduled`, the annotation: fixed rate, fixed delay or cron, with
///   `${...}` placeholders so schedules can live in properties;
/// - `CronExpression`: Spring's six-field cron format, with `L`, `W`, `#`
///   and macros such as `@daily`;
/// - `TaskScheduler`, to schedule work from code (a reminder at a given
///   time, a poll started on demand), with `Trigger`, `CronTrigger`,
///   `PeriodicTrigger` and `OneShotTrigger`;
/// - `ErrorHandler`, to receive the errors of the tasks.
///
/// Tasks stop when the context closes, and so after a hot-reload restart.
///
/// Re-exports `spring_boot_starter_logging` and through it `spring_boot_dart`
/// and `spring_core_dart`: the starter is the only dependency an
/// application lists.
library;

// Logging and spring_boot_dart (re-exported by the logging starter), so
// this starter is the only dependency an application needs.
export 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
export 'package:spring_boot_starter_scheduling/src/cron_expression.dart';
export 'package:spring_boot_starter_scheduling/src/scheduled.dart';
export 'package:spring_boot_starter_scheduling/src/scheduled_annotation_bean_post_processor.dart';
export 'package:spring_boot_starter_scheduling/src/scheduling_auto_configuration.dart';
export 'package:spring_boot_starter_scheduling/src/task_scheduler.dart';
export 'package:spring_boot_starter_scheduling/src/trigger.dart';
