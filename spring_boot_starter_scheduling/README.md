# spring_boot_starter_scheduling

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

Scheduled tasks for [`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
applications, like Spring's `@Scheduled`: annotate a bean method and it runs
every few seconds, after each run with a pause, or at cron times. Tasks stop
when the context closes.

## Installation

```yaml
dependencies:
  spring_boot_dart: ^0.3.0
  spring_boot_starter_scheduling: ^0.3.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.3.0   # required: makes @Scheduled methods callable
```

```bash
dart run build_runner build
```

That is all: the starter is found automatically (no `@EnableScheduling`).

## Quick example

```dart
import 'package:spring_boot_starter_scheduling/spring_boot_starter_scheduling.dart';

@Component()
class Reports {
  Reports(this.repository);
  final ReportRepository repository;

  @Scheduled(fixedRate: Duration(minutes: 5))
  void refreshCache() => repository.refresh();

  @Scheduled(fixedDelay: Duration(seconds: 30))
  Future<void> syncWithServer() async => await repository.sync();

  @Scheduled(cron: '0 0 9 * * MON-FRI') // 9:00 on working days
  void morningDigest() => repository.sendDigest();
}
```

Start the application as usual (`runApplication(args)`); the tasks start
once the context is ready.

## `@Scheduled`

Give exactly one of `cron`, `fixedRate` or `fixedDelay`.

| Attribute | Meaning | Example |
|---|---|---|
| `fixedRate` | start every period (measured between starts) | `fixedRate: Duration(minutes: 5)` |
| `fixedDelay` | wait this long after each run completes | `fixedDelay: Duration(seconds: 30)` |
| `initialDelay` | wait before the first run (not with `cron`); alone: one run after it (Spring 6.1) | `initialDelay: Duration(seconds: 10)` |
| `cron` | run at cron times; `-` switches the task off | `cron: '0 */15 * * * *'` |
| `zone` | time zone of `cron`: leave out for local time, or `'UTC'` | `zone: 'UTC'` |
| `scheduler` | the `TaskScheduler` bean to run on, by qualifier or bean name (`${...}` allowed); default: the only one, the primary one or `taskScheduler` | `scheduler: 'reportsScheduler'` |
| `fixedRateString`, `fixedDelayString`, `initialDelayString` | the same as text, with `${...}` placeholders and Spring Boot durations; blank (also once resolved) is not set | `fixedRateString: r'${reports.rate:5m}'` |

Rules:

- The method must be public and take no parameters. It may return a
  `Future`: the run counts as finished when the future completes.
- Several `@Scheduled` on one method give several schedules.
- Only singleton beans are scheduled (`@Scope('prototype')` beans are
  ignored with a warning).
- A wrong attribute (two kinds, a bad cron, an unknown zone or
  `scheduler`, a missing property) stops the startup with a message naming
  `Class.method`.
- The method is called on the bean as other beans see it, so AOP advice
  (`@Around`, `@Cacheable`, ...) applies.

## Cron expressions

Six fields, like Spring (not five like Unix cron):

```text
second minute hour day-of-month month day-of-week
```

| Expression | Runs |
|---|---|
| `0 * * * * *` | every minute, at second 0 |
| `*/10 * * * * *` | every 10 seconds |
| `0 */15 * * * *` | every 15 minutes |
| `0 0 * * * *` | every hour |
| `0 0 9-17 * * MON-FRI` | every hour from 9 to 17 on working days |
| `0 30 8 * * *` | 8:30 every day |
| `0 0 0 1 * *` | midnight on the 1st of each month |
| `0 0 18 L * *` | 18:00 on the last day of the month |
| `0 0 12 LW * *` | noon on the last working day of the month |
| `0 0 10 15W * *` | 10:00 on the working day nearest to the 15th |
| `0 0 20 ? * FRIL` | 20:00 on the last Friday of the month |
| `0 0 9 ? * MON#1` | 9:00 on the first Monday of the month |
| `0 0 9 ? * MON#1,MON#3` | 9:00 on the first and the third Monday |
| `0 0 0 1,L * *` | midnight on the first and the last day of the month |
| `0 0 10 * * SAT-SUN` | 10:00 at the weekend |
| `0 0 0 25 DEC *` | midnight on December 25th |
| `@hourly`, `@daily` (`@midnight`), `@weekly`, `@monthly`, `@yearly` (`@annually`) | the usual macros |

- Values: `*`, `5`, lists `1,15,30`, ranges `9-17`, steps `*/5`, `0-30/10`,
  `5/15` (from 5, every 15). Months `JAN`-`DEC`, case-insensitive. `?`
  means "any" in the day fields.
- Days of the week as in Spring: `MON`-`SUN` are 1-7 and 0 is Sunday too;
  Sunday at the start of a range is 0, so `SAT-SUN`, `MON-SUN` and
  `SUN-TUE` all work. `*/2` is MON, WED, FRI, SUN.
- The specials `L`, `L-n`, `nW`, `LW`, `nL`, `n#k` may be combined in lists
  with each other and with values (`1,L`, `MON-FRI,SATL`).
- As in Spring, a day must match both day fields, and ranges cannot wrap
  around (`FRI-MON` is an error: write `FRI-SUN,MON`).
- Local time follows the wall clock: a time inside the hour skipped when
  clocks go forward runs at the first valid time after it; a time inside
  the hour repeated when clocks go back runs once.

Check an expression in code:

```dart
final cron = CronExpression.parse('0 0 9 * * MON-FRI');
print(cron.next(DateTime.now())); // the next run
CronExpression.isValid('0 0 25 * * *'); // false: hour 25
```

## Configuration from properties

Every text attribute resolves placeholders, so schedules can live in
`application.properties` and change per profile:

```dart
@Scheduled(fixedRateString: r'${reports.rate:5m}')
void refresh() { ... }

@Scheduled(cron: r'${reports.cleanup-cron:-}') // off unless configured
void cleanup() { ... }
```

```properties
# lib/resources/application.properties
reports.rate=10m
reports.cleanup-cron=0 0 3 * * *
```

Durations: `500` (milliseconds), `10s`, `5m`, `2h`, `1d`, `PT1H30M`.

| Property | Default | Meaning |
|---|---|---|
| `spring.task.scheduling.enabled` | `true` | `false` switches scheduling off (no `TaskScheduler`, no tasks) |
| `spring.task.scheduling.shutdown.await-termination` | `false` | `true`: the context's `closeAsync()` waits for the runs going on when it closes (a run, or its `Future`, is never interrupted) |
| `spring.task.scheduling.shutdown.await-termination-period` | — | How long to wait at most (`30s`); then a warning is logged and the shutdown goes on. Without it the wait is unbounded |

The synchronous `close()` cannot wait: a run going on finishes after the
close (no further runs start) and `TimerTaskScheduler.runningTasks` lists
it. Your own `TaskScheduler` bean gets the same through a `Future`-returning
`destroy()` (`DisposableBean`).

## Scheduling in code: `TaskScheduler`

Inject the `TaskScheduler` bean to schedule work yourself:

```dart
@Service()
class Reminders {
  Reminders(this.scheduler);
  final TaskScheduler scheduler;

  ScheduledTask remindAt(DateTime at, String text) =>
      scheduler.scheduleAt(() => notify(text), at);

  ScheduledTask poll() => scheduler.scheduleWithFixedDelay(
    checkInbox,
    const Duration(seconds: 30),
  );
}

final task = reminders.poll();
print(task.nextExecution);
task.cancel();
```

Triggers: `PeriodicTrigger` (fixed rate or delay), `CronTrigger`,
`OneShotTrigger`, or your own `Trigger`. Declare your own `TaskScheduler`
bean to replace the default `TimerTaskScheduler`. With several
`TaskScheduler` beans, `@Scheduled` methods run on the primary one or the
one named `taskScheduler`, unless they name another with `scheduler:`.

## Asynchronous tasks and overlapping

Everything runs on Dart's event loop, so a task never runs twice at the
same time:

- `fixedDelay`: the pause starts when the run (its `Future`) completes.
- `fixedRate`: when a run takes longer than the period, the next run starts
  right after it, once; missed runs are not caught up.
- `cron`: the next time is computed after the run, so times missed during
  a long run are skipped.

## `TaskExecutor` and `@Async` listeners

The starter also registers Spring Boot's `applicationTaskExecutor` (alias
`taskExecutor`): a `SimpleAsyncTaskExecutor` of the core, which runs each
task in a later event-loop turn and logs its errors. Declaring your own
`TaskExecutor` bean replaces it. Having it switches `@Async` on for
`@EventListener` methods (Spring's `@EnableAsync`): such a listener runs on
the executor instead of the publishing call.

```dart
@Component()
class Mailer {
  @EventListener()
  @Async() // or @Async('mailExecutor') for another TaskExecutor bean
  Future<void> onPlaced(OrderPlaced order) => sendConfirmation(order);
}
```

## Errors

An exception (thrown or from the returned `Future`) is logged at error
level to the `spring.scheduling` logger, with the task name; the task keeps
its schedule. Handle errors in the method if you need retries or alerts,
or declare an `ErrorHandler` bean (Spring's `ErrorHandler`, which Spring
sets on its `ThreadPoolTaskScheduler`): it receives every error instead
of the log. With several, the primary one is used (none without one). A handler that throws stops the task, like Spring's
`LOG_AND_PROPAGATE`.

```dart
@Component()
class ReportErrors implements ErrorHandler {
  @override
  void handleError(Object error, StackTrace stackTrace) =>
      crashReporter.record(error, stackTrace);
}
```

## Testing

Scheduled methods run in `springBootTest` too. To keep tests
deterministic, either switch scheduling off and call the methods directly:

```dart
final app = springBootTest(
  springApplication,
  properties: {'spring.task.scheduling.enabled': false},
);

test('refresh', () => app.getBean<Reports>().refreshCache());
```

or replace the scheduler with one on a controlled clock
(`TimerTaskScheduler(now: ..., createTimer: ...)`) through `BeanOverride`.
`ScheduledAnnotationBeanPostProcessor.scheduledTasks` lists what is
scheduled.

## Hot reload

Tasks belong to the context: a hot-reload restart closes it (cancelling
every task) and the new context schedules the methods of the new code.

## Differences from Spring

- No `@EnableScheduling`: the dependency switches scheduling on;
  `spring.task.scheduling.enabled=false` switches it off.
- Time zones: local time or UTC only (Dart has no time zone database).
- Durations are `Duration`s instead of numbers plus `timeUnit`.
- `TaskScheduler.schedule(task, Instant)` is `scheduleAt(task, DateTime)`
  (Dart has no overloads).
- `fixedRate` tasks never overlap and do not catch up missed runs: when a
  run takes longer than the period, the next one starts right after it,
  once (Spring's single-threaded scheduler runs the missed executions back
  to back).
- A method returning a `Future` is awaited before its run counts as
  finished, with `fixedRate` and `cron` too, so a slow run delays the next
  one instead of overlapping it (Spring does not wait for a returned
  `CompletableFuture`, and waits for a reactive result only with
  `fixedDelay`).
- `#k` in the day of week takes 1-5 (Spring accepts larger ordinals that
  never match).
- `spring.task.scheduling.shutdown.await-termination[-period]` works with
  the context's `closeAsync()` only (`close()` cannot wait); a run that is
  going on is never interrupted and, without `await-termination`, finishes
  after the close (no further runs start).
- `@Async` works on `@EventListener` methods only and needs no
  `@EnableAsync` (the `TaskExecutor` bean switches it on); there is no
  `spring.task.execution.*` pool configuration (Dart has no threads).
- Not yet: `SchedulingConfigurer`, scheduling of prototype beans.
