# spring_boot_starter_logging

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

```text
23:08:01.580  INFO [neon.checkout] paid 12.5 {order=1}
```

## Properties

```properties
logging.level.root=info                  # Boot's default with this starter
logging.level.neon.checkout=debug        # a logger and its descendants
logging.group.payments=neon.card,neon.cash
logging.level.payments=trace
logging.pattern.console=%d{HH:mm:ss.SSS} %5p [%logger] %m%X%ex
logging.threshold.console=warn           # console: warnings and errors only
logging.console.enabled=true
logging.buffer.enabled=true
logging.buffer.capacity=1000
logging.threshold.buffer=debug
logging.file.name=logs/shop.log          # a log file (or logging.file.path=logs → logs/spring.log)
logging.pattern.file=%d %5p [%logger] %m%X%ex
logging.threshold.file=info
logging.file.max-size=10MB               # roll over into shop.log.1, .2, ...
logging.file.max-history=7               # rolled-over files kept
logging.file.clean-history-on-start=false
logging.enabled=false                    # turn the starter off
```

Pattern tokens: `%d{yyyy-MM-dd HH:mm:ss.SSS}`, `%p`/`%level`,
`%c`/`%logger`, `%m`/`%msg`, `%X{key}` (one field), `%X` (all fields),
`%ex` (error and stack trace), `%seq`, `%n`, `%%`; widths pad (`%5p`,
`%-20logger`). An unknown token fails the start.

## Log files

`logging.file.name` (a file) or `logging.file.path` (a directory with
`spring.log`) turns on a `FileAppender`. Lines logged in one synchronous
burst are written together at the end of the microtask; the rest is
written when the context closes. When the file would grow past
`max-size` it becomes `shop.log.1` (older ones shift to `.2`, `.3`, ...) and
only `max-history` of them are kept. Differences from Logback: the history
counts files, not days, and archives are not compressed.

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
| Change levels at runtime | `loggingSystem.setLevel('neon', SpringLogLevel.debug)`, `rootLevel` |

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
