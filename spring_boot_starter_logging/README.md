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
  spring_boot_dart: ^0.1.0
  spring_boot_starter_logging: ^0.1.0
```

```dart
const log = SpringLog('neon.checkout');

log.info('paid 12.5', fields: {'order': 1});
```

Spring Boot's console line (with `spring.application.name=shop`):

```text
2026-10-23T23:08:01.580+02:00  INFO 4711 --- [shop] [           main] neon.checkout                            : paid 12.5 {order=1}
```

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
spring.output.ansi.enabled=detect        # %clr colours: detect (a terminal), always, never
logging.threshold.console=warn           # console: warnings and errors only
logging.console.enabled=true
logging.buffer.enabled=true
logging.buffer.capacity=1000
logging.threshold.buffer=debug
logging.file.name=logs/shop.log          # a log file (or logging.file.path=logs → logs/spring.log)
logging.pattern.file=%d %5p [%logger] %m%X%n%ex   # default: Boot's
logging.threshold.file=info
logging.logback.rollingpolicy.max-file-size=10MB  # roll over into shop.log.1, .2, ...
logging.logback.rollingpolicy.max-history=7       # rolled-over files kept
logging.logback.rollingpolicy.total-size-cap=0B   # their total size; 0B: no limit
logging.logback.rollingpolicy.clean-history-on-start=false
logging.enabled=false                    # turn the starter off
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
...); only `max-history` of them are kept, and the oldest are deleted while
together they exceed `total-size-cap`.

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
- Not supported: caller data (`%C`, `%M`, `%L`, `%F`, `%caller`),
  `%marker`, `%property`, `%replace`, `%contextName`, Logback's colour
  words (`%red`, `%highlight`, ...), `%d` time zones other than UTC (Dart
  has no time zone database), `logback.xml` / `logback-spring.xml`.
- `%clr` colours are on when `spring.output.ansi.enabled` says so; `detect`
  means a terminal on standard output (never on the web or in a file).
- Rolling is by size into numbered files (`shop.log.1`, `.2`, ...), not
  `logging.logback.rollingpolicy.file-name-pattern` with dates;
  `max-history` counts files, not days; archives are not compressed.
- No structured logging (`logging.structured.*`), no `logging.config`,
  no predefined `web` / `sql` logger groups, no `logging.charset.*`.
