import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

final log = <String>[];

class Plain implements Lifecycle {
  Plain(this.name) {
    log.add('$name:created');
  }
  final String name;
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

// Spring's defaults through the mixin.
class Defaults with SmartLifecycle {
  Defaults() {
    log.add('defaults:created');
  }
  @override
  bool isRunning = false;
  @override
  void start() => isRunning = true;
  @override
  void stop() {
    isRunning = false;
    log.add('defaults:stop');
  }
}

class Async extends Defaults {
  @override
  void stopWithCallback(void Function() callback) {
    log.add('async:stopWithCallback');
    super.stopWithCallback(callback);
  }
}

class Recorded implements ApplicationListener<String> {
  Recorded(this.name);
  final String name;
  @override
  void onApplicationEvent(String event) => log.add('$name:$event');
}

class OrderedRecorded extends Recorded implements Ordered {
  OrderedRecorded(super.name, this.order);
  @override
  final int order;
}

BeanDefinition<T> listenerBean<T extends Recorded>(String name, T bean) =>
    BeanDefinition<T>(
      name: name,
      create: (_) => bean,
      eventListeners: [
        EventListenerMethod.of<T, String>('$T.onApplicationEvent', (b, e) {
          b.onApplicationEvent(e);
          return null;
        }),
      ],
    );

AnnotationConfigApplicationContext context(
  List<BeanDefinition<Object>> defs, {
  ApplicationContext? parent,
  String? id,
}) => AnnotationConfigApplicationContext(
  [BeanModule('m', defs)],
  environment: StandardEnvironment(systemEnvironment: {}),
  parent: parent,
  id: id,
);

void main() {
  setUp(log.clear);

  group('DefaultLifecycleProcessor', () {
    test('does not create lazy plain Lifecycle beans; SmartLifecycle yes', () {
      final ctx = context([
        BeanDefinition<Plain>(
          name: 'lazyPlain',
          lazy: true,
          types: const [Plain, Lifecycle],
          create: (_) => Plain('lazyPlain'),
        ),
        BeanDefinition<Plain>(
          name: 'eager',
          types: const [Plain, Lifecycle],
          create: (_) => Plain('eager'),
        ),
        BeanDefinition<Defaults>(
          name: 'lazySmart',
          lazy: true,
          types: const [Defaults, SmartLifecycle, Lifecycle],
          create: (_) => Defaults(),
        ),
      ])..refresh();
      expect(log, ['eager:created', 'defaults:created']);
      expect(ctx.getBean<Defaults>().isRunning, isTrue);
      ctx
        ..start()
        ..stop();
      expect(log, isNot(contains('lazyPlain:created')));
      expect(log, containsAll(['eager:start', 'eager:stop']));
      ctx.close();
    });
  });

  group('SmartLifecycle defaults', () {
    test('auto-startup, default phase, stopWithCallback', () {
      final bean = Defaults();
      expect(bean.isAutoStartup, isTrue);
      expect(bean.phase, SmartLifecycle.defaultPhase);
      bean.stopWithCallback(() => log.add('callback'));
      expect(log, ['defaults:created', 'defaults:stop', 'callback']);
    });

    test('the processor stops smart lifecycles through the callback', () {
      final ctx = context([
        BeanDefinition<Async>(
          name: 'async',
          types: const [Async, SmartLifecycle, Lifecycle],
          create: (_) => Async(),
        ),
      ])..refresh();
      log.clear();
      ctx.close();
      expect(log, ['async:stopWithCallback', 'defaults:stop']);
    });
  });

  group('active flag', () {
    test('isActive during refresh; close() from ContextRefreshedEvent', () {
      late final AnnotationConfigApplicationContext ctx;
      bool? activeInCreate;
      ctx = context([
        BeanDefinition<Plain>(
          name: 'eager',
          create: (_) {
            activeInCreate = ctx.isActive;
            return Plain('eager');
          },
          preDestroy: (_) => log.add('eager:destroyed'),
        ),
      ]);
      expect(ctx.isActive, isFalse);
      ctx
        ..addListener<ContextRefreshedEvent>((_) => ctx.close())
        ..addListener<ContextClosedEvent>((_) => log.add('closed event'))
        ..refresh();
      expect(activeInCreate, isTrue);
      expect(ctx.isClosed, isTrue);
      expect(ctx.isActive, isFalse);
      expect(log, containsAllInOrder(['closed event', 'eager:destroyed']));
    });

    test('isActive is false after a failed refresh', () {
      final ctx = context([
        BeanDefinition<Plain>(
          name: 'bad',
          create: (_) => throw StateError('boom'),
        ),
      ]);
      expect(ctx.refresh, throwsA(isA<BeanCreationException>()));
      expect(ctx.isActive, isFalse);
    });
  });

  group('events', () {
    test('Object listeners receive the payload, not the wrapper', () {
      final received = <Object>[];
      final ctx = context([
        BeanDefinition<Recorded>(
          name: 'methods',
          create: (_) => Recorded('m'),
          eventListeners: [
            EventListenerMethod.of<Recorded, Object>('Recorded.any', (_, e) {
              received.add('method:$e');
              return null;
            }),
            EventListenerMethod<Recorded>.matching(
              id: 'Recorded.matching',
              accepts: (candidate) => true,
              invoke: (_, event) {
                received.add(
                  'matching:${EventListenerMethod.match(event, (c) => true)}',
                );
                return null;
              },
            ),
          ],
        ),
      ])..addListener<Object>(received.add);
      ctx
        ..refresh()
        ..publishEvent('hello');
      expect(
        received,
        containsAll(['hello', 'method:hello', 'matching:hello']),
      );
      expect(received.whereType<PayloadApplicationEvent<Object>>(), isEmpty);
      expect(received.whereType<ContextRefreshedEvent>(), hasLength(1));
      // An ApplicationEvent type still gets the wrapper.
      final wrapped = <PayloadApplicationEvent<Object>>[];
      ctx
        ..addListener<PayloadApplicationEvent<Object>>(wrapped.add)
        ..publishEvent('again');
      expect(wrapped.single.payload, 'again');
      ctx.close();
    });

    test('Ordered ApplicationListener beans are ordered by their order', () {
      final ctx = context([
        listenerBean('plain', Recorded('plain')),
        listenerBean('late', OrderedRecorded('late', 10)),
        listenerBean('early', OrderedRecorded('early', -10)),
      ])..refresh();
      log.clear();
      ctx.publishEvent('e');
      expect(log, ['early:e', 'late:e', 'plain:e']);
      ctx.close();
    });

    test('publishEvent before or after a failed refresh goes to the parent '
        'only', () {
      final parentEvents = <String>[];
      final parent = context([])
        ..addListener<String>(parentEvents.add)
        ..refresh();
      final child = context([], parent: parent);
      final childEvents = <String>[];
      child
        ..addListener<String>(childEvents.add)
        ..publishEvent('before');
      expect(parentEvents, ['before']);
      final failed = context([
        BeanDefinition<Plain>(
          name: 'bad',
          create: (_) => throw StateError('boom'),
        ),
      ], parent: parent)..addListener<String>(childEvents.add);
      expect(failed.refresh, throwsA(isA<BeanCreationException>()));
      failed.publishEvent('failed');
      expect(parentEvents, ['before', 'failed']);
      expect(childEvents, isEmpty);
      parent.close();
    });
  });

  test('context ids are unique by default; an explicit id is kept', () {
    final a = context([]);
    final b = context([]);
    expect(a.id, startsWith('AnnotationConfigApplicationContext@'));
    expect(a.id, isNot(b.id));
    expect(a.displayName, a.id);
    final named = context([], id: 'shop');
    expect(named.id, 'shop');
    expect(named.displayName, 'AnnotationConfigApplicationContext(shop)');
  });
}
