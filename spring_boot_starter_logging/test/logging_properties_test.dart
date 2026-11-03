import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
import 'package:spring_boot_starter_logging/src/properties/logging_properties.dart';
import 'package:test/test.dart';

// `LoggingSystem.configure` binds the classes of logging_properties.dart.
// Components the system builds with defaults of their own (the pattern, the
// buffer, the file appender) must agree with the class defaults, since the
// metadata shows the class.
void main() {
  StandardEnvironment env(Map<String, Object?> properties) =>
      StandardEnvironment(systemEnvironment: const {})
        ..propertySources.addFirst(MapPropertySource('test', properties));

  test('the pattern defaults are the ones the default patterns carry', () {
    final pattern = LoggingPatternProperties();
    final defaults = RegExp(r'\$\{(LOG_\w+):-(.*?)\}');
    final inPatterns = {
      for (final match in defaults.allMatches(
        LogPattern.defaultConsolePattern + LogPattern.defaultFilePattern,
      ))
        match[1]!: match[2]!,
    };
    expect(inPatterns['LOG_LEVEL_PATTERN'], pattern.level);
    expect(inPatterns['LOG_DATEFORMAT_PATTERN'], pattern.dateformat);
    expect(
      inPatterns['LOG_EXCEPTION_CONVERSION_WORD'],
      LoggingProperties().exceptionConversionWord,
    );
    expect(pattern.correlation, isNull);
  });

  test('the buffer and the file defaults are the classes defaults', () {
    expect(LogBuffer().capacity, LoggingBufferProperties().capacity);
    final rolling = LoggingRollingPolicyProperties();
    final appender = FileAppender('/tmp/spring_logging_defaults.log');
    addTearDown(appender.close);
    expect(appender.maxFileSize, rolling.maxFileSize.toBytes());
    expect(appender.maxHistory, rolling.maxHistory);
    expect(appender.totalSizeCap, rolling.totalSizeCap?.toBytes() ?? 0);
  });

  test('a level accepts warn and fatal, and false is off', () {
    final system = LoggingSystem.instance;
    addTearDown(system.uninstall);
    system.configure(env({'logging.threshold.console': 'warn'}));
    expect(system.console.threshold, SpringLogLevel.warning);
    system.configure(env({'logging.threshold.console': 'fatal'}));
    expect(system.console.threshold, SpringLogLevel.error);
    system.configure(env({'logging.threshold.console': 'false'}));
    expect(system.console.threshold, SpringLogLevel.off);
    expect(
      () => system.configure(env({'logging.threshold.console': 'loud'})),
      throwsFormatException,
    );
  });

  test('values that cannot be read fail the binding', () {
    final system = LoggingSystem.instance;
    expect(
      () => system.configure(env({'logging.console.enabled': 'maybe'})),
      throwsA(isA<ConfigurationPropertiesBindException>()),
    );
    expect(
      () => system.configure(env({'spring.output.ansi.enabled': 'rainbow'})),
      throwsA(isA<ConfigurationPropertiesBindException>()),
    );
    expect(
      () => system.configure(env({'logging.buffer.capacity': 'many'})),
      throwsA(isA<ConfigurationPropertiesBindException>()),
    );
  });

  test('the console target takes the Logback names', () {
    final system = LoggingSystem.instance;
    addTearDown(() => system.configure(env({})));
    system
      ..configure(env({'logging.console.target': 'System.err'}))
      ..configure(env({'logging.console.target': 'stdout'}));
  });

  test('a pattern keeps its placeholders as written', () {
    final system = LoggingSystem.instance;
    final lines = <String>[];
    addTearDown(system.uninstall);
    system
      ..configure(
        env({
          'logging.pattern.console': r'${NOPE:-fallback} %m',
          'spring.output.ansi.enabled': 'never',
        }),
      )
      ..console.out = lines.add
      ..console.append(SpringLogRecord(SpringLogLevel.info, 'neon', 'hi'));
    expect(lines.single, startsWith('fallback hi'));
  });
}
