import 'dart:async';

import 'package:spring_boot_starter_scheduling/spring_auto_configuration.dart';
import 'package:spring_boot_starter_scheduling/spring_boot_starter_scheduling.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'fake_clock.dart';

final start = DateTime.utc(2026, 1, 1, 12);

class Reports {
  final calls = <String>[];

  void refresh() => calls.add('refresh');
  void hourly() => calls.add('hourly');
  void cleanup() => calls.add('cleanup');
  void twice() => calls.add('twice');
  Future<void> sync() async => calls.add('sync');
}

/// What the generator writes for `Reports` (annotatedMethods only).
BeanDefinition<Reports> reportsDefinition(
  Map<String, List<Scheduled>> methods, {
  bool lazy = false,
  String scope = ScopeType.singleton,
  Reports? instance,
}) => BeanDefinition<Reports>(
  name: 'reports',
  lazy: lazy,
  scope: scope,
  create: (_) => instance ?? Reports(),
  annotatedMethods: [
    for (final MapEntry(key: name, value: annotations) in methods.entries)
      BeanMethod<Reports>(
        name,
        invoke: (bean, arguments) => Function.apply(switch (name) {
          'refresh' => bean.refresh,
          'hourly' => bean.hourly,
          'cleanup' => bean.cleanup,
          'twice' => bean.twice,
          'sync' => bean.sync,
          _ => throw ArgumentError(name),
        }, arguments),
        annotations: annotations,
      ),
  ],
);

void main() {
  late FakeClock clock;
  late TimerTaskScheduler scheduler;

  setUp(() {
    clock = FakeClock(start);
    scheduler = TimerTaskScheduler(now: clock.now, createTimer: clock.timer);
  });

  ApplicationContextRunner runner(List<BeanDefinition<Object>> beans) =>
      const ApplicationContextRunner()
          .withUserConfiguration(
            BeanModule('app', [
              BeanDefinition<TaskScheduler>(
                name: 'taskScheduler',
                create: (_) => scheduler,
              ),
              ...beans,
            ]),
          )
          .withAutoConfiguration(springBootStarterSchedulingAutoConfiguration);

  Reports reportsOf(AssertableApplicationContext context) =>
      context.getBean<Reports>();

  test('fixed rate, fixed delay and cron methods run after refresh', () {
    runner([
      reportsDefinition({
        'refresh': [const Scheduled(fixedRate: Duration(minutes: 5))],
        'hourly': [const Scheduled(cron: '0 0 * * * *', zone: 'UTC')],
        'twice': [
          const Scheduled(fixedDelay: Duration(minutes: 30)),
          const Scheduled(fixedRateString: '45m', initialDelayString: '1m'),
        ],
      }),
    ]).run((context) {
      final processor = context.getBean<ScheduledAnnotationBeanPostProcessor>();
      expect(processor.scheduledTasks.map((t) => t.name), [
        'Reports.refresh',
        'Reports.hourly',
        'Reports.twice',
        'Reports.twice',
      ]);
      expect(processor.isRunning, isTrue);
      final hourly = processor.scheduledTasks[1].trigger as CronTrigger;
      expect(hourly.utc, isTrue);

      clock.elapse(const Duration(hours: 1));
      final calls = reportsOf(context).calls;
      expect(calls.where((c) => c == 'refresh'), hasLength(13)); // 0, 5, ... 60
      expect(calls.where((c) => c == 'hourly'), hasLength(1)); // 13:00
      expect(
        calls.where((c) => c == 'twice'),
        hasLength(3 + 2),
      ); // 0, 30, 60 + 1, 46
    });
    // Closing the context cancelled everything.
    expect(clock.pendingTimers, 0);
  });

  test('initialDelay alone runs the method once (Spring 6.1)', () {
    runner([
      reportsDefinition({
        'refresh': [const Scheduled(initialDelay: Duration(minutes: 1))],
        'cleanup': [const Scheduled(initialDelayString: r'${jobs.warm-up:2m}')],
      }),
    ]).run((context) {
      final tasks = context
          .getBean<ScheduledAnnotationBeanPostProcessor>()
          .scheduledTasks;
      expect(tasks.map((t) => t.name), ['Reports.refresh', 'Reports.cleanup']);
      expect(tasks.first.nextExecution, start.add(const Duration(minutes: 1)));
      clock.elapse(const Duration(hours: 3));
      expect(reportsOf(context).calls, ['refresh', 'cleanup']);
    });
  });

  test('placeholders, Spring Boot durations and a switched-off cron', () {
    runner([
      reportsDefinition({
        'refresh': [const Scheduled(fixedRateString: r'${reports.rate}')],
        'hourly': [const Scheduled(cron: r'${reports.cron:0 0 * * * *}')],
        'cleanup': [const Scheduled(cron: r'${reports.cleanup:-}')],
        'twice': [const Scheduled(fixedDelayString: '1000')],
      }),
    ]).withPropertyValues(['reports.rate=PT10M']).run((context) {
      final tasks = context
          .getBean<ScheduledAnnotationBeanPostProcessor>()
          .scheduledTasks;
      expect(tasks.map((t) => t.name), [
        'Reports.refresh',
        'Reports.hourly',
        'Reports.twice',
      ]);
      expect(
        (tasks.first.trigger as PeriodicTrigger).period,
        const Duration(minutes: 10),
      );
      expect(
        (tasks.last.trigger as PeriodicTrigger).period,
        const Duration(seconds: 1),
      );
      clock.elapse(const Duration(minutes: 20));
      expect(
        reportsOf(context).calls.where((c) => c == 'refresh'),
        hasLength(3),
      );
      expect(reportsOf(context).calls, isNot(contains('cleanup')));
    });
  });

  test('scheduler: picks a TaskScheduler bean by name or qualifier', () {
    final other = TimerTaskScheduler(now: clock.now, createTimer: clock.timer);
    runner([
      BeanDefinition<TaskScheduler>(
        name: 'reportsScheduler',
        qualifiers: const {'reports'},
        create: (_) => other,
      ),
      reportsDefinition({
        'refresh': [const Scheduled(fixedRate: Duration(minutes: 1))],
        'hourly': [
          const Scheduled(cron: '@hourly', scheduler: 'reportsScheduler'),
        ],
        'cleanup': [
          const Scheduled(
            fixedDelay: Duration(minutes: 1),
            scheduler: r'${reports.scheduler}',
          ),
        ],
        'twice': [
          const Scheduled(fixedDelay: Duration(minutes: 1), scheduler: ''),
        ],
      }),
    ]).withPropertyValues(['reports.scheduler=reports']).run((context) {
      expect(context.hasFailed, isFalse, reason: '${context.startupFailure}');
      // The default: the TaskScheduler named `taskScheduler`.
      expect(scheduler.tasks.map((t) => t.name), [
        'Reports.refresh',
        'Reports.twice',
      ]);
      expect(other.tasks.map((t) => t.name), [
        'Reports.hourly',
        'Reports.cleanup',
      ]);
      clock.elapse(const Duration(hours: 1));
      expect(reportsOf(context).calls, contains('hourly'));
    });
    expect(clock.pendingTimers, 0);
  });

  test('a lazy bean is scheduled when it is created', () {
    runner([
      reportsDefinition({
        'refresh': [const Scheduled(fixedRate: Duration(seconds: 1))],
      }, lazy: true),
    ]).run((context) {
      final processor = context.getBean<ScheduledAnnotationBeanPostProcessor>();
      expect(processor.scheduledTasks, isEmpty);
      final reports = reportsOf(context);
      expect(processor.scheduledTasks, hasLength(1));
      clock.elapse(const Duration(seconds: 2));
      expect(reports.calls, ['refresh', 'refresh', 'refresh']);
    });
  });

  test('the method is called on the bean as other beans see it', () {
    final advised = <String>[];
    runner([
      reportsDefinition({
        'refresh': [const Scheduled(fixedRate: Duration(seconds: 1))],
      }),
      BeanDefinition<WrappingProcessor>(
        name: 'wrapping',
        types: const [WrappingProcessor, BeanPostProcessor],
        create: (_) => WrappingProcessor(advised),
      ),
    ]).run((context) {
      clock.elapse(Duration.zero);
      expect(advised, ['refresh']);
    });
  });

  test('a proxy implementing only interfaces: the target is called', () {
    final reports = Reports();
    runner([
      reportsDefinition({
        'refresh': [const Scheduled(fixedRate: Duration(seconds: 1))],
      }, instance: reports),
      BeanDefinition<InterfaceProxyProcessor>(
        name: 'interfaceProxy',
        types: const [InterfaceProxyProcessor, BeanPostProcessor],
        create: (_) => InterfaceProxyProcessor(),
      ),
    ]).run((context) {
      clock.elapse(Duration.zero);
      expect(reports.calls, ['refresh']);
    });
  });

  test('an asynchronous fixed-delay method is awaited', () async {
    final reports = Reports();
    final environment = StandardEnvironment(systemEnvironment: const {});
    final context = AnnotationConfigApplicationContext([
      BeanModule('app', [
        BeanDefinition<TaskScheduler>(
          name: 'taskScheduler',
          create: (_) => scheduler,
        ),
        reportsDefinition({
          'sync': [const Scheduled(fixedDelay: Duration(seconds: 10))],
        }, instance: reports),
      ]),
      springBootStarterSchedulingAutoConfiguration,
    ], environment: environment)..refresh();
    await clock.elapseAsync(const Duration(seconds: 25));
    expect(reports.calls, ['sync', 'sync', 'sync']);
    context.close();
    expect(clock.pendingTimers, 0);
  });

  test('prototypes are not scheduled', () {
    final logs = <SpringLogRecord>[];
    final previous = SpringLog.handler;
    SpringLog.handler = logs.add;
    addTearDown(() => SpringLog.handler = previous);
    runner([
      reportsDefinition({
        'refresh': [const Scheduled(fixedRate: Duration(seconds: 1))],
      }, scope: ScopeType.prototype),
    ]).run((context) {
      context.getBean<Reports>();
      expect(
        context.getBean<ScheduledAnnotationBeanPostProcessor>().scheduledTasks,
        isEmpty,
      );
    });
    expect(logs.map((r) => r.message), contains(contains("scope 'prototype'")));
  });

  test('a *String that is or resolves to blank is not set, like Spring', () {
    runner([
      reportsDefinition({
        // The fixedRate counts; the empty fixedRateString does not.
        'refresh': [
          const Scheduled(
            fixedRate: Duration(minutes: 10),
            fixedRateString: r'${jobs.rate:}',
            initialDelayString: '',
          ),
        ],
        'cleanup': [
          const Scheduled(
            fixedRateString: r'${jobs.rate:}',
            fixedDelayString: '5m',
            initialDelayString: r'${jobs.initial:}',
          ),
        ],
      }),
    ]).run((context) {
      expect(context.hasFailed, isFalse);
      final tasks = context
          .getBean<ScheduledAnnotationBeanPostProcessor>()
          .scheduledTasks;
      final refresh = tasks.first.trigger as PeriodicTrigger;
      expect(refresh.period, const Duration(minutes: 10));
      expect(refresh.fixedRate, isTrue);
      final cleanup = tasks.last.trigger as PeriodicTrigger;
      expect(cleanup.period, const Duration(minutes: 5));
      expect(cleanup.fixedRate, isFalse);
    });
    // Nothing left: the usual error.
    runner([
      reportsDefinition({
        'refresh': [const Scheduled(fixedRateString: r'${jobs.rate:}')],
      }),
    ]).run((context) {
      expect(
        '${context.startupFailure}',
        contains('give one of cron, fixedRate or fixedDelay'),
      );
    });
  });

  group('misconfiguration fails the startup naming the method', () {
    final cases = <String, (Scheduled, String)>{
      'nothing': (
        const Scheduled(),
        'give one of cron, fixedRate or fixedDelay',
      ),
      'two kinds': (
        const Scheduled(
          fixedRate: Duration(seconds: 1),
          fixedDelay: Duration(seconds: 1),
        ),
        'only one of',
      ),
      'a duration twice': (
        const Scheduled(fixedRate: Duration(seconds: 1), fixedRateString: '1s'),
        'not both',
      ),
      'initialDelay with cron': (
        const Scheduled(cron: '@daily', initialDelay: Duration(seconds: 1)),
        'initialDelay is not supported with cron',
      ),
      'unknown zone': (
        const Scheduled(cron: '@daily', zone: 'Europe/Kyiv'),
        'zone "Europe/Kyiv"',
      ),
      'invalid cron': (const Scheduled(cron: '0 0 25 * * *'), 'hour field'),
      'not a duration': (
        const Scheduled(fixedRateString: 'soon'),
        'is not a duration',
      ),
      'missing property': (
        const Scheduled(fixedRateString: r'${jobs.rate}'),
        'jobs.rate',
      ),
      'zero rate': (
        const Scheduled(fixedRate: Duration.zero),
        'must be positive',
      ),
      'negative delay': (
        const Scheduled(fixedDelay: Duration(seconds: -1)),
        'must not be negative',
      ),
      'unknown scheduler': (
        const Scheduled(fixedRate: Duration(seconds: 1), scheduler: 'nope'),
        "scheduler 'nope': no TaskScheduler bean",
      ),
    };
    for (final MapEntry(key: name, value: (scheduled, message))
        in cases.entries) {
      test(name, () {
        runner([
          reportsDefinition({
            'refresh': [scheduled],
          }),
        ]).run((context) {
          expect(context, hasFailed());
          expect('${context.startupFailure}', contains('Reports.refresh'));
          expect('${context.startupFailure}', contains(message));
        });
      });
    }

    test('parameters', () {
      runner([
        BeanDefinition<Reports>(
          name: 'reports',
          create: (_) => Reports(),
          annotatedMethods: [
            BeanMethod<Reports>(
              'refresh',
              parameterTypes: const [int],
              invoke: (bean, arguments) => null,
              annotations: const [Scheduled(fixedRate: Duration(seconds: 1))],
            ),
          ],
        ),
      ]).run((context) {
        expect(
          '${context.startupFailure}',
          contains('Reports.refresh: it must not take parameters'),
        );
      });
    });
  });

  group('auto-configuration', () {
    final bare = const ApplicationContextRunner().withAutoConfiguration(
      springBootStarterSchedulingAutoConfiguration,
    );

    test('a TimerTaskScheduler unless the application has a TaskScheduler', () {
      bare.run((context) {
        expect(context, hasSingleBean<TaskScheduler>());
        expect(context.getBean<TaskScheduler>(), isA<TimerTaskScheduler>());
        expect(context, hasSingleBean<ScheduledAnnotationBeanPostProcessor>());
      });
      runner(const []).run((context) {
        expect(context.getBean<TaskScheduler>(), same(scheduler));
      });
    });

    test('an applicationTaskExecutor runs @Async listeners', () async {
      final received = <String>[];
      final listener = BeanDefinition<Reports>(
        name: 'reports',
        create: (_) => Reports(),
        eventListeners: [
          EventListenerMethod.of<Reports, String>('Reports.on', (_, event) {
            received.add(event);
            return null;
          }, async: const Async()),
        ],
      );
      await bare.withUserConfiguration(BeanModule('app', [listener])).runAsync((
        context,
      ) async {
        expect(context, hasSingleBean<TaskExecutor>());
        final executor = context.getBean<TaskExecutor>();
        expect(context.getBeanByName('taskExecutor'), same(executor));
        context.context.publishEvent('hello');
        expect(received, isEmpty);
        await (executor as SimpleAsyncTaskExecutor).whenIdle;
        expect(received, ['hello']);
      });
      final own = SimpleAsyncTaskExecutor();
      bare
          .withUserConfiguration(
            BeanModule('app', [
              BeanDefinition<TaskExecutor>(name: 'mine', create: (_) => own),
            ]),
          )
          .run((context) {
            expect(context, hasSingleBean<TaskExecutor>());
            expect(context.getBean<TaskExecutor>(), same(own));
          });
    });

    test('spring.task.scheduling.enabled=false switches it off', () {
      runner([
            reportsDefinition({
              'refresh': [const Scheduled(fixedRate: Duration(seconds: 1))],
            }),
          ])
          .withPropertyValues(['spring.task.scheduling.enabled=false'])
          .run((context) {
            expect(
              context,
              doesNotHaveBean<ScheduledAnnotationBeanPostProcessor>(),
            );
            clock.elapse(const Duration(seconds: 5));
            expect(context.getBean<Reports>().calls, isEmpty);
          });
      bare.withPropertyValues(['spring.task.scheduling.enabled=false']).run((
        context,
      ) {
        expect(context, doesNotHaveBean<TaskScheduler>());
      });
    });

    test('the default scheduler shuts down with the context', () {
      late TimerTaskScheduler timers;
      bare.run((context) {
        timers = context.getBean<TaskScheduler>() as TimerTaskScheduler;
      });
      expect(timers.isShutdown, isTrue);
    });

    group('spring.task.scheduling.shutdown.await-termination', () {
      final logs = captureLogs();

      // A context with the real scheduler and a run that lasts until
      // [finished] completes.
      Future<(ConfigurableApplicationContext, TimerTaskScheduler)> running(
        Map<String, Object?> properties,
        Completer<void> finished,
      ) async {
        final context = AnnotationConfigApplicationContext(
          [springBootStarterSchedulingAutoConfiguration],
          environment: StandardEnvironment(systemEnvironment: {})
            ..propertySources.addFirst(MapPropertySource('test', properties)),
        );
        await context.refreshAsync();
        final scheduler =
            context.getBean<TaskScheduler>() as TimerTaskScheduler;
        scheduler.schedule(
          () => finished.future,
          OneShotTrigger(scheduler.now()),
          name: 'slow',
        );
        await Future<void>.delayed(Duration.zero);
        expect(scheduler.runningTasks, hasLength(1));
        return (context, scheduler);
      }

      test('closeAsync waits for the runs going on', () async {
        final finished = Completer<void>();
        final (context, scheduler) = await running({
          'spring.task.scheduling.shutdown.await-termination': 'true',
        }, finished);
        var closed = false;
        final closing = context.closeAsync().then((_) => closed = true);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(closed, isFalse);
        expect(scheduler.isShutdown, isTrue);
        finished.complete();
        await closing;
        expect(closed, isTrue);
        expect(scheduler.runningTasks, isEmpty);
      });

      test('await-termination-period bounds the wait', () async {
        final (context, scheduler) = await running({
          'spring.task.scheduling.shutdown.await-termination': true,
          'spring.task.scheduling.shutdown.await-termination-period': '20ms',
        }, Completer<void>());
        final watch = Stopwatch()..start();
        await context.closeAsync();
        expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(15));
        expect(scheduler.runningTasks, hasLength(1));
        expect(
          logs.messages,
          contains(contains('Timed out while waiting for the TaskScheduler')),
        );
      });

      test('off by default: close does not wait', () async {
        final (context, scheduler) = await running(const {}, Completer<void>());
        await context.closeAsync();
        expect(context.isClosed, isTrue);
        expect(scheduler.runningTasks, hasLength(1));
      });
    });
  });
}

/// Replaces `reports` with a subclass recording the calls (like an AOP
/// proxy that extends the class).
final class WrappingProcessor extends BeanPostProcessor {
  WrappingProcessor(this.advised);

  final List<String> advised;

  @override
  Object postProcessAfterInitialization(Object bean, String beanName) =>
      bean is Reports ? AdvisedReports(advised) : bean;
}

class AdvisedReports extends Reports {
  AdvisedReports(this.advised);

  final List<String> advised;

  @override
  void refresh() => advised.add('refresh');
}

/// Replaces `reports` with a proxy that is not a `Reports`.
final class InterfaceProxyProcessor extends BeanPostProcessor {
  @override
  Object postProcessAfterInitialization(Object bean, String beanName) =>
      bean is Reports ? InterfaceOnlyProxy(bean) : bean;
}

class InterfaceOnlyProxy implements Advised {
  InterfaceOnlyProxy(this.aopTarget);

  @override
  final Object aopTarget;

  @override
  List<PointcutAdvisor> get aopAdvisors => const [];

  @override
  void addAdvisor(PointcutAdvisor advisor) => ProxyInvoker.notAdvised(this);

  @override
  bool removeAdvisor(PointcutAdvisor advisor) => ProxyInvoker.notAdvised(this);

  @override
  void addAdvice(MethodInterceptor advice) => ProxyInvoker.notAdvised(this);

  @override
  bool removeAdvice(MethodInterceptor advice) => ProxyInvoker.notAdvised(this);
}
