import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Wraps every [LifecycleBean] in a [_Wrapper], like an AOP proxy.
class _WrappingPostProcessor extends BeanPostProcessor {
  @override
  Object postProcessAfterInitialization(Object bean, String beanName) =>
      bean is LifecycleBean ? _Wrapper(bean) : bean;
}

class _Wrapper {
  _Wrapper(this.target);
  final LifecycleBean target;
}

void main() {
  setUp(log.clear);

  group('manual singletons', () {
    test('an overriding definition replaces a registered singleton', () {
      final factory = DefaultListableBeanFactory()
        ..allowBeanDefinitionOverriding = true
        ..registerSingleton('greeter', English(), types: [Greeter]);
      expect(factory.getBeanByName('greeter'), isA<English>());
      factory.registerBeanDefinition(
        BeanDefinition<French>(
          name: 'greeter',
          types: const [French, Greeter],
          create: (_) => French(),
        ),
      );
      expect(factory.getBeanByName('greeter'), isA<French>());
      expect(factory.getBean<Greeter>(), isA<French>());
    });

    test('removing the definition forgets the singleton', () {
      final factory = DefaultListableBeanFactory()
        ..registerSingleton('greeter', English(), types: [Greeter]);
      factory.removeBeanDefinition('greeter');
      expect(factory.containsSingleton('greeter'), isFalse);
      expect(factory.getSingleton('greeter'), isNull);
      factory.registerSingleton('greeter', French(), types: [Greeter]);
      expect(factory.getBean<Greeter>(), isA<French>());
    });

    test('registerSingleton rejects alias clashes, works when frozen', () {
      final factory = DefaultListableBeanFactory()
        ..registerBeanDefinition(english(aliases: ['en']));
      expect(
        () => factory.registerSingleton('en', French()),
        throwsA(isA<BeanDefinitionOverrideException>()),
      );
      // Like Spring, ready-made objects may be added after the freeze.
      factory
        ..freezeConfiguration()
        ..registerSingleton('late', French());
      expect(factory.getBeanByName('late'), isA<French>());
    });
  });

  test('parent beans in collections match qualifiers, not only names', () {
    final parent = DefaultListableBeanFactory()
      ..registerBeanDefinition(english(qualifiers: {'formal'}))
      ..registerBeanDefinition(french());
    final child = DefaultListableBeanFactory(parentBeanFactory: parent);
    expect(child.optionalDependencyMap<Greeter>(qualifier: 'formal')!.keys, [
      'english',
    ]);
    expect(child.optionalDependencyMap<Greeter>(qualifier: 'french')!.keys, [
      'french',
    ]);
    expect(child.optionalDependencyMap<Greeter>(qualifier: 'none'), isNull);
  });

  test('scoped beans are destroyed through the raw instance', () {
    final scope = SimpleMapScope();
    final factory = DefaultListableBeanFactory()
      ..registerBeanDefinition(lifecycleDefinition('s', scope: 'x'))
      ..registerScope('x', scope)
      ..addBeanPostProcessor(_WrappingPostProcessor());
    final exposed = factory.getBeanByName('s');
    expect(exposed, isA<_Wrapper>());
    factory.destroyScopedBean('s');
    expect(log, containsAllInOrder(['s:preDestroy', 's:destroy']));
    expect(log, contains('s:destroyMethod'));
  });
}
