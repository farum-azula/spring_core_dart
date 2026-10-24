import 'dart:async';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart/src/context/shutdown_hook.dart';
import 'package:test/test.dart';

final log = <String>[];

AnnotationConfigApplicationContext ctx(List<BeanDefinition<Object>> defs) =>
    AnnotationConfigApplicationContext([
      BeanModule('m', defs),
    ], environment: StandardEnvironment(systemEnvironment: {}));

class Ready {
  const Ready(this.from);
  final String from;
}

class Publisher {}

class Listener {
  final seen = <String>[];
}

class Initializer implements SmartInitializingSingleton {
  Initializer(this.name, this.publisher);
  final String name;
  final ApplicationEventPublisher? publisher;
  @override
  void afterSingletonsInstantiated() {
    log.add('sis:$name');
    publisher?.publishEvent(Ready(name));
  }
}

class Slow with SmartLifecycle {
  Slow(this.name);
  final String name;
  Completer<void>? later;
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

  @override
  void stopWithCallback(void Function() callback) {
    final later = this.later = Completer<void>();
    later.future.then((_) {
      stop();
      callback();
    });
  }
}

class SlowRegistrar implements BeanRegistrar {
  const SlowRegistrar(this.value);
  final String value;
  @override
  void register(BeanRegistry registry, Environment environment) =>
      registry.registerBean<String>((_) => value, name: 'x');
}

BeanDefinition<Listener> listener({bool lazy = false}) =>
    BeanDefinition<Listener>(
      name: 'listener',
      lazy: lazy,
      create: (_) => Listener(),
      eventListeners: [
        EventListenerMethod.of<Listener, Ready>(
          'Listener.onReady',
          (bean, event) => bean.seen.add(event.from),
        ),
      ],
    );

void main() {
  setUp(log.clear);

  group('@EventListener methods are registered after the singletons', () {
    test('an event published from a @PostConstruct while the listener bean '
        'is being created does not fail the refresh', () {
      // The listener depends on the publisher, so the publisher's
      // @PostConstruct runs while the listener is being created.
      final context = ctx([
        BeanDefinition<Listener>(
          name: 'listener',
          create: (r) {
            r.dependency<Publisher>();
            return Listener();
          },
          dependencies: const [Dependency(Publisher)],
          eventListeners: [
            EventListenerMethod.of<Listener, Ready>(
              'Listener.onReady',
              (bean, event) => bean.seen.add(event.from),
            ),
          ],
        ),
        BeanDefinition<Publisher>(
          name: 'publisher',
          create: (_) => Publisher(),
          postConstruct: (_) => log.add('published'),
        ),
      ]);
      // A @PostConstruct publishing through the context.
      context.beanFactory.addBeanPostProcessor(_PublishOnInit(context));
      expect(context.refresh, returnsNormally);
      expect(log, contains('published'));
      // Like Spring, the startup event did not reach the @EventListener.
      expect(context.getBean<Listener>().seen, isEmpty);
      context
        ..publishEvent(const Ready('later'))
        ..close();
      expect(log, isNot(contains('failed')));
    });

    test('a bean listening to the event of its own @PostConstruct', () {
      late AnnotationConfigApplicationContext context;
      context = ctx([
        BeanDefinition<Listener>(
          name: 'listener',
          create: (_) => Listener(),
          postConstruct: (_) => context.publishEvent(const Ready('init')),
          eventListeners: [
            EventListenerMethod.of<Listener, Ready>(
              'Listener.onReady',
              (bean, event) => bean.seen.add(event.from),
            ),
          ],
        ),
      ]);
      expect(context.refresh, returnsNormally);
      expect(context.getBean<Listener>().seen, isEmpty);
      context.publishEvent(const Ready('after'));
      expect(context.getBean<Listener>().seen, ['after']);
      context.close();
    });

    test('a SmartInitializingSingleton event reaches the @EventListener '
        'methods (registered before the callbacks)', () {
      late AnnotationConfigApplicationContext context;
      context = ctx([
        BeanDefinition<Initializer>(
          name: 'init',
          create: (_) => Initializer('init', context),
        ),
        listener(),
      ]);
      context.refresh();
      expect(context.getBean<Listener>().seen, ['init']);
      context.close();
    });

    test('a lazy listener bean is created by the first event', () {
      final context = ctx([listener(lazy: true)])..refresh();
      expect(context.beanFactory.containsSingleton('listener'), isFalse);
      context.publishEvent(const Ready('x'));
      expect(context.getBean<Listener>().seen, ['x']);
      context.close();
    });
  });

  test('SmartInitializingSingleton callbacks run in bean definition order, '
      'not creation order', () {
    final context = ctx([
      BeanDefinition<Initializer>(
        name: 'a',
        create: (r) {
          r.dependency<Initializer>(qualifier: 'b');
          return Initializer('a', null);
        },
        dependencies: const [Dependency(Initializer, qualifier: 'b')],
      ),
      BeanDefinition<Initializer>(
        name: 'b',
        create: (_) => Initializer('b', null),
      ),
    ])..refresh();
    // b is created first (a depends on it); Spring iterates beanNames.
    expect(log, ['sis:a', 'sis:b']);
    context.close();
  });

  group('registerBean / BeanRegistrar sources', () {
    test('two registerBean calls with one name are an override', () {
      final context = ctx([])
        ..registerBean<String>((_) => 'first', name: 'x')
        ..registerBean<String>((_) => 'second', name: 'x');
      expect(context.refresh, throwsA(isA<BeanDefinitionOverrideException>()));
    });

    test('with overriding allowed the second registerBean wins', () {
      final context = ctx([])
        ..registerBean<String>((_) => 'first', name: 'x')
        ..registerBean<String>((_) => 'second', name: 'x');
      (context.beanFactory as DefaultListableBeanFactory)
              .allowBeanDefinitionOverriding =
          true;
      context.refresh();
      expect(context.getBeanByName('x'), 'second');
      context.close();
    });

    test('two BeanRegistrars registering one name are an override', () {
      final context = ctx([])
        ..register(const SlowRegistrar('a'))
        ..register(const SlowRegistrar('b'));
      (context.beanFactory as DefaultListableBeanFactory)
              .allowBeanDefinitionOverriding =
          true;
      context.refresh();
      expect(context.getBeanByName('x'), 'b');
      context.close();
    });
  });

  group('restart() and stop()+start() with a pending stop callback', () {
    test('restart starts a bean once its stop callback fires', () async {
      final slow = Slow('slow');
      final context = ctx([
        BeanDefinition<Slow>(
          name: 'slow',
          types: const [Slow, SmartLifecycle, Lifecycle],
          create: (_) => slow,
        ),
      ])..refresh();
      expect(log, ['slow:start']);
      context.restart();
      // Still stopping: not skipped as running, not started twice.
      expect(log, ['slow:start']);
      slow.later!.complete();
      await pumpEventQueue();
      expect(log, ['slow:start', 'slow:stop', 'slow:start']);
      expect(slow.isRunning, isTrue);
      context.close();
    });

    test('stop() then start() starts it after the callback', () async {
      final slow = Slow('slow');
      final context = ctx([
        BeanDefinition<Slow>(
          name: 'slow',
          types: const [Slow, SmartLifecycle, Lifecycle],
          create: (_) => slow,
        ),
      ])..refresh();
      context
        ..stop()
        ..start();
      slow.later!.complete();
      await pumpEventQueue();
      expect(log, ['slow:start', 'slow:stop', 'slow:start']);
      expect(slow.isRunning, isTrue);
      context.close();
    });

    test('a stop after the restart cancels the pending start', () async {
      final slow = Slow('slow');
      final context = ctx([
        BeanDefinition<Slow>(
          name: 'slow',
          types: const [Slow, SmartLifecycle, Lifecycle],
          create: (_) => slow,
        ),
      ])..refresh();
      context
        ..restart()
        ..stop();
      slow.later!.complete();
      await pumpEventQueue();
      expect(log, ['slow:start', 'slow:stop']);
      expect(slow.isRunning, isFalse);
      context.close();
    });
  });

  group('registerShutdownHook', () {
    final original = shutdownHookPlatform;
    tearDown(() => shutdownHookPlatform = original);

    test('closes with closeAsync: async stops and @PreDestroy finish before '
        'the exit', () async {
      void Function(int)? signal;
      final exited = Completer<int>();
      shutdownHookPlatform = (
        watch: (onSignal) {
          signal = onSignal;
          return () {};
        },
        exit: exited.complete,
      );
      final slow = Slow('slow');
      final destroyed = Completer<void>();
      final context = ctx([
        BeanDefinition<Slow>(
          name: 'slow',
          types: const [Slow, SmartLifecycle, Lifecycle],
          create: (_) => slow,
          preDestroy: (_) async {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            log.add('slow:destroyed');
            destroyed.complete();
          },
        ),
      ]);
      await context.refreshAsync();
      context.registerShutdownHook();
      signal!(143);
      await pumpEventQueue();
      expect(exited.isCompleted, isFalse);
      slow.later!.complete();
      expect(await exited.future, 143);
      expect(log, ['slow:start', 'slow:stop', 'slow:destroyed']);
      expect(context.isClosed, isTrue);
    });
  });
}

// Publishes an event from every bean's init, like a @PostConstruct calling
// publishEvent.
final class _PublishOnInit extends BeanPostProcessor {
  _PublishOnInit(this.context);
  final ApplicationEventPublisher context;
  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    if (bean is Publisher) {
      context.publishEvent(const Ready('publisher'));
    }
    return bean;
  }
}
