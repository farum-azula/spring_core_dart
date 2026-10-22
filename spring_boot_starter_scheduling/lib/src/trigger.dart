import 'package:spring_boot_starter_scheduling/src/cron_expression.dart';

/// What a [Trigger] knows about the previous runs of its task, like
/// Spring's `TriggerContext`.
///
/// ```dart
/// final context = TriggerContext(now: DateTime.now());
/// trigger.nextExecution(context); // the first run
/// ```
///
/// Spring (Java):
/// ```java
/// TriggerContext context = new SimpleTriggerContext();
/// trigger.nextExecution(context);
/// ```
final class TriggerContext {
  /// A context; all times are `null` before the first run.
  TriggerContext({
    required this.now,
    this.lastScheduledExecution,
    this.lastActualExecution,
    this.lastCompletion,
  });

  /// The current time of the scheduler's clock.
  final DateTime now;

  /// When the previous run was due.
  final DateTime? lastScheduledExecution;

  /// When the previous run actually started.
  final DateTime? lastActualExecution;

  /// When the previous run completed (its `Future` included).
  final DateTime? lastCompletion;
}

/// Decides when a task runs next, like Spring's `Trigger`.
///
/// ```dart
/// final class EveryWorkingHour implements Trigger {
///   @override
///   DateTime? nextExecution(TriggerContext context) =>
///       CronExpression.parse('0 0 9-17 * * MON-FRI').next(context.now);
/// }
///
/// scheduler.schedule(sendReport, EveryWorkingHour());
/// ```
///
/// Spring (Java):
/// ```java
/// Trigger trigger = context -> CronExpression.parse("0 0 9-17 * * MON-FRI")
///     .next(context.getClock().instant());
/// ```
abstract interface class Trigger {
  /// The next run after the runs described by [context]; `null` stops the
  /// task.
  DateTime? nextExecution(TriggerContext context);
}

/// Runs at the times of a [CronExpression], like Spring's `CronTrigger`.
///
/// The next time is computed from the completion of the previous run (or
/// from when it was due, if that is later), so a run that takes longer
/// than the interval skips the times it missed.
///
/// ```dart
/// final trigger = CronTrigger(CronExpression.parse('0 */10 * * * *'));
/// scheduler.schedule(cleanUp, trigger);
/// ```
///
/// Spring (Java):
/// ```java
/// scheduler.schedule(this::cleanUp, new CronTrigger("0 */10 * * * *"));
/// ```
final class CronTrigger implements Trigger {
  /// A trigger for [expression]; [utc] evaluates it in UTC instead of
  /// local time.
  CronTrigger(this.expression, {this.utc = false});

  /// The cron expression.
  final CronExpression expression;

  /// Whether the expression is evaluated in UTC.
  final bool utc;

  @override
  DateTime? nextExecution(TriggerContext context) {
    var base = context.lastCompletion ?? context.now;
    final scheduled = context.lastScheduledExecution;
    if (context.lastCompletion != null &&
        scheduled != null &&
        base.isBefore(scheduled)) {
      base = scheduled;
    }
    final next = expression.next(utc ? base.toUtc() : base.toLocal());
    return next;
  }

  @override
  String toString() =>
      'CronTrigger(${expression.expression}'
      '${utc ? ', UTC' : ''})';
}

/// Runs periodically, like Spring's `PeriodicTrigger`: every [period]
/// between starts ([fixedRate]) or [period] after each completion.
///
/// A fixed-rate run never overlaps the previous one: when a run takes
/// longer than [period], the next one starts as soon as it completes, once,
/// and the rate continues from there (missed runs are not caught up).
///
/// ```dart
/// scheduler.schedule(poll, PeriodicTrigger(Duration(seconds: 30)));
/// scheduler.schedule(
///   refresh,
///   PeriodicTrigger(Duration(minutes: 5), fixedRate: true,
///       initialDelay: Duration(seconds: 10)),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// PeriodicTrigger trigger = new PeriodicTrigger(Duration.ofMinutes(5));
/// trigger.setFixedRate(true);
/// trigger.setInitialDelay(Duration.ofSeconds(10));
/// ```
final class PeriodicTrigger implements Trigger {
  /// A trigger every [period] (> 0); [initialDelay] before the first run.
  PeriodicTrigger(
    this.period, {
    this.fixedRate = false,
    this.initialDelay = Duration.zero,
  }) {
    if (period <= Duration.zero) {
      throw ArgumentError.value(period, 'period', 'must be positive');
    }
    if (initialDelay.isNegative) {
      throw ArgumentError.value(
        initialDelay,
        'initialDelay',
        'must not be negative',
      );
    }
  }

  /// The interval.
  final Duration period;

  /// Measured between starts (`true`) or from completion to start.
  final bool fixedRate;

  /// Delay before the first run.
  final Duration initialDelay;

  @override
  DateTime? nextExecution(TriggerContext context) {
    final scheduled = context.lastScheduledExecution;
    final completion = context.lastCompletion;
    if (scheduled == null) {
      return context.now.add(initialDelay);
    }
    if (!fixedRate) {
      return (completion ?? context.now).add(period);
    }
    final next = scheduled.add(period);
    return completion != null && next.isBefore(completion) ? completion : next;
  }

  @override
  String toString() =>
      'PeriodicTrigger(${fixedRate ? 'fixedRate' : 'fixedDelay'}: $period'
      '${initialDelay == Duration.zero ? '' : ', initialDelay: $initialDelay'})';
}
