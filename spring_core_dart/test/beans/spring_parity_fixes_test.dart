import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

import 'support.dart';

class Closeable implements InitializingBean, DisposableBean {
  @override
  void afterPropertiesSet() => log.add('afterPropertiesSet');
  @override
  void destroy() => log.add('destroy');
  void close() => log.add('close');
}

void main() {
  setUp(log.clear);

  test('exception hierarchy like Spring', () {
    expect(
      BeanCurrentlyInCreationException(['a', 'b', 'a']),
      isA<BeanCreationException>(),
    );
    expect(
      UnsatisfiedDependencyException('a', 'b', 'reason'),
      isA<BeanCreationException>(),
    );
    expect(
      BeanDefinitionOverrideException('a', null),
      isA<BeanDefinitionStoreException>(),
    );
    expect(
      BeanIsNotAFactoryException('a', English),
      isA<BeanNotOfRequiredTypeException>(),
    );
  });

  test('init and inferred destroy callbacks run once', () {
    DefaultListableBeanFactory()
      ..registerBeanDefinition(
        BeanDefinition<Closeable>(
          name: 'c',
          create: (_) => Closeable(),
          initMethodName: 'afterPropertiesSet',
          initMethod: (bean) => bean.afterPropertiesSet(),
          destroyMethodName: BeanDefinition.inferMethod,
          destroyMethod: (bean) => bean.close(),
        ),
      )
      ..preInstantiateSingletons()
      ..destroySingletons();
    expect(log, ['afterPropertiesSet', 'destroy']);
  });

  test('destroy errors are logged by the DisposableBeanAdapter logger', () {
    final records = <SpringLogRecord>[];
    final saved = SpringLog.handler;
    SpringLog.handler = records.add;
    addTearDown(() => SpringLog.handler = saved);
    final factory = DefaultListableBeanFactory()
      ..registerBeanDefinition(
        BeanDefinition<Counter>(
          name: 'bad',
          create: (_) => Counter(),
          preDestroy: (_) => throw StateError('boom'),
        ),
      )
      ..preInstantiateSingletons()
      ..destroySingletons();
    final ConfigurableBeanFactory configurable = factory;
    expect(configurable.destructionErrors, [isA<StateError>()]);
    expect(
      records.single,
      isA<SpringLogRecord>()
          .having(
            (r) => r.loggerName,
            'logger',
            'spring_core_dart.beans.factory.support.DisposableBeanAdapter',
          )
          .having((r) => r.level, 'level', SpringLogLevel.warning),
    );
  });

  test('a FactoryBean looked up by its own type is listed as &name', () {
    final factory = DefaultListableBeanFactory()
      ..registerBeanDefinition(
        BeanDefinition<GreeterFactory>(
          name: 'greeter',
          types: const [GreeterFactory, FactoryBean<Greeter>],
          factoryObjectTypes: const [Greeter],
          create: (_) => GreeterFactory(),
        ),
      );
    expect(factory.getBeanNamesForType(GreeterFactory), ['&greeter']);
    expect(factory.getBeansOfType<GreeterFactory>().keys, ['&greeter']);
    expect(factory.getBeanNamesForType(Greeter), ['greeter']);
  });

  test('sorted beans and provider streams: ancestors and non-candidates', () {
    final parent = DefaultListableBeanFactory()
      ..registerBeanDefinition(french());
    final child = DefaultListableBeanFactory(parentBeanFactory: parent)
      ..registerBeanDefinition(english(autowireCandidate: false));
    expect(child.getSortedBeans<Greeter>(), hasLength(2));
    final provider = child.getBeanProvider<Greeter>();
    expect(provider.orderedList(), hasLength(2));
    expect(provider.toList(), hasLength(2));
  });
}
