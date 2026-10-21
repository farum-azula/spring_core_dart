import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
import 'package:test/test.dart';

SpringLogRecord record(
  SpringLogLevel level,
  String logger,
  String message, {
  Map<String, Object?> fields = const {},
  Object? error,
  DateTime? time,
}) => SpringLogRecord(
  level,
  logger,
  message,
  fields: fields,
  error: error,
  time: time,
);

void main() {
  test('keeps the last records; counts and logger names', () {
    final buffer = LogBuffer(capacity: 3);
    for (var i = 0; i < 5; i++) {
      buffer.append(record(SpringLogLevel.info, 'b.$i', 'm$i'));
    }
    expect(buffer.records.map((r) => r.message), ['m2', 'm3', 'm4']);
    expect(buffer.dropped, 2);
    expect(buffer.length, 3);
    expect(buffer.loggerNames, ['b.2', 'b.3', 'b.4']);
    expect(buffer.counts[SpringLogLevel.info], 3);
    expect(buffer.counts[SpringLogLevel.error], 0);
    expect(buffer.counts.containsKey(SpringLogLevel.off), isFalse);

    buffer.capacity = 1;
    expect(buffer.records.single.message, 'm4');
    expect(() => buffer.capacity = 0, throwsArgumentError);
    expect(
      () => buffer.records.add(buffer.records.first),
      throwsUnsupportedError,
    );

    buffer.clear();
    expect(buffer.isEmpty, isTrue);
    expect(buffer.dropped, 0);
  });

  test('threshold drops lower records', () {
    final buffer = LogBuffer(threshold: SpringLogLevel.warning)
      ..append(record(SpringLogLevel.info, 'a', 'no'))
      ..append(record(SpringLogLevel.error, 'a', 'yes'));
    expect(buffer.records.map((r) => r.message), ['yes']);
  });

  group('LogQuery', () {
    final t0 = DateTime(2026);
    final buffer = LogBuffer()
      ..append(record(SpringLogLevel.debug, 'neon.shop', 'basket ok', time: t0))
      ..append(
        record(
          SpringLogLevel.warning,
          'neon.shop.pay',
          'slow',
          fields: {'order': 42},
          time: t0.add(const Duration(minutes: 1)),
        ),
      )
      ..append(
        record(
          SpringLogLevel.error,
          'neonx',
          'failed',
          error: StateError('Card declined'),
          time: t0.add(const Duration(minutes: 2)),
        ),
      );

    List<String> messages(LogQuery query) =>
        buffer.query(query).map((r) => r.message).toList();

    test('criteria', () {
      expect(messages(const LogQuery()), ['basket ok', 'slow', 'failed']);
      expect(messages(const LogQuery(minLevel: SpringLogLevel.warning)), [
        'slow',
        'failed',
      ]);
      expect(
        messages(
          const LogQuery(levels: {SpringLogLevel.debug, SpringLogLevel.error}),
        ),
        ['basket ok', 'failed'],
      );
      expect(messages(const LogQuery(logger: 'neon')), ['basket ok', 'slow']);
      expect(messages(const LogQuery(logger: 'neon.shop.pay')), ['slow']);
      expect(messages(const LogQuery(text: 'DECLINED')), ['failed']); // error
      expect(messages(const LogQuery(text: 'shop.pay')), ['slow']); // logger
      expect(messages(const LogQuery(text: '42')), ['slow']); // field value
      expect(messages(const LogQuery(fields: {'order': '42'})), ['slow']);
      expect(messages(LogQuery(since: t0.add(const Duration(seconds: 30)))), [
        'slow',
        'failed',
      ]);
      expect(messages(const LogQuery(text: '  ')), hasLength(3));
    });

    test('copyWith replaces and removes criteria; value equality', () {
      const query = LogQuery(minLevel: SpringLogLevel.info, text: 'x');
      final changed = query.copyWith(text: 'slow', logger: 'neon');
      expect(changed.minLevel, SpringLogLevel.info);
      expect(changed.text, 'slow');
      expect(changed.logger, 'neon');
      expect(changed.copyWith(minLevel: null).minLevel, isNull);
      expect(
        changed,
        LogQuery(minLevel: SpringLogLevel.info, text: 'slow', logger: 'neon'),
      );
      expect(changed.hashCode, changed.copyWith().hashCode);
      expect(changed, isNot(query));
    });

    test('export', () {
      expect(
        buffer.export(
          const LogQuery(minLevel: SpringLogLevel.warning),
          LogPattern('%-5p %logger: %m%X'),
        ),
        'WARN  neon.shop.pay: slow {order=42}\nERROR neonx: failed',
      );
    });
  });

  test('watch emits the current list, then once per burst', () async {
    final buffer = LogBuffer()..append(record(SpringLogLevel.info, 'a', 'old'));
    final lists = <List<String>>[];
    final subscription = buffer
        .watch(const LogQuery(minLevel: SpringLogLevel.info))
        .listen((records) => lists.add([for (final r in records) r.message]));
    await pumpEventQueue();
    expect(lists, [
      ['old'],
    ]);

    buffer
      ..append(record(SpringLogLevel.info, 'a', 'one'))
      ..append(record(SpringLogLevel.debug, 'a', 'hidden'))
      ..append(record(SpringLogLevel.error, 'a', 'two'));
    await pumpEventQueue();
    expect(lists.last, ['old', 'one', 'two']);
    expect(lists, hasLength(2)); // one event for the burst

    buffer.clear();
    await pumpEventQueue();
    expect(lists.last, isEmpty);
    await subscription.cancel();
  });

  test('onRecord streams each record synchronously', () {
    final buffer = LogBuffer();
    final seen = <String>[];
    buffer.onRecord.listen((r) => seen.add(r.message));
    buffer.append(record(SpringLogLevel.info, 'a', 'now'));
    expect(seen, ['now']);
  });
}
