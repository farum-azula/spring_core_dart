import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

abstract interface class Greeter {
  String greet();
}

class English implements Greeter {
  @override
  String greet() => 'hello';
}

class French implements Greeter {
  @override
  String greet() => 'bonjour';
}

/// A `@Primary` decorator that reaches its delegate through a provider.
class Loud implements Greeter {
  Loud(this.delegate);
  final ObjectProvider<Greeter> delegate;
  @override
  String greet() => delegate.getObject().greet().toUpperCase();
}

/// A `@Primary` composite iterating the other greeters through a provider.
class Chorus implements Greeter {
  Chorus(this.all);
  final ObjectProvider<Greeter> all;
  @override
  String greet() => all.map((g) => g.greet()).join(' ');
  String ordered() => all.orderedList().map((g) => g.greet()).join(' ');
}

class Holder {
  Holder(this.greeters);
  final ObjectProvider<Greeter> greeters;
}

AnnotationConfigApplicationContext start(List<BeanDefinition<Object>> beans) =>
    AnnotationConfigApplicationContext([BeanModule('m', beans)])..refresh();

BeanDefinition<English> english({int? order}) => BeanDefinition<English>(
  name: 'english',
  types: const [English, Greeter],
  order: order,
  create: (_) => English(),
);

BeanDefinition<French> french({int? order}) => BeanDefinition<French>(
  name: 'french',
  types: const [French, Greeter],
  order: order,
  create: (_) => French(),
);

void main() {
  group('ObjectProvider injection points resolve for the injecting bean', () {
    test('a @Primary decorator gets the other bean, not itself', () {
      final context = start([
        english(),
        BeanDefinition<Loud>(
          name: 'loud',
          types: const [Loud, Greeter],
          primary: true,
          dependencies: const [Dependency.provider(Greeter, name: 'delegate')],
          create: (r) => Loud(r.provider<Greeter>(name: 'delegate')),
        ),
      ]);
      // Before: getObject() returned the primary decorator itself and
      // greet() recursed until a StackOverflowError.
      expect(context.getBean<Greeter>().greet(), 'HELLO');
      context.close();
    });

    test('a @Primary composite iterates the other beans only', () {
      final context = start([
        english(order: 2),
        french(order: 1),
        BeanDefinition<Chorus>(
          name: 'chorus',
          types: const [Chorus, Greeter],
          primary: true,
          create: (r) => Chorus(r.provider<Greeter>()),
        ),
      ]);
      final chorus = context.getBean<Greeter>() as Chorus;
      expect(chorus.greet(), 'hello bonjour'); // registration order
      expect(chorus.ordered(), 'bonjour hello'); // @Order
      expect(chorus.all, hasLength(2));
      context.close();
    });

    test('the parameter name selects among several candidates', () {
      final factory = DefaultListableBeanFactory()
        ..registerBeanDefinition(english())
        ..registerBeanDefinition(french())
        ..registerBeanDefinition(
          BeanDefinition<Holder>(
            name: 'holder',
            create: (r) => Holder(r.provider<Greeter>(name: 'french')),
          ),
        );
      final holder = factory.getBean<Holder>();
      expect(holder.greeters.getObject(), isA<French>());
      expect(holder.greeters.getIfUnique(), isA<French>());
      // The programmatic provider has no injection point name.
      expect(
        () => factory.getBeanProvider<Greeter>().getObject(),
        throwsA(isA<NoUniqueBeanDefinitionException>()),
      );
    });

    test('beans resolved later are registered as dependencies', () {
      final log = <String>[];
      final factory = DefaultListableBeanFactory()
        ..registerBeanDefinition(
          BeanDefinition<English>(
            name: 'english',
            types: const [English, Greeter],
            create: (_) => English(),
            preDestroy: (_) => log.add('english'),
          ),
        )
        ..registerBeanDefinition(
          BeanDefinition<Holder>(
            name: 'holder',
            create: (r) => Holder(r.provider<Greeter>()),
            preDestroy: (_) => log.add('holder'),
          ),
        );
      final holder = factory.getBean<Holder>();
      holder.greeters.getObject(); // after holder's creation
      expect(factory.getDependentBeans('english'), ['holder']);
      factory.destroySingletons();
      expect(log, ['holder', 'english']);
    });

    test('a provider is never an edge of the bean graph', () {
      expect(
        () => start([
          BeanDefinition<Loud>(
            name: 'loud',
            types: const [Loud, Greeter],
            dependencies: const [
              Dependency.provider(Greeter, name: 'delegate'),
            ],
            create: (r) => Loud(r.provider<Greeter>(name: 'delegate')),
          ),
        ]).close(),
        returnsNormally,
      );
    });

    test('toString and isEmpty create no beans', () {
      var created = 0;
      final factory = DefaultListableBeanFactory()
        ..registerBeanDefinition(
          BeanDefinition<English>(
            name: 'english',
            types: const [English, Greeter],
            create: (_) {
              created++;
              return English();
            },
          ),
        );
      final provider = factory.getBeanProvider<Greeter>();
      expect(provider.toString(), 'ObjectProvider<Greeter>');
      expect(provider.isEmpty, isFalse);
      expect(provider.isNotEmpty, isTrue);
      expect(provider.length, 1);
      expect(factory.getBeanProvider<French>().isEmpty, isTrue);
      expect(created, 0);
      expect(provider.first, isA<English>());
      expect(created, 1);
    });
  });
}
