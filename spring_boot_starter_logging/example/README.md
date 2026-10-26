# spring_boot_starter_logging: examples

**What it does:** gives a
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart) app proper
logging — formatted console output, log levels per part of the app, log
files, and an in-memory log list you can show on a screen in Flutter.

## Setup

Add the dependency and run the generator again. That is all: the starter
is found and switched on automatically.

```yaml
dependencies:
  spring_boot_starter_logging: ^0.3.1

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.3.1   # required: turns annotations into code
```

```bash
dart run build_runner build
```

## 1. Write logs

`@Log` on a class gives it a `log` getter, like Lombok's `@Slf4j`. The
generator writes it into the `.spring.dart` file of the scan; import that
file:

```dart
import 'package:shop/app.spring.dart'; // the generated file

@Service()
@Log(topic: 'shop.checkout') // without topic: 'shop.Checkout'
class Checkout {
  void pay(double amount) {
    log.info('paid $amount');
    log.debug(() => 'details: ${expensiveDump()}'); // built only if debug is on
    log.error('payment failed', error: e, stackTrace: s);
  }
}
```

### Without the annotation

Where no generated file is at hand (a library, a script, a top-level
function), create the logger yourself: the same `SpringLog`, named by you.

```dart
const log = SpringLog('shop.checkout');

void pay(double amount) => log.info('paid $amount');
```

Spring Boot's line (`[shop]` is `spring.application.name`, `[main]` the
isolate):

```text
2026-10-22T12:00:01.120+02:00  INFO 4711 --- [shop] [           main] shop.checkout                            : paid 12.5
```

## 2. Choose what is shown

```properties
# lib/resources/application.properties
logging.level.root=info              # everything: info and above
logging.level.shop.checkout=debug    # this logger and everything below it
```

Or without editing files: `LOGGING_LEVEL_SHOP_CHECKOUT=debug dart run bin/main.dart`.

## 3. Extra data on every line

```dart
log.info('order placed', fields: {'order': 42});
// ... shop.checkout                            : order placed {order=42}

// Everything logged inside gets the field (also in async code):
SpringLog.withFields({'request': requestId}, () => handle(request));
```

## 4. Console format

```properties
logging.pattern.console=%d{HH:mm:ss} %-5p [%logger{20}] %m%X%n%ex
logging.threshold.console=warn       # console shows only warnings and errors
# or keep Spring Boot's line and change parts of it:
logging.pattern.dateformat=HH:mm:ss.SSS
logging.pattern.level=%-5p
```

Logback's pattern syntax: `%d` time, `%p` level, `%logger{20}` name
(shortened to about 20 characters), `%m` message, `%X` fields, `%t`
isolate, `%ex` error with stack trace, `%clr(...)` colours, `%-20` /
`%.20` widths. A pattern it cannot read stops the start.

## 5. Log files

```properties
logging.file.name=logs/app.log
logging.logback.rollingpolicy.max-file-size=10MB   # then app.log.1, app.log.2, ...
logging.logback.rollingpolicy.max-history=7        # how many old files to keep
```

In Flutter, set the writable folder before starting:

```dart
LoggingSystem.instance.fileDirectory =
    (await getApplicationDocumentsDirectory()).path; // path_provider
```

## 6. A log screen in Flutter

The last records are kept in memory (`LogBuffer`). Inject it or use
`LoggingSystem.instance.buffer`, and show a live, filtered list:

```dart
StreamBuilder<List<SpringLogRecord>>(
  stream: buffer.watch(const LogQuery(minLevel: SpringLogLevel.info)),
  builder: (context, snapshot) => ListView(
    children: [
      for (final record in snapshot.data ?? const <SpringLogRecord>[])
        ListTile(
          title: Text(record.message),
          subtitle: Text('${record.loggerName} · ${record.time}'),
        ),
    ],
  ),
);
```

Also: `buffer.counts[SpringLogLevel.error]` for a badge,
`query.copyWith(text: 'payment')` for search, `buffer.export()` to share,
`buffer.clear()`.

## 7. Send logs somewhere else

```dart
class CrashReports extends LogAppender {
  CrashReports() : super(threshold: SpringLogLevel.error);

  @override
  void write(SpringLogRecord record) =>
      crashlytics.recordError(record.error ?? record.message, record.stackTrace);
}

LoggingSystem.instance.addAppender(CrashReports());
```

## 8. Change levels while the app runs

```dart
context.getBean<LoggingSystem>().setLogLevel('shop', SpringLogLevel.debug);
context.getBean<LoggingSystem>().setLogLevel('ROOT', SpringLogLevel.warning);
```

## Try it

[`example.dart`](example.dart) next to this file is a Spring Boot
application showing levels, fields and the buffer:
`dart run example/example.dart --logging.level.shop=debug`.
