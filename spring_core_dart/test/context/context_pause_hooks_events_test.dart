import 'dart:async';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart/src/context/shutdown_hook.dart';
import 'package:test/test.dart';

final log = <String>[];

AnnotationConfigApplicationContext ctx(
  List<BeanDefinition<Object>> defs, {
  ApplicationContext? parent,
}) => AnnotationConfigApplicationContext(
  [BeanModule('m', defs)],
  parent: parent,
  environment: StandardEnvironment(systemEnvironment: {}),
);

class Part with SmartLifecycle {
  Part(
    this.name, {
    this.isPauseable = true,
    this.isAutoStartup = true,
    this.later,
  });
  final String name;
  @override
  final bool isPauseable;
  @override
  final bool isAutoStartup;
  final Completer<void>? later;
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
    final later = this.later;
    if (later == null) {
      super.stopWithCallback(callback);
      return;
    }
    later.future.then((_) {
      stop();
      callback();
    });
  }
}

class Plain implements Lifecycle {
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

BeanDefinition<Part> part(Part instance) => BeanDefinition<Part>(
  name: instance.name,
  types: const [Part, SmartLifecycle, Lifecycle],
  create: (_) => instance,
);

class Order {
  Order(this.id);
  final int id;
}

class Audit {
  final seen = <PayloadApplicationEvent<Order>>[];
  void on(PayloadApplicationEvent<Order> event) => seen.add(event);
}

class Widget {}

class WidgetFactory extends FactoryBean<Widget> {
  final orders = <int>[];
  @override
  Widget getObject() => Widget();
  void on(Order order) => orders.add(order.id);
}

class Experimental {
  const Experimental();
}

class OnNotExperimental implements Condition {
  const OnNotExperimental();
  static final seen = <String?>[];
  @override
  bool matches(ConditionContext context) {
    seen.add(context.definition?.name);
    final annotations = context.definition?.annotations ?? const [];
    return annotations.whereType<Experimental>().isEmpty;
  }
}

class HookContext extends AnnotationConfigApplicationContext {
  HookContext(super.modules)
    : super(environment: StandardEnvironment(systemEnvironment: {}));

  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {
    log.add('postProcessBeanFactory(a: ${containsBeanDefinition('a')})');
    beanFactory.registerSingleton('extra', 'extra', types: const [String]);
  }

  @override
  void onRefresh() => log.add('onRefresh');

  @override
  void onClose() => log.add('onClose(closed: $isClosed)');
}

BeanDefinition<Object> logged(String name) => BeanDefinition<Object>(
  name: name,
  create: (_) {
    log.add('$name:create');
    return Object();
  },
  preDestroy: (_) => log.add('$name:destroy'),
);

void main() {
  setUp(log.clear);

  group('pause() / restart()', () {
    late AnnotationConfigApplicationContext context;
    late List<String> events;

    setUp(() {
      events = [];
      context = ctx([
        part(Part('web')),
        part(Part('keeper', isPauseable: false)),
        part(Part('manual', isAutoStartup: false)),
        BeanDefinition<Plain>(
          name: 'plain',
          types: const [Plain, Lifecycle],
          create: (_) => Plain(),
        ),
      ]);
      context
        ..addListener<ContextPausedEvent>((_) => events.add('paused'))
        ..addListener<ContextStoppedEvent>((_) => events.add('stopped'))
        ..addListener<ContextRestartedEvent>((_) => events.add('restarted'))
        ..addListener<ContextStartedEvent>((_) => events.add('started'))
        ..refresh()
        ..start();
      log.clear();
    });

    tearDown(() => context.close());

    test('pause stops all but the non-pauseable smart beans', () {
      context.pause();
      expect(log, unorderedEquals(['web:stop', 'manual:stop', 'plain:stop']));
      expect(context.getBean<Part>(qualifier: 'keeper').isRunning, isTrue);
      expect(context.isRunning, isFalse);
      // A ContextPausedEvent is a ContextStoppedEvent.
      expect(events, ['started', 'paused', 'stopped']);
    });

    test('restart starts the auto-startup beans again', () {
      context.pause();
      log.clear();
      context.restart();
      expect(log, ['web:start']);
      expect(context.getBean<Part>(qualifier: 'manual').isRunning, isFalse);
      expect(context.getBean<Plain>().isRunning, isFalse);
      expect(context.isRunning, isTrue);
      expect(events.sublist(3), ['restarted', 'started']);
    });

    test('restart while running stops the pauseable beans first', () {
      context.restart();
      expect(log, containsAllInOrder(['web:stop', 'web:start']));
      expect(log, isNot(contains('keeper:stop')));
      expect(log, contains('manual:stop'));
      expect(log.where((e) => e.endsWith(':start')), ['web:start']);
    });

    test('pause after stop leaves the beans alone', () {
      context.stop();
      log.clear();
      context.pause();
      expect(log, isEmpty);
      expect(events.last, 'stopped');
      expect(events, contains('paused'));
    });
  });

  test('pauseAsync waits for the stop callbacks before the event', () async {
    final later = Completer<void>();
    final context = ctx([part(Part('slow', later: later))]);
    final events = <String>[];
    context
      ..addListener<ContextPausedEvent>((_) => events.add('paused'))
      ..refresh();
    final paused = context.pauseAsync();
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
    later.complete();
    await paused;
    expect(log, ['slow:start', 'slow:stop']);
    expect(events, ['paused']);
    context.close();
  });

  group('template hooks', () {
    test('postProcessBeanFactory, onRefresh and onClose run in order', () {
      final context = HookContext([
        BeanModule('m', [logged('a')]),
      ])..refresh();
      expect(context.getBeanByName('extra'), 'extra');
      context.close();
      expect(log, [
        'postProcessBeanFactory(a: true)',
        'onRefresh',
        'a:create',
        'a:destroy',
        'onClose(closed: false)',
      ]);
      expect(context.isClosed, isTrue);
    });

    test('closeAsync calls onClose too', () async {
      final context = HookContext([
        BeanModule('m', [logged('a')]),
      ])..refresh();
      await context.closeAsync();
      expect(log.last, 'onClose(closed: false)');
    });
  });

  group('registerShutdownHook', () {
    late void Function(int)? signal;
    late List<String> calls;
    final original = shutdownHookPlatform;

    setUp(() {
      signal = null;
      calls = [];
      shutdownHookPlatform = (
        watch: (onSignal) {
          calls.add('watch');
          signal = onSignal;
          return () => calls.add('unwatch');
        },
        exit: (code) => calls.add('exit $code'),
      );
    });

    tearDown(() => shutdownHookPlatform = original);

    test('a signal closes the context, then ends the process', () async {
      final context = ctx([logged('a')])
        ..refresh()
        ..registerShutdownHook()
        ..registerShutdownHook();
      signal!(143);
      // closeAsync: the exit comes once the close has finished.
      await pumpEventQueue();
      expect(context.isClosed, isTrue);
      expect(calls, ['watch', 'unwatch', 'exit 143']);
      expect(log, contains('a:destroy'));
    });

    test('closing the context stops watching', () {
      ctx([])
        ..refresh()
        ..registerShutdownHook()
        ..close();
      expect(calls, ['watch', 'unwatch']);
    });
  });

  group('PayloadApplicationEvent', () {
    test('a listener of PayloadApplicationEvent<T> gets T payloads', () {
      final context = ctx([])..refresh();
      final typed = <int>[];
      final payloads = <int>[];
      context
        ..addListener<PayloadApplicationEvent<Order>>(
          (e) => typed.add(e.payload.id),
        )
        ..addListener<Order>((order) => payloads.add(order.id))
        ..publishEvent(Order(1))
        ..publishEvent('not an order');
      expect(typed, [1]);
      expect(payloads, [1]);
      context.close();
    });

    test('a generated PayloadApplicationEvent<T> listener matches on the '
        'runtime payload type', () {
      final context = ctx([
        BeanDefinition<Audit>(
          name: 'audit',
          create: (_) => Audit(),
          eventListeners: [
            EventListenerMethod.forPayload<Audit, Order>(
              'Audit.on',
              (bean, event) => bean.on(event),
              condition: (event) => event.payload.id > 0,
            ),
          ],
        ),
      ])..refresh();
      context
        ..publishEvent<Object>(Order(2))
        ..publishEvent(Order(0))
        ..publishEvent('x');
      final seen = context.getBean<Audit>().seen;
      expect(seen.map((e) => e.payload.id), [2]);
      expect(seen.single.source, same(context));
      context.close();
    });

    test('@EventListener methods of a FactoryBean run on the factory', () {
      final context = ctx([
        BeanDefinition<WidgetFactory>(
          name: 'widget',
          types: const [WidgetFactory],
          factoryObjectTypes: const [Widget],
          create: (_) => WidgetFactory(),
          eventListeners: [
            EventListenerMethod.of<WidgetFactory, Order>('WidgetFactory.on', (
              bean,
              order,
            ) {
              bean.on(order);
              return null;
            }),
          ],
        ),
      ])..refresh();
      context.publishEvent(Order(7));
      expect(context.getBean<Widget>(), isA<Widget>());
      expect((context.getBeanByName('&widget') as WidgetFactory).orders, [7]);
      context.close();
    });
  });

  test('a condition sees the definition being evaluated', () {
    OnNotExperimental.seen.clear();
    final context = AnnotationConfigApplicationContext([
      BeanModule(
        'm',
        [
          BeanDefinition<Object>(
            name: 'stable',
            create: (_) => Object(),
            conditions: const [OnNotExperimental()],
          ),
          BeanDefinition<Object>(
            name: 'beta',
            annotations: const [Experimental()],
            create: (_) => Object(),
            conditions: const [OnNotExperimental()],
          ),
        ],
        propertySources: const [
          PropertySourceDeclaration([], conditions: [OnNotExperimental()]),
        ],
      ),
    ], environment: StandardEnvironment(systemEnvironment: {}))..refresh();
    expect(context.containsBean('stable'), isTrue);
    expect(context.containsBean('beta'), isFalse);
    expect(OnNotExperimental.seen, [null, 'stable', 'beta']);
    context.close();
  });

  group('child contexts', () {
    test('message lookups use the parent message source', () {
      final messages = StaticMessageSource()
        ..addMessage('greeting', '', 'Hello');
      final parent = ctx([
        BeanDefinition<StaticMessageSource>(
          name: 'messageSource',
          types: const [StaticMessageSource, MessageSource],
          create: (_) => messages,
        ),
      ])..refresh();
      final own = StaticMessageSource();
      final child = ctx([
        BeanDefinition<StaticMessageSource>(
          name: 'messageSource',
          types: const [StaticMessageSource, MessageSource],
          create: (_) => own,
        ),
      ], parent: parent)..refresh();
      final plain = ctx([], parent: parent)..refresh();
      expect(own.parentMessageSource, same(messages));
      parent.close();
      // The closed parent context would throw; its message source answers.
      expect(child.getMessage('greeting'), 'Hello');
      expect(plain.getMessage('greeting'), 'Hello');
      child.close();
      plain.close();
    });

    test('a child uses an ancestor conversionService bean', () {
      final service = DefaultConversionService();
      final parent = ctx([
        BeanDefinition<DefaultConversionService>(
          name: 'conversionService',
          types: const [DefaultConversionService, ConversionService],
          create: (_) => service,
        ),
      ])..refresh();
      final child = ctx([], parent: parent)..refresh();
      expect(child.beanFactory.conversionService, same(service));
      child.close();
      parent.close();
    });
  });
}
