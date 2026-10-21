import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('lookups after refresh follow later registrations (cache cleared)', () {
    final factory = DefaultListableBeanFactory()
      ..registerBeanDefinition(
        BeanDefinition<English>(
          name: 'english',
          types: const [English, Greeter],
          create: (_) => English(),
        ),
      )
      ..freezeConfiguration()
      ..preInstantiateSingletons();
    expect(factory.getBean<Greeter>(), isA<English>());
    expect(factory.getBean<Greeter>(), same(factory.getBean<Greeter>()));

    // Allowed after freezing, like Spring; must invalidate the caches.
    factory.registerSingleton(
      'french',
      French(),
      types: const [French, Greeter],
    );
    expect(
      () => factory.getBean<Greeter>(),
      throwsA(isA<NoUniqueBeanDefinitionException>()),
    );
    expect(factory.getBeanNamesForType(Greeter), ['english', 'french']);
  });

  test('lookups before freezing see new definitions', () {
    final factory = DefaultListableBeanFactory();
    expect(factory.findBean<Greeter>(), isNull);
    factory.registerBeanDefinition(
      BeanDefinition<German>(
        name: 'german',
        types: const [German, Greeter],
        create: (_) => German(),
      ),
    );
    expect(factory.findBean<Greeter>(), isA<German>());
    factory.removeBeanDefinition('german');
    expect(factory.findBean<Greeter>(), isNull);
  });
}
