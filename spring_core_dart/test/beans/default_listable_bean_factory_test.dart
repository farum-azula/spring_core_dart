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

void main() {
  setUp(() {
    log.clear();
    Counter.created = 0;
  });

  group('registry', () {
    test('names, counts, definitions', () {
      final factory = factoryWith([english(), french()]);
      expect(factory.beanDefinitionNames, ['english', 'french']);
      expect(factory.beanDefinitionCount, 2);
      expect(factory.containsBeanDefinition('english'), isTrue);
      expect(factory.getBeanDefinition('french').beanType, French);
      expect(
        () => factory.getBeanDefinition('none'),
        throwsA(isA<NoSuchBeanDefinitionException>()),
      );
    });

    test('duplicates: error, override, same source no-op', () {
      final factory = factoryWith([english()]);
      expect(
        () => factory.registerBeanDefinition(english()),
        throwsA(isA<BeanDefinitionOverrideException>()),
      );
      factory
        ..registerBeanDefinition(
          BeanDefinition<Counter>(
            name: 'c',
            source: 'src',
            create: (_) => Counter(),
          ),
        )
        ..registerBeanDefinition(
          BeanDefinition<Counter>(
            name: 'c',
            source: 'src',
            create: (_) => Counter(),
          ),
        );
      expect(factory.beanDefinitionCount, 2);

      factory
        ..getBean<English>()
        ..allowBeanDefinitionOverriding = true
        ..registerBeanDefinition(
          BeanDefinition<French>(name: 'english', create: (_) => French()),
        );
      expect(factory.getBeanByName('english'), isA<French>());
    });

    test('invalid names', () {
      final factory = DefaultListableBeanFactory();
      for (final name in ['', '&x']) {
        expect(
          () => factory.registerBeanDefinition(
            BeanDefinition<Counter>(name: name, create: (_) => Counter()),
          ),
          throwsA(isA<BeanDefinitionStoreException>()),
        );
      }
    });

    test('aliases', () {
      final factory = factoryWith([
        english(aliases: ['en', 'eng']),
      ])..registerAlias('en', 'e');
      expect(factory.getBeanByName('e'), isA<English>());
      expect(factory.isAlias('en'), isTrue);
      expect(factory.isBeanNameInUse('eng'), isTrue);
      expect(
        factory.getAliases('english'),
        unorderedEquals(['en', 'eng', 'e']),
      );
      expect(
        factory.getAliases('en'),
        unorderedEquals(['english', 'eng', 'e']),
      );
      factory
        ..registerAlias('english', 'english')
        ..registerAlias('english', 'en');
      expect(
        () => factory.registerAlias('english', 'english2'),
        returnsNormally,
      );
      expect(
        () => factory.registerAlias('other', 'en'),
        throwsA(isA<BeanDefinitionOverrideException>()),
      );
      expect(
        () => factory.registerAlias('en', 'english'),
        throwsA(isA<BeanDefinitionOverrideException>()),
      );
      expect(
        () => factory.registerAlias('e', 'en'),
        throwsA(isA<BeanDefinitionOverrideException>()),
      );
      factory.removeAlias('e');
      expect(factory.isAlias('e'), isFalse);
      expect(() => factory.removeAlias('e'), throwsArgumentError);
      expect(
        () => factory.registerBeanDefinition(
          BeanDefinition<Counter>(name: 'eng', create: (_) => Counter()),
        ),
        throwsA(isA<BeanDefinitionOverrideException>()),
      );
    });

    test('removeBeanDefinition destroys the singleton and aliases', () {
      final factory =
          factoryWith([
              lifecycleDefinition('a'),
              english(aliases: ['en']),
            ])
            ..getBeanByName('a')
            ..removeBeanDefinition('a');
      expect(log, contains('a:destroyMethod'));
      factory.removeBeanDefinition('en');
      expect(factory.isAlias('en'), isFalse);
      expect(
        () => factory.removeBeanDefinition('a'),
        throwsA(isA<NoSuchBeanDefinitionException>()),
      );
    });

    test('frozen configuration is a cache hint, like Spring', () {
      final factory = factoryWith([french()])..freezeConfiguration();
      expect(factory.isConfigurationFrozen, isTrue);
      expect(factory.getBean<Greeter>(), isA<French>());
      // Registering and removing still work and clear the lookup caches.
      factory.registerBeanDefinition(english(primary: true));
      expect(factory.getBean<Greeter>(), isA<English>());
      factory.removeBeanDefinition('english');
      expect(factory.getBean<Greeter>(), isA<French>());
      expect(
        () => factory.removeBeanDefinition('x'),
        throwsA(isA<NoSuchBeanDefinitionException>()),
      );
    });
  });

  group('lookup by type', () {
    test('own type and supertypes', () {
      final factory = factoryWith([english()]);
      expect(factory.getBean<Greeter>(), same(factory.getBean<English>()));
      expect(factory.findBean<French>(), isNull);
      expect(
        () => factory.getBean<French>(),
        throwsA(
          isA<NoSuchBeanDefinitionException>().having(
            (e) => e.toString(),
            'text',
            contains('No bean of type French'),
          ),
        ),
      );
    });

    test('ambiguity, primary, fallback, qualifier, alias', () {
      expect(
        () => factoryWith([english(), french()]).getBean<Greeter>(),
        throwsA(
          isA<NoUniqueBeanDefinitionException>()
              .having((e) => e.candidates, 'candidates', ['english', 'french'])
              .having((e) => e.toString(), 'text', contains('@Primary')),
        ),
      );
      expect(
        factoryWith([english(), french(primary: true)]).getBean<Greeter>(),
        isA<French>(),
      );
      expect(
        () =>
            factoryWith([english(primary: true), french(primary: true)])
                .getBean<Greeter>(),
        throwsA(isA<NoUniqueBeanDefinitionException>()),
      );
      expect(
        factoryWith([english(fallback: true), french()]).getBean<Greeter>(),
        isA<French>(),
      );
      final qualified = factoryWith([
        english(aliases: ['en']),
        french(qualifiers: {'fr'}),
      ]);
      expect(qualified.getBean<Greeter>(qualifier: 'fr'), isA<French>());
      expect(qualified.getBean<Greeter>(qualifier: 'en'), isA<English>());
      expect(qualified.getBean<Greeter>(qualifier: 'french'), isA<French>());
      expect(qualified.findBean<Greeter>(qualifier: 'de'), isNull);
    });

    test('dependency name breaks ties like Spring', () {
      final factory = factoryWith([english(), french()]);
      expect(factory.dependency<Greeter>(name: 'french'), isA<French>());
      expect(
        () => factory.dependency<Greeter>(name: 'german'),
        throwsA(isA<NoUniqueBeanDefinitionException>()),
      );
      expect(factory.optionalDependency<French>(name: 'x'), isA<French>());
    });

    test('non-autowire candidates are skipped by type but found by name', () {
      final factory = factoryWith([
        english(autowireCandidate: false),
        french(),
      ]);
      expect(factory.getBean<Greeter>(), isA<French>());
      expect(factory.getBean<Greeter>(qualifier: 'english'), isA<English>());
      expect(factory.getBeanNamesForType(Greeter), ['english', 'french']);
    });

    test('resolvable dependencies', () {
      final factory = factoryWith([])
        ..registerResolvableDependency(BeanFactory, Object());
      expect(factory.containsBeanOfType(BeanFactory), isTrue);
      expect(
        () => factory.getBean<BeanFactory>(),
        throwsA(isA<BeanNotOfRequiredTypeException>()),
      );
      final ok = factoryWith([])
        ..registerResolvableDependency(Greeter, English());
      expect(ok.getBean<Greeter>(), isA<English>());
      expect(ok.findBean<Greeter>(qualifier: 'x'), isNull);
    });

    test('getBeanByName, containsBean, isSingleton, getType', () {
      final factory = factoryWith([
        english(),
        BeanDefinition<Counter>(
          name: 'proto',
          scope: ScopeType.prototype,
          create: (_) => Counter(),
        ),
      ]);
      expect(factory.getBeanByName('english'), isA<English>());
      expect(factory.containsBean('english'), isTrue);
      expect(factory.containsBean('&english'), isFalse);
      expect(factory.containsBean('none'), isFalse);
      expect(factory.containsLocalBean('english'), isTrue);
      expect(factory.isSingleton('english'), isTrue);
      expect(factory.isPrototype('proto'), isTrue);
      expect(factory.isSingleton('proto'), isFalse);
      expect(factory.getType('english'), English);
      expect(factory.getType('none'), isNull);
      expect(
        () => factory.getBeanByName('none'),
        throwsA(
          isA<NoSuchBeanDefinitionException>().having(
            (e) => e.beanName,
            'name',
            'none',
          ),
        ),
      );
      expect(
        () => factory.isSingleton('none'),
        throwsA(isA<NoSuchBeanDefinitionException>()),
      );
      expect(
        () => factory.getBeanByName('&english'),
        throwsA(isA<BeanIsNotAFactoryException>()),
      );
    });

    test('listing and sorting', () {
      final factory = factoryWith([
        BeanDefinition<OrderedGreeter>(
          name: 'ordered',
          types: const [OrderedGreeter, Greeter],
          create: (_) => OrderedGreeter(5),
        ),
        english(order: 1),
        french(),
        BeanDefinition<PriorityGreeter>(
          name: 'priority',
          types: const [PriorityGreeter, Greeter],
          create: (_) => PriorityGreeter(),
        ),
        BeanDefinition<German>(
          name: 'german',
          types: const [German, Greeter],
          scope: ScopeType.prototype,
          create: (_) => German(),
        ),
      ]);
      expect(factory.getBeansOfType<Greeter>().keys, [
        'ordered',
        'english',
        'french',
        'priority',
        'german',
      ]);
      expect(
        factory.getBeansOfType<Greeter>(includeNonSingletons: false).keys,
        isNot(contains('german')),
      );
      expect(factory.getSortedBeans<Greeter>().map((g) => g.greet()), [
        'priority',
        'hello',
        'ordered 5',
        'bonjour',
        'hallo',
      ]);
      expect(
        factory.getSortedBeans<Greeter>(qualifier: 'french'),
        hasLength(1),
      );
      // Like Spring, only lists are sorted; maps keep registration order.
      expect(factory.dependencyList<Greeter>().first, isA<PriorityGreeter>());
      expect(factory.dependencyMap<Greeter>().keys.first, 'ordered');
    });
  });

  group('scopes', () {
    test('singleton is created once, eagerly with preInstantiate', () {
      final factory = factoryWith([
        BeanDefinition<Counter>(name: 'c', create: (_) => Counter()),
        BeanDefinition<Holder>(
          name: 'lazy',
          lazy: true,
          create: (_) => throw StateError('never'),
        ),
      ])..preInstantiateSingletons();
      expect(Counter.created, 1);
      factory.getBean<Counter>();
      expect(Counter.created, 1);
      expect(factory.containsSingleton('c'), isTrue);
      expect(factory.getSingleton('c'), isA<Counter>());
      expect(factory.singletonNames, ['c']);
    });

    test('prototype is new every time', () {
      final factory = factoryWith([
        BeanDefinition<Counter>(
          name: 'c',
          scope: ScopeType.prototype,
          create: (_) => Counter(),
        ),
      ])..preInstantiateSingletons();
      expect(Counter.created, 0);
      expect(
        factory.getBean<Counter>(),
        isNot(same(factory.getBean<Counter>())),
      );
    });

    test('custom scope with destruction callbacks', () {
      final scope = SimpleMapScope(conversationId: 'screen-1');
      final factory = factoryWith([
        lifecycleDefinition('scoped', scope: 'screen'),
        BeanDefinition<Counter>(
          name: 'plain',
          scope: 'screen',
          create: (_) => Counter(),
        ),
      ])..registerScope('screen', scope);
      expect(factory.registeredScopeNames, ['screen']);
      expect(factory.getRegisteredScope('screen'), same(scope));
      expect(scope.conversationId, 'screen-1');
      final first = factory.getBeanByName('scoped');
      expect(factory.getBeanByName('scoped'), same(first));
      factory.getBean<Counter>();
      expect(scope.names, ['scoped', 'plain']);
      scope.destroy();
      expect(log, containsAllInOrder(['scoped:preDestroy', 'scoped:destroy']));
      expect(factory.getBeanByName('scoped'), isNot(same(first)));
      expect(scope.remove('plain'), isNull);
      expect(scope.remove('scoped'), isNotNull);
    });

    test('destroyScopedBean', () {
      final scope = SimpleMapScope();
      final factory =
          factoryWith([lifecycleDefinition('s', scope: 'x'), english()])
            ..registerScope('x', scope)
            ..getBeanByName('s')
            ..destroyScopedBean('s');
      expect(log, contains('s:destroyMethod'));
      factory.destroyScopedBean('s');
      expect(() => factory.destroyScopedBean('english'), throwsArgumentError);
    });

    test('unknown scope and built-in scope names', () {
      final factory = factoryWith([
        BeanDefinition<Counter>(
          name: 'c',
          scope: 'nope',
          create: (_) => Counter(),
        ),
      ]);
      expect(
        () => factory.getBean<Counter>(),
        throwsA(
          isA<ScopeNotRegisteredException>().having(
            (e) => e.toString(),
            'text',
            contains("'nope'"),
          ),
        ),
      );
      expect(
        () => factory.registerScope(ScopeType.singleton, SimpleMapScope()),
        throwsArgumentError,
      );
    });
  });

  group('lifecycle', () {
    test('creation and destruction order with post-processors', () {
      final factory = factoryWith([lifecycleDefinition('a')])
        ..addBeanPostProcessor(RecordingPostProcessor('p1'))
        ..addBeanPostProcessor(RecordingPostProcessor('p2'));
      expect(factory.beanPostProcessorCount, 2);
      expect(factory.beanPostProcessors, hasLength(2));
      factory.preInstantiateSingletons();
      expect(log, [
        'a:construct',
        'a:inject',
        'a:beanName',
        'a:beanFactory',
        'p1:before:a',
        'p2:before:a',
        'a:postConstruct',
        'a:afterPropertiesSet',
        'a:initMethod',
        'p1:after:a',
        'p2:after:a',
      ]);
      final bean = factory.getBean<LifecycleBean>();
      expect(bean.beanName, 'a');
      expect(bean.factory, same(factory));
      log.clear();
      factory.destroySingletons();
      expect(log, [
        'p1:destruction:a',
        'p2:destruction:a',
        'a:preDestroy',
        'a:destroy',
        'a:destroyMethod',
      ]);
      expect(factory.singletonNames, isEmpty);
    });

    test('dependents are destroyed first; dependsOn creates first', () {
      final factory = factoryWith([
        lifecycleDefinition(
          'user',
          onCreate: (r) => r.getBeanByName('service'),
        ),
        lifecycleDefinition('service', dependsOn: ['config']),
        lifecycleDefinition('config'),
      ])..preInstantiateSingletons();
      expect(log.where((e) => e.endsWith(':construct')), [
        'config:construct',
        'service:construct',
        'user:construct',
      ]);
      expect(factory.getDependentBeans('service'), ['user']);
      expect(factory.getDependenciesForBean('service'), ['config']);
      log.clear();
      factory.destroySingletons();
      expect(log.where((e) => e.endsWith(':destroy')), [
        'user:destroy',
        'service:destroy',
        'config:destroy',
      ]);
    });

    test('destroy errors are collected and do not stop shutdown', () {
      final factory =
          factoryWith([
              BeanDefinition<Counter>(
                name: 'bad',
                create: (_) => Counter(),
                preDestroy: (_) => throw StateError('boom'),
              ),
              lifecycleDefinition('good'),
            ])
            ..preInstantiateSingletons()
            ..destroySingletons();
      expect(factory.destructionErrors, [isA<StateError>()]);
      expect(log, contains('good:destroy'));
    });

    test('post-processors can replace beans; factory products too', () {
      final factory = factoryWith([
        english(),
        BeanDefinition<GreeterFactory>(
          name: 'german',
          types: const [GreeterFactory, FactoryBean<Greeter>],
          factoryObjectTypes: const [Greeter],
          create: (_) => GreeterFactory(),
        ),
      ])..addBeanPostProcessor(_Wrapping());
      expect(factory.getBean<Greeter>(qualifier: 'english').greet(), '[hello]');
      expect(factory.getBeanByName('german'), isA<_Wrapped>());
    });

    test('a replaced bean of the wrong type is reported', () {
      final factory = factoryWith([english()])
        ..addBeanPostProcessor(_Wrapping());
      expect(
        () => factory.getBean<English>(),
        throwsA(isA<BeanNotOfRequiredTypeException>()),
      );
    });

    test('SmartInitializingSingleton runs after all singletons', () {
      final factory = factoryWith([
        BeanDefinition<_Smart>(name: 'smart', create: (_) => _Smart()),
        lifecycleDefinition('later'),
      ])..preInstantiateSingletons();
      expect(log.last, 'smart:afterSingletonsInstantiated');
      expect(factory, isNotNull);
    });

    test('initializeBean and autowireBean', () {
      final factory = factoryWith([english()])
        ..addBeanPostProcessor(RecordingPostProcessor('p'))
        ..registerConfigurer(
          Holder,
          (bean, r) => (bean as Holder).value = r.getBean<Greeter>().greet(),
        );
      final bean = LifecycleBean('manual');
      expect(factory.initializeBean(bean, 'manual'), same(bean));
      expect(
        log,
        containsAllInOrder([
          'manual:beanName',
          'p:before:manual',
          'manual:afterPropertiesSet',
          'p:after:manual',
        ]),
      );
      final holder = Holder(French());
      factory.autowireBean(holder);
      expect(holder.value, 'hello');
      expect(() => factory.autowireBean(Counter()), throwsArgumentError);
    });
  });

  group('FactoryBean', () {
    BeanDefinition<GreeterFactory> factoryBean({
      bool singleton = true,
      String scope = ScopeType.singleton,
    }) => BeanDefinition<GreeterFactory>(
      name: 'greeter',
      types: const [GreeterFactory, FactoryBean<Greeter>],
      factoryObjectTypes: const [Greeter],
      scope: scope,
      create: (_) => GreeterFactory(singleton: singleton),
    );

    test('product by type and name, factory by & and own type', () {
      final factory = factoryWith([factoryBean()]);
      expect(factory.getBean<Greeter>(), isA<German>());
      expect(
        factory.getBeanByName('greeter'),
        same(factory.getBean<Greeter>()),
      );
      final greeterFactory =
          factory.getBeanByName('&greeter') as GreeterFactory;
      expect(greeterFactory.calls, 1);
      expect(factory.getBean<GreeterFactory>(), same(greeterFactory));
      expect(factory.containsBean('&greeter'), isTrue);
      expect(factory.getType('greeter'), Greeter);
      expect(factory.getType('&greeter'), GreeterFactory);
      expect(factory.isSingleton('greeter'), isTrue);
      expect(factory.isPrototype('greeter'), isFalse);
      expect(factory.isSingleton('&greeter'), isTrue);
      expect(factory.getAliases('&greeter'), isEmpty);
    });

    test('non-singleton products are created every time', () {
      final factory = factoryWith([factoryBean(singleton: false)]);
      expect(
        factory.getBean<Greeter>(),
        isNot(same(factory.getBean<Greeter>())),
      );
      expect(factory.isSingleton('greeter'), isFalse);
      expect(factory.isPrototype('greeter'), isTrue);
    });

    test('a product that throws is wrapped', () {
      final factory = factoryWith([
        BeanDefinition<_FailingFactory>(
          name: 'failing',
          factoryObjectTypes: const [Greeter],
          create: (_) => _FailingFactory(),
        ),
      ]);
      expect(
        () => factory.getBean<Greeter>(),
        throwsA(isA<BeanCreationException>()),
      );
    });

    test('a non-factory flagged as factory is rejected', () {
      final factory = factoryWith([
        BeanDefinition<Counter>(
          name: 'fake',
          factoryObjectTypes: const [Greeter],
          create: (_) => Counter(),
        ),
      ]);
      expect(
        () => factory.getBean<Greeter>(),
        throwsA(isA<BeanIsNotAFactoryException>()),
      );
    });
  });

  group('dependency resolution', () {
    test('lists and maps; required and optional', () {
      final factory = factoryWith([french(order: 2), english(order: 1)]);
      expect(factory.dependencyList<Greeter>().map((g) => g.greet()), [
        'hello',
        'bonjour',
      ]);
      expect(factory.dependencyMap<Greeter>().keys, ['french', 'english']);
      expect(factory.optionalDependencyList<Counter>(), isNull);
      expect(factory.optionalDependencyMap<Counter>(), isNull);
      expect(
        () => factory.dependencyList<Counter>(),
        throwsA(isA<NoSuchBeanDefinitionException>()),
      );
      expect(
        () => factory.dependencyMap<Counter>(),
        throwsA(isA<NoSuchBeanDefinitionException>()),
      );
      expect(
        factory.dependencyList<Greeter>(qualifier: 'english'),
        hasLength(1),
      );
      expect(factory.optionalDependency<Counter>(), isNull);
    });

    test('values: placeholders, conversion, optional, expressions', () {
      final factory = factoryWith([])
        ..addEmbeddedValueResolver(
          (v) => v.replaceAll(r'${port}', '8080').contains(r'${')
              ? throw PlaceholderResolutionException('missing', v, [v])
              : v.replaceAll(r'${port}', '8080'),
        );
      expect(factory.hasEmbeddedValueResolver, isTrue);
      expect(factory.value<int>(r'${port}'), 8080);
      expect(factory.value<String>('plain'), 'plain');
      expect(factory.optionalValue<int>(r'${missing}'), isNull);
      expect(
        () => factory.value<int>(r'${missing}'),
        throwsA(isA<PlaceholderResolutionException>()),
      );
      factory.beanExpressionResolver = _UpperResolver();
      expect(factory.value<String>('#{abc}'), '#{ABC}');
      expect(factory.beanExpressionResolver, isA<_UpperResolver>());
      factory.conversionService = DefaultConversionService();
      expect(factory.value<List<int>>('1,2'), [1, 2]);
    });

    test('ObjectProvider', () {
      final factory = factoryWith([english(), french()]);
      final provider = factory.provider<Greeter>();
      expect(
        () => provider.getObject(),
        throwsA(isA<NoUniqueBeanDefinitionException>()),
      );
      expect(
        () => provider.getIfAvailable(),
        throwsA(isA<NoUniqueBeanDefinitionException>()),
      );
      expect(provider.getIfUnique(), isNull);
      expect(provider.getIfUnique(German.new), isA<German>());
      String? unique;
      provider.ifUnique((g) => unique = g.greet());
      expect(unique, isNull);
      expect(provider.orderedList(), hasLength(2));
      expect(provider.toList(), hasLength(2));

      final single = factory.getBeanProvider<Greeter>(qualifier: 'french');
      expect(single.getObject(), isA<French>());
      String? available;
      single
        ..ifAvailable((g) => available = g.greet())
        ..ifUnique((g) => unique = g.greet());
      expect(available, 'bonjour');
      expect(unique, 'bonjour');

      final none = factory.provider<Counter>();
      expect(none.getIfAvailable(), isNull);
      expect(none.getIfAvailable(Counter.new), isA<Counter>());
      none.ifAvailable((_) => fail('not available'));
      expect(none.orderedList(), isEmpty);
      expect(none, isEmpty);
    });
  });

  group('errors', () {
    test('creation errors are wrapped with the chain of beans', () {
      final factory = factoryWith([
        BeanDefinition<Holder>(
          name: 'outer',
          create: (r) => Holder(r.getBean<Greeter>()),
        ),
        BeanDefinition<English>(
          name: 'inner',
          types: const [English, Greeter],
          create: (_) => throw StateError('boom'),
        ),
      ]);
      expect(
        () => factory.getBean<Holder>(),
        throwsA(
          isA<BeanCreationException>()
              .having((e) => e.beanName, 'bean', 'outer')
              .having(
                (e) => e.cause,
                'cause',
                isA<BeanCreationException>()
                    .having((e) => e.beanName, 'bean', 'inner')
                    .having((e) => e.cause, 'cause', isA<StateError>()),
              )
              .having(
                (e) => e.toString(),
                'text',
                contains('nested exception'),
              ),
        ),
      );
    });

    test('runtime cycles', () {
      final factory = factoryWith([
        BeanDefinition<Counter>(
          name: 'a',
          create: (r) {
            r.getBeanByName('b');
            return Counter();
          },
        ),
        BeanDefinition<Holder>(
          name: 'b',
          create: (r) {
            r.getBeanByName('a');
            return Holder(English());
          },
        ),
      ]);
      // Like Spring, the cycle is wrapped in the creation errors of the
      // beans being created.
      expect(
        () => factory.getBeanByName('a'),
        throwsA(
          isA<BeanCreationException>()
              .having((e) => e.beanName, 'bean', 'a')
              .having(
                (e) => e.rootCause,
                'root cause',
                isA<BeanCurrentlyInCreationException>()
                    .having((e) => e.cycle, 'cycle', ['a', 'b', 'a'])
                    .having((e) => e.beanName, 'bean', 'a'),
              ),
        ),
      );
      expect(factory.isCurrentlyInCreation('a'), isFalse);
    });
  });

  group('validation', () {
    void expectInvalid(
      List<BeanDefinition<Object>> definitions,
      Matcher matcher,
    ) => expect(
      () => factoryWith(definitions).validateBeanGraph(),
      throwsA(matcher),
    );

    BeanDefinition<Holder> holder(
      List<Dependency> dependencies, {
      List<String> dependsOn = const [],
    }) => BeanDefinition<Holder>(
      name: 'holder',
      dependencies: dependencies,
      dependsOn: dependsOn,
      create: (r) => Holder(r.getBean<Greeter>()),
    );

    test('missing, ambiguous, collection and dependsOn', () {
      // Lookup failures are wrapped per bean and injection point, like a
      // failure while the bean is created.
      Matcher unsatisfied(Matcher cause) =>
          isA<UnsatisfiedDependencyException>()
              .having((e) => e.beanName, 'bean', 'holder')
              .having((e) => e.cause, 'cause', cause);
      expectInvalid(
        [
          holder(const [Dependency(Greeter)]),
        ],
        unsatisfied(
          isA<NoSuchBeanDefinitionException>().having(
            (e) => e.requiredBy,
            'by',
            'holder',
          ),
        ),
      );
      expectInvalid([
        holder(const [Dependency(Greeter)]),
        english(),
        french(),
      ], unsatisfied(isA<NoUniqueBeanDefinitionException>()));
      expectInvalid([
        holder(const [Dependency.collection(Greeter)]),
      ], unsatisfied(isA<NoSuchBeanDefinitionException>()));
      expectInvalid([
        holder(const [Dependency.map(Greeter)]),
      ], unsatisfied(isA<NoSuchBeanDefinitionException>()));
      expectInvalid(
        [
          holder(const [], dependsOn: ['ghost']),
        ],
        isA<NoSuchBeanDefinitionException>().having(
          (e) => e.beanName,
          'name',
          'ghost',
        ),
      );
    });

    test('valid graphs', () {
      for (final definitions in <List<BeanDefinition<Object>>>[
        [
          holder(const [Dependency(Greeter, optional: true)]),
        ],
        [
          holder(const [Dependency.collection(Greeter, optional: true)]),
        ],
        [
          holder(const [Dependency.provider(Greeter)]),
        ],
        [
          holder(const [Dependency(Greeter, name: 'french')]),
          english(),
          french(),
        ],
        [
          holder(const [Dependency.collection(Greeter)]),
          english(),
          french(),
        ],
        [
          holder(const [Dependency.value(r'${x}', optional: true)]),
        ],
        [
          holder(const [], dependsOn: ['english']),
          english(),
        ],
      ]) {
        expect(
          () => factoryWith(definitions).validateBeanGraph(),
          returnsNormally,
        );
      }
      final resolvable = factoryWith([
        holder(const [Dependency(Greeter)]),
      ])..registerResolvableDependency(Greeter, English());
      expect(resolvable.validateBeanGraph, returnsNormally);
    });

    test('value placeholders are checked', () {
      final factory =
          factoryWith([
            holder(const [Dependency.value(r'${port}')]),
          ])..addEmbeddedValueResolver(
            (v) => throw PlaceholderResolutionException(
              'Could not resolve',
              'port',
              [v],
            ),
          );
      expect(
        factory.validateBeanGraph,
        throwsA(
          isA<UnsatisfiedDependencyException>()
              .having((e) => e.beanName, 'bean', 'holder')
              .having(
                (e) => e.toString(),
                'text',
                contains(r'@Value("${port}")'),
              ),
        ),
      );
    });

    test('cycles through dependencies and dependsOn', () {
      expectInvalid(
        [
          BeanDefinition<Counter>(
            name: 'a',
            dependencies: const [Dependency(Holder)],
            create: (_) => Counter(),
          ),
          BeanDefinition<Holder>(
            name: 'b',
            dependsOn: const ['a'],
            create: (_) => Holder(English()),
          ),
        ],
        isA<BeanCurrentlyInCreationException>().having(
          (e) => e.cycle,
          'cycle',
          ['a', 'b', 'a'],
        ),
      );
    });

    test('dependency descriptions', () {
      expect(
        const Dependency(Greeter, qualifier: 'x').toString(),
        "Greeter('x')",
      );
      expect(
        const Dependency.collection(Greeter).toString(),
        'collection of Greeter',
      );
      expect(const Dependency.map(Greeter).toString(), 'map of Greeter');
      expect(const Dependency.provider(Greeter).kind, DependencyKind.provider);
    });
  });

  group('singletons and hierarchy', () {
    test('registerSingleton', () {
      final english = English();
      final factory = DefaultListableBeanFactory()
        ..registerSingleton('en', english, types: [English, Greeter]);
      expect(factory.getBean<Greeter>(), same(english));
      expect(
        () => factory.registerSingleton('en', English()),
        throwsA(isA<BeanDefinitionOverrideException>()),
      );
      factory.registerSingleton('plain', Counter());
      expect(factory.getBean<Counter>(), isA<Counter>());
      factory.destroySingletons();
      expect(
        factory.getBean<Greeter>(),
        same(english),
        reason: 'manual singletons survive',
      );
    });

    test('parent factory', () {
      final parent = factoryWith([
        english(aliases: ['en']),
        french(),
      ]);
      final child = factoryWith([
        BeanDefinition<German>(
          name: 'german',
          types: const [German, Greeter],
          create: (_) => German(),
        ),
      ], parent: parent);
      expect(child.parentBeanFactory, same(parent));
      expect(child.getBean<English>(), same(parent.getBean<English>()));
      expect(child.findBean<French>(), isA<French>());
      expect(child.getBeanByName('en'), isA<English>());
      expect(child.containsBean('english'), isTrue);
      expect(child.containsLocalBean('english'), isFalse);
      expect(child.containsBeanOfType(English), isTrue);
      expect(
        child.containsBeanOfType(English, includeAncestors: false),
        isFalse,
      );
      expect(child.isSingleton('english'), isTrue);
      expect(child.isPrototype('english'), isFalse);
      expect(child.getType('english'), English);
      expect(child.getAliases('english'), ['en']);
      expect(child.dependencyList<Greeter>(), hasLength(3));
      expect(child.dependencyMap<Greeter>(qualifier: 'en').keys, ['english']);
      expect(child.getBean<Greeter>(), isA<German>());
      final validated = factoryWith([
        BeanDefinition<Holder>(
          name: 'h',
          dependencies: const [
            Dependency(French),
            Dependency.collection(English),
          ],
          dependsOn: const ['english'],
          create: (r) => Holder(r.getBean<French>()),
        ),
      ], parent: parent);
      expect(validated.validateBeanGraph, returnsNormally);
      child.parentBeanFactory = null;
      expect(child.findBean<English>(), isNull);
    });
  });
}

class _Wrapped implements Greeter {
  _Wrapped(this.inner);
  final Greeter inner;
  @override
  String greet() => '[${inner.greet()}]';
}

class _Wrapping extends BeanPostProcessor {
  @override
  Object postProcessAfterInitialization(Object bean, String beanName) =>
      bean is Greeter ? _Wrapped(bean) : bean;
}

class _Smart implements SmartInitializingSingleton {
  @override
  void afterSingletonsInstantiated() =>
      log.add('smart:afterSingletonsInstantiated');
}

class _FailingFactory extends FactoryBean<Greeter> {
  @override
  Greeter getObject() => throw StateError('no product');
}

class _UpperResolver implements BeanExpressionResolver {
  @override
  Object? evaluate(String value, BeanFactory beanFactory) =>
      value.toUpperCase();
}
