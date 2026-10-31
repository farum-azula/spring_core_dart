# spring_boot_starter_scheduling: examples

This starter runs methods of your
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart) beans on a
schedule: every few seconds, with a pause after each run, or at cron
times such as "9:00 on working days". You annotate the method; the tasks
start when the application is ready and stop when it closes.

[`example.dart`](example.dart) is a small Spring Boot application with a
`Heartbeat` bean that beats every second (a fixed rate taken from a
property) and reports every 2 seconds (a cron expression), and a
`Reminder` that schedules a one-off task through the `TaskScheduler`
bean. It runs for three seconds, logs how many beats there were, and
closes the context, which cancels every task.

## Run it

```yaml
dependencies:
  spring_boot_starter_scheduling: ^0.5.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.5.0   # required: turns annotations into code
```

Adding the dependency and running the generator is all the setup: the
starter is found and switched on automatically. From the package
directory:

```bash
dart run build_runner build
dart run example/example.dart
```

After the startup lines it logs something like (the date and time that
start each line are left out here):

```text
... example : beat 1
... example : report at 2026-10-28 14:07:46.005713
... example : beat 2
... example : one-off after 1.5 s
... example : beat 3
... example : report at 2026-10-28 14:07:48.001638
... example : beat 4
... example : 4 beats
```

The rate comes from the `heartbeat.rate` property (1 second when it is not
set), so a command-line argument changes it:

```bash
dart run example/example.dart --heartbeat.rate=500ms
```

The sections below show the usual cases.

## 1. Run a method every few minutes

```dart
@Component()
class Prices {
  // A run starts every 5 minutes, measured between starts.
  @Scheduled(fixedRate: Duration(minutes: 5))
  void refresh() { ... }
}
```

## 2. Wait after each run (good for network calls)

```dart
// The first sync 5 s after the start, then a 30 s pause after each one.
@Scheduled(fixedDelay: Duration(seconds: 30), initialDelay: Duration(seconds: 5))
Future<void> sync() async {
  await api.pushChanges(); // the pause starts after this completes
}
```

## 3. Run at fixed times with cron

```dart
@Scheduled(cron: '0 0 9 * * MON-FRI') // 9:00 on working days
void morningDigest() { ... }

@Scheduled(cron: '0 0 18 L * *') // 18:00 on the last day of the month
void monthlyReport() { ... }
```

A cron expression has six fields, starting with the seconds:
`second minute hour day-of-month month day-of-week`. The example's
`*/2 * * * * *` means every 2 seconds.

## 4. Take the schedule from properties

```dart
@Scheduled(fixedRateString: r'${prices.refresh-rate:5m}') // 5 minutes unless configured
void refresh() { ... }

@Scheduled(cron: r'${reports.cleanup-cron:-}') // `-` = off unless configured
void cleanup() { ... }
```

```properties
# lib/resources/application.properties
prices.refresh-rate=1m
reports.cleanup-cron=0 0 3 * * *
```

## 5. Schedule in code

When the time is only known at runtime, inject the `TaskScheduler`:

```dart
@Service()
@Log()
class Reminders {
  Reminders(this.scheduler);
  final TaskScheduler scheduler;

  // Once, at the time the user picked.
  ScheduledTask remindAt(DateTime at, String text) =>
      scheduler.scheduleAt(() => log.info(text), at);
}
```

The example does the same with `scheduler.schedule(task, OneShotTrigger(time))`.

## 6. Switch it off in tests

So tests do not depend on timers, switch scheduling off and call the
methods directly:

```dart
final app = springBootTest(
  springApplication,
  properties: {'spring.task.scheduling.enabled': false},
);
```

Cron expressions in detail, `TaskScheduler`, `@Async` listeners, error
handling and the differences from Spring are in the package
[README](https://pub.dev/packages/spring_boot_starter_scheduling).
