# spring_boot_starter_scheduling: examples

**What it does:** runs methods of your
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart) beans on a
schedule — every few seconds, with a pause after each run, or at cron times
such as "9:00 on working days".

## Setup

Add the dependency and run the generator again. The starter is found and
switched on automatically.

```yaml
dependencies:
  spring_boot_dart: ^0.3.0
  spring_boot_starter_scheduling: ^0.3.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.3.0   # required: turns annotations into code
```

```bash
dart run build_runner build
```

## 1. Run a method every few minutes

```dart
@Component()
class Prices {
  @Scheduled(fixedRate: Duration(minutes: 5))
  void refresh() { ... }
}
```

## 2. Wait after each run (good for network calls)

```dart
@Scheduled(fixedDelay: Duration(seconds: 30), initialDelay: Duration(seconds: 5))
Future<void> sync() async {
  await api.pushChanges(); // the 30 s pause starts after this completes
}
```

## 3. Run at fixed times with cron

```dart
@Scheduled(cron: '0 0 9 * * MON-FRI') // 9:00 on working days
void morningDigest() { ... }

@Scheduled(cron: '0 0 18 L * *') // 18:00 on the last day of the month
void monthlyReport() { ... }
```

Six fields: `second minute hour day month weekday`. More in the
[README](https://pub.dev/packages/spring_boot_starter_scheduling).

## 4. Take the schedule from properties

```dart
@Scheduled(fixedRateString: r'${prices.refresh-rate:5m}')
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

```dart
@Service()
class Reminders {
  Reminders(this.scheduler);
  final TaskScheduler scheduler;

  void remindAt(DateTime at, String text) =>
      scheduler.schedule(() => print(text), OneShotTrigger(at));
}
```

## 6. Switch it off in tests

```dart
final app = springBootTest(
  springApplication,
  properties: {'spring.task.scheduling.enabled': false},
);
```

## Runnable example

[`example.dart`](example.dart) starts a context with a scheduled bean (the
bean definition is written by hand there, so it runs without code
generation), lets it run for three seconds and closes it:

```bash
dart run example/example.dart
```
