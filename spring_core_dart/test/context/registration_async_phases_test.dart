import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

class Clock {}

class Greeter {
  Greeter(this.clock);
  final Clock clock;
}

class Repo {}

AnnotationConfigApplicationContext context(
  List<Object> components, {
  Map<String, Object?> properties = const {},
}) {
  final result = AnnotationConfigApplicationContext(
    const [],
    environment: StandardEnvironment(systemEnvironment: {})
      ..propertySources.addFirst(MapPropertySource('test', properties)),
  );
  components.forEach(result.register);
  return result;
}

class GreeterRegistrar implements BeanRegistrar {
  const GreeterRegistrar();

  @override
  void register(BeanRegistry registry, Environment environment) {
    registry.registerBean<Clock>((_) => Clock(), name: 'clock');
    if (environment.getProperty('greeter.enabled') == 'true') {
      registry
        ..registerBean<Greeter>(
          (context) => Greeter(context.dependency<Clock>()),
          name: 'greeter',
          primary: true,
          lazy: true,
          description: 'greets',
          order: 3,
          aliases: const ['hello'],
        )
        ..register(const NestedRegistrar());
    }
  }
}

class NestedRegistrar implements BeanRegistrar {
  const NestedRegistrar();

  @override
  void register(BeanRegistry registry, Environment environment) {
    final name = registry.registerBean<Repo>(
      (_) => Repo(),
      scope: ScopeType.prototype,
    );
    registry.registerAlias(name, 'repo');
  }
}

class RepoSelector implements ImportSelector, EnvironmentAware {
  late Environment environment;

  @override
  void setEnvironment(Environment environment) =>
      this.environment = environment;

  @override
  List<BeanModule> selectImports() => [
    BeanModule('selected', [
      BeanDefinition<Repo>(
        name: environment.getProperty('repo.name') ?? 'repo',
        create: (_) => Repo(),
      ),
    ]),
  ];
}

class ClockRegistrar implements ImportBeanDefinitionRegistrar {
  @override
  void registerBeanDefinitions(BeanDefinitionRegistry registry) {
    if (!registry.containsBeanDefinition('clock')) {
      registry.registerBeanDefinition(
        BeanDefinition<Clock>(name: 'clock', create: (_) => Clock()),
      );
    }
  }
}

class Mailer {
  final received = <String>[];
}

class Recording extends BeanPostProcessor implements PriorityOrdered {
  Recording(this.seen);
  final List<String> seen;
  @override
  int get order => 0;
  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    seen.add(beanName);
    return bean;
  }
}

class OrderedProcessor extends BeanPostProcessor implements Ordered {
  @override
  int get order => 1;
}

class PlainProcessor extends BeanPostProcessor {
  PlainProcessor([this.repo]);
  final Repo? repo;
}

class LoggingFactoryProcessor implements BeanFactoryPostProcessor {
  LoggingFactoryProcessor(this.name, this.log);
  final String name;
  final List<String> log;
  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) =>
      log.add('invoke:$name');
}

class PriorityFactoryProcessor extends LoggingFactoryProcessor
    implements PriorityOrdered {
  PriorityFactoryProcessor(super.name, super.log);
  @override
  int get order => 0;
}

class OrderedFactoryProcessor extends LoggingFactoryProcessor
    implements Ordered {
  OrderedFactoryProcessor(super.name, super.log);
  @override
  int get order => 0;
}

class AddingRegistryProcessor
    implements BeanDefinitionRegistryPostProcessor, PriorityOrdered {
  AddingRegistryProcessor(this.log);
  final List<String> log;
  @override
  int get order => 0;
  @override
  void postProcessBeanDefinitionRegistry(BeanDefinitionRegistry registry) {
    log.add('registry:first');
    registry.registerBeanDefinition(
      BeanDefinition<LateRegistryProcessor>(
        name: 'late',
        types: const [
          LateRegistryProcessor,
          BeanDefinitionRegistryPostProcessor,
          BeanFactoryPostProcessor,
        ],
        create: (_) => LateRegistryProcessor(log),
      ),
    );
  }

  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {}
}

class LateRegistryProcessor implements BeanDefinitionRegistryPostProcessor {
  LateRegistryProcessor(this.log);
  final List<String> log;
  @override
  void postProcessBeanDefinitionRegistry(BeanDefinitionRegistry registry) =>
      log.add('registry:late');
  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) =>
      log.add('factory:late');
}

class Paths implements EmbeddedValueResolverAware {
  late StringValueResolver resolver;
  @override
  void setEmbeddedValueResolver(StringValueResolver resolver) =>
      this.resolver = resolver;
}

class Worker with SmartLifecycle {
  @override
  bool isRunning = false;
  @override
  void start() => isRunning = true;
  @override
  void stop() => isRunning = false;
}

BeanDefinition<Mailer> mailer({Async? async, bool Function(String)? when}) =>
    BeanDefinition<Mailer>(
      name: 'mailer',
      create: (_) => Mailer(),
      eventListeners: [
        EventListenerMethod.of<Mailer, String>(
          'Mailer.on',
          (bean, event) {
            if (event == 'fail') {
              throw StateError('cannot send');
            }
            bean.received.add(event);
            return event == 'reply' ? 'replied' : null;
          },
          condition: when,
          async: async,
        ),
      ],
    );

BeanDefinition<SimpleAsyncTaskExecutor> executor(
  String name,
  SimpleAsyncTaskExecutor executor,
) => BeanDefinition<SimpleAsyncTaskExecutor>(
  name: name,
  types: const [SimpleAsyncTaskExecutor, TaskExecutor],
  create: (_) => executor,
);

BeanDefinition<ApplicationEventMulticaster> multicaster(
  List<Object> errors, {
  TaskExecutor? taskExecutor,
}) => BeanDefinition<ApplicationEventMulticaster>(
  name: 'applicationEventMulticaster',
  types: const [ApplicationEventMulticaster],
  create: (_) => SimpleApplicationEventMulticaster(
    taskExecutor: taskExecutor,
    errorHandler: (error, _) => errors.add(error),
  ),
);

void main() {
  group('programmatic registration', () {
    test('a BeanRegistrar registered on the context', () {
      final ctx = context(
        [const GreeterRegistrar()],
        properties: {'greeter.enabled': 'true'},
      )..refresh();
      final greeter = ctx.getBean<Greeter>();
      expect(greeter.clock, same(ctx.getBean<Clock>()));
      expect(ctx.getBeanByName('hello'), same(greeter));
      final definition = ctx.beanFactory.getBeanDefinition('greeter');
      expect(definition.primary, isTrue);
      expect(definition.lazy, isTrue);
      expect(definition.description, 'greets');
      expect(definition.order, 3);
      // Nested registrar: generated name, prototype scope, alias.
      expect(ctx.containsBeanDefinition('Repo#0'), isTrue);
      expect(ctx.isPrototype('repo'), isTrue);
      expect(ctx.getBeanByName('repo'), isNot(same(ctx.getBeanByName('repo'))));
    });

    test('the registrar reads the environment', () {
      final ctx = context([const GreeterRegistrar()])..refresh();
      expect(ctx.containsBean('clock'), isTrue);
      expect(ctx.containsBean('greeter'), isFalse);
    });

    test('@Import declarations run when the importing class matches', () {
      final ctx = context([
        BeanModule(
          'app',
          [BeanDefinition<Repo>(name: 'repo', create: (_) => Repo())],
          registrars: [
            const ImportDeclaration(GreeterRegistrar.new),
            ImportDeclaration(
              ClockRegistrar.new,
              conditions: const [
                ProfileCondition(['cloud']),
              ],
            ),
          ],
        ),
      ])..refresh();
      expect(ctx.beanFactory.beanDefinitionNames, ['repo', 'clock']);
      expect(
        ctx.beanFactory.getBeanDefinition('clock').source,
        startsWith('BeanRegistrar GreeterRegistrar#'),
      );
    });

    test('an ImportSelector imports modules before the importing one', () {
      final ctx = context(
        [
          BeanModule(
            'app',
            [BeanDefinition<Clock>(name: 'clock', create: (_) => Clock())],
            registrars: [const ImportDeclaration(RepoSelector.new)],
          ),
        ],
        properties: {'repo.name': 'store'},
      )..refresh();
      expect(ctx.beanFactory.beanDefinitionNames, ['store', 'clock']);
    });

    test('an ImportBeanDefinitionRegistrar and registerBean', () {
      final ctx = context([ClockRegistrar()])
        ..registerBean<Greeter>((r) => Greeter(r.dependency<Clock>()))
        ..registerBean<Greeter>(
          (r) => Greeter(r.dependency<Clock>()),
          fallback: true,
        )
        ..refresh();
      expect(ctx.beanFactory.beanDefinitionNames, [
        'clock',
        'Greeter#0',
        'Greeter#1',
      ]);
      expect(ctx.getBean<Greeter>(), same(ctx.getBeanByName('Greeter#0')));
    });

    test('registering after refresh or a wrong type fails clearly', () {
      final ctx = context([])..refresh();
      expect(
        () => ctx.register(const GreeterRegistrar()),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('has been refreshed already'), contains('before')),
          ),
        ),
      );
      expect(
        () => ctx.registerBean<Clock>((_) => Clock(), name: 'clock'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains("register bean 'clock'"),
          ),
        ),
      );
      expect(() => context([42]), throwsArgumentError);
    });
  });

  group('asynchronous events', () {
    test('the multicaster delivers on its task executor', () async {
      final errors = <Object>[];
      final executor = SimpleAsyncTaskExecutor();
      final ctx = context([
        BeanModule('m', [
          mailer(),
          multicaster(errors, taskExecutor: executor),
        ]),
      ])..refresh();
      final received = ctx.getBean<Mailer>().received;
      ctx
        ..publishEvent('hello')
        ..publishEvent('fail');
      expect(received, isEmpty);
      await executor.whenIdle;
      expect(received, ['hello']);
      expect(errors.single, isA<StateError>());
    });

    test('a listener condition fails inside the error handler', () {
      final errors = <Object>[];
      final ctx = context([
        BeanModule('m', [
          mailer(when: (event) => throw ArgumentError(event)),
          multicaster(errors),
        ]),
      ])..refresh();
      final seen = <String>[];
      ctx
        ..addListener<String>(seen.add)
        ..publishEvent('x');
      expect(errors.single, isA<ArgumentError>());
      expect(seen, ['x']);
    });

    test('@Async listeners run on the TaskExecutor bean', () async {
      final errors = <Object>[];
      final pool = SimpleAsyncTaskExecutor();
      final ctx = context([
        BeanModule('m', [
          mailer(async: const Async()),
          executor('pool', pool),
          multicaster(errors),
        ]),
      ])..refresh();
      final replies = <String>[];
      ctx.addListener<String>(replies.add);
      final received = ctx.getBean<Mailer>().received;
      ctx
        ..publishEvent('reply')
        ..publishEvent('fail');
      expect(received, isEmpty);
      await pool.whenIdle;
      // The result is a String event too, delivered asynchronously.
      expect(received, ['reply', 'replied']);
      // The result is published as an event; the failure is handled.
      expect(replies, ['reply', 'fail', 'replied']);
      expect(errors.single, isA<StateError>());
    });

    test('@Async picks the named executor; ignored without any', () async {
      final first = SimpleAsyncTaskExecutor();
      final second = SimpleAsyncTaskExecutor();
      final ctx = context([
        BeanModule('m', [
          mailer(async: const Async('second')),
          executor('first', first),
          executor('second', second),
        ]),
      ])..refresh();
      ctx.publishEvent('a');
      expect(second.activeCount, 1);
      expect(first.activeCount, 0);
      await second.whenIdle;
      expect(ctx.getBean<Mailer>().received, ['a']);

      final sync = context([
        BeanModule('m', [mailer(async: const Async())]),
      ])..refresh();
      sync.publishEvent('b');
      expect(sync.getBean<Mailer>().received, ['b']);

      final missing = context([
        BeanModule('m', [
          mailer(async: const Async('nope')),
          executor('first', first),
        ]),
      ])..refresh();
      expect(
        () => missing.publishEvent('c'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains("No TaskExecutor bean named 'nope'"),
          ),
        ),
      );
    });

    test('SyncTaskExecutor and SimpleAsyncTaskExecutor errors', () async {
      final log = <String>[];
      const SyncTaskExecutor().execute(() => log.add('now'));
      expect(log, ['now']);
      final errors = <Object>[];
      final executor = SimpleAsyncTaskExecutor(
        errorHandler: (e, _) {
          errors.add(e);
        },
      )..execute(() async => throw StateError('later'));
      expect(executor.activeCount, 1);
      await executor.whenIdle;
      expect(errors.single, isA<StateError>());
    });
  });

  test('lifecycle beans are found by their instance type', () {
    final ctx = context([
      BeanModule('m', [
        BeanDefinition<Object>(
          name: 'worker',
          types: const [Object],
          create: (_) => Worker(),
        ),
      ]),
    ])..refresh();
    final worker = ctx.getBeanByName('worker') as Worker;
    expect(worker.isRunning, isTrue);
    ctx.close();
    expect(worker.isRunning, isFalse);
  });

  group('post-processor phases', () {
    test('bean post-processors are created phase by phase', () {
      final seen = <String>[];
      final ctx = context([
        BeanModule('m', [
          BeanDefinition<PlainProcessor>(
            name: 'plain',
            types: const [PlainProcessor, BeanPostProcessor],
            create: (_) => PlainProcessor(),
          ),
          BeanDefinition<OrderedProcessor>(
            name: 'ordered',
            types: const [OrderedProcessor, BeanPostProcessor, Ordered],
            create: (_) => OrderedProcessor(),
          ),
          BeanDefinition<Recording>(
            name: 'recording',
            types: const [
              Recording,
              BeanPostProcessor,
              PriorityOrdered,
              Ordered,
            ],
            create: (_) => Recording(seen),
          ),
        ]),
      ])..refresh();
      expect(seen, containsAllInOrder(['ordered', 'plain']));
      expect(seen, isNot(contains('recording')));
      ctx.close();
    });

    test('factory post-processors are created phase by phase', () {
      final log = <String>[];
      BeanDefinition<T> processor<T extends LoggingFactoryProcessor>(
        String name,
        T Function() create,
        List<Type> types,
      ) => BeanDefinition<T>(
        name: name,
        types: [T, BeanFactoryPostProcessor, ...types],
        create: (_) {
          log.add('create:$name');
          return create();
        },
      );
      context([
        BeanModule('m', [
          processor('plain', () => LoggingFactoryProcessor('plain', log), []),
          processor('ordered', () => OrderedFactoryProcessor('ordered', log), [
            Ordered,
          ]),
          processor(
            'priority',
            () => PriorityFactoryProcessor('priority', log),
            [PriorityOrdered, Ordered],
          ),
          BeanDefinition<AddingRegistryProcessor>(
            name: 'first',
            types: const [
              AddingRegistryProcessor,
              BeanDefinitionRegistryPostProcessor,
              BeanFactoryPostProcessor,
              PriorityOrdered,
              Ordered,
            ],
            create: (_) => AddingRegistryProcessor(log),
          ),
        ]),
      ]).refresh();
      expect(log, [
        'registry:first',
        'registry:late',
        'factory:late',
        'create:priority',
        'invoke:priority',
        'create:ordered',
        'invoke:ordered',
        'create:plain',
        'invoke:plain',
      ]);
    });

    test('a bean created for a post-processor is reported', () {
      final records = <SpringLogRecord>[];
      final stop = SpringLog.listen(records.add);
      SpringLog.setLevel('spring_core_dart.context', SpringLogLevel.info);
      addTearDown(() {
        stop();
        SpringLog.resetLevels();
      });
      context([
        BeanModule('m', [
          BeanDefinition<Repo>(name: 'repo', create: (_) => Repo()),
          BeanDefinition<PlainProcessor>(
            name: 'auditor',
            types: const [PlainProcessor, BeanPostProcessor],
            create: (r) => PlainProcessor(r.dependency<Repo>()),
          ),
        ]),
      ]).refresh();
      expect(
        records.map((r) => r.message),
        contains(
          allOf(
            contains(
              "Bean 'repo' of type [Repo] is not eligible for getting "
              'processed by all BeanPostProcessors',
            ),
            contains('currently created BeanPostProcessor [auditor]'),
          ),
        ),
      );
    });
  });

  test('EmbeddedValueResolverAware resolves placeholders and SpEL', () {
    final ctx = context(
      [
        BeanModule('m', [
          BeanDefinition<Paths>(name: 'paths', create: (_) => Paths()),
        ]),
      ],
      properties: {'app.home': '/srv'},
    )..refresh();
    final resolve = ctx.getBean<Paths>().resolver;
    expect(resolve(r'${app.home}'), '/srv');
    expect(resolve(r"#{'${app.home}' + '/cache'}"), '/srv/cache');
    expect(resolve('#{1 + 2}'), '3');
    expect(resolve('#{null}'), '');
  });
}
