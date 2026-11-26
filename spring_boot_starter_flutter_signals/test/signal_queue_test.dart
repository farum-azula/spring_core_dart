// A queue of writes at its capacity.
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_core/signals_core.dart' as signals;
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';

void main() {
  test('full, with on-overflow: flush, while it tells its readers: a write '
      'that finds no room is refused, the queue never holds more than its '
      'capacity', () {
    final bean = SignalBean('Board')
      ..runtime = SignalRuntime(
        queues: SignalQueues(
          // Told only when the test flushes it.
          SignalQueueSettings(
            schedule: (flush) => () {},
            capacity: 1,
          ),
        ),
      );
    final queue = bean.runtime!.queues.primary;
    final a = bean.field('a', () => 0);
    final b = bean.field('b', () => 0);
    final c = bean.field('c', () => 0);
    final held = <int>[];
    // A reader that writes two fields while the queue tells it.
    final stop = signals.effect(() {
      if (a.read() == 1) {
        b.write(1);
        c.write(1);
        held.add(queue.pending);
      }
    });
    addTearDown(stop);

    a.write(1);
    queue.flush();

    expect(held, [1]);
    expect(queue.drops, 1);
    expect(b.read(), 1);
    expect(c.read(), 0, reason: 'refused: the field keeps its value');
    expect(queue.pending, 0);
  });
}
