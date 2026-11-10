import 'dart:async';
import 'dart:isolate';

import 'package:spring_core_dart/core.dart';
import 'package:test/test.dart';

int _square(int n) => n * n;

String _name(int _) => Isolate.current.debugName ?? '?';

Future<String> _slowName(int millis) async {
  await Future<void>.delayed(Duration(milliseconds: millis));
  return Isolate.current.debugName ?? '?';
}

int _spin(int millis) {
  final watch = Stopwatch()..start();
  var n = 0;
  while (watch.elapsedMilliseconds < millis) {
    n++;
  }
  return n;
}

Never _fail(String message) => throw FormatException(message);

Object _unsendable(int _) => ReceivePort();

void main() {
  late IsolateTaskExecutor executor;

  IsolateTaskExecutor pool({
    int? core,
    int? max,
    int? queue,
    Duration keepAlive = const Duration(seconds: 60),
    bool coreTimeout = true,
  }) {
    executor = IsolateTaskExecutor(
      settings: IsolateTaskExecutorSettings(
        coreSize: core,
        maxSize: max,
        queueCapacity: queue,
        keepAlive: keepAlive,
        allowCoreTimeout: coreTimeout,
      ),
    );
    addTearDown(executor.shutdown);
    return executor;
  }

  test('runs a function with its message in another isolate', () async {
    pool(core: 1);
    expect(executor.poolSize, 0, reason: 'no isolate before the first task');
    expect(await executor.submitWith(_square, 7), 49);
    expect(await executor.submitWith(_name, 0), 'task-1');
    expect(executor.poolSize, 1);
  });

  test('runs a closure, copying what it uses', () async {
    pool(core: 1);
    const base = 40;
    expect(await executor.submit(() => base + 2), 42);
  });

  test("an error of the task is the future's error", () async {
    pool(core: 1);
    await expectLater(
      executor.submitWith(_fail, 'bad'),
      throwsA(
        isA<FormatException>().having((e) => e.message, 'message', 'bad'),
      ),
    );
    // The isolate goes on.
    expect(await executor.submitWith(_square, 3), 9);
    expect(executor.poolSize, 1);
  });

  test('a result that cannot be copied back is an error', () async {
    pool(core: 1);
    await expectLater(
      executor.submitWith(_unsendable, 0),
      throwsA(isA<IsolateTaskException>()),
    );
    expect(await executor.submitWith(_square, 2), 4);
  });

  test(
    'a closure that cannot be copied fails the call, not the pool',
    () async {
      pool(core: 1);
      await executor.submitWith(_square, 1);
      final port = ReceivePort();
      addTearDown(port.close);
      await expectLater(
        executor.submit(() => port.hashCode),
        throwsArgumentError,
      );
      expect(await executor.submitWith(_square, 5), 25);
    },
  );

  test('up to core-size isolates, then the queue', () async {
    pool(core: 2);
    final names = await Future.wait([
      for (var i = 0; i < 6; i++) executor.submitWith(_slowName, 60),
    ]);
    expect(names.toSet(), {'task-1', 'task-2'});
    expect(executor.poolSize, 2);
    expect(executor.queueSize, 0);
  });

  test('grows to max-size only when the queue is full', () async {
    pool(core: 1, max: 3, queue: 1);
    final running = [
      for (var i = 0; i < 4; i++) executor.submitWith(_slowName, 150),
    ];
    // 1 core isolate, 1 queued, 2 more isolates for the next two.
    expect(executor.poolSize, 3);
    expect(executor.queueSize, 1);
    expect(
      () => executor.submitWith(_slowName, 1),
      throwsA(isA<IsolateTaskRejectedException>()),
    );
    expect((await Future.wait(running)).toSet(), hasLength(3));
  });

  test('an idle isolate leaves after keep-alive', () async {
    pool(core: 1, keepAlive: const Duration(milliseconds: 80));
    await executor.submitWith(_square, 1);
    expect(executor.poolSize, 1);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(executor.poolSize, 0);
    // The next task starts another.
    expect(await executor.submitWith(_name, 0), 'task-2');
  });

  test('core isolates stay without allow-core-timeout', () async {
    pool(
      core: 1,
      keepAlive: const Duration(milliseconds: 50),
      coreTimeout: false,
    );
    await executor.submitWith(_square, 1);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(executor.poolSize, 1);
  });

  test('the calling isolate stays free while a task computes', () async {
    pool(core: 1);
    final sampler = IsolateLoadSampler(
      interval: const Duration(milliseconds: 10),
    )..load();
    addTearDown(sampler.stop);
    await executor.submitWith(_spin, 300);
    final load = sampler.load();
    expect(load.maxLag, lessThan(const Duration(milliseconds: 100)));
  });

  test('its isolates are rows of the task manager', () async {
    pool(core: 2);
    final work = [
      executor.submitWith(_spin, 200),
      executor.submitWith(_spin, 200),
    ];
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final loads = executor.loads();
    expect(loads.map((l) => l.name), ['task-1', 'task-2']);
    expect(loads.every((l) => l.kind == 'task' && l.active == 1), isTrue);
    await Future.wait(work);
    final after = executor.loads();
    expect(after.first.busy, greaterThan(0.3));
    expect(after.first.active, 0);
    expect(after.first.details['tasks'], 1);
  });

  test('shutdown fails what waits and refuses what comes', () async {
    pool(core: 1);
    final first = executor.submitWith(_slowName, 500);
    final second = executor.submitWith(_square, 2);
    unawaited(first.then<void>((_) {}, onError: (_) {}));
    final refused = expectLater(
      second,
      throwsA(isA<IsolateTaskRejectedException>()),
    );
    await executor.shutdown();
    await refused;
    expect(executor.poolSize, 0);
    expect(
      () => executor.submitWith(_square, 1),
      throwsA(isA<IsolateTaskRejectedException>()),
    );
  });
}
