import 'package:spring_boot_dart/spring_boot_dart.dart';

// The `logging.*` settings. `LoggingSystem.configure` binds these classes
// from the environment (the system is set up before any application bean
// exists), and the editor metadata (`spring_gen/spring_metadata.json`) is
// generated from the same classes, so the description and the reading
// cannot drift apart.

// The levels a property takes: the names of `SpringLogLevel`, and the
// aliases `warn` and `fatal`, which an enum field could not accept.
const _levels = [
  'trace',
  'debug',
  'info',
  'warn',
  'warning',
  'error',
  'fatal',
  'off',
];

/// Where the console writes on the Dart VM.
enum ConsoleTarget {
  /// Standard output.
  stdout,

  /// Standard error.
  stderr,

  /// Logback's name for standard output (`System.out`), the same as
  /// `stdout`.
  systemOut,

  /// Logback's name for standard error (`System.err`), the same as
  /// `stderr`.
  systemErr,
}

/// Whether the console output uses ANSI colours.
enum AnsiOutput {
  /// Colours when the console supports them.
  detect,

  /// Always colours. The default, except where the console shows the
  /// codes as text (a Flutter app on iOS).
  always,

  /// Never colours.
  never,
}

/// The `logging.*` settings.
@ConfigurationProperties('logging')
class LoggingProperties {
  /// Whether the starter installs the logging system; false leaves
  /// `SpringLog` with its plain output.
  bool enabled = true;

  /// The level of the logger named by the key, for example
  /// `logging.level.neon.checkout=debug`. `root` is the level of every
  /// logger without a level of its own or of an ancestor (`info` when not
  /// set). Also `warn` and `fatal`; `false` (YAML's `off`) is `off`.
  @PropertyValues(_levels)
  Map<String, String> level = {};

  /// A name for several loggers, usable in `logging.level.<group>`.
  Map<String, List<String>> group = {};

  /// How exceptions are printed.
  @RawValue()
  String exceptionConversionWord = '%wEx';

  /// Puts `[spring.application.group]` into the default patterns.
  bool includeApplicationGroup = true;

  /// Puts `[spring.application.name]` into the default patterns.
  bool includeApplicationName = true;

  /// The line formats.
  LoggingPatternProperties pattern = LoggingPatternProperties();

  /// The lowest level each output keeps.
  LoggingThresholdProperties threshold = LoggingThresholdProperties();

  /// The console output.
  LoggingConsoleProperties console = LoggingConsoleProperties();

  /// The in-memory buffer (the `logBuffer` bean).
  LoggingBufferProperties buffer = LoggingBufferProperties();

  /// The log file.
  LoggingFileProperties file = LoggingFileProperties();

  /// The character sets of the outputs.
  LoggingCharsetProperties charset = LoggingCharsetProperties();
}

/// `logging.pattern.*`.
class LoggingPatternProperties {
  /// The line format of the console. `${...}` stays as written: the
  /// pattern resolves it itself.
  @RawValue()
  String? console;

  /// The line format of the log file; empty switches the file off.
  @RawValue()
  String? file;

  /// The format of the level in a line.
  @RawValue()
  String level = '%5p';

  /// The correlation column. Default: empty.
  @RawValue()
  String? correlation;

  /// The format of `%d` in the default patterns (times are UTC).
  @RawValue()
  String dateformat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXX";
}

/// `logging.threshold.*`.
class LoggingThresholdProperties {
  /// The lowest level the console shows.
  @PropertyValues(_levels)
  String console = 'trace';

  /// The lowest level the in-memory buffer keeps.
  @PropertyValues(_levels)
  String buffer = 'trace';

  /// The lowest level the log file keeps.
  @PropertyValues(_levels)
  String file = 'trace';
}

/// `logging.console.*`.
class LoggingConsoleProperties {
  /// The console output.
  bool enabled = true;

  /// Where the console writes on the Dart VM. Default: `stdout`; not
  /// setting it leaves the output an application set itself (Flutter's
  /// `debugPrint`).
  ConsoleTarget? target;
}

/// `logging.buffer.*`.
class LoggingBufferProperties {
  /// Whether the in-memory buffer (the `logBuffer` bean) receives records.
  bool enabled = true;

  /// How many records the in-memory buffer keeps.
  @Range(1, 1000000)
  int capacity = 1000;
}

/// `logging.file.*`.
class LoggingFileProperties {
  /// The log file; a relative path is resolved against
  /// `LoggingSystem.fileDirectory`.
  String? name;

  /// A directory; the file is `spring.log` in it.
  String? path;

  /// When and how the file rolls over.
  LoggingRollingPolicyProperties rollingPolicy =
      LoggingRollingPolicyProperties();
}

/// `logging.file.rolling-policy.*`.
class LoggingRollingPolicyProperties {
  /// Deletes the rolled files when the application starts.
  bool cleanHistoryOnStart = false;

  /// The size at which the file rolls over to `.1`, `.2`, ….
  DataSize maxFileSize = DataSize.ofMegabytes(10);

  /// How many rolled files are kept.
  int maxHistory = 7;

  /// The largest total size of the rolled files. Default: 0B (no limit).
  DataSize? totalSizeCap;
}

/// `logging.charset.*`.
class LoggingCharsetProperties {
  /// The character set of the console.
  String? console;

  /// The character set of the log file.
  String? file;
}

/// The application's group, which the default patterns show:
/// `spring.application.group`.
@ConfigurationProperties('spring.application')
class ApplicationGroupProperties {
  /// The application's group, shown in the default log patterns when
  /// `logging.include-application-group` is true.
  String? group;
}

/// The console colours: `spring.output.ansi.*`.
@ConfigurationProperties('spring.output.ansi')
class AnsiProperties {
  /// Colours on the console: `%clr`, or the time, level and logger of a
  /// pattern without colours. Default: `always`, except where the console
  /// shows the codes as text (a Flutter app on iOS): `never` there.
  AnsiOutput? enabled;
}
