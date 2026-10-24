import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_dart/src/autoconfigure/message_source_auto_configuration.dart';
import 'package:test/test.dart';

abstract interface class Greeter {}

class Hello implements Greeter {}

class TestHello extends Hello {}

class Clock {}

class Marker {}

/// An annotation class for `annotations:`.
class Experimental {
  const Experimental();
}

BeanDefinition<Hello> hello(String name, {bool defaultCandidate = true}) =>
    BeanDefinition<Hello>(
      name: name,
      types: const [Hello, Greeter],
      defaultCandidate: defaultCandidate,
      create: (_) => Hello(),
    );

BeanDefinition<Marker> marker(String name, Condition condition) =>
    BeanDefinition<Marker>(
      name: name,
      conditions: [condition],
      create: (_) => Marker(),
    );

void main() {
  AnnotationConfigApplicationContext context(
    List<BeanDefinition<Object>> definitions, {
    ApplicationContext? parent,
    Map<String, String> system = const {},
    Map<String, Object?> properties = const {},
  }) {
    final environment = StandardEnvironment(systemEnvironment: system)
      ..propertySources.addFirst(MapPropertySource('test', properties));
    final context = AnnotationConfigApplicationContext(
      [BeanModule('app', definitions)],
      parent: parent,
      environment: environment,
    )..refresh();
    addTearDown(context.close);
    return context;
  }

  group('@ConditionalOnBean / @ConditionalOnMissingBean', () {
    test("without arguments: the @Bean's own type", () {
      final present = context([
        hello('mine'),
        BeanDefinition<Hello>(
          name: 'fallbackHello',
          conditions: const [ConditionalOnMissingBean()],
          create: (_) => Hello(),
        ),
        BeanDefinition<Clock>(
          name: 'clock',
          conditions: const [ConditionalOnMissingBean()],
          create: (_) => Clock(),
        ),
        BeanDefinition<Clock>(
          name: 'secondClock',
          conditions: const [ConditionalOnBean()],
          create: (_) => Clock(),
        ),
      ]);
      expect(present.containsBean('fallbackHello'), isFalse);
      expect(present.containsBean('clock'), isTrue);
      expect(present.containsBean('secondClock'), isTrue);
    });

    test('type lists: all for OnBean, none for OnMissingBean', () {
      final c = context([
        hello('hello'),
        marker('both', const ConditionalOnBean.where(types: [Hello, Clock])),
        marker('one', const ConditionalOnBean.where(types: [Hello])),
        marker(
          'noneMissing',
          const ConditionalOnMissingBean.where(types: [Clock, Hello]),
        ),
        marker(
          'allMissing',
          const ConditionalOnMissingBean.where(types: [Clock, Marker]),
        ),
        marker('names', const ConditionalOnBean.where(names: ['hello', 'one'])),
      ]);
      expect(c.containsBean('both'), isFalse);
      expect(c.containsBean('one'), isTrue);
      expect(c.containsBean('noneMissing'), isFalse);
      expect(c.containsBean('allMissing'), isFalse, reason: 'Marker exists');
      expect(c.containsBean('names'), isTrue);
    });

    test('ignored types do not count', () {
      final c = context([
        BeanDefinition<TestHello>(
          name: 'testHello',
          types: const [TestHello, Hello, Greeter],
          create: (_) => TestHello(),
        ),
        BeanDefinition<Hello>(
          name: 'realHello',
          conditions: const [
            ConditionalOnMissingBean.where(
              types: [Hello],
              ignored: [TestHello],
            ),
          ],
          create: (_) => Hello(),
        ),
        marker('plain', const ConditionalOnMissingBean(Hello)),
      ]);
      expect(c.containsBean('realHello'), isTrue);
      expect(c.containsBean('plain'), isFalse);
    });

    test('annotations: a bean whose definition carries the annotation', () {
      final c = context([
        BeanDefinition<Hello>(
          name: 'hello',
          annotations: const [Experimental()],
          create: (_) => Hello(),
        ),
        marker(
          'withExperimental',
          const ConditionalOnBean.where(annotations: [Experimental]),
        ),
        marker(
          'withoutExperimental',
          const ConditionalOnMissingBean.where(annotations: [Experimental]),
        ),
        marker(
          'withDeprecated',
          const ConditionalOnBean.where(annotations: [Deprecated]),
        ),
      ]);
      expect(c.containsBean('withExperimental'), isTrue);
      expect(c.containsBean('withoutExperimental'), isFalse);
      expect(c.containsBean('withDeprecated'), isFalse);
    });

    test('search: current, ancestors, all', () {
      final parent = context([hello('parentHello')]);
      final child = context([
        marker('all', const ConditionalOnBean(Hello)),
        marker(
          'current',
          const ConditionalOnBean.where(
            types: [Hello],
            search: SearchStrategy.current,
          ),
        ),
        marker(
          'ancestors',
          const ConditionalOnBean.where(
            types: [Hello],
            search: SearchStrategy.ancestors,
          ),
        ),
        marker(
          'missingHere',
          const ConditionalOnMissingBean.named(
            'parentHello',
            search: SearchStrategy.current,
          ),
        ),
        marker(
          'missingAnywhere',
          const ConditionalOnMissingBean.named('parentHello'),
        ),
      ], parent: parent);
      expect(child.containsBean('all'), isTrue);
      expect(child.containsLocalBean('current'), isFalse);
      expect(child.containsBean('ancestors'), isTrue);
      expect(child.containsBean('missingHere'), isTrue);
      expect(child.containsBean('missingAnywhere'), isFalse);
    });

    test('non-default candidates do not count', () {
      final c = context([
        hello('hidden', defaultCandidate: false),
        marker('found', const ConditionalOnBean(Hello)),
      ]);
      expect(c.containsBean('found'), isFalse);
    });

    test('a parent messageSource does not stop the auto-configured one '
        '(SearchStrategy.current)', () {
      ClasspathResources.registerAll(const {
        'conditions_test/messages.properties': EmbeddedResource.text(
          'greeting=Hello',
        ),
      });
      final parent = context([
        BeanDefinition<StaticMessageSource>(
          name: 'messageSource',
          types: const [StaticMessageSource, MessageSource],
          create: (_) => StaticMessageSource(),
        ),
      ]);
      final child = context(
        messageSourceAutoConfiguration,
        parent: parent,
        properties: const {
          'spring.messages.basename': 'conditions_test/messages',
        },
      );
      expect(
        child.getBeanByName('messageSource'),
        isA<ReloadableResourceBundleMessageSource>(),
      );
      expect(child.getMessage('greeting'), 'Hello');
    });

    test('toString names what is checked', () {
      expect(
        const ConditionalOnMissingBean(Clock).toString(),
        '@ConditionalOnMissingBean (types: Clock)',
      );
      expect(
        const ConditionalOnBean.named('x').toString(),
        '@ConditionalOnBean (name: x)',
      );
      expect(
        const ConditionalOnMissingBean().toString(),
        "@ConditionalOnMissingBean (the bean's own type)",
      );
    });
  });

  group('@ConditionalOnCloudPlatform', () {
    test('matches the detected or enforced platform', () {
      final conditions = [
        marker(
          'k8s',
          const ConditionalOnCloudPlatform(CloudPlatform.kubernetes),
        ),
        marker(
          'heroku',
          const ConditionalOnCloudPlatform(CloudPlatform.heroku),
        ),
      ];
      final detected = context(
        conditions,
        system: const {
          'KUBERNETES_SERVICE_HOST': '10.0.0.1',
          'KUBERNETES_SERVICE_PORT': '443',
        },
      );
      expect(detected.containsBean('k8s'), isTrue);
      expect(detected.containsBean('heroku'), isFalse);
      final enforced = context(
        conditions,
        properties: const {'spring.main.cloud-platform': 'heroku'},
      );
      expect(enforced.containsBean('heroku'), isTrue);
      final off = context(
        conditions,
        system: const {'DYNO': 'web.1'},
        properties: const {'spring.main.cloud-platform': 'none'},
      );
      expect(off.containsBean('heroku'), isFalse);
      expect(context(conditions).containsBean('k8s'), isFalse);
    });
  });
}
