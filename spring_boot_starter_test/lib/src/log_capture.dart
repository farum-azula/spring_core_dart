import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test_api/scaffolding.dart';

/// Records what is logged through `SpringLog` during each test of the
/// enclosing `main` or `group`, so a test can check its logs.
///
/// Use it to check that code warns about a slow payment, or that an error
/// is logged instead of thrown. Call it once in `main` (or a `group`),
/// outside the tests: it registers a `setUp` that empties the capture and
/// starts listening, and a `tearDown` that stops. Records are captured
/// after the logger's own level filtered them; [level] lowers (or raises)
/// the global `SpringLog.level` during each test, and the previous level
/// comes back afterwards. In a test class, a `@CapturedOutput()` field does
/// the same.
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
///
/// Spring (Java): Spring Boot's `OutputCaptureExtension`, which captures
/// everything printed; this captures `SpringLog` records only.
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

/// The log records of the current test, collected by [captureLogs], with
/// helpers to filter them by level or logger.
///
/// It is emptied before every test.
///
/// ```dart
/// // Only the checkout's own warnings, not the gateway's.
/// expect(logs.ofLogger('shop.checkout'), hasLength(1));
/// ```
final class CapturedLogs {
  CapturedLogs._();

  final _records = <SpringLogRecord>[];

  /// The captured records, oldest first, with level, logger and message.
  List<SpringLogRecord> get records => List.unmodifiable(_records);

  /// The messages of [records], oldest first: the simplest thing to match
  /// with `contains`.
  List<String> get messages => [for (final record in _records) record.message];

  /// Every record as `LEVEL [logger] message`, one per line; also what
  /// [toString] returns, so a failed expectation shows the whole log.
  String get text => [for (final record in _records) _line(record)].join('\n');

  static String _line(SpringLogRecord record) =>
      '${record.level.name.toUpperCase()} [${record.loggerName}] '
      '${record.message}';

  /// The records of exactly [level]: `atLevel(SpringLogLevel.warning)` does
  /// not include errors.
  List<SpringLogRecord> atLevel(SpringLogLevel level) => [
    for (final record in _records)
      if (record.level == level) record,
  ];

  /// The records of the logger [name] and of the loggers below it:
  /// `ofLogger('shop')` includes `shop.checkout`, not `shopping`.
  List<SpringLogRecord> ofLogger(String name) => [
    for (final record in _records)
      if (record.loggerName == name || record.loggerName.startsWith('$name.'))
        record,
  ];

  /// Forgets the records captured so far in this test, for example to
  /// check only what a second call logs.
  void clear() => _records.clear();

  @override
  String toString() => text;
}
