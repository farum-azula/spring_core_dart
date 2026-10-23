import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

import '../beans/support.dart';

class OrderPlaced {
  OrderPlaced(this.id);
  final int id;
}

class OrderShipped extends ApplicationEvent {
  OrderShipped(super.source, this.id);
  final int id;
}

class Audit {
  final events = <Object>[];
}

class AwareBean
    implements
        ApplicationContextAware,
        EnvironmentAware,
        ResourceLoaderAware,
        ApplicationEventPublisherAware,
        MessageSourceAware,
        EmbeddedValueResolverAware {
  final calls = <String>[];
  StringValueResolver? resolver;

  @override
  void setApplicationContext(ApplicationContext applicationContext) =>
      calls.add('context');
  @override
  void setEnvironment(Environment environment) => calls.add('environment');
  @override
  void setResourceLoader(ResourceLoader resourceLoader) =>
      calls.add('resources');
  @override
  void setApplicationEventPublisher(ApplicationEventPublisher publisher) =>
      calls.add('publisher');
  @override
  void setMessageSource(MessageSource messageSource) => calls.add('messages');
  @override
  void setEmbeddedValueResolver(StringValueResolver resolver) {
    this.resolver = resolver;
    calls.add('resolver');
  }
}

class Server with SmartLifecycle {
  Server(this.name, this.phase, {this.isAutoStartup = true});
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

class OnFlag implements Condition {
  const OnFlag(this.flag);
  final String flag;
  @override
  bool matches(ConditionContext context) =>
      context.environment.getPropertyAs<bool>(flag) ?? false;
}

class OnMissingGreeter implements Condition {
  const OnMissingGreeter();
  @override
  bool matches(ConditionContext context) =>
      !context.beanFactory.containsBeanOfType(Greeter) &&
      context.registry.beanDefinitionCount >= 0 &&
      !context.resourceLoader.getResource('nothing:x').exists();
}

class LazyMaker implements BeanFactoryPostProcessor {
  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {
    log.add('bfpp');
    beanFactory.getBeanDefinition('french').lazy = true;
  }
}

class Registrar
    implements BeanDefinitionRegistryPostProcessor, PriorityOrdered {
  @override
  int get order => 0;
  @override
  void postProcessBeanDefinitionRegistry(BeanDefinitionRegistry registry) {
    log.add('registry');
    registry.registerBeanDefinition(
      BeanDefinition<German>(
        name: 'german',
        types: const [German, Greeter],
        create: (_) => German(),
      ),
    );
  }

  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) =>
      log.add('registry:factory');
}

class OrderedBpp extends BeanPostProcessor implements Ordered {
  OrderedBpp(this.order);
  @override
  final int order;
  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    if (bean is LifecycleBean) {
      log.add('bpp$order:$beanName');
    }
    return bean;
  }
}

class PriorityBpp extends BeanPostProcessor implements PriorityOrdered {
  @override
  int get order => 10;
  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    if (bean is LifecycleBean) {
      log.add('priority:$beanName');
    }
    return bean;
  }
}

class PlainBpp extends BeanPostProcessor {
  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    if (bean is LifecycleBean) {
      log.add('plain:$beanName');
    }
    return bean;
  }
}

BeanModule module(
  List<BeanDefinition<Object>> definitions, {
  List<PropertySourceDeclaration> propertySources = const [],
  List<BeanModule> imports = const [],
  Map<Type, BeanConfigurer> configurers = const {},
  String name = 'test',
}) => BeanModule(
  name,
  definitions,
  propertySources: propertySources,
  imports: imports,
  configurers: configurers,
);

AnnotationConfigApplicationContext context(
  List<BeanDefinition<Object>> definitions, {
  Map<String, Object?> properties = const {},
  ApplicationContext? parent,
  ResourceLoader? resourceLoader,
  List<PropertySourceDeclaration> propertySources = const [],
}) {
  final environment = StandardEnvironment(systemEnvironment: {})
    ..propertySources.addFirst(MapPropertySource('test', properties));
  return AnnotationConfigApplicationContext(
    [module(definitions, propertySources: propertySources)],
    environment: environment,
    parent: parent,
    resourceLoader: resourceLoader,
  );
}

void main() {
  setUp(() {
    log.clear();
    Counter.created = 0;
  });

  group('refresh', () {
    test('creates eager singletons and exposes infrastructure', () {
      final ctx = context([
        english(),
        BeanDefinition<Counter>(name: 'c', create: (_) => Counter()),
      ])..refresh();
      expect(ctx.isActive, isTrue);
      expect(ctx.startupDate, isNotNull);
      expect(Counter.created, 1);
      expect(ctx.getBean<Environment>(), same(ctx.environment));
      expect(ctx.getBean<PropertyResolver>(), same(ctx.environment));
      expect(ctx.getBean<ApplicationContext>(), same(ctx));
      expect(ctx.getBean<ApplicationEventPublisher>(), same(ctx));
      expect(ctx.getBean<ResourceLoader>(), same(ctx));
      expect(ctx.getBean<BeanFactory>(), same(ctx.beanFactory));
      expect(ctx.getBean<MessageSource>(), isA<DelegatingMessageSource>());
      expect(ctx.autowireCapableBeanFactory, same(ctx.beanFactory));
      expect(ctx.id, startsWith('AnnotationConfigApplicationContext@'));
      expect(ctx.toString(), contains('AnnotationConfigApplicationContext'));
    });

    test('refresh twice, use before refresh, after close', () {
      final ctx = context([english()]);
      expect(() => ctx.getBean<English>(), throwsStateError);
      // Like Spring 7: not delivered, no error.
      expect(() => ctx.publishEvent('x'), returnsNormally);
      ctx.refresh();
      expect(ctx.refresh, throwsStateError);
      expect(() => ctx.register(module([])), throwsStateError);
      ctx.close();
      expect(ctx.isClosed, isTrue);
      expect(() => ctx.getBean<English>(), throwsStateError);
      ctx.close();
    });

    test(
      'failed refresh destroys created beans and leaves a failed context',
      () {
        final ctx = context([
          lifecycleDefinition('ok'),
          BeanDefinition<Counter>(
            name: 'bad',
            create: (_) => throw StateError('x'),
          ),
        ]);
        expect(ctx.refresh, throwsA(isA<BeanCreationException>()));
        expect(log, contains('ok:destroy'));
        expect(ctx.isActive, isFalse);
        expect(() => ctx.getBean<Counter>(), throwsStateError);
        expect(() => ctx.publishEvent('late'), returnsNormally);
        ctx.close();
        expect(ctx.isClosed, isFalse);
      },
    );

    test('required properties are validated first', () {
      final ctx = context([]);
      ctx.environment.setRequiredProperties(['app.name']);
      expect(ctx.refresh, throwsA(isA<MissingRequiredPropertiesException>()));
    });

    test('graph validation runs before creation', () {
      final ctx = context([
        lifecycleDefinition('first'),
        BeanDefinition<Holder>(
          name: 'needy',
          lazy: true,
          dependencies: const [Dependency(Greeter)],
          create: (r) => Holder(r.getBean<Greeter>()),
        ),
      ]);
      expect(ctx.refresh, throwsA(isA<UnsatisfiedDependencyException>()));
      expect(log, isEmpty);
    });

    test('@Value through the environment', () {
      final ctx = context(
        [
          BeanDefinition<Holder>(
            name: 'holder',
            dependencies: const [Dependency.value(r'${app.name}')],
            create: (r) =>
                Holder(English())..value = r.value<String>(r'${app.name}'),
          ),
        ],
        properties: {'app.name': 'NEON'},
      )..refresh();
      expect(ctx.getBean<Holder>().value, 'NEON');
      final failing = context([
        BeanDefinition<Holder>(
          name: 'holder',
          dependencies: const [Dependency.value(r'${missing}')],
          create: (r) => Holder(English()),
        ),
      ]);
      expect(failing.refresh, throwsA(isA<UnsatisfiedDependencyException>()));
    });

    test('a conversionService bean is used for values', () {
      final service = DefaultConversionService()
        ..addConverter<String, Greeter>(
          (s) => s == 'fr' ? French() : English(),
        );
      final ctx = context([
        BeanDefinition<DefaultConversionService>(
          name: 'conversionService',
          types: const [DefaultConversionService, ConversionService],
          create: (_) => service,
        ),
        BeanDefinition<Holder>(
          name: 'h',
          create: (r) => Holder(r.value<Greeter>('fr')),
        ),
      ])..refresh();
      expect(ctx.getBean<Holder>().greeter, isA<French>());
    });
  });

  group('modules', () {
    test('@PropertySource declarations: last wins, before conditions', () {
      final loader = DefaultResourceLoader(
        protocolResolvers: [
          InMemoryProtocolResolver('mem:', {
            'a.properties': 'name=a\nfeature=true',
            'b.properties': 'name=b',
          }),
        ],
      );
      final ctx = context(
        [
          BeanDefinition<Counter>(
            name: 'flagged',
            conditions: const [OnFlag('feature')],
            create: (_) => Counter(),
          ),
        ],
        resourceLoader: loader,
        propertySources: const [
          PropertySourceDeclaration(['mem:a.properties']),
          PropertySourceDeclaration([
            'mem:b.properties',
            'mem:none.properties',
          ], ignoreResourceNotFound: true),
        ],
      )..refresh();
      expect(ctx.environment.getProperty('name'), 'b');
      expect(ctx.containsBean('flagged'), isTrue);
    });

    test('conditions: profiles and custom; registry visible in order', () {
      final ctx = context(
        [
          BeanDefinition<English>(
            name: 'dev',
            types: const [English, Greeter],
            conditions: const [
              ProfileCondition(['dev']),
            ],
            create: (_) => English(),
          ),
          BeanDefinition<French>(
            name: 'fallbackGreeter',
            types: const [French, Greeter],
            conditions: const [OnMissingGreeter()],
            create: (_) => French(),
          ),
          BeanDefinition<Counter>(
            name: 'off',
            conditions: const [OnFlag('feature')],
            create: (_) => Counter(),
          ),
        ],
        properties: {'spring.profiles.active': 'prod'},
      )..refresh();
      expect(ctx.containsBean('dev'), isFalse);
      expect(ctx.getBean<Greeter>(), isA<French>());
      expect(ctx.containsBean('off'), isFalse);

      final dev = context(
        [
          BeanDefinition<English>(
            name: 'dev',
            types: const [English, Greeter],
            conditions: const [
              ProfileCondition(['dev']),
            ],
            create: (_) => English(),
          ),
          BeanDefinition<French>(
            name: 'fallbackGreeter',
            types: const [French, Greeter],
            conditions: const [OnMissingGreeter()],
            create: (_) => French(),
          ),
        ],
        properties: {'spring.profiles.active': 'dev'},
      )..refresh();
      expect(dev.getBean<Greeter>(), isA<English>());
    });

    test('imports are registered first and only once', () {
      final shared = module([english()], name: 'shared');
      final ctx =
          AnnotationConfigApplicationContext([
              module([french()], imports: [shared], name: 'a'),
              module([], imports: [shared], name: 'b'),
            ], environment: StandardEnvironment(systemEnvironment: {}))
            ..register(module([], name: 'late'))
            ..refresh();
      expect(
        ctx.beanDefinitionNames.where((n) => n == 'english'),
        hasLength(1),
      );
      expect(
        ctx.beanDefinitionNames.indexOf('english'),
        lessThan(ctx.beanDefinitionNames.indexOf('french')),
      );
    });

    test('configurers enable autowireBean', () {
      final ctx = AnnotationConfigApplicationContext([
        module(
          [english()],
          configurers: {
            Holder: (bean, r) =>
                (bean as Holder).value = r.getBean<Greeter>().greet(),
          },
        ),
      ], environment: StandardEnvironment(systemEnvironment: {}))..refresh();
      final holder = Holder(French());
      ctx.autowireCapableBeanFactory.autowireBean(holder);
      expect(holder.value, 'hello');
    });
  });

  group('post-processors', () {
    test('registry and factory post-processors, programmatic and beans', () {
      final ctx =
          context([
              english(),
              french(),
              BeanDefinition<Registrar>(
                name: 'registrar',
                types: const [
                  Registrar,
                  BeanDefinitionRegistryPostProcessor,
                  BeanFactoryPostProcessor,
                ],
                create: (_) => Registrar(),
              ),
              BeanDefinition<LazyMaker>(
                name: 'lazyMaker',
                types: const [LazyMaker, BeanFactoryPostProcessor],
                create: (_) => LazyMaker(),
              ),
            ])
            ..addBeanFactoryPostProcessor(_Programmatic())
            ..refresh();
      // Spring's order: registry post-processing, then postProcessBeanFactory of
      // registry processors, then of regular programmatic ones, then beans.
      expect(log, ['registry', 'registry:factory', 'programmatic', 'bfpp']);
      expect(ctx.containsBean('german'), isTrue);
      expect(ctx.beanFactory.getBeanDefinition('french').lazy, isTrue);
      expect(ctx.beanFactory.containsSingleton('french'), isFalse);
    });

    test('programmatic registry post-processor', () {
      final ctx = context([])
        ..addBeanFactoryPostProcessor(Registrar())
        ..refresh();
      expect(ctx.getBean<German>(), isA<German>());
    });

    test('bean post-processors: PriorityOrdered, Ordered, rest', () {
      context([
        BeanDefinition<PlainBpp>(
          name: 'plainBpp',
          types: const [PlainBpp, BeanPostProcessor],
          create: (_) => PlainBpp(),
        ),
        BeanDefinition<OrderedBpp>(
          name: 'second',
          types: const [OrderedBpp, BeanPostProcessor, Ordered],
          create: (_) => OrderedBpp(2),
        ),
        BeanDefinition<OrderedBpp>(
          name: 'first',
          types: const [OrderedBpp, BeanPostProcessor],
          order: 1,
          create: (_) => OrderedBpp(1),
        ),
        BeanDefinition<PriorityBpp>(
          name: 'priorityBpp',
          types: const [
            PriorityBpp,
            BeanPostProcessor,
            PriorityOrdered,
            Ordered,
          ],
          create: (_) => PriorityBpp(),
        ),
        lifecycleDefinition('bean'),
      ]).refresh();
      expect(log.where((e) => e.contains(':bean') && !e.startsWith('bean')), [
        'priority:bean',
        'bpp1:bean',
        'bpp2:bean',
        'plain:bean',
      ]);
    });

    test('context aware callbacks in Spring order', () {
      final ctx = context(
        [BeanDefinition<AwareBean>(name: 'aware', create: (_) => AwareBean())],
        properties: {'x': '1'},
      )..refresh();
      final bean = ctx.getBean<AwareBean>();
      expect(bean.calls, [
        'environment',
        'resolver',
        'resources',
        'publisher',
        'messages',
        'context',
      ]);
      expect(bean.resolver!(r'${x}'), '1');
    });
  });

  group('events', () {
    BeanDefinition<Audit> audit({
      List<EventListenerMethod<Audit>> listeners = const [],
      bool lazy = false,
      String scope = ScopeType.singleton,
    }) => BeanDefinition<Audit>(
      name: 'audit',
      lazy: lazy,
      scope: scope,
      eventListeners: listeners,
      create: (_) => Audit(),
    );

    test(
      'payload and ApplicationEvent listeners, return values republished',
      () {
        final ctx = context([
          audit(
            listeners: [
              EventListenerMethod.of<Audit, OrderPlaced>('Audit.onPlaced', (
                bean,
                event,
              ) {
                bean.events.add('placed ${event.id}');
                return OrderShipped(bean, event.id);
              }),
              EventListenerMethod.of<Audit, OrderShipped>('Audit.onShipped', (
                bean,
                event,
              ) {
                bean.events.add('shipped ${event.id}');
                return ['note ${event.id}', null];
              }),
              EventListenerMethod.of<Audit, String>(
                'Audit.onNote',
                (bean, note) => bean.events.add(note),
                condition: (note) => note.startsWith('note'),
              ),
            ],
          ),
        ])..refresh();
        ctx.publishEvent(OrderPlaced(7));
        ctx.publishEvent('ignored by condition');
        expect(ctx.getBean<Audit>().events, [
          'placed 7',
          'shipped 7',
          'note 7',
        ]);
      },
    );

    test('listener order and context events', () {
      final ctx = context([
        audit(
          listeners: [
            EventListenerMethod.of<Audit, ApplicationContextEvent>(
              'Audit.second',
              (bean, e) => bean.events.add('second:${e.runtimeType}'),
              order: 2,
            ),
            EventListenerMethod.of<Audit, ContextRefreshedEvent>(
              'Audit.first',
              (bean, e) => bean.events.add('first:${e.applicationContext.id}'),
              order: 1,
            ),
          ],
        ),
      ])..refresh();
      final events = ctx.getBean<Audit>().events;
      expect(events, [
        startsWith('first:AnnotationConfigApplicationContext@'),
        'second:ContextRefreshedEvent',
      ]);
      ctx
        ..start()
        ..stop();
      expect(events.skip(2), [
        'second:ContextStartedEvent',
        'second:ContextStoppedEvent',
      ]);
      ctx.close();
      expect(events.last, 'second:ContextClosedEvent');
    });

    test(
      'events published during refresh are delivered after listeners are ready',
      () {
        final ctx = context([
          audit(
            listeners: [
              EventListenerMethod.of<Audit, String>(
                'Audit.s',
                (b, e) => b.events.add(e),
              ),
            ],
          ),
          BeanDefinition<Counter>(
            name: 'publisher',
            create: (r) {
              r.getBean<ApplicationEventPublisher>().publishEvent('early');
              return Counter();
            },
          ),
        ])..refresh();
        expect(ctx.getBean<Audit>().events, ['early']);
      },
    );

    test('lazy and prototype listener beans are created per event', () {
      final ctx = context([
        audit(
          scope: ScopeType.prototype,
          listeners: [
            EventListenerMethod.of<Audit, int>('Audit.n', (b, e) {
              log.add('event $e');
              return null;
            }),
          ],
        ),
      ])..refresh();
      ctx
        ..publishEvent(1)
        ..publishEvent(2);
      expect(log, ['event 1', 'event 2']);
    });

    test('programmatic listeners and removal', () {
      final ctx = context([]);
      final seen = <int>[];
      final early = ctx.addListener<int>(seen.add, order: 1);
      ctx.refresh();
      ctx.publishEvent(1);
      early.remove();
      expect(early.isRemoved, isTrue);
      early.remove();
      ctx.publishEvent(2);
      final late = ctx.addListener<int>(seen.add);
      ctx.publishEvent(3);
      late.remove();
      expect(seen, [1, 3]);
      final listener = ApplicationListenerAdapter.forListener(
        _IntListener(seen),
      );
      ctx.addApplicationListener(listener);
      ctx.publishEvent(4);
      ctx.removeApplicationListener(listener);
      ctx.publishEvent(5);
      expect(seen, [1, 3, 4]);
      expect(listener.order, Ordered.lowestPrecedence);
    });

    test('events propagate to the parent context', () {
      final parent = context([])..refresh();
      final seen = <Object>[];
      parent.addListener<String>(seen.add);
      final child = context([], parent: parent)..refresh();
      child.publishEvent('hi');
      expect(seen, ['hi']);
    });

    test('custom multicaster bean with error handler', () {
      final errors = <Object>[];
      final ctx = context([
        BeanDefinition<SimpleApplicationEventMulticaster>(
          name: AnnotationConfigApplicationContext
              .applicationEventMulticasterBeanName,
          types: const [
            SimpleApplicationEventMulticaster,
            ApplicationEventMulticaster,
          ],
          create: (_) => SimpleApplicationEventMulticaster(
            errorHandler: (error, _) => errors.add(error),
          ),
        ),
      ])..refresh();
      ctx.addListener<String>((_) => throw StateError('listener'));
      ctx.publishEvent('x');
      expect(errors, [isA<StateError>()]);
    });

    test('listener errors propagate by default', () {
      final ctx = context([])..refresh();
      ctx.addListener<String>((_) => throw StateError('listener'));
      expect(() => ctx.publishEvent('x'), throwsStateError);
    });
  });

  group('lifecycle', () {
    test('SmartLifecycle auto-start by phase, stop in reverse, close', () {
      final ctx = context([
        BeanDefinition<Server>(
          name: 'late',
          types: const [Server, SmartLifecycle, Lifecycle],
          create: (_) => Server('late', 10),
        ),
        BeanDefinition<Server>(
          name: 'early',
          types: const [Server, SmartLifecycle, Lifecycle],
          create: (_) => Server('early', -5),
        ),
        BeanDefinition<Server>(
          name: 'manual',
          types: const [Server, SmartLifecycle, Lifecycle],
          create: (_) => Server('manual', 0, isAutoStartup: false),
        ),
        BeanDefinition<PlainLifecycle>(
          name: 'plain',
          types: const [PlainLifecycle, Lifecycle],
          create: (_) => PlainLifecycle(),
        ),
      ])..refresh();
      expect(log, ['early:start', 'late:start']);
      expect(ctx.isRunning, isTrue);
      log.clear();
      ctx.start();
      expect(log, ['manual:start', 'plain:start']);
      log.clear();
      ctx.stop();
      expect(log, ['late:stop', 'plain:stop', 'manual:stop', 'early:stop']);
      expect(ctx.isRunning, isFalse);
      ctx.start();
      log.clear();
      ctx.close();
      expect(log, ['late:stop', 'plain:stop', 'manual:stop', 'early:stop']);
    });

    test('custom lifecycle processor bean', () {
      final ctx = context([
        BeanDefinition<_RecordingLifecycleProcessor>(
          name: AnnotationConfigApplicationContext.lifecycleProcessorBeanName,
          types: const [_RecordingLifecycleProcessor, LifecycleProcessor],
          create: (_) => _RecordingLifecycleProcessor(),
        ),
      ])..refresh();
      ctx.close();
      expect(log, ['onRefresh', 'onClose']);
    });
  });

  group('messages and resources', () {
    test('default delegating source falls back to the parent', () {
      final parentSource = StaticMessageSource()
        ..addMessage('hi', '', 'Hello {0}');
      final parent = context([
        BeanDefinition<StaticMessageSource>(
          name: 'messageSource',
          types: const [
            StaticMessageSource,
            MessageSource,
            HierarchicalMessageSource,
          ],
          create: (_) => parentSource,
        ),
      ])..refresh();
      final child = context([], parent: parent)..refresh();
      expect(child.getMessage('hi', args: ['NEON']), 'Hello NEON');
      expect(
        child.getMessageFromResolvable(
          DefaultMessageSourceResolvable.code(
            'missing',
            defaultMessage: 'dflt',
          ),
        ),
        'dflt',
      );
      expect(
        () => child.getMessage('missing'),
        throwsA(isA<NoSuchMessageException>()),
      );

      final ownSource = StaticMessageSource();
      final withOwn = context([
        BeanDefinition<StaticMessageSource>(
          name: 'messageSource',
          types: const [StaticMessageSource, MessageSource],
          create: (_) => ownSource,
        ),
      ], parent: parent)..refresh();
      expect(withOwn.getMessage('hi', args: ['x']), 'Hello x');
      // Like Spring: the parent's message source, not the parent context.
      expect(ownSource.parentMessageSource, same(parentSource));
    });

    test('@Value Resource conversion uses the context resource loader', () {
      final ctx = context([
        BeanDefinition<Resource>(
          name: 'required',
          create: (r) => r.value<Resource>('mem:a.txt'),
        ),
        BeanDefinition<Resource>(
          name: 'optional',
          create: (r) => r.optionalValue<Resource>(' mem:a.txt ')!,
        ),
      ])..addProtocolResolver(InMemoryProtocolResolver('mem:', {'a.txt': 'A'}));
      ctx.refresh();
      expect(
        (ctx.getBeanByName('required') as Resource).readAsStringSync(),
        'A',
      );
      expect(
        (ctx.getBeanByName('optional') as Resource).readAsStringSync(),
        'A',
      );
    });

    test('resources and protocol resolvers', () {
      final ctx = context([])
        ..addProtocolResolver(InMemoryProtocolResolver('mem:', {'a.txt': 'A'}));
      ctx.refresh();
      expect(ctx.getResource('mem:a.txt').readAsStringSync(), 'A');
      expect(ctx.getResources('mem:a.txt'), hasLength(1));
      final custom = AnnotationConfigApplicationContext(
        [],
        resourceLoader: _FixedLoader(),
      );
      expect(
        () => custom.addProtocolResolver(InMemoryProtocolResolver('m:', {})),
        throwsStateError,
      );
    });
  });

  group('hierarchy and delegation', () {
    test('child sees parent beans and merges the environment', () {
      final parentEnv = StandardEnvironment(systemEnvironment: {})
        ..propertySources.addFirst(
          const MapPropertySource('parent', {'p': '1'}),
        )
        ..setActiveProfiles(['parentProfile']);
      final parent = AnnotationConfigApplicationContext([
        module([
          english(aliases: ['en']),
        ]),
      ], environment: parentEnv)..refresh();
      final child = context([french()], parent: parent)..refresh();
      expect(child.parent, same(parent));
      expect(child.parentBeanFactory, same(parent));
      expect(child.getBean<English>(), same(parent.getBean<English>()));
      expect(child.environment.getProperty('p'), '1');
      expect(child.environment.activeProfiles, ['parentProfile']);
      expect(child.containsBean('english'), isTrue);
      expect(child.containsLocalBean('english'), isFalse);
      expect(child.getAliases('english'), ['en']);
    });

    test('delegating bean factory API', () {
      final ctx = context([
        english(),
        french(order: -1),
        BeanDefinition<Counter>(
          name: 'proto',
          scope: ScopeType.prototype,
          create: (_) => Counter(),
        ),
      ])..refresh();
      expect(ctx.findBean<German>(), isNull);
      expect(ctx.getBeanByName('french'), isA<French>());
      expect(ctx.getBeanProvider<Greeter>().orderedList().first, isA<French>());
      expect(ctx.containsBeanOfType(Greeter), isTrue);
      expect(ctx.isSingleton('english'), isTrue);
      expect(ctx.isPrototype('proto'), isTrue);
      expect(ctx.getType('english'), English);
      expect(ctx.containsBeanDefinition('english'), isTrue);
      // The context's own singletons (environment, messageSource, ...) are
      // registered objects, not bean definitions, like in Spring.
      expect(ctx.beanDefinitionCount, 3);
      expect(ctx.getBeanNamesForType(Greeter), ['english', 'french']);
      expect(ctx.getBeansOfType<Greeter>().length, 2);
      expect(ctx.getSortedBeans<Greeter>().first, isA<French>());
      expect(
        ctx.displayName,
        startsWith('AnnotationConfigApplicationContext@'),
      );
    });
  });
}

class _Programmatic implements BeanFactoryPostProcessor {
  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) =>
      log.add('programmatic');
}

class _IntListener implements ApplicationListener<int> {
  _IntListener(this.seen);
  final List<int> seen;
  @override
  void onApplicationEvent(int event) => seen.add(event);
}

class _RecordingLifecycleProcessor implements LifecycleProcessor {
  @override
  bool isRunning = false;
  @override
  void onClose() => log.add('onClose');
  @override
  Future<void> onCloseAsync() async => log.add('onCloseAsync');
  @override
  void onRefresh() => log.add('onRefresh');
  @override
  void onRestart() => log.add('onRestart');
  @override
  void onPause() => log.add('onPause');
  @override
  Future<void> onPauseAsync() async => log.add('onPauseAsync');
  @override
  void start() {}
  @override
  void stop() {}
}

class _FixedLoader implements ResourceLoader {
  @override
  Resource getResource(String location) => const DescriptiveResource('fixed');
}
