// spring_boot_starter_logging: the in-memory LogBuffer behind a log viewer,
// shown in the console. A Flutter screen would use `buffer.watch(query)` in
// a StreamBuilder; this prints the same data once the application started.

// This screen exists to show the log viewer in the console.
// ignore_for_file: avoid_print
import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';

@Component()
@Order()
class ConsoleLogScreen implements ApplicationRunner {
  ConsoleLogScreen(this.buffer);

  /// The starter's buffer, injected like any bean. Nullable = optional: the
  /// tour (bin/main.dart) starts without the logging auto-configuration.
  final LogBuffer? buffer;

  @override
  void run(ApplicationArguments args) {
    final buffer = this.buffer;
    if (buffer == null) {
      return;
    }
    const query = LogQuery(logger: 'neon'); // this app's loggers only
    final records = buffer.query(query);
    final counts = buffer.counts.entries
        .where((entry) => entry.value > 0)
        .map((entry) => '${LogPattern.levelName(entry.key)} ${entry.value}')
        .join(', ');
    print(
      '┌ console log screen: ${records.length} of ${buffer.length} records '
      '($counts) · loggers: ${buffer.loggerNames.join(', ')}',
    );
    print(buffer.export(query, LogPattern('│ %-5p [%logger] %m%X')));
    print('└');
  }
}
