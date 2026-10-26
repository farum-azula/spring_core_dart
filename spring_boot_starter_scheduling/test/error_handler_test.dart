import 'package:spring_boot_starter_scheduling/spring_auto_configuration.dart';
import 'package:spring_boot_starter_scheduling/spring_boot_starter_scheduling.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'fake_clock.dart';

final class Collect implements ErrorHandler {
  final errors = <Object>[];

  @override
  void handleError(Object error, StackTrace stackTrace) => errors.add(error);
}

final class Propagate implements ErrorHandler {
  @override
  void handleError(Object error, StackTrace stackTrace) =>
      Error.throwWithStackTrace(error, stackTrace);
}

void main() {
  late FakeClock clock;
  late List<SpringLogRecord> logs;
  late void Function() stop;

  setUp(() {
    clock = FakeClock(DateTime.utc(2026, 1, 1, 12));
    logs = [];
    stop = SpringLog.listen(logs.add);
  });
  tearDown(() => stop());

  test('an ErrorHandler gets the errors; the task keeps running', () async {
    final handler = Collect();
    final scheduler = TimerTaskScheduler(
      now: clock.now,
      createTimer: clock.timer,
      errorHandler: handler,
    );
    addTearDown(scheduler.shutdown);
    var runs = 0;
    scheduler.scheduleAtFixedRate(() {
      runs++;
      throw StateError('sync $runs');
    }, const Duration(seconds: 1));
    scheduler.scheduleAtFixedRate(() async {
      throw StateError('async');
    }, const Duration(seconds: 1));
    await clock.elapseAsync(const Duration(seconds: 2));
    expect(runs, 3);
    expect(handler.errors.whereType<StateError>().map((e) => e.message), [
      'sync 1',
      'async',
      'sync 2',
      'async',
      'sync 3',
      'async',
    ]);
    expect(logs.where((r) => r.level == SpringLogLevel.error), isEmpty);
  });

  test('a handler that throws stops the task (LOG_AND_PROPAGATE)', () async {
    final scheduler = TimerTaskScheduler(
      now: clock.now,
      createTimer: clock.timer,
      errorHandler: Propagate(),
    );
    addTearDown(scheduler.shutdown);
    var runs = 0;
    final task = scheduler.scheduleAtFixedRate(() {
      runs++;
      throw StateError('boom');
    }, const Duration(seconds: 1));
    await clock.elapseAsync(const Duration(seconds: 3));
    expect(runs, 1);
    expect(task.isCancelled, isTrue);
    expect(
      logs.map((r) => r.message),
      contains('Scheduled task task failed and will not run again'),
    );
  });

  test('the auto-configured scheduler uses the ErrorHandler bean', () {
    final handler = Collect();
    const ApplicationContextRunner()
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterSchedulingAutoConfiguration)
        .withBean<ErrorHandler>(() => handler)
        .run((context) {
          final scheduler = context.getBean<TaskScheduler>();
          expect((scheduler as TimerTaskScheduler).errorHandler, same(handler));
        });
  });

  test('two ErrorHandler beans: the primary one, or none', () {
    final first = Collect();
    final second = Collect();
    BeanModule handlers({bool primary = false}) => BeanModule('handlers', [
      BeanDefinition<ErrorHandler>(name: 'first', create: (_) => first),
      BeanDefinition<ErrorHandler>(
        name: 'second',
        primary: primary,
        create: (_) => second,
      ),
    ]);
    const runner = ApplicationContextRunner();
    runner
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterSchedulingAutoConfiguration)
        .withUserConfiguration(handlers())
        .run((context) {
          expect(context.hasFailed, isFalse);
          final scheduler = context.getBean<TaskScheduler>();
          expect((scheduler as TimerTaskScheduler).errorHandler, isNull);
        });
    runner
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterSchedulingAutoConfiguration)
        .withUserConfiguration(handlers(primary: true))
        .run((context) {
          final scheduler = context.getBean<TaskScheduler>();
          expect((scheduler as TimerTaskScheduler).errorHandler, same(second));
        });
  });
}
