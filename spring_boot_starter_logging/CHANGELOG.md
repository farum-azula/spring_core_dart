## 0.8.0

- No changes of its own; released with the family version 0.8.0.

## 0.7.4

- No changes of its own; released with the family version 0.7.4.

## 0.7.3

- No changes of its own; released with the family version 0.7.3.

## 0.7.2

- README: the link goes to the package's own page on farum-azula.org, and what the README says was checked against the code and brought up to date.
- Docs: without the starter `SpringLog` shows INFO and above; the predefined `web` and `sql` groups are documented.
- The package's page on pub.dev links its documentation, [farum-azula.org](https://farum-azula.org) (`documentation` in `pubspec.yaml`).

## 0.7.1

- No changes of its own; released with the family version 0.7.1.

## 0.7.0

- No changes of its own: its generated code (`lib/spring_gen/`) is regenerated with spring_core_dart_generator 0.7.0.

## 0.6.3

- `LoggingSystem.configure` binds the `logging.*`, `spring.output.ansi.*` and `spring.application.group` settings through the `@ConfigurationProperties` classes (`lib/src/properties/logging_properties.dart`) instead of reading each key by name, so the editor metadata and the reading cannot drift apart. It takes a `ConfigurableEnvironment` (was `PropertyResolver`), as does `LoggingSystemInitializer`. A value that cannot be read (a level, a number, a size, an on/off value, `logging.console.target`, `spring.output.ansi.enabled`) now fails with a `ConfigurationPropertiesBindException` listing the property, not a `FormatException`; an invalid pattern or charset is still a `FormatException`. Keys, defaults and accepted values are unchanged: log patterns keep their `${...}` as written (`@RawValue`), `logging.console.target` still accepts `System.out` / `System.err`.
- A Flutter app on iOS logs without colours by default: its system log
  escaped the codes (`flutter: \^[[32m INFO`). The layout of the line is the
  same on every platform; `spring.output.ansi.enabled=always` still forces
  colours.

## 0.6.2

- No changes of its own; released with the family version 0.6.2.

## 0.6.1

- No changes of its own; released with the family version 0.6.1.

## 0.6.0

### Breaking

- Properties renamed: `logging.logback.rollingpolicy.*` is `logging.file.rolling-policy.*` (there is no Logback). An old name stops the start, naming the new one. The names from before Spring Boot 2.4 (`logging.file.max-size`, ...) are still ignored with a warning, which now names the new keys.

### Changes

- `logging.console.target` (`stdout` or `stderr`) chooses the console's stream on the Dart VM, as Logback's `ConsoleAppender` target; it is not a Spring Boot property.
- The console writes to standard output on the VM (it was `print`), and uses `print` in Flutter and on the web.

## 0.5.0

### Changes

- A log file that cannot be written breaks nothing else, as in Logback: one that cannot be opened at the start (a read-only directory) is reported on the console and the application starts without it (it failed the start).
- When writing fails later (a full disk), the error is reported once, the lines are dropped, and writing is tried again after a pause that grows from 20 ms to about 5 minutes; once a line is written again, one line says how many were lost (`FileAppender.isFailing` tells meanwhile).
- A roll-over that fails is reported once and tried again a minute later, the lines going on into the current file; an old archive that cannot be deleted is kept, with a warning.
- Errors of the file no longer escape as uncaught errors from `flush`, a roll-over or `close()`, and the previous log handler is always given back when logging shuts down.

## 0.4.3

- Flutter security (#15)
- feat: single sign-on with OAuth 2.0 / OpenID Connect (spring_boot_sta… (#11)
- docs: the READMEs and docs/ rewritten: what it is, why and when you need it, an example, then Spring (#10)

## 0.4.2

- Docs (#9)

## 0.4.1

- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs
- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs

## 0.4.0

- feat: spring_security_core, spring_boot_starter_security and a CI quality gate

## 0.3.2

- feat: hot reload on the Dart VM, flutter_notes example, fixes for example resources and workspace builds

## 0.3.1

- The example is a Spring Boot application; the logger comes from `@Log` (the README shows `@Log` first and the hand-made `SpringLog('name')` as the alternative for code outside a scan).
- `spring_auto_configuration.dart` re-exports `spring_boot_dart`'s auto-configuration, so a test naming `springBootAutoConfiguration` (`ApplicationContextRunner`) needs no other dependency.

## 0.3.0

- feat(spring_boot_starter_flutter): themes from properties, free reads in Spring widgets

## 0.2.3

- add spring application handling
- docs(spring_boot_starter_flutter): add an example for pub.dev

## 0.2.2

- ci: run only the tests of the packages a change affects

## 0.2.1

- feat: spring_boot_starter_flutter, @Log, --dart-define properties, Flutter counter example

## 0.2.0

- `logging.logback.rollingpolicy.max-history=0` (`FileAppender(maxHistory: 0)`) keeps every archive, like Logback (it deleted them all).
- `logging.charset.*` takes Java's charset aliases too (`utf8`, `ISO8859_1`, `ascii7`, ...).
- Logback's colour words `%black` ... `%white`, `%gray`, `%boldRed` ..., `%highlight`; `%replace(...){regex, replacement}`, `%kvp`, `%prefix(...)`, `%property{key}`.
- `logging.charset.file` (UTF-8, ISO-8859-1, US-ASCII; `FileAppender(encoding:)`); `logging.charset.console` is checked.
- `logging.logback.rollingpolicy.file-name-pattern` is ignored with a warning (rolling is by size only).
- On/off properties (`logging.console.enabled`, `logging.buffer.enabled`, `logging.include-application-name` / `-group`, `logging.logback.rollingpolicy.clean-history-on-start`, `logging.enabled`) take true / false in any case (and on / off, yes / no, 1 / 0); anything else fails the start (`FALSE` and `nope` were on).
- An empty `logging.pattern.console=` turns the console off (it printed empty lines); an empty `logging.pattern.file=` writes no file.
- A threshold of `false` (YAML's `off`) is OFF.
- Lines logged while the application starts, before the logging system is set up, are replayed into the file, the buffer and added appenders.
- A failed start: the logging system stays installed until the failure is logged, so the report (or `Application run failed` with the error) reaches the log file.
- `%r` / `%relative` is never negative: records older than the first pattern (buffered before the logging system started) move the origin back.

## 0.1.7

- Breaking: Spring Boot's default console and file lines (`LogPattern.defaultConsolePattern` / `defaultFilePattern`, replacing `LogPattern.defaultPattern`): ISO-8601 time with offset, PID, `--- [app]`, `[isolate]`, `%-40.40logger{39} :`; `logging.pattern.dateformat`, `logging.pattern.level`, `logging.pattern.correlation`, `logging.exception-conversion-word`, `logging.include-application-name` / `-group`, `spring.output.ansi.enabled`
- Breaking: `LogPattern` follows Logback: format modifiers (`%-40.40`, `%.-10`), `%logger{n}` abbreviation, `%t` / `%thread`, Java date patterns (`'T'`, `XXX`; `%d` alone is `yyyy-MM-dd HH:mm:ss,SSS`), `%ex` without a leading line break (write `%n%ex`), errors printed also without `%ex` (`%nopex` turns that off), Boot's `%clr(...)`, `%esb`, `%wEx`, `${PID}` / `${NAME:-default}`; anything it cannot parse fails the start; appenders use `LogPattern.formatLine`
- Breaking: `logging.logback.rollingpolicy.max-file-size`, `.max-history`, `.clean-history-on-start` and the new `.total-size-cap` replace `logging.file.max-size`, `logging.file.max-history`, `logging.file.clean-history-on-start` (now ignored with a warning); `FileAppender(maxSize:)` is `maxFileSize:`, new `totalSizeCap:`
- Breaking: `LoggingSystem.setLevel` is `setLogLevel` (Boot's name); `ROOT` in any case (or `null`) is the root logger, also in `logging.level.ROOT`

## 0.1.6

- update road map
- ci: release with a button on main, skip new packages when publishing; shorter pubspec descriptions

## 0.1.5

- add feign runner + web socket runner
- add web core + faign starter for http calling

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
