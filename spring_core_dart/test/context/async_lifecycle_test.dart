import 'dart:async';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

final log = <String>[];

AnnotationConfigApplicationContext ctx(List<BeanDefinition<Object>> defs) =>
    AnnotationConfigApplicationContext([
      BeanModule('m', defs),
    ], environment: StandardEnvironment(systemEnvironment: {}));

Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 2));

/// Asynchronous `afterPropertiesSet` and `destroy`.
class Db implements InitializingBean, DisposableBean {
  Db(this.name, {this.failInit = false});
  final String name;
  final bool failInit;
  bool open = false;

  @override
  Future<void> afterPropertiesSet() async {
    await tick();
    if (failInit) {
      throw StateError('$name cannot open');
    }
    open = true;
    log.add('$name:init');
  }

  @override
  Future<void> destroy() async {
    await tick();
    open = false;
    log.add('$name:destroy');
  }
}

class Repo {
  Repo(this.db);
  final Db db;
}

BeanDefinition<Db> db(
  String name, {
  bool failInit = false,
  bool lazy = false,
}) => BeanDefinition<Db>(
  name: name,
  lazy: lazy,
  types: const [Db, InitializingBean, DisposableBean],
  create: (_) => Db(name, failInit: failInit),
);

BeanDefinition<Repo> repo() => BeanDefinition<Repo>(
  name: 'repo',
  dependencies: const [Dependency(Db)],
  create: (r) => Repo(r.dependency<Db>()),
  preDestroy: (repo) async {
    await tick();
    log.add('repo:destroy(db open: ${repo.db.open})');
  },
);

class Server with SmartLifecycle {
  Server(this.name, {this.phase = 0, this.isAutoStartup = true});
  final String name;
  @override
  final int phase;
  @override
  final bool isAutoStartup;
  @override
  bool isRunning = false;
  @override
  void start() {
    isRunning = true;
    log.add('$name:start');
  }

  @override
  void stop() {
    isRunning = false;
    log.add('$name:stop');
  }
}

/// Calls the stop callback later (after [delay]), or never.
class SlowServer extends Server {
  SlowServer(super.name, {super.phase, this.delay});
  final Duration? delay;

  @override
  void stopWithCallback(void Function() callback) {
    stop();
    if (delay case final delay?) {
      Future<void>.delayed(delay, () {
        log.add('$name:stopped');
        callback();
      });
    }
  }
}

class Consumer extends Server {
  Consumer(this.broker) : super('consumer');
  final Server broker;
}

class PlainLifecycle implements Lifecycle {
  @override
  bool isRunning = false;
  @override
  void start() {
    isRunning = true;
    log.add('plain:start');
  }

  @override
  void stop() {
    isRunning = false;
    log.add('plain:stop');
  }
}

BeanDefinition<Server> server(
  String name, {
  int phase = 0,
  bool autoStartup = true,
  Duration? stopDelay,
  bool slow = false,
}) => BeanDefinition<Server>(
  name: name,
  types: const [Server, SmartLifecycle, Lifecycle],
  create: (_) => slow
      ? SlowServer(name, phase: phase, delay: stopDelay)
      : Server(name, phase: phase, isAutoStartup: autoStartup),
);

class Recorder implements GenericApplicationListener {
  Recorder(this.name);
  final String name;
  @override
  bool supportsEvent(Object event) =>
      event is PayloadApplicationEvent && event.payload is String;
  @override
  void onApplicationEvent(Object event) =>
      log.add('$name:${(event as PayloadApplicationEvent).payload}');
}

class SmartRecorder with SmartApplicationListener {
  @override
  bool supportsEventType(Type eventType) => eventType == ContextRefreshedEvent;
  @override
  void onApplicationEvent(Object event) =>
      log.add('smart:${event.runtimeType}');
}

class Handler {
  Future<Object?> handle(String event) async {
    await tick();
    if (event == 'fail') {
      throw StateError('cannot handle');
    }
    return event.length;
  }
}

/// Publishes from a bean factory post-processor, before any listener is
/// registered (an early event).
class EarlyPublisher implements BeanFactoryPostProcessor {
  EarlyPublisher(this.publisher);
  final ApplicationEventPublisher publisher;
  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) =>
      publisher.publishEvent('early');
}

void main() {
  late SpringLogHandler savedHandler;
  final logged = <SpringLogRecord>[];
  setUp(() {
    log.clear();
    logged.clear();
    savedHandler = SpringLog.handler;
    SpringLog.handler = logged.add;
  });
  tearDown(() => SpringLog.handler = savedHandler);

  group('refreshAsync', () {
    test(
      'awaits @PostConstruct, afterPropertiesSet and the init method in '
      'order, before the lifecycle start and ContextRefreshedEvent',
      () async {
        final c = ctx([
          BeanDefinition<Db>(
            name: 'db',
            types: const [Db, InitializingBean, DisposableBean],
            create: (_) => Db('db'),
            postConstruct: (db) async {
              await tick();
              log.add('db:postConstruct');
            },
            initMethod: (db) async {
              await tick();
              log.add('db:initMethod(open: ${db.open})');
            },
          ),
          server('server'),
        ])..addListener<ContextRefreshedEvent>((_) => log.add('refreshed'));
        await c.refreshAsync();
        expect(log, [
          'db:postConstruct',
          'db:init',
          'db:initMethod(open: true)',
          'server:start',
          'refreshed',
        ]);
        expect(c.isActive, isTrue);
        expect(c.getBean<Db>().open, isTrue);
      },
    );

    test('runAsync refreshes asynchronously', () async {
      final c = await ApplicationContext.runAsync([
        BeanModule('m', [db('db')]),
      ], environment: StandardEnvironment(systemEnvironment: {}));
      expect(c.getBean<Db>().open, isTrue);
      await c.closeAsync();
    });

    test('refresh() fails for an asynchronous init callback', () {
      final c = ctx([db('db')]);
      expect(
        c.refresh,
        throwsA(
          isA<BeanCreationException>()
              .having((e) => e.beanName, 'beanName', 'db')
              .having((e) => '$e', 'message', contains('refreshAsync()')),
        ),
      );
      expect(c.isActive, isFalse);
    });

    test('a failing asynchronous init fails the refresh naming the bean; the '
        'created singletons are destroyed (asynchronously too)', () async {
      final c = ctx([db('first'), db('second', failInit: true)]);
      await expectLater(
        c.refreshAsync(),
        throwsA(
          isA<BeanCreationException>().having(
            (e) => e.beanName,
            'beanName',
            'second',
          ),
        ),
      );
      expect(c.isActive, isFalse);
      // `second` was registered before its init failed, so it is
      // destroyed too (its resources opened so far are released).
      expect(log.where((e) => !e.startsWith('db:')), [
        'first:init',
        'second:destroy',
        'first:destroy',
      ]);
    });

    test('a bean created after the refresh needs synchronous init', () async {
      final c = ctx([db('db', lazy: true)]);
      await c.refreshAsync();
      expect(
        () => c.getBean<Db>(),
        throwsA(
          isA<BeanCreationException>().having(
            (e) => '$e',
            'message',
            contains('lazy, prototype, scoped'),
          ),
        ),
      );
    });
  });

  group('closeAsync', () {
    test('awaits destroy callbacks, dependents first', () async {
      final c = ctx([db('db'), repo()]);
      await c.refreshAsync();
      log.clear();
      final closing = c.closeAsync();
      expect(c.isActive, isTrue, reason: 'closing');
      await closing;
      expect(log, ['repo:destroy(db open: true)', 'db:destroy']);
      expect(c.isClosed, isTrue);
    });

    test(
      'close() does not wait: the asynchronous callback is logged',
      () async {
        final c = ctx([db('db')]);
        await c.refreshAsync();
        log.clear();
        c.close();
        expect(c.isClosed, isTrue);
        expect(log, isEmpty);
        expect(
          logged.map((r) => '${r.message}: ${r.error}'),
          contains(allOf(contains("bean 'db'"), contains('closeAsync()'))),
        );
        expect(c.beanFactory.destructionErrors, hasLength(1));
        await tick();
        expect(log, ['db:destroy'], reason: 'the callback still runs');
      },
    );

    test('waits for SmartLifecycle stop callbacks per phase, at most the '
        'timeout of the phase', () async {
      final c = ctx([
        server(
          'slow',
          phase: 10,
          slow: true,
          stopDelay: const Duration(milliseconds: 20),
        ),
        server('stuck', phase: 0, slow: true),
        server('quick', phase: 0),
        BeanDefinition<LifecycleProcessor>(
          name: AnnotationConfigApplicationContext.lifecycleProcessorBeanName,
          create: (r) => DefaultLifecycleProcessor(
            r.dependency<ConfigurableListableBeanFactory>(),
            timeoutPerShutdownPhase: const Duration(seconds: 5),
            timeoutsForShutdownPhases: {0: const Duration(milliseconds: 30)},
          ),
        ),
      ]);
      await c.refreshAsync();
      log.clear();
      final watch = Stopwatch()..start();
      await c.closeAsync();
      expect(log, ['slow:stop', 'slow:stopped', 'quick:stop', 'stuck:stop']);
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(45));
      expect(
        logged.map((r) => r.message),
        contains(
          'Failed to shut down 1 bean with phase value 0 within timeout of '
          '30ms: [stuck]',
        ),
      );
      expect(c.isClosed, isTrue);
    });
  });

  group('lifecycle dependencies', () {
    test('a dependency starts before its dependent and stops after it, '
        'whatever the phase', () {
      final c = ctx([
        BeanDefinition<Consumer>(
          name: 'consumer',
          types: const [Consumer, Server, SmartLifecycle, Lifecycle],
          dependencies: const [Dependency(Server, name: 'broker')],
          create: (r) => Consumer(r.dependency<Server>(name: 'broker')),
        ),
        server('broker', phase: 100),
      ])..refresh();
      expect(log, ['broker:start', 'consumer:start']);
      log.clear();
      c.close();
      expect(log, ['consumer:stop', 'broker:stop']);
    });

    test('at refresh a plain Lifecycle dependency of an auto-startup bean is '
        'started, a SmartLifecycle one that is not auto-startup is not', () {
      final c = ctx([
        BeanDefinition<Consumer>(
          name: 'consumer',
          types: const [Consumer, Server, SmartLifecycle, Lifecycle],
          dependsOn: const ['plain', 'manual'],
          dependencies: const [Dependency(Server, name: 'manual')],
          create: (r) => Consumer(r.dependency<Server>(name: 'manual')),
        ),
        server('manual', autoStartup: false),
        BeanDefinition<PlainLifecycle>(
          name: 'plain',
          types: const [PlainLifecycle, Lifecycle],
          create: (_) => PlainLifecycle(),
        ),
      ])..refresh();
      expect(log, ['plain:start', 'consumer:start']);
      log.clear();
      c.start();
      expect(log, ['manual:start']);
    });

    test(
      'a failing ContextRefreshedEvent listener stops the started beans',
      () {
        final c = ctx([server('a'), server('b', phase: 1)])
          ..addListener<ContextRefreshedEvent>(
            (_) => throw StateError('not ready'),
          );
        expect(c.refresh, throwsStateError);
        expect(log, ['a:start', 'b:start', 'b:stop', 'a:stop']);
        expect(c.isActive, isFalse);
      },
    );

    test('a bean failing to start stops the beans started before', () {
      final c = ctx([
        server('a'),
        BeanDefinition<Server>(
          name: 'broken',
          types: const [Server, SmartLifecycle, Lifecycle],
          create: (_) => _BrokenServer(),
        ),
      ]);
      // Like Spring: wrapped in an ApplicationContextException.
      expect(
        c.refresh,
        throwsA(
          isA<ApplicationContextException>()
              .having((e) => e.message, 'message', contains("'broken'"))
              .having((e) => e.cause, 'cause', isA<StateError>()),
        ),
      );
      expect(log, ['a:start', 'a:stop']);
    });
  });

  group('listeners', () {
    test('GenericApplicationListener and SmartApplicationListener beans '
        'receive events, also behind another declared type', () {
      final c = ctx([
        BeanDefinition<Recorder>(
          name: 'recorder',
          types: const [Recorder, GenericApplicationListener],
          create: (_) => Recorder('recorder'),
        ),
        // Like a `@Bean Object hidden()` method: the type says nothing.
        BeanDefinition<Object>(
          name: 'hidden',
          create: (_) => Recorder('hidden'),
        ),
        BeanDefinition<SmartRecorder>(
          name: 'smart',
          create: (_) => SmartRecorder(),
        ),
      ])..refresh();
      c.publishEvent('hello');
      expect(log, [
        'smart:ContextRefreshedEvent',
        'recorder:hello',
        'hidden:hello',
      ]);
      c.close();
      c.publishEvent('after');
      expect(log, hasLength(3));
    });

    test('a listener registered as a singleton receives events once', () {
      final listener = Recorder('singleton');
      final c = ctx([])
        ..beanFactory.registerSingleton('audit', listener)
        ..addApplicationListener(listener)
        ..refresh();
      c.publishEvent('hello');
      expect(log, ['singleton:hello']);
    });

    test('a prototype GenericApplicationListener bean is warned about', () {
      final c = ctx([
        BeanDefinition<Recorder>(
          name: 'proto',
          scope: ScopeType.prototype,
          create: (_) => Recorder('proto'),
        ),
      ])..refresh();
      c.getBean<Recorder>();
      c.publishEvent('hello');
      expect(log, isEmpty);
      expect(
        logged.map((r) => r.message),
        contains(
          contains("Bean 'proto' implements GenericApplicationListener"),
        ),
      );
    });

    test('a Future-returning @EventListener republishes its result and routes '
        'errors to the error handler', () async {
      final errors = <Object>[];
      final c = ctx([
        BeanDefinition<Handler>(
          name: 'handler',
          create: (_) => Handler(),
          eventListeners: [
            EventListenerMethod.of<Handler, String>(
              'Handler.handle',
              (bean, event) => bean.handle(event),
            ),
          ],
        ),
        BeanDefinition<ApplicationEventMulticaster>(
          name: AnnotationConfigApplicationContext
              .applicationEventMulticasterBeanName,
          create: (_) => SimpleApplicationEventMulticaster(
            errorHandler: (error, _) => errors.add(error),
          ),
        ),
      ])..refresh();
      final lengths = <int>[];
      c.addListener<int>(lengths.add);
      c.publishEvent('hello');
      c.publishEvent('fail');
      expect(lengths, isEmpty, reason: 'published when the Future completes');
      await tick();
      await tick();
      expect(lengths, [5]);
      expect(errors, [isA<StateError>()]);
    });

    test('without an error handler the asynchronous error is logged', () async {
      final c = ctx([
        BeanDefinition<Handler>(
          name: 'handler',
          create: (_) => Handler(),
          eventListeners: [
            EventListenerMethod.of<Handler, String>(
              'Handler.handle',
              (bean, event) => bean.handle(event),
            ),
          ],
        ),
      ])..refresh();
      c.publishEvent('fail');
      await tick();
      await tick();
      expect(
        logged
            .where((r) => r.level == SpringLogLevel.error)
            .map((r) => '${r.message}: ${r.error}'),
        [
          'Unexpected error occurred in asynchronous listener: Bad state: cannot handle',
        ],
      );
    });

    test('early events are replayed once the listeners are registered; events '
        'published while singletons are created are delivered right away', () {
      final c = ctx([
        BeanDefinition<EarlyPublisher>(
          name: 'earlyPublisher',
          types: const [EarlyPublisher, BeanFactoryPostProcessor],
          create: (r) =>
              EarlyPublisher(r.dependency<ApplicationEventPublisher>()),
        ),
        BeanDefinition<Recorder>(
          name: 'recorder',
          create: (_) => Recorder('recorder'),
        ),
        BeanDefinition<Object>(
          name: 'publisher',
          create: (r) {
            r.dependency<ApplicationEventPublisher>().publishEvent('during');
            log.add('publisher:created');
            return Object();
          },
        ),
      ])..addApplicationListener(Recorder('programmatic'));
      c.refresh();
      expect(log, [
        'programmatic:early',
        'programmatic:during',
        'recorder:during',
        'publisher:created',
      ]);
    });
  });
}

class _BrokenServer extends Server {
  _BrokenServer() : super('broken', phase: 1);
  @override
  void start() => throw StateError('cannot start');
}
