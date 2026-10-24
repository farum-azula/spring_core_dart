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

class Always implements ConfigurationCondition {
  const Always(this.phase);
  final ConfigurationPhase phase;
  @override
  ConfigurationPhase get configurationPhase => phase;
  @override
  bool matches(ConditionContext context) {
    log.add('always ${phase.name}');
    return true;
  }
}

class RecordingRegistrar implements ImportBeanDefinitionRegistrar {
  RecordingRegistrar(this.name, this.registered);
  final String name;
  final List<String> registered;
  @override
  void registerBeanDefinitions(BeanDefinitionRegistry registry) =>
      registered.add(name);
}

class AuditAll implements GenericApplicationListener {
  final seen = <Object>[];
  @override
  bool supportsEvent(Object event) =>
      event is PayloadApplicationEvent<Object> && event.payload is Ping;
  @override
  void onApplicationEvent(Object event) =>
      seen.add((event as PayloadApplicationEvent<Object>).payload);
}

class PingAudit with SmartApplicationListener {
  final seen = <Object>[];
  @override
  bool supportsEventType(Type eventType) =>
      eventType == ContextRefreshedEvent ||
      eventType == (PayloadApplicationEvent<Ping>);
  @override
  void onApplicationEvent(Object event) => seen.add(event);
}

BeanDefinition<Clock> clock(
  String name, {
  List<Condition> conditions = const [],
  bool beanMethod = true,
  String configuration = 'config',
  String? source,
}) => BeanDefinition<Clock>(
  name: name,
  create: (_) => Clock(name),
  conditions: conditions,
  source: source,
  factoryBeanName: beanMethod ? configuration : null,
  factoryMethodName: beanMethod ? name : null,
);

class ConfigClass {}

// A @Configuration class.
BeanDefinition<ConfigClass> configClass(
  String name, {
  List<Condition> conditions = const [],
  String? source,
}) => BeanDefinition<ConfigClass>(
  name: name,
  create: (_) => ConfigClass(),
  conditions: conditions,
  source: source,
  annotations: const [Configuration()],
);

class OnClock implements ConfigurationCondition {
  const OnClock(this.phase);
  final ConfigurationPhase phase;
  @override
  ConfigurationPhase get configurationPhase => phase;
  @override
  bool matches(ConditionContext context) =>
      context.beanFactory.getBeanNamesForType(Clock).isNotEmpty;
}

class PropertySet implements Condition {
  const PropertySet(this.key);
  final String key;
  @override
  bool matches(ConditionContext context) =>
      context.environment.containsProperty(key);
}

class ClockRegistrar implements ImportBeanDefinitionRegistrar {
  @override
  void registerBeanDefinitions(BeanDefinitionRegistry registry) =>
      registry.registerBeanDefinition(
        BeanDefinition<Clock>(
          name: 'registrarClock',
          create: (_) => Clock('registrarClock'),
        ),
      );
}

class ClockBeanRegistrar implements BeanRegistrar {
  @override
  void register(BeanRegistry registry, Environment environment) =>
      registry.registerBean<Clock>(
        (_) => Clock('registrarClock'),
        name: 'registrarClock',
      );
}

// Counts its evaluations in [log].
class Counted implements Condition {
  const Counted();
  @override
  bool matches(ConditionContext context) {
    log.add('counted');
    return true;
  }
}

// The generator's shapes for class [name] of library `lib`: its class
// conditions as a ConditionGroup, the class, its @Bean methods, its imports.
List<Condition> classGroup(String name, List<Condition> conditions) => [
  ConditionGroup('lib#$name', conditions),
];

BeanDefinition<ConfigClass> config(
  String name, [
  List<Condition> conditions = const [],
]) => configClass(
  name.toLowerCase(),
  conditions: conditions,
  source: 'lib#$name',
);

BeanDefinition<Clock> clockOf(
  String className,
  String name, [
  List<Condition> conditions = const [],
]) => clock(
  name,
  conditions: conditions,
  configuration: className.toLowerCase(),
  source: 'lib#$className.$name',
);

ImportDeclaration importOf(
  String className,
  Object Function() create, [
  List<Condition> conditions = const [],
]) => ImportDeclaration(
  create,
  importer: 'lib#$className',
  conditions: conditions,
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

    test('lazy GenericApplicationListener and SmartApplicationListener '
        'beans are created by the first event and receive it', () {
      final context = ctx([
        [
          BeanDefinition<AuditAll>(
            name: 'audit',
            types: const [AuditAll, GenericApplicationListener],
            lazy: true,
            create: (_) => AuditAll(),
          ),
          BeanDefinition<PingAudit>(
            name: 'pingAudit',
            types: const [
              PingAudit,
              SmartApplicationListener,
              GenericApplicationListener,
              Ordered,
            ],
            lazy: true,
            create: (_) => PingAudit(),
          ),
        ],
      ])..refresh();
      final factory = factoryOf(context);
      // ContextRefreshedEvent asked them (Spring creates such listener
      // beans to ask them, too).
      expect(factory.containsSingleton('audit'), isTrue);
      context
        ..publishEvent(const Ping(1))
        ..publishEvent(const Ping(2));
      final audit = context.getBean<AuditAll>();
      final pingAudit = context.getBean<PingAudit>();
      expect([for (final e in audit.seen) (e as Ping).id], [1, 2]);
      expect(
        [
          for (final e in pingAudit.seen)
            switch (e) {
              PayloadApplicationEvent<Object>(:final Ping payload) =>
                payload.id,
              _ => e.runtimeType,
            },
        ],
        // The event that created it reached it.
        [ContextRefreshedEvent, 1, 2],
      );
      factory.destroySingleton('audit');
      context.publishEvent(const Ping(3));
      expect(audit.seen, hasLength(2));
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

    test('the registrars and selected imports of a class skipped by a '
        'registerBean condition do not run; those of a registered one run '
        'after it', () {
      final registered = <String>[];
      const skippedClass = ConditionGroup('Skipped', [
        Never(ConfigurationPhase.registerBean),
      ]);
      const keptClass = ConditionGroup('Kept', [
        OnMissingClock(ConfigurationPhase.registerBean),
      ]);
      final context = ctx([
        BeanModule(
          'skipped',
          [
            clock('never', conditions: const [skippedClass]),
          ],
          registrars: [
            ImportDeclaration(
              () => RecordingRegistrar('skipped', registered),
              conditions: const [skippedClass],
            ),
            ImportDeclaration(
              () => PlainSelector(
                BeanModule('selected', [clock('selected', beanMethod: false)]),
              ),
              conditions: const [skippedClass],
            ),
          ],
        ),
        BeanModule(
          'kept',
          [
            clock('kept', conditions: const [keptClass]),
          ],
          registrars: [
            ImportDeclaration(
              () => RecordingRegistrar('kept', registered),
              conditions: const [keptClass],
            ),
          ],
        ),
      ])..refresh();
      expect(registered, ['kept']);
      // Like Spring, the selector runs while parsing; what it selects is
      // not registered (imported by a skipped class).
      expect(log, contains('select plain'));
      expect(context.getBeanNamesForType(Clock), ['kept']);
      context.close();
    });

    test('a registerBean condition does not stop property sources; '
        'a parseConfiguration one stops imports too', () {
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
      // Spring's TrackedConditionEvaluator: imported by a skipped class.
      expect(context.getBeanNamesForType(Clock), isEmpty);
      context.close();
    });

    test('the modules selected by a class with a registerBean condition '
        'register before its @Bean methods', () {
      const configClass = ConditionGroup('Config', [
        Always(ConfigurationPhase.registerBean),
      ]);
      final context = ctx([
        BeanModule(
          'config',
          [
            clock(
              'fallbackClock',
              conditions: const [
                configClass,
                OnMissingClock(ConfigurationPhase.registerBean),
              ],
            ),
          ],
          registrars: [
            ImportDeclaration(
              () => PlainSelector(
                BeanModule('selected', [clock('selectedClock')]),
              ),
              conditions: const [configClass],
            ),
          ],
        ),
      ])..refresh();
      expect(context.getBeanNamesForType(Clock), ['selectedClock']);
      // The class's conditions are decided once.
      expect(log.where((line) => line == 'always registerBean'), hasLength(1));
      context.close();
    });

    test('a registerBean fallback in a selected module is decided before '
        'the importing class\'s @Bean methods', () {
      const configClass = ConditionGroup('Config', [
        Always(ConfigurationPhase.registerBean),
      ]);
      final context = ctx([
        BeanModule(
          'config',
          [
            clock('appClock', conditions: const [configClass]),
          ],
          registrars: [
            ImportDeclaration(
              () => PlainSelector(
                BeanModule('selected', [
                  clock(
                    'selectedFallback',
                    conditions: const [
                      OnMissingClock(ConfigurationPhase.registerBean),
                    ],
                  ),
                ]),
              ),
              conditions: const [configClass],
            ),
          ],
        ),
      ])..refresh();
      expect(context.getBeanNamesForType(Clock), [
        'selectedFallback',
        'appClock',
      ]);
      context.close();
    });

    test('an earlier class\'s registerBean @Bean is visible to a later '
        'class\'s registerBean condition before its selected module', () {
      const later = ConditionGroup('Later', [
        OnClock(ConfigurationPhase.registerBean),
      ]);
      final context = ctx([
        BeanModule(
          'app',
          [
            configClass('earlier'),
            clock(
              'fooClock',
              conditions: const [
                OnMissingClock(ConfigurationPhase.registerBean),
              ],
              configuration: 'earlier',
            ),
            configClass('later', conditions: const [later]),
          ],
          registrars: [
            ImportDeclaration(
              () => PlainSelector(
                BeanModule('selected', [configClass('selectedConfig')]),
              ),
              conditions: const [later],
            ),
          ],
        ),
      ])..refresh();
      expect(context.beanDefinitionNames, [
        'earlier',
        'fooClock',
        'selectedConfig',
        'later',
      ]);
      context.close();
    });

    test('a registrar of an earlier class runs before a later class\'s '
        'registerBean @Bean is decided', () {
      for (final (name, conditions, importer) in [
        (
          'conditional',
          const [
            ConditionGroup('Earlier', [
              Always(ConfigurationPhase.registerBean),
            ]),
          ],
          null,
        ),
        // Placed by the generator's importer (no condition group).
        ('unconditional', const <Condition>[], 'lib#Earlier'),
      ]) {
        final context = ctx([
          BeanModule(
            'app',
            [
              configClass(
                'earlier',
                conditions: conditions,
                source: 'lib#Earlier',
              ),
              configClass('later', source: 'lib#Later'),
              clock(
                'laterClock',
                conditions: const [
                  OnMissingClock(ConfigurationPhase.registerBean),
                ],
                source: 'lib#Later.laterClock',
              ),
            ],
            registrars: [
              ImportDeclaration(
                ClockRegistrar.new,
                conditions: conditions,
                importer: importer,
              ),
            ],
          ),
        ])..refresh();
        expect(context.getBeanNamesForType(Clock), [
          'registrarClock',
        ], reason: name);
        context.close();
      }
    });

    test('a module selected by a class with a registerBean condition is '
        'parsed at once: its property source is visible to later '
        'parse-phase conditions', () {
      const config = ConditionGroup('Config', [
        Always(ConfigurationPhase.registerBean),
      ]);
      final context = ctx([
        BeanModule(
          'config',
          [
            configClass('config', conditions: const [config]),
          ],
          registrars: [
            ImportDeclaration(
              () => PlainSelector(
                BeanModule(
                  'selected',
                  [configClass('selectedConfig')],
                  propertySources: const [
                    PropertySourceDeclaration([
                      'classpath:spring7/selected.properties',
                    ]),
                  ],
                  resources: const {
                    'spring7/selected.properties': EmbeddedResource.text(
                      'feature.on=true',
                    ),
                  },
                ),
              ),
              conditions: const [config],
            ),
          ],
        ),
        BeanModule('later', [
          clock('featureClock', conditions: const [PropertySet('feature.on')]),
        ]),
      ])..refresh();
      expect(context.getBeanNamesForType(Clock), ['featureClock']);
      expect(
        context.beanDefinitionNames,
        containsAll(['selectedConfig', 'config']),
      );
      context.close();
    });

    test('a hand-written definition without a class source or factory '
        'method is decided at once', () {
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

  group('one decision per configuration class (twelfth batch)', () {
    const onClock = OnClock(ConfigurationPhase.registerBean);
    const onMissingClock = OnMissingClock(ConfigurationPhase.registerBean);

    test("a BeanRegistrar of an earlier class runs before a later class's "
        'registerBean @Bean is decided', () {
      final context = ctx([
        BeanModule(
          'app',
          [
            config('AEarlier'),
            config('BLater'),
            clockOf('BLater', 'laterClock', const [onMissingClock]),
          ],
          registrars: [importOf('AEarlier', ClockBeanRegistrar.new)],
        ),
      ])..refresh();
      expect(context.getBeanNamesForType(Clock), ['registrarClock']);
      context.close();
    });

    test('a kept class registers its beans, then its registrars; the '
        'modules it selects come before it', () {
      final registered = <String>[];
      final audit = classGroup('BAudit', const [onClock]);
      final context = ctx([
        BeanModule(
          'app',
          [
            config('AClocks'),
            clockOf('AClocks', 'clock'),
            config('BAudit', audit),
            clockOf('BAudit', 'auditClock', audit),
          ],
          registrars: [
            importOf(
              'BAudit',
              () => RecordingRegistrar('audit', registered),
              audit,
            ),
            importOf(
              'BAudit',
              () => PlainSelector(BeanModule('feature', [config('Feature')])),
              audit,
            ),
          ],
        ),
      ])..refresh();
      expect(context.beanDefinitionNames, [
        'aclocks',
        'clock',
        'feature',
        'baudit',
        'auditClock',
      ]);
      expect(registered, ['audit']);
      context.close();
    });

    test('a skipped class registers nothing: no bean, registrar or '
        'selected module', () {
      final registered = <String>[];
      final fallback = classGroup('BFallback', const [onMissingClock]);
      final context = ctx([
        BeanModule(
          'app',
          [
            config('AClocks'),
            clockOf('AClocks', 'clock'),
            config('BFallback', fallback),
            clockOf('BFallback', 'fallbackClock', fallback),
          ],
          registrars: [
            importOf(
              'BFallback',
              () => RecordingRegistrar('fallback', registered),
              fallback,
            ),
            importOf(
              'BFallback',
              () => PlainSelector(BeanModule('feature', [config('Feature')])),
              fallback,
            ),
          ],
        ),
      ])..refresh();
      expect(context.beanDefinitionNames, ['aclocks', 'clock']);
      expect(registered, isEmpty);
      context.close();
    });

    test('a class whose condition checks for the bean its imported class '
        'defines stays registered (the decision is shared)', () {
      final pooled = classGroup('Pooled', const [onMissingClock]);
      // Generator @Import: the imported class first, nested conditions.
      final hikari = classGroup('Hikari', pooled);
      final imported = ctx([
        BeanModule('app', [
          config('Hikari', hikari),
          clockOf('Hikari', 'hikariClock', hikari),
          config('Pooled', pooled),
        ]),
      ])..refresh();
      expect(imported.beanDefinitionNames, ['hikari', 'hikariClock', 'pooled']);
      imported.close();
      // A selector's import.
      final selected = ctx([
        BeanModule(
          'app',
          [config('Pooled', pooled)],
          registrars: [
            importOf(
              'Pooled',
              () => PlainSelector(
                BeanModule('hikari', [
                  config('Hikari'),
                  clockOf('Hikari', 'hikariClock'),
                ]),
              ),
              pooled,
            ),
          ],
        ),
      ])..refresh();
      expect(selected.beanDefinitionNames, ['hikari', 'hikariClock', 'pooled']);
      selected.close();
    });

    test('a class skipped in the registerBean phase still loads its '
        '@PropertySource', () {
      final skipped = classGroup('Settings', const [
        Never(ConfigurationPhase.registerBean),
      ]);
      final context = ctx([
        BeanModule(
          'app',
          [config('Settings', skipped)],
          propertySources: [
            PropertySourceDeclaration(const [
              'classpath:spring7/settings.properties',
            ], conditions: skipped),
          ],
          resources: const {
            'spring7/settings.properties': EmbeddedResource.text(
              'settings.loaded=yes',
            ),
          },
        ),
      ])..refresh();
      expect(context.containsBean('settings'), isFalse);
      expect(context.environment.getProperty('settings.loaded'), 'yes');
      context.close();
    });

    test('a module selected by several classes is skipped only when all of '
        'them are; registered directly, it is no longer imported', () {
      final feature = BeanModule('feature', [config('Feature')]);
      final skipped = classGroup('Skipped', const [
        Never(ConfigurationPhase.registerBean),
      ]);
      final alsoSkipped = classGroup('AlsoSkipped', const [
        Never(ConfigurationPhase.registerBean),
      ]);
      final kept = classGroup('Kept', const [
        Always(ConfigurationPhase.registerBean),
      ]);
      BeanModule app(List<(String, List<Condition>)> importers) => BeanModule(
        'app',
        [for (final (name, conditions) in importers) config(name, conditions)],
        registrars: [
          for (final (name, conditions) in importers)
            importOf(name, () => PlainSelector(feature), conditions),
        ],
      );
      for (final (components, expected) in [
        (
          [
            app([('Skipped', skipped), ('Kept', kept)]),
          ],
          true,
        ),
        (
          [
            app([('Skipped', skipped), ('AlsoSkipped', alsoSkipped)]),
          ],
          false,
        ),
        (
          [
            app([('Skipped', skipped)]),
            feature,
          ],
          true,
        ),
      ]) {
        final context = ctx(components)..refresh();
        expect(context.containsBean('feature'), expected);
        context.close();
      }
    });

    test('a plain class condition is evaluated once for the class, its '
        '@Bean methods and its imports', () {
      final registered = <String>[];
      final counted = classGroup('Counted', const [Counted()]);
      final context = ctx([
        BeanModule(
          'app',
          [
            config('Counted', counted),
            clockOf('Counted', 'countedClock', counted),
          ],
          registrars: [
            importOf(
              'Counted',
              () => RecordingRegistrar('counted', registered),
              counted,
            ),
          ],
        ),
      ])..refresh();
      expect(log.where((line) => line == 'counted'), hasLength(1));
      expect(registered, ['counted']);
      expect(context.getBeanNamesForType(Clock), ['countedClock']);
      context.close();
    });

    test('a component with @Bean methods is a (lite) configuration class: '
        'decided in the reader', () {
      final lite = classGroup('Lite', const [onMissingClock]);
      final context = ctx([
        BeanModule('app', [
          BeanDefinition<ConfigClass>(
            name: 'lite',
            create: (_) => ConfigClass(),
            conditions: lite,
            source: 'lib#Lite',
          ),
          clockOf('Lite', 'liteClock', lite),
        ]),
        BeanModule('later', [clock('appClock', beanMethod: false)]),
      ])..refresh();
      expect(context.getBeanNamesForType(Clock), ['appClock']);
      expect(context.containsBean('lite'), isFalse);
      context.close();
    });
  });

  group('components decided in the reader (thirteenth batch)', () {
    const onClock = OnClock(ConfigurationPhase.registerBean);
    const onMissingClock = OnMissingClock(ConfigurationPhase.registerBean);

    // A scanned @Component class [name] with its class conditions.
    BeanDefinition<Object> component(
      String name, [
      List<Condition> conditions = const [],
    ]) {
      final group = classGroup(name, conditions);
      return name.endsWith('Clock')
          ? clock(
              name[0].toLowerCase() + name.substring(1),
              beanMethod: false,
              conditions: group,
              source: 'lib#$name',
            )
          : BeanDefinition<ConfigClass>(
              name: name[0].toLowerCase() + name.substring(1),
              create: (_) => ConfigClass(),
              conditions: group,
              source: 'lib#$name',
            );
    }

    test("a component's missing-bean condition sees an earlier class's "
        'registrar bean', () {
      for (final registrar in <Object Function()>[
        ClockRegistrar.new,
        ClockBeanRegistrar.new,
      ]) {
        final context = ctx([
          BeanModule(
            'app',
            [
              config('AConfig'),
              component('DefaultClock', [onMissingClock]),
            ],
            registrars: [importOf('AConfig', registrar)],
          ),
        ])..refresh();
        expect(context.getBeanNamesForType(Clock), ['registrarClock']);
        context.close();
      }
    });

    test("a component's on-bean condition sees an earlier class's "
        'conditional @Bean', () {
      final context = ctx([
        BeanModule('app', [
          config('BConfig'),
          clockOf('BConfig', 'clock', const [onMissingClock]),
          component('MailListener', [onClock]),
        ]),
      ])..refresh();
      expect(context.beanDefinitionNames, ['bconfig', 'clock', 'mailListener']);
      context.close();
    });

    test('a component before the @Bean it looks for is decided first '
        '(class order)', () {
      final context = ctx([
        BeanModule('app', [
          component('MailListener', [onClock]),
          config('BConfig'),
          clockOf('BConfig', 'clock', const [onMissingClock]),
        ]),
      ])..refresh();
      expect(context.beanDefinitionNames, ['bconfig', 'clock']);
      context.close();
    });

    test('an imported class without @Bean methods is decided in the reader '
        "after the importer's earlier registrar", () {
      // AConfig imports ClockRegistrar; BConfig imports DefaultClock (the
      // generator inlines it before BConfig, under its own source).
      final b = classGroup('BConfig', const []);
      final context = ctx([
        BeanModule(
          'app',
          [
            config('AConfig'),
            component('DefaultClock', [...b, onMissingClock]),
            config('BConfig', b),
          ],
          registrars: [importOf('AConfig', ClockRegistrar.new)],
        ),
      ])..refresh();
      expect(context.getBeanNamesForType(Clock), ['registrarClock']);
      context.close();
    });
  });
}

class SmartFactoryBeanDefault extends SmartFactoryBean<Client> {
  @override
  Client getObject() => Client();
}
