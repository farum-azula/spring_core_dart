import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test_api/scaffolding.dart';

/// Records logged through `SpringLog` during each test, like Spring Boot's
/// `OutputCaptureExtension` (for logs).
///
/// Call it in `main` (or a `group`): every test starts with an empty
/// capture.
///
/// ```dart
/// void main() {
///   final logs = captureLogs(level: SpringLogLevel.debug);
///
///   test('warns about a slow payment', () {
///     checkout.pay(slowOrder);
///     expect(logs.messages, contains('payment took 3 s'));
///     expect(logs.atLevel(SpringLogLevel.warning), hasLength(1));
///   });
/// }
/// ```
CapturedLogs captureLogs({SpringLogLevel? level}) {
  final logs = CapturedLogs._();
  void Function()? cancel;
  SpringLogLevel? savedLevel;
  setUp(() {
    logs.clear();
    if (level != null) {
      savedLevel = SpringLog.level;
      SpringLog.level = level;
    }
    cancel = SpringLog.listen(logs._records.add);
  });
  tearDown(() {
    cancel?.call();
    cancel = null;
    if (savedLevel case final saved?) {
      SpringLog.level = saved;
      savedLevel = null;
    }
  });
  return logs;
}

/// The records captured by [captureLogs] in the current test.
final class CapturedLogs {
  CapturedLogs._();

  final _records = <SpringLogRecord>[];

  /// Captured records, oldest first.
  List<SpringLogRecord> get records => List.unmodifiable(_records);

  /// Messages of [records].
  List<String> get messages => [for (final record in _records) record.message];

  /// Every record as `LEVEL [logger] message`, one per line.
  String get text => [for (final record in _records) _line(record)].join('\n');

  static String _line(SpringLogRecord record) =>
      '${record.level.name.toUpperCase()} [${record.loggerName}] '
      '${record.message}';

  /// Records of exactly [level].
  List<SpringLogRecord> atLevel(SpringLogLevel level) => [
    for (final record in _records)
      if (record.level == level) record,
  ];

  /// Records of the logger [name] or its descendants.
  List<SpringLogRecord> ofLogger(String name) => [
    for (final record in _records)
      if (record.loggerName == name || record.loggerName.startsWith('$name.'))
        record,
  ];

  /// Forgets the captured records.
  void clear() => _records.clear();

  @override
  String toString() => text;
}
