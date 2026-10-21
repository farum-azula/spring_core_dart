import 'package:spring_core_dart/core.dart';
import 'package:test/test.dart';

void main() {
  late SpringLogLevel savedLevel;
  late SpringLogHandler savedHandler;
  final records = <SpringLogRecord>[];

  setUp(() {
    savedLevel = SpringLog.level;
    savedHandler = SpringLog.handler;
    records.clear();
    SpringLog.handler = records.add;
  });

  tearDown(() {
    SpringLog.level = savedLevel;
    SpringLog.handler = savedHandler;
  });

  test('warning is the default threshold', () {
    const log = SpringLog('test.log');
    log
      ..debug('hidden')
      ..info('hidden')
      ..warning('shown', error: StateError('boom'))
      ..error('also shown');
    expect(records.map((r) => r.message), ['shown', 'also shown']);
    expect(records.first.loggerName, 'test.log');
    expect(
      records.first.toString(),
      contains('WARNING: shown: Bad state: boom'),
    );
  });

  test('level can be lowered or switched off', () {
    const log = SpringLog('test.log');
    SpringLog.level = SpringLogLevel.trace;
    log
      ..trace('t')
      ..debug('d');
    expect(records.map((r) => r.level), [
      SpringLogLevel.trace,
      SpringLogLevel.debug,
    ]);
    expect(log.isEnabled(SpringLogLevel.trace), isTrue);

    SpringLog.level = SpringLogLevel.off;
    log.error('nothing');
    expect(records, hasLength(2));
    expect(log.isEnabled(SpringLogLevel.off), isFalse);
  });
}
