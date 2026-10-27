# spring_boot_starter_logging

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

Logging for [`spring_boot_dart`](../spring_boot_dart) applications, like
`spring-boot-starter-logging`. Add the dependency; the generator discovers
the auto-configuration and a `LoggingSystem` is installed behind the
`SpringLog` facade. No code needed.

```yaml
dependencies:
  spring_boot_starter_logging: ^0.4.1
```

```dart
import 'package:neon/app.spring.dart'; // the generated file

@Service()
@Log(topic: 'neon.checkout') // generates the `log` getter, like Lombok's @Slf4j
class Checkout {
  void pay(int order, double amount) =>
      log.info('paid $amount', fields: {'order': order});
}
```

Spring Boot's console line (with `spring.application.name=shop`):

```text
2026-10-23T23:08:01.580+02:00  INFO 4711 --- [shop] [           main] neon.checkout                            : paid 12.5 {order=1}
```

*In the guides:* [server, 11. Logging](https://github.com/farum-azula/spring_core_dart/tree/main/example/server_guide#11-logging), [app, 10. Logging](https://github.com/farum-azula/spring_core_dart/tree/main/example/flutter_guide#10-logging).

## Properties

```properties
logging.level.root=info                  # Boot's default with this starter (ROOT in any case)
logging.level.neon.checkout=debug        # a logger and its descendants
logging.group.payments=neon.card,neon.cash
logging.level.payments=trace
logging.pattern.console=%d{HH:mm:ss.SSS} %5p [%logger{20}] %m%X%n%ex   # default: Boot's
logging.pattern.dateformat=yyyy-MM-dd'T'HH:mm:ss.SSSXXX  # %d of the default patterns
logging.pattern.level=%5p                # the level of the default patterns
logging.pattern.correlation=             # after [thread] in the default patterns
logging.exception-conversion-word=%wEx   # the error of the default patterns
logging.include-application-name=true    # [spring.application.name] in the default patterns
logging.include-application-group=true   # [spring.application.group]
spring.output.ansi.enabled=always        # console colours: always (default), detect (a terminal, Flutter debug), never
logging.threshold.console=warn           # console: warnings and errors only
logging.console.enabled=true
logging.buffer.enabled=true
logging.buffer.capacity=1000
logging.threshold.buffer=debug
logging.file.name=logs/shop.log          # a log file (or logging.file.path=logs → logs/spring.log)
logging.pattern.file=%d %5p [%logger] %m%X%n%ex   # default: Boot's
logging.threshold.file=info
logging.charset.file=UTF-8               # also ISO-8859-1, US-ASCII
logging.logback.rollingpolicy.max-file-size=10MB  # roll over into shop.log.1, .2, ...
logging.logback.rollingpolicy.max-history=7       # rolled-over files kept; 0: all
logging.logback.rollingpolicy.total-size-cap=0B   # their total size; 0B: no limit
logging.logback.rollingpolicy.clean-history-on-start=false
logging.enabled=false                    # turn the starter off (on/off values: true / false in any case)
```

## Patterns

Logback's `PatternLayout` syntax with Spring Boot's converters
(`LogPattern`):

| Conversion | Output |
|---|---|
| `%d`, `%date{pattern[, UTC]}` | time; Java pattern letters (`yyyy-MM-dd'T'HH:mm:ss.SSSXXX`, `EEE`, `MMM`, `a`, ...), `ISO8601` (the default: `yyyy-MM-dd HH:mm:ss,SSS`) |
| `%p`, `%le`, `%level` | `TRACE DEBUG INFO WARN ERROR` |
| `%c`, `%lo`, `%logger{n}` | logger name, shortened like Logback (`%logger{15}`: `n.c.Payments`; `{0}`: the last segment) |
| `%m`, `%msg`, `%message` | message |
| `%t`, `%thread` | isolate name (`main`) |
| `%X{key}`, `%X{key:-default}`, `%X` | one field; all fields as ` {k=v, ...}` |
| `%ex`, `%exception`, `%throwable{short\|full\|n}`, `%xEx`, `%rEx` | error and stack trace |
| `%wEx` | the same between line breaks (Boot) |
| `%nopex` | no error output |
| `%clr(...){color}` | colours (Boot): `faint`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `black`, `white`, `bright_*`; none: by level |
| `%esb(...){VAR}` | `[value] ` of its content or a variable, nothing when empty (Boot) |
| `%red(...)`, `%boldRed(...)`, `%gray(...)`, ..., `%highlight(...)` | Logback's colours, always ANSI: `black red green yellow blue magenta cyan white gray`, `bold...`; `%highlight` by level |
| `%replace(...){regex, replacement}` | its content with the matches replaced (`$1` for groups) |
| `%kvp{DOUBLE\|SINGLE\|NONE}` | the fields as `key="value"` pairs |
| `%prefix(...)` | each conversion inside as `name=value` (`level=INFO`) |
| `%property{key}` | a variable or property (`null` when there is none) |
| `%(...)` | groups content for a format modifier |
| `%r`, `%relative` | milliseconds since logging started |
| `%seq` | record sequence number |
| `%n`, `%%`, `\%`, `\(`, `\)` | line break, `%`, `(`, `)` |

Format modifiers as in Logback: `%5p` pads left, `%-5p` right, `%.10c`
keeps the last 10 characters, `%.-10c` the first 10, `%-40.40logger{39}`
all of it. `${PID}`, `${LOG_LEVEL_PATTERN:-%5p}` and other `${NAME}` /
`${NAME:-default}` are replaced first: Boot's logging variables (`PID`,
`APPLICATION_NAME`, `LOG_DATEFORMAT_PATTERN`, ...), then properties
(`${spring.application.name}`). As in Logback, a pattern without an error
conversion still prints errors after the line. Anything the parser
cannot read (an unknown word, an unclosed `(`, an unknown colour, date
letter or variable) fails the start.

## Log files

`logging.file.name` (a file) or `logging.file.path` (a directory with
`spring.log`) turns on a `FileAppender`. Lines logged in one synchronous
burst are written together at the end of the microtask; the rest is
written when the context closes. When the file would grow past
`max-file-size` it becomes `shop.log.1` (older ones shift to `.2`, `.3`,
...); only `max-history` of them are kept (all with `0`, like Logback), and
the oldest are deleted while together they exceed `total-size-cap`.

Relative locations are resolved against `LoggingSystem.instance.fileDirectory`
when it is set, else against the working directory. In Flutter the
writable directory is only known at runtime, so set it before starting
(the coming Flutter starter will do it for you):

```dart
LoggingSystem.instance.fileDirectory =
    (await getApplicationDocumentsDirectory()).path; // path_provider
await runApplicationAsync(args);
```

On the web there is no file system: `logging.file.*` is ignored with a
warning and `FileAppender.isSupported` is `false`.

## A log screen (Flutter)

`LogBuffer` keeps the last records in memory. It is a bean (inject it) and
also `LoggingSystem.instance.buffer`. Its API is made for a log viewer:

```dart
class LogScreen extends StatefulWidget { ... }

class _LogScreenState extends State<LogScreen> {
  final buffer = LoggingSystem.instance.buffer;
  var query = const LogQuery(minLevel: SpringLogLevel.info);

  @override
  Widget build(BuildContext context) => Column(children: [
    TextField(onChanged: (text) => setState(() => query = query.copyWith(text: text))),
    Expanded(
      child: StreamBuilder<List<SpringLogRecord>>(
        stream: buffer.watch(query), // current list, then one per burst
        builder: (context, snapshot) {
          final records = snapshot.data ?? const [];
          return ListView.builder(
            itemCount: records.length,
            itemBuilder: (context, i) => ListTile(
              key: ValueKey(records[i].sequence),
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
| Live filtered list | `buffer.watch(query)` → `Stream<List<SpringLogRecord>>` |
| Snapshot | `buffer.records`, `buffer.query(query)` |
| Every new record | `buffer.onRecord` |
| Badges | `buffer.counts[SpringLogLevel.error]`, `buffer.dropped` |
| Logger filter menu | `buffer.loggerNames` |
| Share / copy | `buffer.export(query)` (or with a `LogPattern`) |
| Clear | `buffer.clear()` |
| Filters | `LogQuery(minLevel, levels, logger, text, fields, since)`, immutable, `copyWith` (`null` removes a criterion) |
| Change levels at runtime | `loggingSystem.setLogLevel('neon', SpringLogLevel.debug)`, `setLogLevel('ROOT', ...)`, `rootLevel` |

Records are immutable and carry `time`, `sequence` (a stable list key),
`level`, `loggerName`, `message`, `fields`, `error`, `stackTrace`.

In Flutter, send the console to `debugPrint` before starting:
`LoggingSystem.instance.console.out = debugPrint;`

## Own appenders

```dart
class CrashReportAppender extends LogAppender {
  CrashReportAppender() : super(threshold: SpringLogLevel.error);

  @override
  void write(SpringLogRecord record) =>
      crashlytics.recordError(record.error ?? record.message, record.stackTrace);
}

LoggingSystem.instance.addAppender(CrashReportAppender());
```

A failing appender does not stop the others.

## Without Spring Boot

```dart
LoggingSystem.instance
  ..configure(environment) // the logging.* properties
  ..install();
```

## Differences from Spring

- One line per record: patterns are Logback's, but the console (`print`)
  and the file add the line break, so a pattern's final `%n` is dropped
  (`LogPattern.formatLine`). Boot's default patterns are used as they are
  (`%m%n%wEx`), with the record's fields (`%X`) after the message.
- `%thread` is the isolate name; `%X` prints ` {k=v, ...}` (with a leading
  space, nothing without fields) instead of `k=v, k=v`.
- Caller data is impossible: a Dart record does not know the class,
  method, line or file that logged it (`%C`, `%M`, `%L`, `%F`, `%caller`
  stop the start as unknown words).
- Not supported: `%marker`, `%contextName`, `%d` time zones other than UTC
  (Dart has no time zone database), `logback.xml` / `logback-spring.xml`.
- The console is coloured by default (`spring.output.ansi.enabled=always`;
  Spring Boot's default is `detect`): `%clr`, and in a pattern that
  colours nothing itself (no `%clr`, no Logback colour) the time faint,
  the level by level and the logger cyan, as in Spring Boot's pattern. So
  a short `logging.pattern.console=%d %5p [%logger] %m` is coloured too.
  Files are never coloured. Where a program reads the output (a log
  collector, Xcode's console, `adb logcat`, output redirected to a file),
  set `never`; `detect` colours only a terminal on standard output or a
  Flutter debug or profile build.
  Logback's colour words (`%red(...)`, `%boldRed(...)`, `%highlight(...)`)
  always write ANSI codes, as Logback does.
- `%kvp` prints the record's fields (Dart has no SLF4J key-value pairs);
  `%prefix` names conversions by Logback's long names (`level=`,
  `logger=`, `%X{key}` as `key=`); `%property` reads the pattern
  variables, then the environment.
- Rolling is by size only, into numbered files (`shop.log.1`, `.2`, ...):
  `logging.logback.rollingpolicy.file-name-pattern` (dates, `%i`, `.gz`)
  is ignored with a warning; `max-history` counts files, not days;
  archives are not compressed.
- `logging.charset.file` takes the encodings Dart knows (UTF-8,
  ISO-8859-1, US-ASCII, by their IANA or Java names such as `utf8`);
  `logging.charset.console` is only checked: the
  console is `print`, which writes text, not bytes.
- An empty `logging.pattern.console=` (or `logging.pattern.file=`) turns
  that output off, as Logback's appender does not start without a
  pattern (Logback also reports a status error).
- Lines logged while the application starts, before the logging system
  is set up during the refresh, are replayed into the file, the buffer and
  added appenders (Spring Boot's `DeferredLogs`); the console showed them
  already through the `SpringLog.handler` of the time, in its format.
- A failed start keeps the logging system installed until the failure
  report is logged (so it reaches the file), then uninstalls it.
- No structured logging (`logging.structured.*`), no `logging.config`,
  no predefined `web` / `sql` logger groups.
