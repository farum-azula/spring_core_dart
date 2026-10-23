import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

/// A bean with an `@EventListener` method (written as the generator does).
class Audit {
  final seen = <String>[];
}

BeanDefinition<Audit> auditBean(Audit audit) => BeanDefinition<Audit>(
  name: 'audit',
  create: (_) => audit,
  eventListeners: [
    EventListenerMethod.of<Audit, SpringApplicationEvent>(
      'Audit.onApplicationEvent',
      (bean, event) => bean.seen.add('${event.runtimeType}'),
    ),
  ],
);

class Runner implements ApplicationRunner {
  Runner(this.events, {this.fail = false, this.wait = false});
  final List<String> events;
  final bool fail;
  final bool wait;

  @override
  FutureOr<void> run(ApplicationArguments args) async {
    if (wait) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    events.add('runner');
    if (fail) {
      throw StateError('runner broke');
    }
  }
}

class SyncRunner implements ApplicationRunner {
  SyncRunner(this.events);
  final List<String> events;

  @override
  void run(ApplicationArguments args) => events.add('runner');
}

class Broken {}

void main() {
  late List<String> events;
  late Audit audit;

  SpringApplication app([List<BeanDefinition<Object>> beans = const []]) {
    audit = Audit();
    return SpringApplication(
      [
        BeanModule('app', [auditBean(audit), ...beans]),
      ],
      out: (_) => events.add('report'),
      listeners: [
        ApplicationListenerAdapter.of<ApplicationEvent>(
          (event) => events.add('${event.runtimeType}'),
        ),
      ],
    );
  }

  BeanDefinition<Object> runner(ApplicationRunner bean) =>
      BeanDefinition<ApplicationRunner>(
        name: 'runner',
        types: const [ApplicationRunner],
        create: (_) => bean,
      );

  setUp(() => events = []);

  test('application events in Spring Boot order', () {
    final context = app([runner(SyncRunner(events))])
        .run(['--a=1'], systemEnvironment: const {});
    addTearDown(context.close);
    expect(events, [
      'ApplicationStartingEvent',
      'ApplicationEnvironmentPreparedEvent',
      'ApplicationContextInitializedEvent',
      'ApplicationPreparedEvent',
      'ContextRefreshedEvent', // the listeners are the context's now
      'ApplicationStartedEvent',
      'runner',
      'ApplicationReadyEvent',
    ]);
    // @EventListener beans see the events published after the refresh.
    expect(audit.seen, ['ApplicationStartedEvent', 'ApplicationReadyEvent']);
  });

  test('the events carry the run; addListener / addListeners', () {
    late ApplicationEnvironmentPreparedEvent prepared;
    late ApplicationStartedEvent started;
    late ApplicationReadyEvent ready;
    final application = app()
      ..addListener<ApplicationEnvironmentPreparedEvent>(
        (event) => prepared = event,
      )
      ..addListeners([
        ApplicationListenerAdapter.of<ApplicationStartedEvent>(
          (event) => started = event,
        ),
        ApplicationListenerAdapter.of<ApplicationReadyEvent>(
          (event) => ready = event,
        ),
      ]);
    expect(application.listeners, hasLength(4));
    final context = application.run([
      '--greeting=hi',
    ], systemEnvironment: const {});
    addTearDown(context.close);
    expect(prepared.springApplication, same(application));
    expect(prepared.source, same(application));
    expect(prepared.args, ['--greeting=hi']);
    expect(prepared.environment.getProperty('greeting'), 'hi');
    expect(started.applicationContext, same(context));
    expect(ready.timeTaken, greaterThanOrEqualTo(started.timeTaken));
  });

  test('a failed start: ApplicationFailedEvent to the application listeners, '
      'before the report', () {
    final broken = app([
      BeanDefinition<Broken>(
        name: 'broken',
        dependencies: const [Dependency(Runner)],
        create: (r) => Broken(),
      ),
    ]);
    late ApplicationFailedEvent failed;
    broken.addListener<ApplicationFailedEvent>((event) => failed = event);
    expect(
      () => broken.run(const [], systemEnvironment: const {}),
      throwsA(isA<NoSuchBeanDefinitionException>()),
    );
    expect(events.sublist(events.length - 2), [
      'ApplicationFailedEvent',
      'report',
    ]);
    expect(events, isNot(contains('ApplicationStartedEvent')));
    expect(failed.exception, isA<NoSuchBeanDefinitionException>());
    expect(failed.applicationContext, isNotNull);
    expect(audit.seen, isEmpty); // the context never ran
  });

  test('a failing runner: ApplicationFailedEvent reaches the beans too, '
      'before the report and the close', () async {
    await expectLater(
      app([runner(Runner(events, fail: true))])
          .runAsync(const [], systemEnvironment: const {}),
      throwsA(isA<StateError>()),
    );
    expect(events.sublist(events.length - 5), [
      'ApplicationStartedEvent',
      'runner',
      'ApplicationFailedEvent',
      'report',
      'ContextClosedEvent',
    ]);
    expect(audit.seen, ['ApplicationStartedEvent', 'ApplicationFailedEvent']);
  });

  test(
    'runAsync: ApplicationReadyEvent after the asynchronous runners',
    () async {
      final context = await app([runner(Runner(events, wait: true))])
          .runAsync(const [], systemEnvironment: const {});
      addTearDown(context.close);
      expect(events.sublist(events.length - 3), [
        'ApplicationStartedEvent',
        'runner',
        'ApplicationReadyEvent',
      ]);
    },
  );

  test(
    'run: ApplicationReadyEvent once the asynchronous runners are done',
    () async {
      final context = app([runner(Runner(events, wait: true))])
          .run(const [], systemEnvironment: const {});
      addTearDown(context.close);
      expect(events.last, 'ApplicationStartedEvent'); // run() returned
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(events.sublist(events.length - 2), [
        'runner',
        'ApplicationReadyEvent',
      ]);
    },
  );
}
