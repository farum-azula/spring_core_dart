import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Runs a bean method on a schedule, like Spring's `@Scheduled`.
///
/// Give exactly one of [cron], [fixedRate] / [fixedRateString] or
/// [fixedDelay] / [fixedDelayString]. The method must be public and take
/// no parameters; it may return a `Future`, which is awaited. Put several
/// `@Scheduled` on one method for several schedules. Requires
/// `spring_core_dart_generator` (it makes the method callable without
/// reflection) and this starter as a dependency.
///
/// ```dart
/// @Component()
/// class Reports {
///   @Scheduled(fixedRate: Duration(minutes: 5))
///   void refresh() { ... }
///
///   @Scheduled(fixedDelayString: r'${reports.sync-delay:30s}',
///       initialDelay: Duration(seconds: 10))
///   Future<void> sync() async { ... }
///
///   @Scheduled(cron: '0 0 9 * * MON-FRI')
///   void morningDigest() { ... }
///
///   @Scheduled(cron: r'${reports.cleanup-cron:-}') // `-`: switched off
///   void cleanup() { ... }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class Reports {
///   @Scheduled(fixedRate = 5, timeUnit = TimeUnit.MINUTES)
///   void refresh() { ... }
///
///   @Scheduled(fixedDelayString = "${reports.sync-delay:30s}",
///       initialDelay = 10, timeUnit = TimeUnit.SECONDS)
///   void sync() { ... }
///
///   @Scheduled(cron = "0 0 9 * * MON-FRI")
///   void morningDigest() { ... }
/// }
/// ```
///
/// [scheduler] picks another `TaskScheduler` bean than the default one
/// (Spring 6.1).
///
/// The `*String` attributes and [cron] resolve `${...}` placeholders and
/// take Spring Boot durations (`10s`, `5m`, `PT1H`; a plain number is
/// milliseconds).
@BeanMethodAnnotation()
class Scheduled {
  /// Creates the annotation; see the class documentation for the rules.
  const Scheduled({
    this.cron,
    this.zone,
    this.fixedRate,
    this.fixedDelay,
    this.initialDelay,
    this.fixedRateString,
    this.fixedDelayString,
    this.initialDelayString,
    this.scheduler,
  });

  /// Spring's value of [cron] that switches the task off.
  ///
  /// ```dart
  /// @Scheduled(cron: r'${jobs.cleanup:-}') // off unless configured
  /// void cleanup() { ... }
  /// ```
  static const cronDisabled = '-';

  /// A six-field cron expression (`second minute hour day month weekday`)
  /// or a macro such as `@daily`; see `CronExpression`. `-` switches the
  /// task off.
  final String? cron;

  /// The time zone of [cron]: `null` for local time, or `'UTC'`.
  final String? zone;

  /// Starts a run every period, measured between starts. Runs never
  /// overlap: when a run takes longer, the next one starts right after it
  /// (once, without catching up the missed runs).
  final Duration? fixedRate;

  /// Waits this long after each run completes (an awaited `Future`
  /// included) before the next one.
  final Duration? fixedDelay;

  /// Delay before the first run of [fixedRate] / [fixedDelay] tasks; not
  /// allowed with [cron].
  final Duration? initialDelay;

  /// [fixedRate] as text: `'10s'`, `r'${jobs.rate}'`, `'500'` (ms).
  final String? fixedRateString;

  /// [fixedDelay] as text: `'10s'`, `r'${jobs.delay:1m}'`.
  final String? fixedDelayString;

  /// [initialDelay] as text: `'30s'`, `r'${jobs.initial-delay:0}'`.
  final String? initialDelayString;

  /// The `TaskScheduler` bean to run the method on, by qualifier or bean
  /// name (`${...}` allowed); `null` for the default scheduler (the only
  /// `TaskScheduler` bean, the primary one, or the one named
  /// `taskScheduler`).
  ///
  /// ```dart
  /// @Scheduled(fixedDelay: Duration(minutes: 1), scheduler: 'reportsScheduler')
  /// void export() { ... }
  /// ```
  final String? scheduler;
}
