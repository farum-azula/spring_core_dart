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
