import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

class Foo {}

class Bar {}

class Config {}

class OnMissingFoo implements Condition {
  const OnMissingFoo();
  @override
  bool matches(ConditionContext context) =>
      !context.beanFactory.containsBeanOfType(Foo);
}

void main() {
  test('class conditions are evaluated once: all @Bean methods or none', () {
    const group = ConditionGroup('test#Config', [OnMissingFoo()]);
    final context = AnnotationConfigApplicationContext([
      BeanModule('m', [
        BeanDefinition<Config>(
          name: 'config',
          conditions: const [group],
          create: (_) => Config(),
        ),
        BeanDefinition<Foo>(
          name: 'foo',
          conditions: const [group],
          create: (_) => Foo(),
        ),
        // Without the group this one would be dropped: foo exists by now.
        BeanDefinition<Bar>(
          name: 'bar',
          conditions: const [group],
          create: (_) => Bar(),
        ),
      ]),
    ], environment: StandardEnvironment(systemEnvironment: {}))..refresh();
    expect(context.containsBean('foo'), isTrue);
    expect(context.containsBean('bar'), isTrue);
  });

  test('a group that fails registers nothing', () {
    const group = ConditionGroup('test#Config', [OnMissingFoo()]);
    final context = AnnotationConfigApplicationContext([
      BeanModule('app', [
        BeanDefinition<Foo>(name: 'appFoo', create: (_) => Foo()),
      ]),
      BeanModule('auto', [
        BeanDefinition<Config>(
          name: 'config',
          conditions: const [group],
          create: (_) => Config(),
        ),
        BeanDefinition<Bar>(
          name: 'bar',
          conditions: const [group],
          create: (_) => Bar(),
        ),
      ]),
    ], environment: StandardEnvironment(systemEnvironment: {}))..refresh();
    expect(context.containsBean('config'), isFalse);
    expect(context.containsBean('bar'), isFalse);
  });
}
