import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Marks a bean method that the application runs by itself on a
/// schedule: every few minutes, after each run with a pause, or at cron
/// times.
///
/// Use it for work nobody calls: refreshing a cache, syncing with a
/// server, sending a daily digest, deleting old files. The method runs
/// from the moment the application context is ready until it closes. The
/// starter must be a dependency and `spring_core_dart_generator` must run,
/// as it makes the method callable without reflection; the bean must be a
/// singleton.
///
/// Give exactly one of [cron], [fixedRate] (or [fixedRateString]) and
/// [fixedDelay] (or [fixedDelayString]). [initialDelay] alone, without any
/// of them, runs the method once after that delay (Spring 6.1). The method
/// must be public and take no parameters. It may return a `Future`: the
/// run counts as finished when the future completes, so runs never
/// overlap. Several `@Scheduled` on one method give several schedules. A
/// wrong attribute (two kinds, a bad cron, an unknown zone, a missing
/// property) stops the start with a message naming `Class.method`. An
/// error thrown by a run is logged (or given to the `ErrorHandler` bean)
/// and the schedule goes on.
///
/// ```dart
/// @Component()
/// class Reports {
///   // Keeps the report cache fresh.
///   @Scheduled(fixedRate: Duration(minutes: 5))
///   void refresh() { ... }
///
///   // Talks to a slow server: the 30 s pause starts when a sync is done;
///   // the first sync waits until the application has settled.
///   @Scheduled(fixedDelayString: r'${reports.sync-delay:30s}',
///       initialDelay: Duration(seconds: 10))
///   Future<void> sync() async { ... }
///
///   @Scheduled(cron: '0 0 9 * * MON-FRI') // 9:00 on working days
///   void morningDigest() { ... }
///
///   // Off unless a profile sets `reports.cleanup-cron`.
///   @Scheduled(cron: r'${reports.cleanup-cron:-}')
///   void cleanup() { ... }
///
///   @Scheduled(initialDelay: Duration(minutes: 1)) // once, a minute in
///   void warmUp() { ... }
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
///
///   @Scheduled(initialDelay = 1, timeUnit = TimeUnit.MINUTES)
///   void warmUp() { ... }
/// }
/// ```
///
/// Differences: durations are `Duration`s instead of a number and a
/// `timeUnit`; there is no `@EnableScheduling`, the dependency is enough.
/// A returned `Future` is awaited with every kind of schedule, so a slow
/// run delays the next one; Spring does not wait for a returned
/// `CompletableFuture`. A `fixedRate` run that takes longer than the
/// period is followed by one run right after it, not by every missed one.
///
/// The `*String` attributes, [cron], [zone] and [scheduler] resolve
/// `${...}` placeholders; the durations take Spring Boot's formats (`10s`,
/// `5m`, `PT1H`; a plain number is milliseconds).
@BeanMethodAnnotation()
class Scheduled {
  /// Marks the method; give one of [cron], [fixedRate] or [fixedDelay] (or
  /// their `*String` forms), or [initialDelay] alone for a single run.
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

  /// The [cron] value `-`, which switches the task off: the method is not
  /// scheduled at all. Mostly used as a placeholder default, so a task
  /// runs only where a property sets its cron.
  ///
  /// ```dart
  /// @Scheduled(cron: r'${jobs.cleanup:-}') // off unless configured
  /// void cleanup() { ... }
  /// ```
  static const cronDisabled = '-';

  /// Runs the method at the times of a cron expression: six fields
  /// (`second minute hour day-of-month month day-of-week`, unlike the five
  /// of Unix cron) or a macro such as `@daily`; see `CronExpression`.
  /// `-` ([cronDisabled]) switches the task off.
  ///
  /// The next time is computed when a run finishes, so times missed during
  /// a long run are skipped. Not allowed with [initialDelay].
  final String? cron;

  /// The time zone [cron] is read in: `null` or empty for the local time
  /// of the machine, or `'UTC'` (also `'Z'` or `'GMT'`, in any case).
  /// Other zones fail the start, as Dart has no time zone database.
  final String? zone;

  /// Starts a run every period, measured between starts, such as a cache
  /// refresh every 5 minutes. Must be positive.
  ///
  /// Runs never overlap: when a run takes longer than the period, the next
  /// one starts right after it, once, without catching up the missed runs.
  final Duration? fixedRate;

  /// Waits this long after each run completes, its `Future` included,
  /// before starting the next one. Use it when runs take a variable time,
  /// such as a sync with a server, and must keep a pause between them.
  /// Must be positive.
  final Duration? fixedDelay;

  /// How long to wait after the start before the first run of a
  /// [fixedRate] or [fixedDelay] task; no wait by default. Not allowed with
  /// [cron]. Given alone, the method runs once, this long after the start.
  final Duration? initialDelay;

  /// [fixedRate] as text, so the rate can come from a property:
  /// `'10s'`, `r'${jobs.rate}'`, `'500'` (milliseconds). Give it or
  /// [fixedRate], not both.
  ///
  /// A blank value, also once resolved (`r'${jobs.rate:}'`), counts as not
  /// set, as in Spring. The same holds for [fixedDelayString] and
  /// [initialDelayString].
  final String? fixedRateString;

  /// [fixedDelay] as text, so the delay can come from a property:
  /// `'10s'`, `r'${jobs.delay:1m}'`.
  final String? fixedDelayString;

  /// [initialDelay] as text, so it can come from a property: `'30s'`,
  /// `r'${jobs.initial-delay:0}'`.
  final String? initialDelayString;

  /// The `TaskScheduler` bean to run the method on, by qualifier or bean
  /// name, when the application declares several (Spring 6.1). `null` or
  /// blank uses the default one: the only `TaskScheduler` bean, the
  /// primary one, or the one named `taskScheduler`. A name with no such
  /// bean fails the start.
  ///
  /// ```dart
  /// @Scheduled(
  ///   fixedDelay: Duration(minutes: 1),
  ///   scheduler: 'reportsScheduler',
  /// )
  /// void export() { ... }
  /// ```
  final String? scheduler;
}
