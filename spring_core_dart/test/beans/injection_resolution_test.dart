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

class Composite implements Greeter {
  Composite(this.greeters);
  final List<Greeter> greeters;
  @override
  String greet() => greeters.map((g) => g.greet()).join(' ');
}

class Setter {
  Greeter? greeter;
}

BeanDefinition<OrderedGreeter> ordered(
  String name,
  int ordered, {
  int? order,
  String? factoryMethodName,
}) => BeanDefinition<OrderedGreeter>(
  name: name,
  types: const [OrderedGreeter, Greeter],
  order: order,
  factoryBeanName: factoryMethodName == null ? null : 'config',
  factoryMethodName: factoryMethodName,
  create: (_) => OrderedGreeter(ordered),
);

void main() {
  group('UnsatisfiedDependencyException', () {
    final unsatisfied = isA<UnsatisfiedDependencyException>();

    test('a missing constructor dependency names the bean and the point', () {
      final factory = factoryWith([
        BeanDefinition<Holder>(
          name: 'holder',
          create: (r) => Holder(r.dependency<Greeter>(name: 'greeter')),
        ),
      ]);
      expect(
        () => factory.getBean<Holder>(),
        throwsA(
          unsatisfied
              .having((e) => e.beanName, 'beanName', 'holder')
              .having((e) => e.dependency, 'dependency', "Greeter 'greeter'")
              .having(
                (e) => e.cause,
                'cause',
                isA<NoSuchBeanDefinitionException>(),
              )
              .having(
                (e) => e.message,
                'message',
                allOf(
                  contains("Bean 'holder'"),
                  contains("Greeter 'greeter'"),
                  contains('No bean of type Greeter'),
                ),
              ),
        ),
      );
    });

    test('an ambiguous dependency keeps the ambiguity as the cause', () {
      final factory = factoryWith([
        english(),
        french(),
        BeanDefinition<Holder>(
          name: 'holder',
          create: (r) => Holder(r.dependency<Greeter>(name: 'greeter')),
        ),
      ]);
      expect(
        () => factory.getBean<Holder>(),
        throwsA(
          unsatisfied
              .having((e) => e.beanName, 'beanName', 'holder')
              .having(
                (e) => e.cause,
                'cause',
                isA<NoUniqueBeanDefinitionException>(),
              ),
        ),
      );
    });

    test('a failing dependency deeper down shows the chain of beans', () {
      final factory = factoryWith([
        BeanDefinition<Holder>(
          name: 'outer',
          create: (r) => Holder(r.dependency<Composite>(name: 'composite')),
        ),
        BeanDefinition<Composite>(
          name: 'inner',
          types: const [Composite, Greeter],
          create: (r) => Composite(r.dependencyList<Greeter>(qualifier: 'x')),
        ),
        BeanDefinition<Counter>(
          name: 'broken',
          create: (_) => throw StateError('boom'),
        ),
        BeanDefinition<Setter>(
          name: 'setter',
          create: (_) => Setter(),
          inject: (bean, r) =>
              bean.greeter = r.dependency<Greeter>(qualifier: 'missing'),
        ),
        BeanDefinition<Holder>(
          name: 'counting',
          create: (r) =>
              Holder(English())
                ..counter = r.dependency<Counter>(name: 'counter'),
        ),
      ]);
      expect(
        () => factory.getBean<Holder>(qualifier: 'outer'),
        throwsA(
          unsatisfied
              .having((e) => e.beanName, 'beanName', 'outer')
              .having(
                (e) => e.dependency,
                'dependency',
                "Composite 'composite'",
              )
              .having(
                (e) => e.cause,
                'cause',
                unsatisfied
                    .having((e) => e.beanName, 'beanName', 'inner')
                    .having(
                      (e) => e.dependency,
                      'dependency',
                      "collection of Greeter('x')",
                    )
                    .having(
                      (e) => e.cause,
                      'cause',
                      isA<NoSuchBeanDefinitionException>(),
                    ),
              )
              .having(
                (e) => e.message,
                'message',
                allOf(contains("'outer'"), contains("'inner'")),
              ),
        ),
      );
      // A creation failure of the dependency is the cause (Spring's
      // BeanCreationException chain), not an injection failure of its own.
      expect(
        () => factory.getBean<Holder>(qualifier: 'counting'),
        throwsA(
          unsatisfied
              .having((e) => e.beanName, 'beanName', 'counting')
              .having((e) => e.dependency, 'dependency', "Counter 'counter'")
              .having(
                (e) => e.cause,
                'cause',
                isA<BeanCreationException>()
                    .having((e) => e.beanName, 'beanName', 'broken')
                    .having((e) => e.cause, 'cause', isA<StateError>()),
              ),
        ),
      );
      // Setter and field injection points are wrapped too.
      expect(
        () => factory.getBean<Setter>(),
        throwsA(
          unsatisfied
              .having((e) => e.beanName, 'beanName', 'setter')
              .having((e) => e.dependency, 'dependency', "Greeter('missing')"),
        ),
      );
    });

    test('validateBeanGraph reports declared dependencies the same way', () {
      Matcher wrapped(String point, Matcher cause) => throwsA(
        unsatisfied
            .having((e) => e.beanName, 'beanName', 'holder')
            .having((e) => e.dependency, 'dependency', point)
            .having((e) => e.cause, 'cause', cause),
      );
      BeanDefinition<Holder> holder(Dependency dependency) =>
          BeanDefinition<Holder>(
            name: 'holder',
            dependencies: [dependency],
            create: (_) => Holder(English()),
          );
      expect(
        factoryWith([holder(const Dependency(Greeter))]).validateBeanGraph,
        wrapped('Greeter', isA<NoSuchBeanDefinitionException>()),
      );
      expect(
        factoryWith([
          english(),
          french(),
          holder(const Dependency(Greeter, name: 'greeter')),
        ]).validateBeanGraph,
        wrapped("Greeter 'greeter'", isA<NoUniqueBeanDefinitionException>()),
      );
      expect(
        factoryWith([
          holder(const Dependency.collection(Greeter, qualifier: 'x')),
        ]).validateBeanGraph,
        wrapped(
          "collection of Greeter('x')",
          isA<NoSuchBeanDefinitionException>(),
        ),
      );
      expect(
        (factoryWith([holder(const Dependency.value(r'${missing}'))])
              ..addEmbeddedValueResolver(
                (v) => throw PlaceholderResolutionException(
                  'No value',
                  'missing',
                  [v],
                ),
              ))
            .validateBeanGraph,
        wrapped(r'@Value("${missing}")', isA<PlaceholderResolutionException>()),
      );
      // Cycles are reported as such, not as unsatisfied dependencies.
      expect(
        factoryWith([
          BeanDefinition<Composite>(
            name: 'self',
            types: const [Composite, Greeter],
            dependencies: const [Dependency(Greeter, qualifier: 'self')],
            create: (r) =>
                Composite([r.dependency<Greeter>(qualifier: 'self')]),
          ),
        ]).validateBeanGraph,
        throwsA(isA<BeanCurrentlyInCreationException>()),
      );
    });

    test('lookups outside bean creation are not wrapped', () {
      final factory = factoryWith([]);
      expect(
        () => factory.dependency<Greeter>(),
        throwsA(
          isA<NoSuchBeanDefinitionException>().having(
            (e) => e,
            'type',
            isNot(unsatisfied),
          ),
        ),
      );
    });
  });

  group('aliases from registerAlias', () {
    test('match @Qualifier, parameter names and qualified lookups', () {
      final factory = factoryWith([english(), french()])
        ..registerAlias('french', 'fr')
        ..registerAlias('fr', 'francais');
      expect(factory.dependency<Greeter>(qualifier: 'fr'), isA<French>());
      expect(factory.dependency<Greeter>(qualifier: 'francais'), isA<French>());
      expect(factory.dependency<Greeter>(name: 'francais'), isA<French>());
      expect(factory.dependencyList<Greeter>(qualifier: 'fr'), [isA<French>()]);
      expect(factory.dependencyMap<Greeter>(qualifier: 'fr').keys, ['french']);
      expect(factory.getBean<Greeter>(qualifier: 'fr'), isA<French>());
      expect(factory.containsBeanOfType(Greeter, qualifier: 'fr'), isTrue);
      expect(
        factory.getBeanProvider<Greeter>(qualifier: 'francais').getObject(),
        isA<French>(),
      );
    });

    test('a removed alias no longer matches', () {
      final factory = factoryWith([english(), french()])
        ..registerAlias('french', 'fr');
      expect(factory.dependency<Greeter>(qualifier: 'fr'), isA<French>());
      factory.removeAlias('fr');
      expect(
        () => factory.dependency<Greeter>(qualifier: 'fr'),
        throwsA(isA<NoSuchBeanDefinitionException>()),
      );
      expect(
        () => factory.dependency<Greeter>(name: 'fr'),
        throwsA(isA<NoUniqueBeanDefinitionException>()),
      );
    });

    test('aliases of parent beans count in child lookups', () {
      final parent = factoryWith([french()])..registerAlias('french', 'fr');
      final child = factoryWith([english()], parent: parent);
      expect(child.dependency<Greeter>(qualifier: 'fr'), isA<French>());
      expect(child.dependency<Greeter>(name: 'fr'), isA<French>());
    });

    test('validateBeanGraph accepts a qualifier that is an alias', () {
      final factory = factoryWith([
        english(),
        french(),
        BeanDefinition<Holder>(
          name: 'holder',
          dependencies: const [Dependency(Greeter, qualifier: 'fr')],
          create: (r) => Holder(r.dependency<Greeter>(qualifier: 'fr')),
        ),
      ]);
      expect(
        factory.validateBeanGraph,
        throwsA(isA<UnsatisfiedDependencyException>()),
      );
      factory.registerAlias('french', 'fr');
      expect(factory.validateBeanGraph, returnsNormally);
      expect(factory.getBean<Holder>().greeter, isA<French>());
    });
  });

  group('autowireCandidate: false', () {
    test('is excluded from injection, even qualified', () {
      final factory = factoryWith([
        english(autowireCandidate: false, qualifiers: {'en'}),
        french(),
      ]);
      expect(
        () => factory.dependency<Greeter>(qualifier: 'english'),
        throwsA(isA<NoSuchBeanDefinitionException>()),
      );
      expect(
        () => factory.dependency<Greeter>(qualifier: 'en'),
        throwsA(isA<NoSuchBeanDefinitionException>()),
      );
      expect(factory.optionalDependency<Greeter>(qualifier: 'en'), isNull);
      expect(factory.optionalDependencyList<Greeter>(qualifier: 'en'), isNull);
      expect(factory.dependency<Greeter>(name: 'english'), isA<French>());
      expect(factory.dependencyList<Greeter>(), [isA<French>()]);
      expect(factory.dependencyMap<Greeter>().keys, ['french']);
      final holder = BeanDefinition<Holder>(
        name: 'holder',
        dependencies: const [Dependency(Greeter, qualifier: 'en')],
        create: (r) => Holder(r.dependency<Greeter>(qualifier: 'en')),
      );
      factory.registerBeanDefinition(holder);
      expect(
        factory.validateBeanGraph,
        throwsA(isA<UnsatisfiedDependencyException>()),
      );
    });

    test('is still found by getBean, findBean and getBeansOfType', () {
      final factory = factoryWith([
        english(autowireCandidate: false),
        french(),
      ]);
      expect(factory.getBean<Greeter>(qualifier: 'english'), isA<English>());
      expect(factory.findBean<Greeter>(qualifier: 'english'), isA<English>());
      expect(factory.getBean<English>(), isA<English>());
      expect(factory.getBean<Greeter>(), isA<French>());
      expect(factory.getBeansOfType<Greeter>().keys, ['english', 'french']);
      expect(factory.getBeanByName('english'), isA<English>());
      // Alone, the non-candidate is the bean of its type.
      final alone = factoryWith([english(autowireCandidate: false)]);
      expect(alone.getBean<Greeter>(), isA<English>());
      expect(alone.findBean<Greeter>(), isA<English>());
      expect(alone.getBeanProvider<Greeter>().getIfAvailable(), isA<English>());
      expect(alone.getBeanProvider<Greeter>().getIfUnique(), isA<English>());
      expect(
        () => alone.dependency<Greeter>(),
        throwsA(isA<NoSuchBeanDefinitionException>()),
      );
      expect(alone.provider<Greeter>().getIfAvailable(), isNull);
    });
  });

  group('collection order', () {
    test('lists are sorted; maps and sets keep registration order', () {
      final factory = factoryWith([
        french(order: 2),
        english(order: 1),
        ordered('zero', 0),
      ]);
      expect(factory.dependencyMap<Greeter>().keys, [
        'french',
        'english',
        'zero',
      ]);
      expect(factory.dependencyMap<Greeter>().values.toSet().toList(), [
        isA<French>(),
        isA<English>(),
        isA<OrderedGreeter>(),
      ]);
      expect(factory.dependencyList<Greeter>(), [
        isA<OrderedGreeter>(),
        isA<English>(),
        isA<French>(),
      ]);
      final parent = factoryWith([ordered('parentZero', 0)]);
      final child = factoryWith([french(order: 2)], parent: parent);
      expect(child.dependencyMap<Greeter>().keys, ['french', 'parentZero']);
    });

    test('@Order on a @Bean method beats Ordered; a class @Order does not', () {
      final factory = factoryWith([
        ordered('classOrder', 10, order: 0),
        ordered('methodOrder', 20, order: 1, factoryMethodName: 'methodOrder'),
        english(order: 5),
        ordered('plain', 3),
      ]);
      List<String> names(List<Greeter> greeters) =>
          greeters.map((g) => g.greet()).toList();
      const expected = ['ordered 20', 'ordered 3', 'hello', 'ordered 10'];
      expect(names(factory.dependencyList<Greeter>()), expected);
      expect(names(factory.getSortedBeans<Greeter>()), expected);
      expect(names(factory.getBeanProvider<Greeter>().orderedList()), expected);
      expect(names(factory.provider<Greeter>().orderedList()), expected);
    });
  });
}
