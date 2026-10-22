import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

class Pool {
  String url = '';
  int maxSize = 10;
  Duration timeout = const Duration(seconds: 5);
}

final poolIntrospection = BeanIntrospection<Pool>(
  annotations: const [ConfigurationProperties('db')],
  properties: [
    BeanProperty<Pool>(
      'url',
      type: String,
      get: (b) => b.url,
      set: (b, v) => b.url = v! as String,
      annotations: const [NotBlank()],
    ),
    BeanProperty<Pool>(
      'maxSize',
      type: int,
      get: (b) => b.maxSize,
      set: (b, v) => b.maxSize = v! as int,
      annotations: const [Min(1)],
    ),
    BeanProperty<Pool>(
      'timeout',
      type: Duration,
      get: (b) => b.timeout,
      set: (b, v) => b.timeout = v! as Duration,
    ),
  ],
  instantiate: Pool.new,
);

abstract interface class Cache {}

class DefaultCache implements Cache {}

class CustomCache implements Cache {}

class Recorder implements ApplicationRunner, CommandLineRunner {
  final calls = <String>[];
  @override
  void run(Object args) => calls.add(
    args is ApplicationArguments
        ? 'app:${args.getOptionValues('mode')}'
        : 'cli:$args',
  );
}

BeanModule appModule({bool customCache = false}) => BeanModule(
  'app',
  [
    BeanDefinition<Pool>(name: 'pool', create: (_) => Pool()),
    BeanDefinition<Recorder>(
      name: 'recorder',
      types: const [Recorder, ApplicationRunner, CommandLineRunner],
      create: (_) => Recorder(),
    ),
    if (customCache)
      BeanDefinition<CustomCache>(
        name: 'customCache',
        types: const [CustomCache, Cache],
        create: (_) => CustomCache(),
      ),
  ],
  introspections: [poolIntrospection],
);

final autoModule = BeanModule('auto', [
  BeanDefinition<DefaultCache>(
    name: 'defaultCache',
    types: const [DefaultCache, Cache],
    conditions: const [ConditionalOnMissingBean(Cache)],
    create: (_) => DefaultCache(),
  ),
]);

void main() {
  final lines = <String>[];
  setUp(lines.clear);

  ConfigurableApplicationContext run(
    List<String> args, {
    Map<String, String> env = const {},
    bool customCache = false,
  }) => SpringApplication(
    [appModule(customCache: customCache)],
    autoConfigurations: [autoModule],
    out: lines.add,
  ).run(args, systemEnvironment: env);

  test('binds @ConfigurationProperties from args and environment', () {
    final context = run(
      ['--db.url=postgres://x', '--db.max-size=20'],
      env: {'DB_TIMEOUT': '30s'},
    );
    final pool = context.getBean<Pool>();
    expect(pool.url, 'postgres://x');
    expect(pool.maxSize, 20);
    expect(pool.timeout, const Duration(seconds: 30));
    context.close();
  });

  test('invalid properties fail startup with a readable report', () {
    expect(() => run(['--db.url=', '--db.max-size=0']), throwsA(anything));
    final report = lines.join('\n');
    expect(report, contains('APPLICATION FAILED TO START'));
    expect(report, contains("Binding to target properties under 'db' failed"));
    expect(report, contains('db.max-size'));
    expect(report, contains('db.url'));
  });

  test('a missing dependency is explained', () {
    expect(
      () => SpringApplication([
        BeanModule('broken', [
          BeanDefinition<Pool>(
            name: 'needsCache',
            dependencies: const [Dependency(Cache)],
            create: (r) => Pool(),
          ),
        ]),
      ], out: lines.add).run(const [], systemEnvironment: const {}),
      throwsA(isA<NoSuchBeanDefinitionException>()),
    );
    expect(
      lines.join('\n'),
      contains("Bean 'needsCache' required a bean of type Cache"),
    );
  });

  test('auto-configuration backs off for the application bean', () {
    final defaults = run(['--db.url=x']);
    expect(defaults.getBean<Cache>(), isA<DefaultCache>());
    defaults.close();
    final custom = run(['--db.url=x'], customCache: true);
    expect(custom.getBean<Cache>(), isA<CustomCache>());
    expect(custom.containsBean('defaultCache'), isFalse);
    custom.close();
  });

  test('runners run in order with the arguments; startup line', () {
    final context = run(['--db.url=x', '--mode=batch', 'file.csv']);
    expect(context.getBean<Recorder>().calls, [
      'app:[batch]',
      'cli:[--db.url=x, --mode=batch, file.csv]',
    ]);
    expect(context.getBean<ApplicationArguments>().nonOptionArgs, ['file.csv']);
    expect(lines.last, startsWith('Started application in '));
    context.close();
  });

  test('both runner kinds are sorted together by order', () {
    final calls = <String>[];
    final context = SpringApplication([
      appModule(),
      BeanModule('runners', [
        BeanDefinition<_AppRunner>(
          name: 'lateApp',
          types: const [_AppRunner, ApplicationRunner],
          order: 2,
          create: (_) => _AppRunner(() => calls.add('app@2')),
        ),
        BeanDefinition<_CliRunner>(
          name: 'earlyCli',
          types: const [_CliRunner, CommandLineRunner],
          order: 1,
          create: (_) => _CliRunner(() => calls.add('cli@1')),
        ),
      ]),
    ], out: lines.add).run(['--db.url=x'], systemEnvironment: const {});
    addTearDown(context.close);
    expect(calls, ['cli@1', 'app@2']);
  });

  group('asynchronous runners: one after another, as in Spring Boot', () {
    late List<String> calls;
    late _Flag flag;

    setUp(() {
      calls = [];
      flag = _Flag();
    });

    SpringApplication app(List<BeanDefinition<Object>> runners) =>
        SpringApplication(
          [
            appModule(),
            BeanModule('runners', [
              BeanDefinition<_Flag>(
                name: 'flag',
                create: (_) => flag,
                destroyMethod: (flag) => flag.closed = true,
              ),
              ...runners,
            ]),
          ],
          out: (line) {
            lines.add(line);
            calls.add(line.split(' ').first); // 'Started', 'Application'
          },
        );

    BeanDefinition<Object> later(
      String name,
      int order,
      void Function() body,
    ) => BeanDefinition<_AppRunner>(
      name: name,
      types: const [_AppRunner, ApplicationRunner],
      order: order,
      create: (_) => _AppRunner(body),
    );

    BeanDefinition<Object> async(
      String name,
      int order,
      Future<void> Function() body,
    ) => BeanDefinition<_AsyncRunner>(
      name: name,
      types: const [_AsyncRunner, CommandLineRunner],
      order: order,
      create: (_) => _AsyncRunner(body),
    );

    Future<void> slow(String name) async {
      calls.add('$name start');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      calls.add('$name end');
    }

    test(
      'runAsync: each runner finishes before the next, then it completes',
      () async {
        final context = await app([
          async('first', 1, () => slow('first')),
          later('second', 2, () => calls.add('second')),
          async('third', 3, () => slow('third')),
        ]).runAsync(['--db.url=x'], systemEnvironment: const {});
        addTearDown(context.close);
        // The startup line comes before the runners (Spring Boot: logStarted,
        // then callRunners).
        expect(calls, [
          'Started',
          'first start',
          'first end',
          'second',
          'third start',
          'third end',
        ]);
      },
    );

    test(
      'run: returns at once, the runners still go one after another',
      () async {
        final done = Completer<void>();
        final context = app([
          async('first', 1, () => slow('first')),
          later('second', 2, () {
            calls.add('second');
            done.complete();
          }),
        ]).run(['--db.url=x'], systemEnvironment: const {});
        addTearDown(context.close);
        expect(calls, ['Started', 'first start']); // up to its first await
        await done.future;
        expect(calls, ['Started', 'first start', 'first end', 'second']);
      },
    );

    test('runAsync: a failing runner is reported, the context closed, the '
        'next runners skipped', () async {
      await expectLater(
        app([
          async('migrations', 1, () async {
            await Future<void>.delayed(Duration.zero);
            throw StateError('migration failed');
          }),
          later('next', 2, () => calls.add('next')),
        ]).runAsync(['--db.url=x'], systemEnvironment: const {}),
        throwsA(isA<StateError>()),
      );
      expect(lines.last, 'Application run failed: Bad state: migration failed');
      expect(flag.closed, isTrue);
      expect(calls, isNot(contains('next')));
    });

    test('run: a failing asynchronous runner closes the context and is '
        'rethrown (uncaught, like a failed run)', () async {
      final errors = <Object>[];
      runZonedGuarded(
        () => app([
          async('migrations', 1, () async {
            await Future<void>.delayed(Duration.zero);
            throw StateError('migration failed');
          }),
        ]).run(['--db.url=x'], systemEnvironment: const {}),
        (error, _) => errors.add(error),
      );
      await pumpEventQueue();
      expect(errors, [isA<StateError>()]);
      expect(lines.last, 'Application run failed: Bad state: migration failed');
      expect(flag.closed, isTrue);
    });

    test('run: a synchronous runner that throws fails the start', () {
      expect(
        () =>
            app([later('broken', 1, () => throw StateError('no config'))])
                .run(['--db.url=x'], systemEnvironment: const {}),
        throwsA(isA<StateError>()),
      );
      expect(lines.last, 'Application run failed: Bad state: no config');
      expect(flag.closed, isTrue);
    });

    test('closing the context stops the remaining runners', () async {
      final release = Completer<void>();
      final context = app([
        async('first', 1, () => release.future),
        later('second', 2, () => calls.add('second')),
      ]).run(['--db.url=x'], systemEnvironment: const {});
      context.close();
      release.complete();
      await pumpEventQueue();
      expect(calls, isNot(contains('second')));
    });
  });

  test('ConditionalOnProperty', () {
    final env = StandardEnvironment(systemEnvironment: {})
      ..propertySources.addFirst(
        MapPropertySource('t', {'a': 'on', 'b': 'false'}),
      );
    final ctx = AnnotationConfigApplicationContext([], environment: env);
    final context = _Ctx(ctx, env);
    expect(const ConditionalOnProperty('a').matches(context), isTrue);
    expect(const ConditionalOnProperty('b').matches(context), isFalse);
    expect(
      const ConditionalOnProperty('a', havingValue: 'ON').matches(context),
      isTrue,
    );
    expect(const ConditionalOnProperty('c').matches(context), isFalse);
    expect(
      const ConditionalOnProperty('c', matchIfMissing: true).matches(context),
      isTrue,
    );
  });

  test('logging.level.root sets SpringLog.level', () {
    final saved = SpringLog.level;
    addTearDown(() => SpringLog.level = saved);
    run(['--db.url=x', '--logging.level.root=debug']).close();
    expect(SpringLog.level, SpringLogLevel.debug);
  });

  test('logging.level.<logger>, groups and LOGGING_LEVEL_ variables', () {
    final saved = SpringLog.level;
    addTearDown(() {
      SpringLog.level = saved;
      SpringLog.resetLevels();
    });
    SpringLog.setLevel('stale.from.earlier.run', SpringLogLevel.trace);
    run(
      [
        '--db.url=x',
        '--logging.level.root=warn',
        '--logging.level.neon.checkout=debug',
        '--logging.group.payments=neon.card, neon.cash',
        '--logging.level.payments=trace',
        '--logging.level.neon.catalog=loud', // unknown: ignored
      ],
      env: {
        'LOGGING_LEVEL_NEON_CHECKOUT': 'error', // command line wins
        'LOGGING_LEVEL_NEON_SHIPPING': 'info',
      },
    ).close();
    expect(SpringLog.level, SpringLogLevel.warning);
    expect(SpringLog.configuredLevels, {
      'neon.checkout': SpringLogLevel.debug,
      'neon.card': SpringLogLevel.trace,
      'neon.cash': SpringLogLevel.trace,
      'neon.shipping': SpringLogLevel.info,
    });
    expect(SpringLog.levelOf('neon.card.visa'), SpringLogLevel.trace);
  });

  test('properties win over the command line; initializers run first', () {
    final seen = <String>[];
    final context =
        SpringApplication(
          [appModule()],
          autoConfigurations: [autoModule],
          initializers: [
            (context) => seen.add('active: ${context.isActive}'),
            (context) => context.beanFactory.registerSingleton(
              'fromInitializer',
              'hello',
              types: const [String],
            ),
          ],
          out: lines.add,
        ).run(
          ['--db.url=from-args'],
          systemEnvironment: const {},
          properties: {'db.url': 'from-test', 'db.max-size': 3},
        );
    addTearDown(context.close);
    expect(context.getBean<Pool>().url, 'from-test');
    expect(context.getBean<Pool>().maxSize, 3);
    expect(context.getBeanByName('fromInitializer'), 'hello');
    expect(seen, ['active: false']);
  });
}

class _Ctx implements ConditionContext {
  _Ctx(this.context, this.environment);
  final AnnotationConfigApplicationContext context;
  @override
  final Environment environment;
  @override
  ConfigurableListableBeanFactory get beanFactory => context.beanFactory;
  @override
  BeanDefinitionRegistry get registry =>
      context.beanFactory as BeanDefinitionRegistry;
  @override
  ResourceLoader get resourceLoader => context;
}

class _AppRunner implements ApplicationRunner {
  _AppRunner(this.call);
  final void Function() call;
  @override
  void run(ApplicationArguments args) => call();
}

class _CliRunner implements CommandLineRunner {
  _CliRunner(this.call);
  final void Function() call;
  @override
  void run(List<String> args) => call();
}

class _AsyncRunner implements CommandLineRunner {
  _AsyncRunner(this.body);
  final Future<void> Function() body;
  @override
  Future<void> run(List<String> args) => body();
}

class _Flag {
  bool closed = false;
}
