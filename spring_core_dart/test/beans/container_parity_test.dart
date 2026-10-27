import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

import 'support.dart';

DefaultListableBeanFactory factoryWith(
  List<BeanDefinition<Object>> definitions, {
  BeanFactory? parent,
}) {
  final factory = DefaultListableBeanFactory(parentBeanFactory: parent);
  definitions.forEach(factory.registerBeanDefinition);
  return factory;
}

BeanDefinition<German> german({
  String name = 'german',
  bool primary = false,
  bool autowireCandidate = true,
  bool defaultCandidate = true,
  int? order,
  String? factoryBeanName,
  String? factoryMethodName,
  List<String> aliases = const [],
  Set<String> qualifiers = const {},
}) => BeanDefinition<German>(
  name: name,
  types: const [German, Greeter],
  primary: primary,
  autowireCandidate: autowireCandidate,
  defaultCandidate: defaultCandidate,
  order: order,
  aliases: aliases,
  qualifiers: qualifiers,
  factoryBeanName: factoryBeanName,
  factoryMethodName: factoryMethodName,
  create: (_) => German(),
);

/// A configuration-like bean collecting greeters.
class Config implements Greeter {
  Config(this.greeters);
  final List<Greeter> greeters;
  @override
  String greet() => 'config';
}

class Scoped {}

class Owner {
  Owner(this.scoped);
  final Scoped scoped;
}

class _Prefixed implements BeanExpressionResolver {
  @override
  Object? evaluate(String value, BeanFactory beanFactory) =>
      value.startsWith(r'$[') ? value.substring(2, value.length - 1) : value;
}

class _Reentrant extends FactoryBean<Greeter> {
  _Reentrant(this.factory);
  final BeanFactory factory;
  @override
  Greeter getObject() => factory.getBean<Greeter>();
}

void main() {
  setUp(log.clear);

  group('self references', () {
    test("a configuration's own @Bean products are not in its collections", () {
      final factory = factoryWith([
        BeanDefinition<Config>(
          name: 'cfg',
          types: const [Config, Greeter],
          create: (r) => Config(r.dependencyList<Greeter>()),
        ),
        german(name: 'own', factoryBeanName: 'cfg', factoryMethodName: 'own'),
        english(),
      ]);
      expect(factory.getBean<Config>().greeters, [isA<English>()]);
    });

    test('a single dependency falls back to an own product', () {
      final factory = factoryWith([
        BeanDefinition<Holder>(
          name: 'cfg',
          create: (r) => Holder(r.dependency<Greeter>()),
        ),
        german(name: 'own', factoryBeanName: 'cfg', factoryMethodName: 'own'),
      ]);
      expect(factory.getBean<Holder>().greeter, isA<German>());
    });
  });

  group('hierarchy', () {
    test('collections see grandparent beans, shadowed by local names', () {
      final grandparent = factoryWith([
        english(order: 1),
        german(name: 'shadowed'),
      ]);
      final parent = factoryWith([
        french(order: 2),
        german(name: 'hidden', autowireCandidate: false),
      ], parent: grandparent);
      final child = factoryWith([
        BeanDefinition<OrderedGreeter>(
          name: 'shadowed',
          types: const [OrderedGreeter, Greeter],
          create: (_) => OrderedGreeter(0),
        ),
      ], parent: parent);
      expect(child.dependencyList<Greeter>().map((g) => g.greet()), [
        'ordered 0',
        'hello',
        'bonjour',
      ], reason: 'parent @Order kept, non-candidate skipped, name shadowed');
      expect(child.dependencyMap<Greeter>().keys, [
        'shadowed',
        'french',
        'english',
      ]);
      expect(
        BeanFactoryUtils.beanNamesForTypeIncludingAncestors(child, Greeter),
        ['shadowed', 'french', 'hidden', 'english'],
      );
    });

    test('single dependencies merge local and parent candidates', () {
      final parent = factoryWith([english(primary: true)]);
      final child = factoryWith([french()], parent: parent);
      expect(
        child.dependency<Greeter>(),
        isA<English>(),
        reason: 'a parent @Primary wins over a plain local bean',
      );
      final tie = factoryWith([french(primary: true)], parent: parent);
      expect(tie.dependency<Greeter>(), isA<French>(), reason: 'local tie');
    });

    test('the parameter name selects a parent bean', () {
      final parent = factoryWith([english(), french()]);
      final child = factoryWith([], parent: parent);
      expect(child.dependency<Greeter>(name: 'french'), isA<French>());
      expect(
        () => child.dependency<Greeter>(),
        throwsA(isA<NoUniqueBeanDefinitionException>()),
        reason: 'ambiguity in the parent is reported',
      );
      expect(child.getBean<Greeter>(qualifier: 'french'), isA<French>());
    });

    test('validateBeanGraph reports ambiguity in the parent', () {
      final parent = factoryWith([english(), french()]);
      final child = factoryWith([
        BeanDefinition<Holder>(
          name: 'holder',
          dependencies: const [Dependency(Greeter)],
          create: (r) => Holder(r.dependency<Greeter>()),
        ),
      ], parent: parent);
      expect(
        child.validateBeanGraph,
        throwsA(
          isA<UnsatisfiedDependencyException>().having(
            (e) => e.cause,
            'cause',
            isA<NoUniqueBeanDefinitionException>(),
          ),
        ),
      );
      final named = factoryWith([
        BeanDefinition<Holder>(
          name: 'holder',
          dependencies: const [Dependency(Greeter, name: 'french')],
          create: (r) => Holder(r.dependency<Greeter>(name: 'french')),
        ),
      ], parent: parent);
      expect(named.validateBeanGraph, returnsNormally);
      expect(named.getBean<Holder>().greeter, isA<French>());
    });

    test('contexts: collections see grandparent beans', () {
      final grandparent = AnnotationConfigApplicationContext([
        BeanModule('g', [english()]),
      ])..refresh();
      final parent = AnnotationConfigApplicationContext([
        BeanModule('p', [french()]),
      ], parent: grandparent)..refresh();
      final child = AnnotationConfigApplicationContext([
        BeanModule('c', [
          BeanDefinition<Config>(
            name: 'cfg',
            types: const [Config, Greeter],
            create: (r) => Config(r.dependencyList<Greeter>()),
          ),
        ]),
      ], parent: parent)..refresh();
      addTearDown(() {
        child.close();
        parent.close();
        grandparent.close();
      });
      expect(child.getBean<Config>().greeters, [isA<French>(), isA<English>()]);
      expect(child.getSortedBeans<Greeter>(), hasLength(3));
      expect(child.getBean<Greeter>(qualifier: 'english'), isA<English>());
    });
  });

  group('autowireCandidate=false', () {
    test('excluded from qualified injection, found by getBean', () {
      final factory = factoryWith([
        english(autowireCandidate: false),
        french(),
      ]);
      expect(
        () => factory.dependency<Greeter>(qualifier: 'english'),
        throwsA(isA<NoSuchBeanDefinitionException>()),
      );
      expect(factory.optionalDependency<Greeter>(qualifier: 'english'), isNull);
      expect(factory.dependency<Greeter>(), isA<French>());
      expect(factory.getBean<Greeter>(qualifier: 'english'), isA<English>());
      expect(factory.getBean<Greeter>(), isA<French>());
      expect(factory.getBean<English>(), isA<English>());
      final alone = factoryWith([english(autowireCandidate: false)]);
      expect(alone.getBean<Greeter>(), isA<English>());
      expect(alone.getBeanProvider<Greeter>().getIfAvailable(), isA<English>());
      expect(
        () => alone.dependency<Greeter>(),
        throwsA(isA<NoSuchBeanDefinitionException>()),
      );
    });
  });

  group('defaultCandidate', () {
    test('containsBeanOfType ignores non-default candidates', () {
      final factory = factoryWith([german(defaultCandidate: false)]);
      expect(factory.containsBeanOfType(Greeter), isFalse);
      expect(factory.containsBeanOfType(Greeter, qualifier: 'german'), isTrue);
      expect(
        () => factory.dependency<Greeter>(),
        throwsA(isA<NoSuchBeanDefinitionException>()),
      );
      expect(factory.dependency<Greeter>(qualifier: 'german'), isA<German>());
      final child = factoryWith([], parent: factory);
      expect(child.containsBeanOfType(Greeter), isFalse);
    });
  });

  group('aliases', () {
    test('registerAlias aliases count as qualifiers and parameter names', () {
      final factory = factoryWith([english(), french()])
        ..registerAlias('french', 'fr')
        ..registerAlias('fr', 'francais');
      expect(factory.dependency<Greeter>(qualifier: 'fr'), isA<French>());
      expect(factory.dependency<Greeter>(name: 'francais'), isA<French>());
      expect(factory.dependencyMap<Greeter>(qualifier: 'francais').keys, [
        'french',
      ]);
      expect(factory.getBeanProvider<Greeter>(qualifier: 'fr').orderedList(), [
        isA<French>(),
      ]);
    });

    test('alias overriding needs allowBeanDefinitionOverriding', () {
      final factory = factoryWith([english(), french()])
        ..registerAlias('english', 'x');
      expect(
        () => factory.registerAlias('french', 'x'),
        throwsA(isA<BeanDefinitionOverrideException>()),
      );
      factory
        ..allowBeanDefinitionOverriding = true
        ..registerAlias('french', 'x');
      expect(factory.getBeanByName('x'), isA<French>());
      factory.registerBeanDefinition(german(name: 'x'));
      expect(factory.isAlias('x'), isFalse);
      expect(factory.getBeanByName('x'), isA<German>());
    });

    test('no dangling alias chains after removal', () {
      final factory = factoryWith([english()])
        ..registerAlias('english', 'en')
        ..registerAlias('en', 'e')
        ..registerAlias('e', 'ee')
        ..removeBeanDefinition('english');
      expect(factory.isAlias('en'), isFalse);
      expect(factory.isAlias('e'), isFalse);
      expect(factory.isAlias('ee'), isFalse);
      expect(factory.isBeanNameInUse('ee'), isFalse);
      expect(factory.containsBean('ee'), isFalse);
    });
  });

  group('determineAutowireCandidate', () {
    test('two @Primary beans are always ambiguous', () {
      final factory = factoryWith([
        english(primary: true),
        french(primary: true),
      ]);
      expect(
        () => factory.dependency<Greeter>(name: 'english'),
        throwsA(
          isA<NoUniqueBeanDefinitionException>().having(
            (e) => e.candidates,
            'candidates',
            ['english', 'french'],
          ),
        ),
      );
      expect(
        () => factory.getBean<Greeter>(),
        throwsA(isA<NoUniqueBeanDefinitionException>()),
      );
    });

    test('the parameter name matches names and aliases, not qualifiers', () {
      final factory = factoryWith([
        english(qualifiers: {'main'}),
        french(),
      ]);
      expect(
        () => factory.dependency<Greeter>(name: 'main'),
        throwsA(isA<NoUniqueBeanDefinitionException>()),
      );
      expect(factory.dependency<Greeter>(qualifier: 'main'), isA<English>());
      final aliased = factoryWith([
        english(aliases: ['main']),
        french(),
      ]);
      expect(aliased.dependency<Greeter>(name: 'main'), isA<English>());
    });

    test('the qualifier-suggested name breaks a tie', () {
      final factory = factoryWith([
        english(qualifiers: {'french'}),
        french(),
      ]);
      expect(factory.dependency<Greeter>(qualifier: 'french'), isA<French>());
      expect(factory.getBean<Greeter>(qualifier: 'french'), isA<French>());
    });

    test('the only default candidate wins', () {
      final factory = factoryWith([
        english(qualifiers: {'q'}),
        german(defaultCandidate: false, qualifiers: {'q'}),
      ]);
      expect(factory.dependency<Greeter>(qualifier: 'q'), isA<English>());
    });
  });

  group('errors', () {
    test('resolution failures are wrapped per bean with the point', () {
      final factory = factoryWith([
        BeanDefinition<Holder>(
          name: 'outer',
          create: (r) => Holder(r.dependency<Greeter>(name: 'greeter')),
        ),
        BeanDefinition<Config>(
          name: 'inner',
          types: const [Config, Greeter],
          create: (r) => Config(r.dependencyList<Greeter>(qualifier: 'x')),
        ),
      ]);
      expect(
        () => factory.getBean<Holder>(),
        throwsA(
          isA<UnsatisfiedDependencyException>()
              .having((e) => e.beanName, 'bean', 'outer')
              .having((e) => e.dependency, 'point', "Greeter 'greeter'")
              .having(
                (e) => e.cause,
                'cause',
                isA<UnsatisfiedDependencyException>()
                    .having((e) => e.beanName, 'bean', 'inner')
                    .having(
                      (e) => e.dependency,
                      'point',
                      "collection of Greeter('x')",
                    )
                    .having(
                      (e) => e.cause,
                      'cause',
                      isA<NoSuchBeanDefinitionException>(),
                    ),
              ),
        ),
      );
    });

    test('re-entrant FactoryBean products report the cycle', () {
      late DefaultListableBeanFactory factory;
      factory = factoryWith([
        BeanDefinition<_Reentrant>(
          name: 'greeter',
          types: const [_Reentrant],
          factoryObjectTypes: const [Greeter],
          create: (_) => _Reentrant(factory),
        ),
      ]);
      expect(
        () => factory.getBean<Greeter>(),
        throwsA(
          isA<BeanCurrentlyInCreationException>()
              .having((e) => e.cycle, 'cycle', ['greeter', 'greeter'])
              .having((e) => e.beanName, 'bean', 'greeter')
              .having((e) => e.message, 'message', contains('getObject()')),
        ),
      );
    });
  });

  group('bookkeeping', () {
    test('removeBeanDefinition forgets dependencies', () {
      final factory = factoryWith([
        BeanDefinition<Holder>(
          name: 'holder',
          create: (r) => Holder(r.dependency<Greeter>()),
        ),
        english(),
      ])..getBean<Holder>();
      expect(factory.getDependentBeans('english'), ['holder']);
      factory.removeBeanDefinition('holder');
      expect(factory.getDependentBeans('english'), isEmpty);
      expect(factory.getDependenciesForBean('holder'), isEmpty);
      expect(factory.isBeanNameInUse('holder'), isFalse);
      factory.removeBeanDefinition('english');
      expect(factory.getDependentBeans('english'), isEmpty);
    });

    test('no bean creation while singletons are destroyed', () {
      late DefaultListableBeanFactory factory;
      factory = factoryWith([
        BeanDefinition<Counter>(
          name: 'a',
          create: (_) => Counter(),
          preDestroy: (_) => factory.getBeanByName('b'),
        ),
        BeanDefinition<Counter>(
          name: 'b',
          lazy: true,
          create: (_) => Counter(),
        ),
      ])..preInstantiateSingletons();
      factory.destroySingletons();
      expect(factory.destructionErrors, [
        isA<BeanCreationNotAllowedException>(),
      ]);
    });

    test('shutdown of many dependent singletons is fast', () {
      final factory = DefaultListableBeanFactory();
      const n = 3000;
      for (var i = 0; i < n; i++) {
        factory.registerBeanDefinition(
          BeanDefinition<Counter>(
            name: 'b$i',
            dependsOn: [if (i > 0) 'b${i - 1}'],
            create: (r) => Counter(),
            preDestroy: (_) => log.add('d'),
          ),
        );
      }
      factory.preInstantiateSingletons();
      final watch = Stopwatch()..start();
      factory.destroySingletons();
      expect(log, hasLength(n));
      expect(watch.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('scoped beans', () {
    test('a custom-scoped bean injected into a singleton is warned once', () {
      final records = <SpringLogRecord>[];
      final saved = SpringLog.handler;
      SpringLog.handler = records.add;
      addTearDown(() => SpringLog.handler = saved);
      factoryWith([
          BeanDefinition<Scoped>(
            name: 'scoped',
            scope: 'screen',
            create: (_) => Scoped(),
          ),
          BeanDefinition<Owner>(
            name: 'owner',
            create: (r) => Owner(r.dependency<Scoped>()),
          ),
          BeanDefinition<Owner>(
            name: 'lazyOwner',
            create: (r) => Owner(r.lazyDependency<Scoped>()()),
          ),
        ])
        ..registerScope('screen', SimpleMapScope())
        ..getBeanByName('owner')
        ..getBeanByName('lazyOwner');
      expect(records, hasLength(1));
      expect(records.single.message, contains("'scoped'"));
      expect(records.single.message, contains("'owner'"));
    });
  });

  group('ordering', () {
    test('map and set keep registration order; only lists sort', () {
      final factory = factoryWith([french(order: 2), english(order: 1)]);
      expect(factory.dependencyMap<Greeter>().keys, ['french', 'english']);
      expect(factory.dependencyList<Greeter>(), [
        isA<English>(),
        isA<French>(),
      ]);
    });

    test('@Order on a @Bean method beats Ordered; a class @Order does not', () {
      final factory = factoryWith([
        BeanDefinition<OrderedGreeter>(
          name: 'classOrder',
          types: const [OrderedGreeter, Greeter],
          order: 0,
          create: (_) => OrderedGreeter(10),
        ),
        BeanDefinition<OrderedGreeter>(
          name: 'methodOrder',
          types: const [OrderedGreeter, Greeter],
          order: 1,
          factoryBeanName: 'cfg',
          factoryMethodName: 'methodOrder',
          create: (_) => OrderedGreeter(20),
        ),
        english(order: 5),
      ]);
      expect(factory.dependencyList<Greeter>().map((g) => g.greet()), [
        'ordered 20',
        'hello',
        'ordered 10',
      ]);
    });
  });

  group('lookups', () {
    test('Object lookups return every bean', () {
      final factory = factoryWith([english(), french()])
        ..registerSingleton('counter', Counter());
      expect(factory.getBeanNamesForType(Object), [
        'english',
        'french',
        'counter',
      ]);
      expect(factory.getBeansOfType<Object>(), hasLength(3));
      expect(factory.dependencyList<Object>(), hasLength(3));
      expect(factory.isTypeMatch('counter', Object), isTrue);
      expect(
        () => factory.getBean<Object>(),
        throwsA(isA<NoUniqueBeanDefinitionException>()),
      );
    });

    test('a registered FactoryBean singleton is dereferenced', () {
      final greeterFactory = GreeterFactory();
      final factory = DefaultListableBeanFactory()
        ..registerSingleton('greeter', greeterFactory);
      expect(factory.getBeanByName('greeter'), isA<German>());
      expect(factory.getBeanByName('&greeter'), same(greeterFactory));
      expect(factory.isFactoryBean('greeter'), isTrue);
      expect(factory.getBean<GreeterFactory>(), same(greeterFactory));
      expect(factory.getType('greeter'), Greeter);
      expect(factory.getBean<Greeter>(), isA<German>());
      expect(factory.getBeanNamesForType(Greeter), ['greeter']);
      expect(factory.isTypeMatch('greeter', Greeter), isTrue);
      expect(factory.isSingleton('greeter'), isTrue);
      expect(greeterFactory.calls, 1);
    });

    test('@Value always goes through the expression resolver', () {
      final factory = DefaultListableBeanFactory()
        ..beanExpressionResolver = _Prefixed()
        ..addEmbeddedValueResolver((v) => v.replaceAll(r'${x}', 'y'));
      expect(factory.value<String>(r'$[${x}]'), 'y');
      expect(factory.value<String>('plain'), 'plain');
      expect(factory.optionalValue<String>(r'$[a]'), 'a');
    });

    test('annotation lookups', () {
      final factory = factoryWith([
        BeanDefinition<English>(
          name: 'english',
          types: const [English, Greeter],
          annotations: const [Order(3), Service()],
          create: (_) => English(),
        ),
        french(),
      ]);
      expect(factory.getBeanNamesForAnnotation<Component>(), ['english']);
      expect(factory.getBeansWithAnnotation<Order>().keys, ['english']);
      expect(factory.findAnnotationOnBean<Order>('english')?.value, 3);
      expect(factory.findAnnotationOnBean<Order>('french'), isNull);
      final child = factoryWith([], parent: factory);
      expect(child.findAnnotationOnBean<Order>('english')?.value, 3);
    });

    test('destroyBean runs the definition callbacks for an instance', () {
      final factory = factoryWith([
        lifecycleDefinition('p', scope: ScopeType.prototype),
      ]);
      final bean = factory.getBeanByName('p');
      factory.destroyBean(bean, beanName: 'p');
      expect(
        log,
        containsAll(['p:preDestroy', 'p:destroy', 'p:destroyMethod']),
      );
    });
  });
}
