// IsolateAutoConfiguration: the beans about isolates (the info, the
// sampler, the task executor with its properties, the loads, the reports),
// each backing off; @ConditionalOnPrimaryIsolate; and the ApplicationLaunch
// bean of a run that can be repeated in another isolate.
import 'dart:isolate';

import 'package:spring_boot_dart/spring_auto_configuration.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

String _isolateName(int _) => Isolate.current.debugName ?? '?';

final class _Source implements IsolateLoadSource {
  @override
  List<IsolateLoad> loads() => const [
    IsolateLoad(name: 'worker', kind: 'own'),
  ];
}

final class _Reporter implements IsolateReporter {
  @override
  String get id => 'answer';

  @override
  Object? report() => 42;
}

final class _Echo implements PrimaryIsolateHandler {
  @override
  String get id => 'echo';

  @override
  Object? handle(Object? request) =>
      '$request from ${IsolateInfo.current.name}';
}

final class _Once {}

SpringApplication _application([
  List<BeanDefinition<Object>> beans = const [],
]) => SpringApplication(
  [BeanModule('app', beans)],
  autoConfigurations: [springBootAutoConfiguration],
  out: (_) {},
);

SpringApplication _plain() => _application();

void main() {
  ConfigurableApplicationContext run(
    List<BeanDefinition<Object>> beans, {
    List<String> args = const [],
  }) {
    final context = _application(
      beans,
    ).run(args, systemEnvironment: const {});
    addTearDown(context.closeAsync);
    return context;
  }

  tearDown(() => IsolateInfo.current = const IsolateInfo());

  test('the beans of one isolate', () {
    final context = run(const []);
    final info = context.getBean<IsolateInfo>();
    expect((info.name, info.index, info.primary), ('main', 0, true));
    expect(context.getBean<IsolateLoadSampler>().isRunning, isFalse);
    final executor = context.getBean<IsolateTaskExecutor>();
    expect(executor.poolSize, 0, reason: 'no isolate before a task');
    // The loads: the sampler's row; the executor has none yet.
    final loads = context.getBean<IsolateLoads>().all();
    expect(loads.map((load) => load.name), ['main']);
    expect(context.getBean<IsolateReports>().own(), isEmpty);
  });

  test('the sources and the reporters of the app are asked too', () {
    final context = run([
      BeanDefinition<_Source>(
        name: 'source',
        types: const [_Source, IsolateLoadSource],
        create: (_) => _Source(),
      ),
      BeanDefinition<_Reporter>(
        name: 'reporter',
        types: const [_Reporter, IsolateReporter],
        create: (_) => _Reporter(),
      ),
    ]);
    expect(
      context.getBean<IsolateLoads>().all().map((load) => load.name),
      containsAll(['main', 'worker']),
    );
    final reports = context.getBean<IsolateReports>();
    expect(reports.own(), {'answer': 42});
    expect(reports.of('answer', own: 'main'), {'main': 42});
  });

  test('the executor runs in isolates named by the property', () async {
    final context = run(
      const [],
      args: const [
        '--spring.task.execution.isolates.core-size=1',
        '--spring.task.execution.isolates.name-prefix=work-',
      ],
    );
    final executor = context.getBean<IsolateTaskExecutor>();
    expect(await executor.submitWith(_isolateName, 0), 'work-1');
    expect(
      context.getBean<IsolateLoads>().all().map((load) => load.name),
      ['main', 'work-1'],
    );
    await context.closeAsync();
    expect(executor.poolSize, 0, reason: 'shut down with the context');
  });

  test('in an isolate of a pool the task isolates carry its name', () async {
    IsolateInfo.current = const IsolateInfo(
      name: 'isolate-2',
      index: 2,
      primary: false,
    );
    final context = run(
      const [],
      args: const ['--spring.task.execution.isolates.core-size=1'],
    );
    expect(context.getBean<IsolateInfo>().name, 'isolate-2');
    expect(
      await context.getBean<IsolateTaskExecutor>().submitWith(_isolateName, 0),
      'isolate-2-task-1',
    );
  });

  test(
    "primaryIsolate asks the handlers; every isolate's load is one",
    () async {
      final context = run([
        BeanDefinition<_Echo>(
          name: 'echo',
          types: const [_Echo, PrimaryIsolateHandler],
          create: (_) => _Echo(),
        ),
      ]);
      final primary = context.getBean<PrimaryIsolate>();
      expect(await primary.ask('echo', 'hi'), 'hi from main');
      final rows = (await primary.ask(IsolateLoadsHandler.handlerId))! as List;
      expect(rows.map((row) => (row as Map)['name']), ['main']);
      expect((rows.single as Map)['kind'], 'main');
    },
  );

  test("the app's own beans win", () {
    final executor = IsolateTaskExecutor();
    final loads = IsolateLoads(const []);
    final context = run([
      BeanDefinition<IsolateTaskExecutor>(
        name: 'ownExecutor',
        create: (_) => executor,
      ),
      BeanDefinition<IsolateLoads>(name: 'ownLoads', create: (_) => loads),
    ]);
    expect(identical(context.getBean<IsolateTaskExecutor>(), executor), isTrue);
    expect(context.containsBean('isolateTaskExecutor'), isFalse);
    expect(identical(context.getBean<IsolateLoads>(), loads), isTrue);
  });

  group('@ConditionalOnPrimaryIsolate', () {
    final once = BeanDefinition<_Once>(
      name: 'once',
      conditions: const [ConditionalOnPrimaryIsolate()],
      create: (_) => _Once(),
    );

    test('in the first isolate: the bean', () {
      expect(run([once]).containsBean('once'), isTrue);
    });

    test('in another: none', () {
      IsolateInfo.current = const IsolateInfo(
        name: 'isolate-1',
        index: 1,
        primary: false,
      );
      expect(run([once]).containsBean('once'), isFalse);
    });
  });

  group('ApplicationLaunch', () {
    test('absent from a run that cannot be repeated', () {
      expect(run(const []).containsBean(ApplicationLaunch.beanName), isFalse);
    });

    test('a run with what returns the application: how to start it again', () {
      final context = _plain().run(
        const ['--app.name=one'],
        systemEnvironment: const {'APP_ENV': 'x'},
        properties: const {'app.mode': 'test'},
        additionalProfiles: const ['extra'],
        hotReload: _plain,
      );
      addTearDown(context.closeAsync);
      final launch = context.getBean<ApplicationLaunch>();
      expect(launch.args, ['--app.name=one']);
      expect(launch.systemEnvironment, {'APP_ENV': 'x'});
      expect(launch.properties, {'app.mode': 'test'});
      expect(launch.additionalProfiles, ['extra']);
      expect(launch.async, isFalse);
      expect(identical(launch.application, _plain), isTrue);
    });

    test(
      'start(): the same application, with properties over its own',
      () async {
        final context = _plain().run(
          const ['--app.name=one'],
          systemEnvironment: const {},
          properties: const {'app.mode': 'test', 'app.kept': 'yes'},
          hotReload: _plain,
        );
        addTearDown(context.closeAsync);
        final again = await context.getBean<ApplicationLaunch>().start(
          properties: const {'app.mode': 'again'},
        );
        addTearDown(again.closeAsync);
        expect(identical(again, context), isFalse);
        expect(again.environment.getProperty('app.name'), 'one');
        expect(again.environment.getProperty('app.mode'), 'again');
        expect(again.environment.getProperty('app.kept'), 'yes');
      },
    );

    test('it crosses to another isolate and starts there', () async {
      final context = _plain().run(
        const ['--app.name=crossed'],
        systemEnvironment: const {},
        hotReload: _plain,
      );
      addTearDown(context.closeAsync);
      final launch = context.getBean<ApplicationLaunch>();
      final name = await Isolate.run(() async {
        final there = await launch.start();
        final name = there.environment.getProperty('app.name');
        await there.closeAsync();
        return name;
      });
      expect(name, 'crossed');
    });

    test('runAsync is repeated with runAsync', () async {
      final context = await _plain().runAsync(
        const [],
        systemEnvironment: const {},
        hotReload: _plain,
      );
      addTearDown(context.closeAsync);
      expect(context.getBean<ApplicationLaunch>().async, isTrue);
    });
  });
}
