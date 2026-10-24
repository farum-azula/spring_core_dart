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
    SpringLog.resetLevels();
  });

  test('hold() keeps every record until release() emits those that pass '
      "the levels of that time (Boot's DeferredLog)", () {
    const log = SpringLog('test.log.held');
    const other = SpringLog('test.other');
    final listened = <String>[];
    final stop = SpringLog.listen((r) => listened.add(r.message));
    addTearDown(stop);
    final outer = SpringLog.hold();
    final inner = SpringLog.hold();
    expect(log.isEnabled(SpringLogLevel.trace), isTrue);
    log
      ..trace('trace')
      ..debug('debug');
    other.info('info elsewhere');
    expect(records, isEmpty);
    expect(listened, isEmpty);
    // An inner hold passes its records to the outer one.
    expect(inner.release(), hasLength(3));
    expect(records, isEmpty);
    log.warning('warning');
    SpringLog.setLevel('test.log', SpringLogLevel.debug);
    expect(outer.isHolding, isTrue);
    final released = outer.release();
    expect(outer.isHolding, isFalse);
    expect(released.map((r) => r.message), ['debug', 'warning']);
    expect(records.map((r) => r.message), ['debug', 'warning']);
    expect(listened, ['debug', 'warning']);
    expect(outer.release(), isEmpty);
    expect(log.isEnabled(SpringLogLevel.trace), isFalse);
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

  test('levels are hierarchical by dots', () {
    SpringLog.level = SpringLogLevel.error;
    SpringLog.setLevel('neon', SpringLogLevel.info);
    SpringLog.setLevel('neon.checkout', SpringLogLevel.debug);
    expect(SpringLog.levelOf('neon.checkout.payment'), SpringLogLevel.debug);
    expect(SpringLog.levelOf('neon.catalog'), SpringLogLevel.info);
    expect(SpringLog.levelOf('neonx'), SpringLogLevel.error);
    expect(SpringLog.levelOf('other'), SpringLogLevel.error);

    const SpringLog('neon.checkout.payment').debug('d');
    const SpringLog('neon.catalog').debug('hidden');
    const SpringLog('other').warning('hidden');
    expect(records.map((r) => r.message), ['d']);

    SpringLog.setLevel('neon.checkout', null); // inherit again
    expect(SpringLog.levelOf('neon.checkout.payment'), SpringLogLevel.info);
    expect(SpringLog.configuredLevels, {'neon': SpringLogLevel.info});
    SpringLog.resetLevels();
    expect(SpringLog.levelOf('neon'), SpringLogLevel.error);
  });

  test('closures are only called when enabled', () {
    var calls = 0;
    String expensive() {
      calls++;
      return 'built';
    }

    const log = SpringLog('lazy');
    log.debug(expensive);
    expect(calls, 0);
    SpringLog.level = SpringLogLevel.debug;
    log.debug(expensive);
    expect(calls, 1);
    expect(records.single.message, 'built');
  });

  test('records carry time, sequence and fields', () async {
    const log = SpringLog('fields');
    final before = DateTime.now();
    log.warning('first', fields: {'order': 1});
    await SpringLog.withFields({'request': 'r1', 'order': 0}, () async {
      await Future<void>.delayed(Duration.zero);
      log.warning('second', fields: {'order': 2});
      SpringLog.withFields({'user': 'ada'}, () => log.warning('third'));
    });
    log.warning('fourth');

    expect(records.map((r) => r.fields).toList(), [
      {'order': 1},
      {'request': 'r1', 'order': 2}, // call fields win
      {'request': 'r1', 'order': 0, 'user': 'ada'},
      isEmpty,
    ]);
    expect(records.first.time.isBefore(before), isFalse);
    final sequences = records.map((r) => r.sequence).toList();
    expect(sequences, orderedEquals([...sequences]..sort()));
    expect(sequences.toSet(), hasLength(4));
    expect(() => records.first.fields['x'] = 1, throwsUnsupportedError);
  });

  test('listeners see every emitted record and can stop', () {
    final seen = <String>[];
    final cancel = SpringLog.listen((r) => seen.add(r.message));
    SpringLog.listen((_) => throw StateError('ignored'))();
    final failing = SpringLog.listen((_) => throw StateError('ignored'));
    const SpringLog('l')
      ..warning('a')
      ..info('below level');
    cancel();
    failing();
    const SpringLog('l').warning('b');
    expect(seen, ['a']);
    expect(records.map((r) => r.message), ['a', 'b']);
  });

  test('parseSpringLogLevel reads property values', () {
    expect(parseSpringLogLevel(' WARN '), SpringLogLevel.warning);
    expect(parseSpringLogLevel('debug'), SpringLogLevel.debug);
    expect(parseSpringLogLevel('Off'), SpringLogLevel.off);
    expect(parseSpringLogLevel('loud'), isNull);
    expect(parseSpringLogLevel(null), isNull);
  });
}
