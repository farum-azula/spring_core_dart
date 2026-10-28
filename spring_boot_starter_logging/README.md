# spring_boot_starter_logging

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

Logging for [`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
applications: formatted console lines, log files that roll over, an
in-memory list of recent records for an in-app log screen, and logger
levels you set in properties or change while the application runs.

`SpringLog`, the logger of `spring_core_dart`, alone prints plain lines
and shows only warnings and errors. Add this starter and its lines come
out in Spring Boot's format, at Spring Boot's default level (`info`),
configured by the same `logging.*` properties a Spring Boot application
uses. No code is needed: the generator finds the starter, and a
`LoggingSystem` is installed behind `SpringLog` when the application
starts.

Every application that logs wants it; the other starters (web, Feign,
WebSocket, scheduling, cache) bring it along. It is the Dart counterpart
of `spring-boot-starter-logging`, with Logback's pattern syntax.

## Install

```yaml
dependencies:
  spring_boot_starter_logging: ^0.4.2
```

## A first log line

`@Log()` on a class gives it a `log` getter. The generator writes the
getter into the `.spring.dart` file of the scan, so import that file:

```dart
import 'package:neon/app.spring.dart'; // the generated file

@Service()
@Log(topic: 'neon.checkout') // the logger's name; without topic: <package>.<Class>
class Checkout {
  // The order goes along as a field: searchable, and printed after the message.
  void pay(int order, double amount) =>
      log.info('paid $amount', fields: {'order': order});
}
```

The console line, in Spring Boot's format (with
`spring.application.name=shop`):

```text
2026-10-23T23:08:01.580+02:00  INFO 4711 --- [shop] [           main] neon.checkout                            : paid 12.5 {order=1}
```

Lombok's `@Slf4j(topic = "neon.checkout")` is the Java counterpart of
`@Log(topic: 'neon.checkout')`. Where no generated file is at hand (a
library, a script, a top-level function), create the logger yourself:
`const log = SpringLog('neon.checkout');`.

*In the guides:* [server, 11. Logging](https://github.com/farum-azula/spring_core_dart/tree/main/example/server_guide#11-logging), [app, 10. Logging](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_guide#10-logging).

## Properties

Everything is set with Spring Boot's `logging.*` properties. The
`logging.level.*` and `logging.group.*` ones are applied by
`spring_boot_dart` itself; the starter reads the rest.

```properties
# Levels: which records exist at all.
logging.level.root=info                  # Boot's default with this starter (ROOT in any case)
logging.level.neon.checkout=debug        # a logger and its descendants
logging.group.payments=neon.card,neon.cash
logging.level.payments=trace             # every logger of the group

# The console.
logging.pattern.console=%d{HH:mm:ss.SSS} %5p [%logger{20}] %m%X%n%ex   # default: Boot's
logging.pattern.dateformat=yyyy-MM-dd'T'HH:mm:ss.SSSXXX  # the %d of the default patterns
logging.pattern.level=%5p                # the level of the default patterns
logging.pattern.correlation=             # after [thread] in the default patterns
logging.exception-conversion-word=%wEx   # the error of the default patterns
logging.include-application-name=true    # [spring.application.name] in the default patterns
logging.include-application-group=true   # [spring.application.group]
spring.output.ansi.enabled=always        # console colours: always (default), detect, never
logging.threshold.console=warn           # console: warnings and errors only
logging.console.enabled=true

# The in-memory buffer (see "A log screen").
logging.buffer.enabled=true
logging.buffer.capacity=1000
logging.threshold.buffer=debug

# A log file (see "Log files").
logging.file.name=logs/shop.log          # or logging.file.path=logs: logs/spring.log
logging.pattern.file=%d %5p [%logger] %m%X%n%ex   # default: Boot's
logging.threshold.file=info
logging.charset.file=UTF-8               # also ISO-8859-1, US-ASCII
logging.logback.rollingpolicy.max-file-size=10MB  # then roll over into shop.log.1, .2, ...
logging.logback.rollingpolicy.max-history=7       # rolled-over files kept; 0: all
logging.logback.rollingpolicy.total-size-cap=0B   # their total size; 0B: no limit
logging.logback.rollingpolicy.clean-history-on-start=false

logging.enabled=false                    # turn the starter off
```

- A level property applies to the logger and every logger below it:
  `neon` covers `neon.checkout`, unless that one has a level of its own.
  An environment variable works too:
  `LOGGING_LEVEL_NEON_CHECKOUT=debug dart run bin/main.dart`.
- The **thresholds** let one output keep fewer records than the levels
  allow, such as a console that shows only warnings while the file gets
  everything. Levels are `trace`, `debug`, `info`, `warn`, `error`, `off`
  in any case.
- `spring.output.ansi.enabled=detect` colours only a terminal on standard
  output, or a Flutter debug or profile build.
- The on/off properties take `true` / `false` in any case, and also
  `on` / `off`, `yes` / `no`, `1` / `0`; other values fail the start. For
  `logging.enabled`, only `false` turns the starter off: as with Spring
  Boot's `@ConditionalOnProperty`, `off`, `no` or `0` leave it on.
- A value the starter cannot read (a pattern, a level, a number, a size, a
  charset) fails the start rather than logging badly.
- The names from before Spring Boot 2.4 (`logging.file.max-size`,
  `logging.file.max-history`, `logging.file.total-size-cap`,
  `logging.file.clean-history-on-start`) are ignored with a warning
  naming the current one.

## Patterns

`logging.pattern.console` and `logging.pattern.file` describe a log line.
The syntax is Logback's `PatternLayout` with Spring Boot's converters, so
the patterns of a Spring Boot application work here as they are. In code
the class is `LogPattern`.

| Conversion | Output |
|---|---|
| `%d`, `%date{pattern[, UTC]}` | the time; Java pattern letters (`yyyy-MM-dd'T'HH:mm:ss.SSSXXX`, `EEE`, `MMM`, `a`, ...), or `ISO8601` (the default: `yyyy-MM-dd HH:mm:ss,SSS`) |
| `%p`, `%le`, `%level` | `TRACE DEBUG INFO WARN ERROR` |
| `%c`, `%lo`, `%logger{n}` | the logger name, shortened as Logback does (`%logger{15}`: `n.c.Payments`; `{0}`: the last segment) |
| `%m`, `%msg`, `%message` | the message |
| `%t`, `%thread` | the isolate name (`main`) |
| `%X{key}`, `%X{key:-default}`, `%X` | one field; `%X` alone gives all fields as ` {k=v, ...}` |
| `%ex`, `%exception`, `%throwable{short\|full\|n}`, `%xEx`, `%rEx` | the error and its stack trace |
| `%wEx` | the same, between line breaks (Spring Boot) |
| `%nopex` | no error output |
| `%clr(...){color}` | colours its content (Spring Boot): `faint`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `black`, `white`, `bright_*`; without a colour, by level |
| `%esb(...){VAR}` | `[value] ` of its content or of a variable, nothing when empty (Spring Boot) |
| `%red(...)`, `%boldRed(...)`, `%gray(...)`, ..., `%highlight(...)` | Logback's colours, always ANSI: `black red green yellow blue magenta cyan white gray` and `bold...`; `%highlight` by level |
| `%replace(...){regex, replacement}` | its content with every match replaced (`$1` for groups) |
| `%kvp{DOUBLE\|SINGLE\|NONE}` | the fields as `key="value"` pairs |
| `%prefix(...)` | each conversion inside as `name=value` (`level=INFO`) |
| `%property{key}` | a variable or property (`null` when there is none) |
| `%(...)` | groups content for a format modifier |
| `%r`, `%relative` | milliseconds since logging started |
| `%seq` | the record's sequence number |
| `%n`, `%%`, `\%`, `\(`, `\)` | a line break, `%`, `(`, `)` |

Format modifiers work as in Logback: `%5p` pads on the left, `%-5p` on
the right, `%.10c` keeps the last 10 characters, `%.-10c` the first 10,
and `%-40.40logger{39}` combines them.

`${NAME}` and `${NAME:-default}` are replaced before the pattern is read:
first Spring Boot's logging variables (`PID`, `APPLICATION_NAME`,
`LOG_DATEFORMAT_PATTERN`, `LOG_LEVEL_PATTERN`, ...), then properties
(`${spring.application.name}`). So `${PID}` and
`${LOG_LEVEL_PATTERN:-%5p}` work as in Spring Boot.

As in Logback, a pattern without an error conversion still prints the
error, on the lines after the record. Anything the parser cannot read (an
unknown word, an unclosed `(`, an unknown colour, date letter or
variable) fails the start.

## Log files

A server keeps its logs in files; an app may keep one to attach to bug
reports. `logging.file.name` (a file) or `logging.file.path` (a directory,
with `spring.log` in it) turns on a `FileAppender`:

- Lines logged in one synchronous burst are written together, in one
  write at the end of the microtask. Lines still waiting are written when
  the context closes.
- When the file would grow past `max-file-size`, it is renamed to
  `shop.log.1` and a new one is started; older files shift to `.2`, `.3`,
  and so on. Only `max-history` of them are kept (all of them with `0`, as
  in Logback), and the oldest are deleted while together they exceed
  `total-size-cap`.
- `clean-history-on-start=true` deletes the rolled-over files when the
  application starts.

Relative locations are resolved against
`LoggingSystem.instance.fileDirectory` when it is set, else against the
working directory. A Flutter app's writable directory is only known at
runtime, so set it before starting the application:

```dart
// The app's documents directory, from path_provider.
LoggingSystem.instance.fileDirectory =
    (await getApplicationDocumentsDirectory()).path;
await runApplicationAsync(args);
```

On the web there is no file system: `logging.file.*` is ignored with a
warning, and `FileAppender.isSupported` is `false`.

## A log screen (Flutter)

A mobile or desktop app has no terminal its users can read. `LogBuffer`
keeps the most recent records in memory, so an app can offer a log
screen, a "send logs" button for bug reports, or an error badge in a
debug menu. It is a bean (`logBuffer`, inject it) and also
`LoggingSystem.instance.buffer`, and its API is made for a log viewer:

```dart
class LogScreen extends StatefulWidget { ... }

class _LogScreenState extends State<LogScreen> {
  final buffer = LoggingSystem.instance.buffer;
  var query = const LogQuery(minLevel: SpringLogLevel.info);

  @override
  Widget build(BuildContext context) => Column(children: [
    // The search box narrows the list as the user types.
    TextField(onChanged: (text) => setState(() => query = query.copyWith(text: text))),
    Expanded(
      child: StreamBuilder<List<SpringLogRecord>>(
        stream: buffer.watch(query), // the current list, then a new one per burst of records
        builder: (context, snapshot) {
          final records = snapshot.data ?? const [];
          return ListView.builder(
            itemCount: records.length,
            itemBuilder: (context, i) => ListTile(
              key: ValueKey(records[i].sequence), // stable while the list changes
              title: Text(records[i].message),
              subtitle: Text('${records[i].loggerName} · ${records[i].fields}'),
            ),
          );
        },
      ),
    ),
  ]);
}
```

| Need | API |
|---|---|
| A live filtered list | `buffer.watch(query)` → `Stream<List<SpringLogRecord>>` |
| A snapshot | `buffer.records`, `buffer.query(query)` |
| Every new record | `buffer.onRecord` |
| Badges | `buffer.counts[SpringLogLevel.error]`, `buffer.dropped` (records pushed out by the capacity) |
| A logger filter menu | `buffer.loggerNames` |
| Share or copy | `buffer.export(query)` (or with a `LogPattern`) |
| Clear | `buffer.clear()` |
| Filters | `LogQuery(minLevel, levels, logger, text, fields, since)`: immutable, changed with `copyWith` |
| Change levels at runtime | `loggingSystem.setLogLevel('neon', SpringLogLevel.debug)`, `setLogLevel('ROOT', ...)`, `rootLevel` |

`copyWith(minLevel: null)` (or `levels`, `logger`, `text`, `since`)
removes that criterion. `fields` is the exception: `copyWith(fields:
null)` keeps the current fields; pass `const {}` to remove them.

Records are immutable and carry `time`, `sequence` (a stable list key),
`level`, `loggerName`, `message`, `fields`, `error` and `stackTrace`.

In Flutter, send the console to `debugPrint` before starting, so long
lines are not cut by the device log:
`LoggingSystem.instance.console.out = debugPrint;`

There is no Spring counterpart of the buffer.

## Changing levels at runtime

To look into one part of a running application without a restart,
inject the `loggingSystem` bean and change a level:

```dart
// An admin action turns on debug lines for the checkout.
@Service()
class LogLevels {
  LogLevels(this.logging);
  final LoggingSystem logging;

  void debugCheckout() => logging.setLogLevel('neon.checkout', SpringLogLevel.debug);
}
```

A `null` level removes the logger's own level, so it inherits again.
`ROOT` (in any case) is the root logger, which always needs a level. This
is Spring Boot's `LoggingSystem.setLogLevel`.

## Your own appenders

An appender is one output of the logging system. To send records
somewhere else as well, such as a crash reporter or a remote log service,
extend `LogAppender` and add it:

```dart
// Errors also go to the crash reporter, with their stack trace.
class CrashReportAppender extends LogAppender {
  CrashReportAppender() : super(threshold: SpringLogLevel.error);

  @override
  void write(SpringLogRecord record) =>
      crashlytics.recordError(record.error ?? record.message, record.stackTrace);
}

LoggingSystem.instance.addAppender(CrashReportAppender());
```

`write` runs synchronously on the logging call, so queue slow work such
as a network call. A failing appender does not stop the others. An added
appender stays until `removeAppender`, also across application restarts.
In Spring this is a Logback `Appender` declared in `logback-spring.xml`;
here it is added in code.

## Without Spring Boot

Without `SpringApplication`, configure and install the logging system
yourself:

```dart
LoggingSystem.instance
  ..configure(environment) // the outputs: patterns, thresholds, buffer, file
  ..install();             // from now on SpringLog records come here
```

`configure` sets up the outputs and the default root level `info`. The
per-logger levels (`logging.level.*`, `logging.group.*`) are applied by
`SpringApplication.applyLoggingLevels(environment)`, or set them with
`setLogLevel`.

## Differences from Spring

- One line per record: patterns are Logback's, but the console (`print`)
  and the file add the line break, so a pattern's final `%n` is dropped
  (`LogPattern.formatLine`). Spring Boot's default patterns are used as
  they are (`%m%n%wEx`), with the record's fields (`%X`) after the
  message.
- `%thread` is the isolate name. `%X` prints ` {k=v, ...}`, with a
  leading space and nothing when there are no fields, instead of
  `k=v, k=v`.
- Caller data is impossible: a Dart record does not know the class,
  method, line or file that logged it. `%C`, `%M`, `%L`, `%F` and
  `%caller` stop the start as unknown words.
- Not supported: `%marker`, `%contextName`, `%d` time zones other than
  UTC (Dart has no time zone database), `logback.xml` /
  `logback-spring.xml`.
- The console is coloured by default (`spring.output.ansi.enabled=always`;
  Spring Boot's default is `detect`). Besides `%clr`, a pattern that
  colours nothing itself (no `%clr`, no Logback colour) gets Spring Boot's
  colours: the time faint, the level by level, the logger cyan. So a short
  `logging.pattern.console=%d %5p [%logger] %m` is coloured too. Files are
  never coloured. Where a program reads the output (a log collector,
  Xcode's console, `adb logcat`, output redirected to a file), set
  `never`. Logback's colour words (`%red(...)`, `%boldRed(...)`,
  `%highlight(...)`) always write ANSI codes, as in Logback.
- `%kvp` prints the record's fields (Dart has no SLF4J key-value pairs).
  `%prefix` names conversions by Logback's long names (`level=`,
  `logger=`, `%X{key}` as `key=`). `%property` reads the pattern
  variables, then the environment.
- Rolling is by size only, into numbered files (`shop.log.1`, `.2`, ...).
  `logging.logback.rollingpolicy.file-name-pattern` (dates, `%i`, `.gz`)
  is ignored with a warning; `max-history` counts files, not days;
  archives are not compressed.
- `logging.charset.file` takes the encodings Dart knows (UTF-8,
  ISO-8859-1, US-ASCII, by their IANA or Java names such as `utf8`);
  characters it cannot encode are written as `?`, as in Java.
  `logging.charset.console` is only checked: the console is `print`,
  which writes text, not bytes.
- An empty `logging.pattern.console=` (or `logging.pattern.file=`) turns
  that output off, because Logback's appender does not start without a
  pattern (Logback also reports a status error).
- Lines logged while the application starts, before the logging system
  is set up during the refresh, are replayed into the file, the buffer and
  added appenders (Spring Boot's `DeferredLogs`). The console showed them
  already, through the `SpringLog.handler` of that moment and in its
  format.
- A failed start keeps the logging system installed until the failure
  report is logged, so the report reaches the file, then uninstalls it.
- No structured logging (`logging.structured.*`), no `logging.config`,
  no predefined `web` / `sql` logger groups.
