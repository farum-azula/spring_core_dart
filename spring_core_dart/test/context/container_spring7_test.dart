import 'package:spring_core_dart/jakarta.dart' as jakarta;
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

final log = <String>[];

// Bean lists become modules; other components are register()ed, in order.
AnnotationConfigApplicationContext ctx(List<Object> components) {
  final context = AnnotationConfigApplicationContext(
    const [],
    environment: StandardEnvironment(systemEnvironment: {}),
  );
  for (final component in components) {
    context.register(
      component is List<BeanDefinition<Object>>
          ? BeanModule('m', component)
          : component,
    );
  }
  return context;
}

DefaultListableBeanFactory factoryOf(ApplicationContext context) =>
    (context as AnnotationConfigApplicationContext).beanFactory
        as DefaultListableBeanFactory;

class Ping {
  const Ping(this.id);
  final int id;
}

class PingListener implements ApplicationListener<Ping> {
  final seen = <int>[];
  @override
  void onApplicationEvent(Ping event) => seen.add(event.id);
}

BeanDefinition<PingListener> pingListener() => BeanDefinition<PingListener>(
  name: 'pings',
  types: const [PingListener, ApplicationListener<Ping>],
  create: (_) => PingListener(),
  eventListeners: [
    EventListenerMethod.of<PingListener, Ping>(
      'PingListener.onApplicationEvent',
      (bean, event) => bean.onApplicationEvent(event),
    ),
  ],
);

abstract interface class Store {
  String get id;
}

class NamedStore implements Store, Ordered {
  NamedStore(this.id, [this._order]);
  @override
  final String id;
  final int? _order;
  @override
  int get order => _order ?? Ordered.lowestPrecedence;
}

class PlainStore implements Store {
  PlainStore(this.id);
  @override
  final String id;
}

BeanDefinition<Store> store(
  String name, {
  int? priority,
  int? order,
  bool primary = false,
  bool ordered = false,
}) => BeanDefinition<Store>(
  name: name,
  create: (_) => ordered ? NamedStore(name, order) : PlainStore(name),
  primary: primary,
  order: ordered ? null : order,
  annotations: [if (priority != null) jakarta.Priority(priority)],
);

class Client {}

class RetryingClient {
  RetryingClient(this.inner);
  final Client inner;
}

class ClientFactory extends SmartFactoryBean<Client> {
  var calls = 0;
  @override
  Client getObject() {
    calls++;
    return Client();
  }

  @override
  bool supportsType(Type type) =>
      super.supportsType(type) || type == RetryingClient;

  @override
  Object? getObjectForType(Type type) =>
      type == RetryingClient ? RetryingClient(getObject()) : getObject();
}

class ClosedScope implements CustomScope {
  bool active = false;
  final _objects = <String, Object>{};
  @override
  Object get(String name, Object Function() objectFactory) {
    if (!active) {
      throw StateError('No screen is open');
    }
    return _objects[name] ??= objectFactory();
  }

  @override
  Object? remove(String name) => _objects.remove(name);

  @override
  void registerDestructionCallback(String name, void Function() callback) {}

  @override
  String? get conversationId => null;
}

class Engine implements SmartLifecycle {
  @override
  bool isRunning = false;
  @override
  int get phase => 0;
  @override
  bool get isAutoStartup => true;
  @override
  bool get isPauseable => true;
  @override
  void start() => throw StateError('no fuel');
  @override
  void stop() => isRunning = false;
  @override
  void stopWithCallback(void Function() callback) {
    stop();
    callback();
  }
}

class Clock {
  Clock(this.name);
  final String name;
}

class Selector implements DeferredImportSelector, Ordered {
  Selector(this.name, this.order, this.module);
  final String name;
  @override
  final int order;
  final BeanModule module;
  @override
  List<BeanModule> selectImports() {
    log.add('select $name');
    return [module];
  }
}

class PlainSelector implements ImportSelector {
  PlainSelector(this.module);
  final BeanModule module;
  @override
  List<BeanModule> selectImports() {
    log.add('select plain');
    return [module];
  }
}

class OnMissingClock implements ConfigurationCondition {
  const OnMissingClock(this.phase);
  final ConfigurationPhase phase;
  @override
  ConfigurationPhase get configurationPhase => phase;
  @override
  bool matches(ConditionContext context) {
    log.add('missing clock? ${phase.name}');
    return context.beanFactory.getBeanNamesForType(Clock).isEmpty;
  }
}

class Never implements ConfigurationCondition {
  const Never(this.phase);
  final ConfigurationPhase phase;
  @override
  ConfigurationPhase get configurationPhase => phase;
  @override
  bool matches(ConditionContext context) => false;
}

BeanDefinition<Clock> clock(
  String name, {
  List<Condition> conditions = const [],
  bool beanMethod = true,
}) => BeanDefinition<Clock>(
  name: name,
  create: (_) => Clock(name),
  conditions: conditions,
  factoryBeanName: beanMethod ? 'config' : null,
  factoryMethodName: beanMethod ? name : null,
);

void main() {
  setUp(log.clear);

  group('ApplicationListener beans and the multicaster', () {
    test('a destroyed ApplicationListener bean gets no events and is not '
        'created again by one; created again, it listens again', () {
      final context = ctx([
        [pingListener()],
      ])..refresh();
      final factory = factoryOf(context);
      final first = context.getBean<PingListener>();
      context.publishEvent(const Ping(1));
      expect(first.seen, [1]);
      factory.destroySingleton('pings');
      context.publishEvent(const Ping(2));
      expect(factory.containsSingleton('pings'), isFalse);
      expect(first.seen, [1]);
      final second = context.getBean<PingListener>();
      context.publishEvent(const Ping(3));
      expect(second.seen, [3]);
      context.close();
    });

    test('removeApplicationListeners(predicate)', () {
      final multicaster = SimpleApplicationEventMulticaster();
      final seen = <String>[];
      final a = ApplicationListenerAdapter.of<String>((e) => seen.add('a$e'));
      final b = ApplicationListenerAdapter.of<String>((e) => seen.add('b$e'));
      multicaster
        ..addApplicationListener(a)
        ..addApplicationListener(b)
        ..removeApplicationListeners((listener) => identical(listener, a))
        ..multicastEvent('1');
      expect(seen, ['b1']);
      expect(multicaster.applicationListeners, [b]);
    });
  });

  group('jakarta @Priority', () {
    test('the highest priority (lowest value) wins getBean and injection', () {
      final context = ctx([
        [
          store('slow', priority: 5),
          store('fast', priority: 1),
          store('plain'),
          BeanDefinition<List<String>>(
            name: 'user',
            create: (r) => [r.dependency<Store>().id],
            dependencies: const [Dependency(Store)],
          ),
        ],
      ])..refresh();
      expect(context.getBean<Store>().id, 'fast');
      expect(context.getBeanByName('user'), ['fast']);
      context.close();
    });

    test('a primary bean beats priority', () {
      final context = ctx([
        [store('fast', priority: 1), store('main', primary: true)],
      ])..refresh();
      expect(context.getBean<Store>().id, 'main');
      context.close();
    });

    test('two beans with the same highest priority are ambiguous', () {
      final context = ctx([
        [
          store('a', priority: 1),
          store('b', priority: 1),
          store('c', priority: 2),
        ],
      ])..refresh();
      expect(
        () => context.getBean<Store>(),
        throwsA(
          isA<NoUniqueBeanDefinitionException>()
              .having((e) => e.samePriority, 'samePriority', 1)
              .having((e) => e.message, 'message', contains('same highest')),
        ),
      );
      context.close();
    });

    test('orders collections after Ordered and @Order', () {
      final context = ctx([
        [
          store('p9', priority: 9),
          store('p1', priority: 1),
          store('order5', order: 5),
          store('ordered3', ordered: true, order: 3),
          store('none'),
        ],
      ])..refresh();
      expect(context.getBeanProvider<Store>().orderedList().map((s) => s.id), [
        'p1',
        'ordered3',
        'order5',
        'p9',
        'none',
      ]);
      context.close();
    });
  });

  group('SmartFactoryBean.supportsType / getObjectForType', () {
    BeanDefinition<ClientFactory> definition() => BeanDefinition<ClientFactory>(
      name: 'client',
      types: const [ClientFactory, SmartFactoryBean<Client>],
      factoryObjectTypes: const [Client],
      create: (_) => ClientFactory(),
    );

    test('a created smart factory serves the extra type', () {
      final context = ctx([
        [definition()],
      ])..refresh();
      final client = context.getBean<Client>();
      final retrying = context.getBean<RetryingClient>();
      expect(retrying.inner, isNot(same(client)));
      // Cached per type for a singleton factory.
      expect(context.getBean<RetryingClient>(), same(retrying));
      expect(context.getBean<Client>(), same(client));
      expect(context.beanFactory.isTypeMatch('client', RetryingClient), isTrue);
      expect(context.beanFactory.isTypeMatch('client', String), isFalse);
      context.close();
    });

    test('by default only the object type is supported', () {
      final factory = ClientFactory();
      expect(factory.supportsType(Client), isTrue);
      expect(factory.supportsType(Object), isTrue);
      expect(
        (SmartFactoryBeanDefault()..supportsType(String)).getObjectForType(
          String,
        ),
        isNull,
      );
    });
  });

  group('ScopeNotActiveException', () {
    late ClosedScope scope;
    late AnnotationConfigApplicationContext context;

    setUp(() {
      scope = ClosedScope();
      context = ctx([
        [
          BeanDefinition<Clock>(
            name: 'screenClock',
            scope: 'screen',
            create: (_) => Clock('screen'),
          ),
        ],
      ]);
      context.beanFactory.registerScope('screen', scope);
      context.refresh();
    });

    tearDown(() => context.close());

    test('getBean in an inactive scope', () {
      expect(
        () => context.getBean<Clock>(),
        throwsA(
          isA<ScopeNotActiveException>()
              .having((e) => e.scopeName, 'scopeName', 'screen')
              .having((e) => e.beanName, 'beanName', 'screenClock')
              .having((e) => e.cause, 'cause', isA<StateError>()),
        ),
      );
    });

    test('getIfAvailable / getIfUnique / ifAvailable treat it as missing', () {
      final provider = context.getBeanProvider<Clock>();
      expect(provider.getIfAvailable(), isNull);
      expect(provider.getIfAvailable(() => Clock('default'))!.name, 'default');
      expect(provider.getIfUnique(), isNull);
      var called = false;
      provider.ifAvailable((_) => called = true);
      expect(called, isFalse);
      expect(provider.getObject, throwsA(isA<ScopeNotActiveException>()));
      scope.active = true;
      expect(provider.getIfAvailable()!.name, 'screen');
    });
  });

  group('lifecycle processor', () {
    test('the default processor is the lifecycleProcessor singleton', () {
      final context = ctx([<BeanDefinition<Object>>[]])..refresh();
      expect(
        context.getBeanByName('lifecycleProcessor'),
        isA<DefaultLifecycleProcessor>(),
      );
      expect(context.getBean<LifecycleProcessor>(), isA<LifecycleProcessor>());
      context.close();
    });

    test('a bean failing to start is an ApplicationContextException', () {
      final context = ctx([
        [
          BeanDefinition<Engine>(
            name: 'engine',
            types: const [Engine, SmartLifecycle, Lifecycle],
            create: (_) => Engine(),
          ),
        ],
      ]);
      expect(
        context.refresh,
        throwsA(
          isA<ApplicationContextException>()
              .having(
                (e) => e.message,
                'message',
                "Failed to start bean 'engine'",
              )
              .having((e) => e.cause, 'cause', isA<StateError>()),
        ),
      );
    });
  });

  group('aliases taken by a definition', () {
    test('with overriding allowed the alias is freed', () {
      final factory = DefaultListableBeanFactory()
        ..allowBeanDefinitionOverriding = true
        ..registerBeanDefinition(
          BeanDefinition<String>(name: 'a', create: (_) => 'A', aliases: ['x']),
        )
        ..registerBeanDefinition(
          BeanDefinition<int>(name: 'x', create: (_) => 1),
        );
      expect(factory.getBeanByName('x'), 1);
      expect(factory.getBeanByName('a'), 'A');
      expect(factory.isAlias('x'), isFalse);
      expect(factory.getAliases('a'), isEmpty);
    });

    test('without overriding: an alias of a bean is an override, a dangling '
        'alias a store error', () {
      final factory = DefaultListableBeanFactory()
        ..registerBeanDefinition(
          BeanDefinition<String>(name: 'a', create: (_) => 'A', aliases: ['x']),
        )
        ..registerAlias('missing', 'y');
      expect(
        () => factory.registerBeanDefinition(
          BeanDefinition<int>(name: 'x', create: (_) => 1),
        ),
        throwsA(isA<BeanDefinitionOverrideException>()),
      );
      expect(
        () => factory.registerBeanDefinition(
          BeanDefinition<int>(name: 'y', create: (_) => 1),
        ),
        throwsA(
          isA<BeanDefinitionStoreException>()
              .having(
                (e) => e,
                'type',
                isNot(isA<BeanDefinitionOverrideException>()),
              )
              .having(
                (e) => e.message,
                'message',
                contains("alias for bean 'missing'"),
              ),
        ),
      );
    });
  });

  group('DeferredImportSelector', () {
    test('runs after every module and component, by order', () {
      final late = BeanModule('late', [clock('late', beanMethod: false)]);
      final early = BeanModule('early', [clock('early', beanMethod: false)]);
      final context = ctx([
        BeanModule(
          'app',
          [clock('app', beanMethod: false)],
          registrars: [
            ImportDeclaration(() => Selector('second', 20, late)),
            ImportDeclaration(() => PlainSelector(BeanModule('plain', []))),
          ],
        ),
        Selector('first', 10, early),
        BeanModule('other', [clock('other', beanMethod: false)]),
      ])..refresh();
      expect(log, ['select plain', 'select first', 'select second']);
      expect(context.beanDefinitionNames, ['app', 'other', 'early', 'late']);
      context.close();
    });

    test('its modules see the application beans (back-off)', () {
      final defaults = BeanModule('defaults', [
        clock(
          'defaultClock',
          conditions: const [OnMissingClock(ConfigurationPhase.registerBean)],
        ),
      ]);
      final context = ctx([
        Selector('defaults', 0, defaults),
        BeanModule('app', [clock('appClock', beanMethod: false)]),
      ])..refresh();
      expect(context.getBeanNamesForType(Clock), ['appClock']);
      context.close();
    });
  });

  group('ConfigurationCondition phases', () {
    test('a registerBean condition of a @Bean method is decided after every '
        'module loaded', () {
      final context = ctx([
        BeanModule('config', [
          clock(
            'fallbackClock',
            conditions: const [OnMissingClock(ConfigurationPhase.registerBean)],
          ),
        ]),
        BeanModule('app', [clock('appClock', beanMethod: false)]),
      ])..refresh();
      expect(context.getBeanNamesForType(Clock), ['appClock']);
      // Not evaluated while parsing.
      expect(log, ['missing clock? registerBean']);
      context.close();
    });

    test('a plain condition is decided at once, in module order', () {
      final context = ctx([
        BeanModule('config', [
          clock(
            'fallbackClock',
            conditions: const [
              OnMissingClock(ConfigurationPhase.parseConfiguration),
            ],
          ),
        ]),
        BeanModule('app', [clock('appClock', beanMethod: false)]),
      ])..refresh();
      expect(context.getBeanNamesForType(Clock), ['fallbackClock', 'appClock']);
      context.close();
    });

    test('a registerBean condition does not stop imports and property '
        'sources; a parseConfiguration one does', () {
      final imported = BeanModule('imported', [
        clock('imported', beanMethod: false),
      ]);
      final skipped = BeanModule('skipped', [
        clock('skipped', beanMethod: false),
      ]);
      final context = ctx([
        BeanModule(
          'config',
          [
            clock(
              'never',
              conditions: const [
                ConditionGroup('Config', [
                  Never(ConfigurationPhase.registerBean),
                ]),
              ],
            ),
          ],
          registrars: [
            ImportDeclaration(
              () => PlainSelector(imported),
              conditions: const [
                ConditionGroup('Config', [
                  Never(ConfigurationPhase.registerBean),
                ]),
              ],
            ),
            ImportDeclaration(
              () => PlainSelector(skipped),
              conditions: const [Never(ConfigurationPhase.parseConfiguration)],
            ),
          ],
        ),
      ])..refresh();
      expect(context.getBeanNamesForType(Clock), ['imported']);
      context.close();
    });

    test('a component with a registerBean condition is decided at once', () {
      final context = ctx([
        BeanModule('a', [
          clock(
            'componentClock',
            beanMethod: false,
            conditions: const [OnMissingClock(ConfigurationPhase.registerBean)],
          ),
        ]),
        BeanModule('b', [clock('appClock', beanMethod: false)]),
      ])..refresh();
      expect(context.getBeanNamesForType(Clock), [
        'componentClock',
        'appClock',
      ]);
      context.close();
    });
  });
}

class SmartFactoryBeanDefault extends SmartFactoryBean<Client> {
  @override
  Client getObject() => Client();
}
