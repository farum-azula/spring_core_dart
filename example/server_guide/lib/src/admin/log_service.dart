// The last log lines for admins (chapter 11): the logging starter keeps
// them in memory, in the LogBuffer bean.
import 'package:spring_security_core/spring_security_core.dart';

/// A log line as JSON: `{"time": "...", "level": "INFO", "logger":
/// "neon.mail", "message": "...", "fields": {"order": "1"}}`.
class LogLine {
  const LogLine({
    required this.time,
    required this.level,
    required this.logger,
    required this.message,
    this.fields = const {},
  });

  final DateTime time;
  final String level;
  final String logger;
  final String message;
  final Map<String, String> fields;
}

@Service()
class LogService {
  LogService(this._buffer);

  final LogBuffer _buffer;

  /// `@Secured`: the plain role check, Spring's oldest annotation.
  @Secured(['ROLE_ADMIN'])
  List<LogLine> recent({
    SpringLogLevel? minLevel,
    String? logger,
    String? text,
    int limit = 100,
  }) {
    final records = _buffer.query(
      LogQuery(minLevel: minLevel, logger: logger, text: text),
    );
    return [
      for (final record in records.skip(
        records.length > limit ? records.length - limit : 0,
      ))
        LogLine(
          time: record.time.toUtc(),
          level: LogPattern.levelName(record.level),
          logger: record.loggerName,
          message: record.message,
          fields: {
            for (final MapEntry(:key, :value) in record.fields.entries)
              key: '$value',
          },
        ),
    ];
  }
}
