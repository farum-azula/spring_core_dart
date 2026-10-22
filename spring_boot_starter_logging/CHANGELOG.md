## 0.1.4

- feat: ObjectMapper in core — JSON on generated metadata (@Introspected, @JsonProperty/@JsonIgnore/@JsonInclude/@JsonCreator/@JsonValue), spring.jackson.* in Boot

## 0.1.3

- add scheduling + cache starters
- fix extension add aop docs

## 0.1.2

- ci: release only from the release branch; fix version-dependent test; Node 24 actions
- fix tests

## 0.1.1

- Example on pub.dev (`example/`) and a description within 180 characters.

## 0.1.0

Initial version.

- Auto-configured `LoggingSystem` behind `SpringLog` (off with
  `logging.enabled=false`), installed before application beans are created
  and uninstalled when the context closes.
- `ConsoleAppender` with Logback-like `LogPattern`s
  (`logging.pattern.console`), thresholds per appender
  (`logging.threshold.console` / `.buffer`).
- `LogBuffer`: the last records in memory with `LogQuery` filtering,
  `watch` streams (one event per burst), counters, logger names and export.
- `FileAppender` (`logging.file.name` / `logging.file.path`,
  `logging.pattern.file`, `logging.threshold.file`) with size-based
  rollover (`logging.file.max-size`, `max-history`,
  `clean-history-on-start`), `LoggingSystem.fileDirectory` for relative
  locations, and a web stub (`FileAppender.isSupported`).
- `parseDataSize` (`10MB`, `512KB`, ...).
- Custom `LogAppender`s; runtime level changes.
