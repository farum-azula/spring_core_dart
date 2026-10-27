import 'package:spring_core_dart/jakarta.dart' as jakarta;
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

import 'support.dart';

DefaultListableBeanFactory factoryWith(List<BeanDefinition<Object>> list) {
  final factory = DefaultListableBeanFactory();
  list.forEach(factory.registerBeanDefinition);
  return factory;
}

/// A configuration that is a Greeter itself and looks up greeters later.
class LazyConfig implements Greeter {
  LazyConfig(this.greeters);
  final ObjectProvider<Greeter> greeters;
  @override
  String greet() => 'config';
}

class Cart {
  Cart() : id = ++created;
  static int created = 0;
  final int id;
  final items = <String>[];
  int get size => items.length;
}

/// What the generator writes for `@Scope(proxyMode:)` (its lazy proxy).
class CartProxy implements Cart {
  CartProxy(this._target);
  final Cart Function() _target;
  @override
  int get id => _target().id;
  @override
  List<String> get items => _target().items;
  @override
  int get size => _target().size;
}

class Shop {
  Shop(this.cart);
  final Cart cart;
}

class Clocked {
  Clocked(this.greeter);
  final jakarta.Provider<Greeter> greeter;
}

class ByName {
  Greeter? greeter;
  Greeter? other;
}

void main() {
  setUp(log.clear);

  group('self references', () {
    test('a collection falls back to own @Bean products, never itself', () {
      final factory = factoryWith([
        BeanDefinition<LazyConfig>(
          name: 'cfg',
          types: const [LazyConfig, Greeter],
          create: (r) => LazyConfig(r.provider<Greeter>()),
        ),
        BeanDefinition<German>(
          name: 'own',
          types: const [German, Greeter],
          factoryBeanName: 'cfg',
          factoryMethodName: 'own',
          create: (_) => German(),
        ),
      ]);
      final config = factory.getBean<LazyConfig>();
      expect(config.greeters.orderedList(), [isA<German>()]);
      factory.registerBeanDefinition(english());
      expect(config.greeters.orderedList(), [isA<English>()]);
    });
  });

  group('scoped proxies', () {
    late SimpleMapScope scope;
    late DefaultListableBeanFactory factory;
    late List<SpringLogRecord> records;

    setUp(() {
      records = [];
      final saved = SpringLog.handler;
      SpringLog.handler = records.add;
      addTearDown(() => SpringLog.handler = saved);
      scope = SimpleMapScope();
      factory = factoryWith([
        BeanDefinition<Cart>(
          name: 'cart',
          scope: 'session',
          scopedProxy: CartProxy.new,
          create: (_) => Cart(),
        ),
        BeanDefinition<Shop>(
          name: 'shop',
          dependencies: const [Dependency(Cart)],
          create: (r) => Shop(r.dependency<Cart>()),
        ),
      ])..registerScope('session', scope);
    });

    test('a singleton reaches the current instance through the proxy', () {
      factory.validateBeanGraph();
      final shop = factory.getBean<Shop>();
      expect(shop.cart, isA<CartProxy>());
      expect(factory.getBean<Cart>(), same(shop.cart));
      shop.cart.items.add('book');
      final first = shop.cart.id;
      expect(shop.cart.size, 1);
      scope.destroy(); // a new session
      expect(shop.cart.id, isNot(first));
      expect(shop.cart.size, 0);
      expect(records, isEmpty, reason: 'no warning with a proxy');
    });

    test('the proxy breaks cycles and is dropped with the definition', () {
      final proxy = factory.getBean<Cart>();
      factory
        ..removeBeanDefinition('cart')
        ..registerBeanDefinition(
          BeanDefinition<Cart>(
            name: 'cart',
            scope: 'session',
            scopedProxy: CartProxy.new,
            dependencies: const [Dependency(Shop)],
            create: (r) {
              r.dependency<Shop>();
              return Cart();
            },
          ),
        );
      expect(factory.validateBeanGraph, returnsNormally);
      expect(factory.getBean<Cart>(), isNot(same(proxy)));
    });
  });

  group('jakarta', () {
    test('Provider<T> injection points get the lazy provider', () {
      final factory = factoryWith([
        english(),
        BeanDefinition<Clocked>(
          name: 'clocked',
          create: (r) => Clocked(r.provider<Greeter>()),
        ),
      ]);
      expect(factory.getBean<Clocked>().greeter.get(), isA<English>());
    });

    BeanDefinition<ByName> byName(
      void Function(ByName bean, DependencyResolver r) inject, {
      List<Dependency> dependencies = const [],
    }) => BeanDefinition<ByName>(
      name: 'byName',
      dependencies: dependencies,
      create: (_) => ByName(),
      inject: inject,
    );

    test('@Resource injects by name, else by type for a default name', () {
      final factory = factoryWith([
        english(),
        french(),
        byName(
          (bean, r) => bean
            ..greeter = r.resource<Greeter>('french', fallbackToType: true)
            ..other = r.optionalResource<Greeter>('missing'),
          dependencies: const [
            Dependency.resource(Greeter, 'french', fallbackToType: true),
            Dependency.resource(Greeter, 'missing', optional: true),
          ],
        ),
      ])..validateBeanGraph();
      final bean = factory.getBean<ByName>();
      expect(bean.greeter, isA<French>());
      expect(bean.other, isNull);
      expect(factory.getDependentBeans('french'), ['byName']);

      final fallback = factoryWith([
        english(),
        byName(
          (bean, r) =>
              bean.greeter = r.resource<Greeter>('main', fallbackToType: true),
        ),
      ]);
      expect(fallback.getBean<ByName>().greeter, isA<English>());
    });

    test('@Resource with an explicit name fails without that bean', () {
      final factory = factoryWith([
        english(),
        byName(
          (bean, r) => bean.greeter = r.resource<Greeter>('main'),
          dependencies: const [Dependency.resource(Greeter, 'main')],
        ),
      ]);
      expect(
        factory.validateBeanGraph,
        throwsA(
          isA<UnsatisfiedDependencyException>()
              .having((e) => e.dependency, 'point', "@Resource Greeter 'main'")
              .having(
                (e) => e.cause,
                'cause',
                isA<NoSuchBeanDefinitionException>(),
              ),
        ),
      );
      expect(
        factory.getBean<ByName>,
        throwsA(isA<UnsatisfiedDependencyException>()),
      );
      final wrongType = factoryWith([
        BeanDefinition<Counter>(name: 'main', create: (_) => Counter()),
        byName((bean, r) => bean.greeter = r.resource<Greeter>('main')),
      ]);
      expect(
        wrongType.getBean<ByName>,
        throwsA(
          isA<UnsatisfiedDependencyException>().having(
            (e) => e.cause,
            'cause',
            isA<BeanNotOfRequiredTypeException>(),
          ),
        ),
      );
    });
  });
}
