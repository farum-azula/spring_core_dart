# spring_boot_starter_logging: examples

This starter gives a
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
application proper logging: console lines in Spring Boot's format, log
levels per part of the application, log files, and an in-memory list of
recent records that a Flutter app can show on a screen.

[`example.dart`](example.dart) is a small Spring Boot application. A
checkout service logs two payments with fields, at three levels; a
receipt is logged through a logger made without the annotation; then the
application reads the warnings back from the in-memory buffer.

## Run it

```yaml
dependencies:
  spring_boot_starter_logging: ^0.4.3

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.3   # required: turns annotations into code
```

Adding the dependency and running the generator is all the setup: the
starter is found and switched on automatically. From the package
directory:

```bash
dart run build_runner build
dart run example/example.dart
```

After the startup lines it logs (each line starts with the date and
time, shortened to `...` here):

```text
...  INFO 4711 --- [           main] shop.checkout                            : paid 12.5 {request=r-1, order=1}
...  INFO 4711 --- [           main] shop.checkout                            : paid 250.0 {request=r-1, order=2}
...  WARN 4711 --- [           main] shop.checkout                            : large payment {request=r-1, order=2}
...  INFO 4711 --- [           main] shop.receipts                            : receipt printed {request=r-1, order=2}
...  INFO 4711 --- [           main] shop.startup                             : 1 warning(s): large payment
```

The debug lines are not there: the default level is `info`. Turn them on
for the `shop` loggers with a command-line argument or an environment
variable, and `basket of order 1 checked` appears:

```bash
dart run example/example.dart --logging.level.shop=debug
LOGGING_LEVEL_SHOP=debug dart run example/example.dart
```

## 1. Write logs

`@Log()` on a class gives it a `log` getter, as Lombok's `@Slf4j` does in
Java. The generator writes the getter into the `.spring.dart` file of the
scan, so import that file:

```dart
import 'example.spring.dart'; // the generated file

@Service()
@Log(topic: 'shop.checkout') // without topic: <package>.Checkout
class Checkout {
  void pay(int order, double amount) {
    log.info('paid $amount', fields: {'order': order});
    // A function: the message is built only when debug is on for this logger.
    log.debug(() => 'basket of order $order checked');
    if (amount > 100) {
      log.warning('large payment', fields: {'order': order});
    }
  }
}
```

`log.error('payment failed', error: e, stackTrace: s)` logs an error with
its stack trace.

### Without the annotation

Where no generated file is at hand (a library, a script, a top-level
function), create the logger yourself: the same `SpringLog`, named by you.

```dart
const _receipts = SpringLog('shop.receipts');

void printReceipt(int order) =>
    _receipts.info('receipt printed', fields: {'order': order});
```

## 2. Choose what is shown

A level applies to a logger and every logger below it:

```properties
# lib/resources/application.properties
logging.level.root=info              # everything: info and above
logging.level.shop.checkout=debug    # this logger and everything below it
```

## 3. Extra data on every line

Fields go after the message and can be searched in the buffer. Fields
given to `SpringLog.withFields` go on every line logged inside, in async
code too; in the example, every line carries `request=r-1`:

```dart
SpringLog.withFields({'request': 'r-1'}, () {
  checkout
    ..pay(1, 12.5)
    ..pay(2, 250);
  printReceipt(2);
});
```

## 4. Console format

```properties
logging.pattern.console=%d{HH:mm:ss} %-5p [%logger{20}] %m%X%n%ex
logging.threshold.console=warn       # the console shows only warnings and errors
# or keep Spring Boot's line and change parts of it:
logging.pattern.dateformat=HH:mm:ss.SSS
logging.pattern.level=%-5p
```

The pattern syntax is Logback's: `%d` the time, `%p` the level,
`%logger{20}` the logger name (shortened to about 20 characters), `%m` the
message, `%X` the fields, `%t` the isolate, `%ex` the error with its stack
trace, `%clr(...)` colours, `%-20` / `%.20` widths. A pattern it cannot
read stops the start.

## 5. Log files

```properties
logging.file.name=logs/app.log
logging.logback.rollingpolicy.max-file-size=10MB   # then app.log.1, app.log.2, ...
logging.logback.rollingpolicy.max-history=7        # how many old files to keep
```

In Flutter, set the writable directory before starting:

```dart
LoggingSystem.instance.fileDirectory =
    (await getApplicationDocumentsDirectory()).path; // path_provider
```

## 6. Read the records back

The last records are kept in memory, in the `LogBuffer` bean. The example
injects it and asks for the warnings:

```dart
@Component()
@Log(topic: 'shop.startup')
class PayOnStartup implements CommandLineRunner {
  PayOnStartup(this.checkout, this.logs);
  final Checkout checkout;
  final LogBuffer logs;

  @override
  void run(List<String> args) {
    // ... the payments above ...
    final warnings = logs.query(const LogQuery(minLevel: SpringLogLevel.warning));
    log.info('${warnings.length} warning(s): ${warnings.single.message}');
  }
}
```

In a Flutter app, the same buffer feeds a live, filtered log screen:

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
`query.copyWith(text: 'payment')` for a search box, `buffer.export()` to
share, `buffer.clear()`.

## 7. Send logs somewhere else

```dart
// Errors also go to the crash reporter.
class CrashReports extends LogAppender {
  CrashReports() : super(threshold: SpringLogLevel.error);

  @override
  void write(SpringLogRecord record) =>
      crashlytics.recordError(record.error ?? record.message, record.stackTrace);
}

LoggingSystem.instance.addAppender(CrashReports());
```

## 8. Change levels while the application runs

```dart
context.getBean<LoggingSystem>().setLogLevel('shop', SpringLogLevel.debug);
context.getBean<LoggingSystem>().setLogLevel('ROOT', SpringLogLevel.warning);
```

Every property, pattern conversion and difference from Spring Boot is in
the package [README](https://pub.dev/packages/spring_boot_starter_logging).
