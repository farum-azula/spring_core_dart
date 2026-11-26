import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';

// Allocates until an object made now is collected: what nobody held
// before is gone too.
Future<void> _collectGarbage() async {
  final probe = WeakReference(Object());
  for (var round = 0; probe.target != null && round < 2000; round++) {
    List<Object>.generate(10000, (_) => Object());
    await Future<void>.delayed(Duration.zero);
  }
  expect(probe.target, isNull, reason: 'no collection happened');
}

void main() {
  test('a computed value first read once the bean is closed is made closed: '
      'the bean code answers, nothing is computed or followed', () {
    final bean = SignalBean('Basket')..close();
    var runs = 0;
    final total = bean.computed('total', () => ++runs * 10);

    expect(total.read(), 10);
    expect(total.read(), 20);
    expect(total.computations, 0);
    expect(bean.members['total'], same(total));
  });

  test('an asynchronous value first read once the bean is closed starts no '
      'load and cannot load again', () async {
    final bean = SignalBean('Catalog')..close();
    final books = bean.asynchronous('books', () => Future.value(3));

    expect(await (books.read()! as Future<Object?>), 3);
    expect(books.loads, 0);
    await expectLater(books.refresh(), throwsStateError);
  });

  test('a field first used once the bean is closed reads and writes a plain '
      'value', () {
    final bean = SignalBean('Basket')..close();
    final coupon = bean.field('coupon', () => 'none');

    expect(coupon.read(), 'none');
    coupon.write('SALE');
    expect(coupon.read(), 'SALE');
  });

  test('a probed bean closes its late members the same way', () {
    final bean = ProbedSignalBean('Basket')..close();
    final total = bean.computed('total', () => 5);

    expect(total.read(), 5);
    expect(total.computations, 0);
  });

  group('a write deferred past the end of the scope (on-scope-end: defer)', () {
    late List<String> warnings;

    setUp(() {
      warnings = [];
      final stop = SpringLog.listen((record) {
        if (record.level == SpringLogLevel.warning) {
          warnings.add(record.message);
        }
      });
      addTearDown(stop);
    });

    // A bean whose scope ends while a buffer holds a write of its field;
    // the buffer then ends and hands the write to [flush].
    Future<void> endScopeInBuffer(SignalFlushSchedule flush, Object written) {
      final bean = SignalBean('Draft')
        ..runtime = SignalRuntime(
          queues: SignalQueues(SignalQueueSettings(schedule: flush)),
          onScopeEnd: OnScopeEnd.defer,
          deferTimeout: const Duration(milliseconds: 20),
        );
      final text = bean.field('text', () => 'kept');
      return SignalBuffer.run(() async {
        text.write(written);
        bean.close();
        await Future<void>.delayed(Duration.zero);
      });
    }

    test('told at once by an immediate queue: freed then, never '
        'discarded', () async {
      await endScopeInBuffer(SignalFlushSchedules.immediate(), 'new');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(warnings, isEmpty);
    });

    test('the same value again: nothing to tell, freed then, never '
        'discarded', () async {
      await endScopeInBuffer(SignalFlushSchedules.microtask(), 'kept');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(warnings, isEmpty);
    });
  });

  test('the states of prototypes nobody holds are let go as more are made, '
      'with no debug tool reading them', () async {
    final beans = SignalBeans();
    addTearDown(beans.dispose);
    final runtime = SignalRuntime(
      queues: SignalQueues(const SignalQueueSettings()),
    );
    void makeDropped(int count) {
      for (var made = 0; made < count; made++) {
        beans.adopt(Object(), SignalBean('Draft'), runtime);
      }
    }

    makeDropped(300);
    await _collectGarbage();
    makeDropped(300);

    expect(beans.keptStates, lessThan(600));
  });
}
