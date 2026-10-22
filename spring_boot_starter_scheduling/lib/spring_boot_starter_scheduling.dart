/// Scheduling for `spring_boot_dart` applications, like Spring's
/// `@Scheduled` support: add the dependency and annotate bean methods.
///
/// - [Scheduled]: fixed rate, fixed delay or cron, with `${...}`
///   placeholders and Spring Boot durations;
/// - [CronExpression]: Spring's six-field cron format, with `L`, `W`, `#`
///   and macros;
/// - [TaskScheduler]: schedule work in code ([Trigger], [CronTrigger],
///   [PeriodicTrigger], [OneShotTrigger]);
/// - tasks stop when the context closes (and so after a hot-reload
///   restart).
///
/// Re-exports `spring_boot_dart`.
library;

export 'package:spring_boot_dart/spring_boot_dart.dart';
export 'package:spring_boot_starter_scheduling/src/cron_expression.dart';
export 'package:spring_boot_starter_scheduling/src/scheduled.dart';
export 'package:spring_boot_starter_scheduling/src/scheduled_annotation_bean_post_processor.dart';
export 'package:spring_boot_starter_scheduling/src/scheduling_auto_configuration.dart';
export 'package:spring_boot_starter_scheduling/src/task_scheduler.dart';
export 'package:spring_boot_starter_scheduling/src/trigger.dart';
