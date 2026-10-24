import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support.dart';

final class Warm {
  bool ready = false;
}

BeanModule _named(String name, List<String> log) => BeanModule(name, [
  BeanDefinition<Counter>(
    name: '${name}Counter',
    create: (_) {
      log.add(name);
      return Counter();
    },
  ),
]);

void main() {
  const runner = ApplicationContextRunner();

  test(
    'runAsync refreshes with refreshAsync (async init is awaited)',
    () async {
      await runner
          .withUserConfiguration(
            BeanModule('warm', [
              BeanDefinition<Warm>(
                name: 'warm',
                create: (_) => Warm(),
                postConstruct: (bean) async {
                  await Future<void>.delayed(Duration.zero);
                  bean.ready = true;
                },
              ),
            ]),
          )
          .runAsync((context) {
            expect(context.hasFailed, isFalse);
            expect(context.getBean<Warm>().ready, isTrue);
          });
      // run() cannot await it.
      runner
          .withUserConfiguration(
            BeanModule('warm', [
              BeanDefinition<Warm>(
                name: 'warm',
                create: (_) => Warm(),
                postConstruct: (bean) async => bean.ready = true,
              ),
            ]),
          )
          .run((context) => expect(context, hasFailed()));
    },
  );

  test('auto-configurations are sorted by name, order, before / after', () {
    final log = <String>[];
    runner
        .withAutoConfiguration(_named('zeta', log))
        .withAutoConfiguration(
          _named('alpha', log),
          const AutoConfigurationModule(after: ['zeta']),
        )
        .withAutoConfiguration(_named('beta', log))
        .withAutoConfiguration(
          _named('gamma', log),
          const AutoConfigurationModule(order: -1),
        )
        .run((context) {
          expect(context.hasFailed, isFalse);
          context.getBean<Counter>(qualifier: 'betaCounter');
        });
    // Boot's AutoConfigurationSorter: alpha pulls zeta in before it.
    expect(log, ['gamma', 'zeta', 'alpha', 'beta']);
  });

  test('withParent: the parent beans are visible', () {
    final parent = AnnotationConfigApplicationContext([
      BeanModule('parent', [
        BeanDefinition<Counter>(name: 'counter', create: (_) => Counter()),
      ]),
    ])..refresh();
    addTearDown(parent.close);
    runner.withParent(parent).run((context) {
      expect(context.context.parent, same(parent));
      expect(context.getBean<Counter>(), same(parent.getBean<Counter>()));
    });
  });

  test('withAllowBeanDefinitionOverriding', () {
    BeanModule module(String prefix) => BeanModule(prefix, [
      BeanDefinition<FakeGreeter>(
        name: 'greeter',
        types: const [FakeGreeter, Greeter],
        create: (_) => FakeGreeter(),
      ),
    ]);
    final twice = runner
        .withUserConfiguration(appModule())
        .withUserConfiguration(module('other'));
    twice.run((context) => expect(context, hasFailed()));
    twice.withAllowBeanDefinitionOverriding(true).run((context) {
      expect(context.hasFailed, isFalse);
      expect(context.getBeanByName('greeter'), isA<FakeGreeter>());
    });
  });

  test('withAllowCircularReferences(true) is not supported', () {
    runner.withAllowCircularReferences(false).run((context) {
      expect(context.hasFailed, isFalse);
    });
    runner.withAllowCircularReferences(true).run((context) {
      expect(context, hasFailed());
      expect(context.startupFailure, isA<UnsupportedError>());
    });
  });

  test("BeanOverride names a new bean like the runner's withBean", () {
    runner.withBeanOverride(URLService()).withBean<Counter>(Counter.new).run((
      context,
    ) {
      expect(context, hasBeanNamed('URLService'));
      expect(context, hasBeanNamed('counter'));
    });
    expect(defaultBeanName('URLService'), 'URLService');
    expect(defaultBeanName('Map<String, int>'), 'map');
    expect(defaultBeanName('HttpClient'), 'httpClient');
  });
}
