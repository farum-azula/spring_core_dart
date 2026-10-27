// Beans Spring accepts and the generator now writes: a @Bean method that
// returns null (Spring's NullBean) and beans of function or record types.
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

class Cache {
  final events = <String>[];
}

class Store {
  Store(this.cache);
  final Cache? cache;
}

typedef Greet = String Function(String);

Type _typeOf<T>() => T;

void main() {
  group('a bean whose create returns null (NullBean)', () {
    late List<String> calls;
    late DefaultListableBeanFactory factory;

    setUp(() {
      calls = [];
      factory = DefaultListableBeanFactory()
        ..registerBeanDefinition(
          BeanDefinition<Cache>(
            name: 'cache',
            create: (_) => null,
            postConstruct: (_) => calls.add('postConstruct'),
            preDestroy: (_) => calls.add('preDestroy'),
          ),
        )
        ..registerBeanDefinition(
          BeanDefinition<Store>(
            name: 'store',
            dependencies: const [Dependency(Cache, optional: true)],
            create: (r) => Store(r.optionalDependency<Cache>()),
          ),
        );
    });

    test('exists by name as a NullBean', () {
      expect(factory.containsBean('cache'), isTrue);
      final bean = factory.getBeanByName('cache');
      expect(bean, isA<NullBean>());
      expect(bean.toString(), 'null');
      // Each null bean is its own instance, as in Spring.
      expect(NullBean(), isNot(same(NullBean())));
    });

    test('is absent for type lookups and injection', () {
      expect(
        () => factory.getBean<Cache>(),
        throwsA(isA<NoSuchBeanDefinitionException>()),
      );
      expect(factory.findBean<Cache>(), isNull);
      expect(factory.getBeansOfType<Cache>(), isEmpty);
      expect(factory.getSortedBeans<Cache>(), isEmpty);
      expect(factory.getBeanProvider<Cache>().getIfAvailable(), isNull);
      expect(factory.getBeanProvider<Cache>().toList(), isEmpty);
      // An optional point gets null.
      expect(factory.getBean<Store>().cache, isNull);
    });

    test('a required injection point fails', () {
      factory.registerBeanDefinition(
        BeanDefinition<Store>(
          name: 'strict',
          create: (r) => Store(r.dependency<Cache>()),
        ),
      );
      expect(
        () => factory.getBeanByName('strict'),
        throwsA(
          isA<BeanCreationException>().having(
            (e) => '$e',
            'message',
            contains('NoSuchBeanDefinitionException'),
          ),
        ),
      );
    });

    test('is neither initialized nor destroyed', () {
      factory
        ..preInstantiateSingletons()
        ..destroySingletons();
      expect(calls, isEmpty);
    });

    test('NullBean.orNull unwraps it for inter-bean calls', () {
      expect(NullBean.orNull<Cache>(factory.getBeanByName('cache')), isNull);
      final cache = Cache();
      expect(NullBean.orNull<Cache>(cache), same(cache));
    });
  });

  group('function and record beans', () {
    test('are found and injected by their exact type', () {
      final factory = DefaultListableBeanFactory()
        ..registerBeanDefinition(
          BeanDefinition<Greet>(
            name: 'greet',
            types: const [Greet, Function],
            create: (_) =>
                (name) => 'hi $name',
          ),
        )
        ..registerBeanDefinition(
          BeanDefinition<(int, String)>(
            name: 'pair',
            types: [_typeOf<(int, String)>(), Record],
            create: (_) => (1, 'one'),
          ),
        )
        ..registerBeanDefinition(
          BeanDefinition<String Function(int)>(
            name: 'label',
            types: [_typeOf<String Function(int)>(), Function],
            create: (_) =>
                (i) => '#$i',
          ),
        );
      expect(factory.getBean<String Function(String)>()('Ada'), 'hi Ada');
      expect(factory.getBean<(int, String)>(), (1, 'one'));
      expect(factory.getBean<String Function(int)>()(2), '#2');
      expect(factory.getBeansOfType<Function>().keys, ['greet', 'label']);
      // Another function type is another bean type.
      expect(factory.findBean<String Function(Object)>(), isNull);
    });
  });
}
