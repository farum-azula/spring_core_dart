import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_dart/src/autoconfigure/jackson_auto_configuration.dart';
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

// Shaped like the generator's output for `package:app/app.dart`: a
// configuration class (its conditions in a ConditionGroup keyed by the
// class), its @Bean methods and its @Imports.
const _lib = 'package:app/app.dart';

class Config {}

class Audit {}

class Feature {}

String _decapitalize(String name) =>
    '${name[0].toLowerCase()}${name.substring(1)}';

List<Condition> classConditions(String className, List<Condition> conditions) =>
    conditions.isEmpty
    ? const []
    : [ConditionGroup('$_lib#$className', conditions)];

BeanDefinition<Config> configClass(
  String className, [
  List<Condition> conditions = const [],
]) => BeanDefinition<Config>(
  name: _decapitalize(className),
  source: '$_lib#$className',
  annotations: const [Configuration()],
  conditions: conditions,
  create: (_) => Config(),
);

BeanDefinition<T> beanMethod<T extends Object>(
  String className,
  String name,
  T Function() create, {
  List<Condition> conditions = const [],
}) => BeanDefinition<T>(
  name: name,
  source: '$_lib#$className.$name',
  factoryBeanName: _decapitalize(className),
  factoryMethodName: name,
  conditions: conditions,
  create: (_) => create(),
);

// A scanned @Component (or a class the generator inlines for an @Import).
BeanDefinition<T> component<T extends Object>(
  String className,
  T Function() create, [
  List<Condition> conditions = const [],
]) => BeanDefinition<T>(
  name: _decapitalize(className),
  source: '$_lib#$className',
  conditions: classConditions(className, conditions),
  create: (_) => create(),
);

class Mailer {}

class MailListener {}

ImportDeclaration imports(
  String className,
  Object Function() create, [
  List<Condition> conditions = const [],
]) => ImportDeclaration(
  create,
  importer: '$_lib#$className',
  conditions: conditions,
);

class MapperRegistrar implements BeanRegistrar {
  @override
  void register(BeanRegistry registry, Environment environment) => registry
      .registerBean<ObjectMapper>((_) => ObjectMapper(), name: 'appMapper');
}

class MapperDefinitionRegistrar implements ImportBeanDefinitionRegistrar {
  @override
  void registerBeanDefinitions(BeanDefinitionRegistry registry) =>
      registry.registerBeanDefinition(
        BeanDefinition<ObjectMapper>(
          name: 'appMapper',
          create: (_) => ObjectMapper(),
        ),
      );
}

class ClockRegistrar implements BeanRegistrar {
  @override
  void register(BeanRegistry registry, Environment environment) =>
      registry.registerBean<Clock>((_) => Clock(), name: 'registrarClock');
}

class AuditRegistrar implements ImportBeanDefinitionRegistrar {
  @override
  void registerBeanDefinitions(BeanDefinitionRegistry registry) =>
      registry.registerBeanDefinition(
        BeanDefinition<Audit>(name: 'registrarAudit', create: (_) => Audit()),
      );
}

class FeatureSelector implements ImportSelector {
  FeatureSelector([this.name = 'Feature']);

  final String name;

  late final _module = BeanModule('selected$name', [
    configClass('${name}Config'),
    beanMethod<Feature>('${name}Config', _decapitalize(name), Feature.new),
  ]);

  @override
  List<BeanModule> selectImports() => [_module];
}

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

  group(
    'bean conditions are decided when beans register (OnBeanCondition)',
    () {
      AnnotationConfigApplicationContext run(
        List<BeanModule> modules, {
        Map<String, Object?> properties = const {},
      }) {
        final environment = StandardEnvironment(systemEnvironment: const {})
          ..propertySources.addFirst(MapPropertySource('test', properties));
        final context = AnnotationConfigApplicationContext(
          modules,
          environment: environment,
        )..refresh();
        addTearDown(context.close);
        return context;
      }

      test('a bean of a registrar @Imported by the application makes the '
          "auto-configuration's @ConditionalOnMissingBean back off", () {
        for (final registrar in <Object Function()>[
          MapperRegistrar.new,
          MapperDefinitionRegistrar.new,
        ]) {
          final context = run([
            BeanModule(
              'app',
              [configClass('AppConfig')],
              registrars: [imports('AppConfig', registrar)],
            ),
            BeanModule('boot', jacksonAutoConfiguration),
          ]);
          expect(context.getBeanNamesForType(ObjectMapper), [
            'appMapper',
          ], reason: '${registrar()}');
        }
      });

      test("an earlier class's registrar is visible to a later class's "
          '@ConditionalOnMissingBean @Bean', () {
        final context = run([
          BeanModule(
            'app',
            [
              configClass('AEarlier'),
              configClass('BLater'),
              beanMethod<Clock>(
                'BLater',
                'laterClock',
                Clock.new,
                conditions: const [ConditionalOnMissingBean()],
              ),
            ],
            registrars: [imports('AEarlier', ClockRegistrar.new)],
          ),
        ]);
        expect(context.getBeanNamesForType(Clock), ['registrarClock']);
      });

      test('a matching @ConditionalOnBean class registers its beans, its '
          'registrars and what its selectors select', () {
        final audit = classConditions('BAudit', const [
          ConditionalOnBean(Clock),
        ]);
        final context = run([
          BeanModule(
            'app',
            [
              configClass('AClocks'),
              beanMethod<Clock>('AClocks', 'clock', Clock.new),
              configClass('BAudit', audit),
              beanMethod<Audit>(
                'BAudit',
                'audit',
                Audit.new,
                conditions: audit,
              ),
            ],
            registrars: [
              imports('BAudit', AuditRegistrar.new, audit),
              imports('BAudit', FeatureSelector.new, audit),
            ],
          ),
        ]);
        expect(
          context.beanDefinitionNames,
          containsAll([
            'bAudit',
            'audit',
            'registrarAudit',
            'featureConfig',
            'feature',
          ]),
        );
      });

      test('a skipped @ConditionalOnMissingBean class registers nothing and '
          'runs no registrar', () {
        final fallback = classConditions('BFallback', const [
          ConditionalOnMissingBean(Clock),
        ]);
        final context = run([
          BeanModule(
            'app',
            [
              configClass('AClocks'),
              beanMethod<Clock>('AClocks', 'clock', Clock.new),
              configClass('BFallback', fallback),
              beanMethod<Clock>(
                'BFallback',
                'fallbackClock',
                Clock.new,
                conditions: fallback,
              ),
            ],
            registrars: [
              imports('BFallback', AuditRegistrar.new, fallback),
              imports('BFallback', FeatureSelector.new, fallback),
            ],
          ),
        ]);
        expect(context.beanDefinitionNames, isNot(contains('bFallback')));
        expect(context.getBeanNamesForType(Clock), ['clock']);
        expect(context.getBeanNamesForType(Audit), isEmpty);
        expect(context.getBeanNamesForType(Feature), isEmpty);
      });

      test(
        'a @ConditionalOnMissingBean class importing the class that '
        'defines the bean stays registered (PooledDataSourceConfiguration)',
        () {
          final pooled = classConditions('Pooled', const [
            ConditionalOnMissingBean(Clock),
          ]);
          // The generator puts the imported class first, its conditions
          // nested in the importer's.
          final hikari = classConditions('Hikari', pooled);
          final context = run([
            BeanModule('app', [
              configClass('Hikari', hikari),
              beanMethod<Clock>(
                'Hikari',
                'hikariClock',
                Clock.new,
                conditions: hikari,
              ),
              configClass('Pooled', pooled),
            ]),
          ]);
          expect(
            context.beanDefinitionNames,
            containsAll(['hikari', 'hikariClock', 'pooled']),
          );
        },
      );

      test('a class whose bean condition does not match still loads its '
          '@PropertySource', () {
        final skipped = classConditions('Settings', const [
          ConditionalOnBean(Audit),
        ]);
        final context = run([
          BeanModule(
            'app',
            [configClass('Settings', skipped)],
            propertySources: [
              PropertySourceDeclaration(const [
                'classpath:bean_conditions/settings.properties',
              ], conditions: skipped),
            ],
            resources: const {
              'bean_conditions/settings.properties': EmbeddedResource.text(
                'settings.loaded=yes',
              ),
            },
          ),
        ]);
        expect(context.containsBean('settings'), isFalse);
        expect(context.environment.getProperty('settings.loaded'), 'yes');
      });

      test("a component's @ConditionalOnMissingBean sees an earlier "
          "class's registrar bean", () {
        final context = run([
          BeanModule(
            'app',
            [
              configClass('AConfig'),
              component<Clock>('DefaultClock', Clock.new, const [
                ConditionalOnMissingBean(Clock),
              ]),
            ],
            registrars: [imports('AConfig', ClockRegistrar.new)],
          ),
        ]);
        expect(context.getBeanNamesForType(Clock), ['registrarClock']);
      });

      test("a component's @ConditionalOnBean sees an earlier class's "
          'conditional @Bean; one before it in class order does not', () {
        List<BeanDefinition<Object>> config() => [
          configClass('BConfig'),
          beanMethod<Mailer>(
            'BConfig',
            'mailer',
            Mailer.new,
            conditions: const [ConditionalOnMissingBean()],
          ),
        ];
        final listener = component<MailListener>(
          'MailListener',
          MailListener.new,
          const [ConditionalOnBean(Mailer)],
        );
        final after = run([
          BeanModule('app', [...config(), listener]),
        ]);
        expect(after.containsBean('mailer'), isTrue);
        expect(after.containsBean('mailListener'), isTrue);
        final before = run([
          BeanModule('app', [listener, ...config()]),
        ]);
        expect(before.containsBean('mailer'), isTrue);
        expect(before.containsBean('mailListener'), isFalse);
      });

      test('an auto-configuration importing a @ConditionalOnMissingBean '
          "component backs off for the application's registrar bean", () {
        final context = run([
          BeanModule(
            'app',
            [configClass('AppConfig')],
            registrars: [imports('AppConfig', ClockRegistrar.new)],
          ),
          // Generator @Import: the imported class first, then the importer.
          BeanModule('boot', [
            component<Clock>('DefaultClock', Clock.new, const [
              ConditionalOnMissingBean(Clock),
            ]),
            configClass('ClockAutoConfiguration'),
          ]),
        ]);
        expect(context.getBeanNamesForType(Clock), ['registrarClock']);
      });

      test('a module selected by a skipped and a kept class is registered', () {
        final skipped = classConditions('Skipped', const [
          ConditionalOnBean(Audit),
        ]);
        final kept = classConditions('Kept', const [ConditionalOnBean(Clock)]);
        final selector = FeatureSelector();
        final context = run([
          BeanModule(
            'app',
            [
              configClass('AClocks'),
              beanMethod<Clock>('AClocks', 'clock', Clock.new),
              configClass('Skipped', skipped),
              configClass('Kept', kept),
            ],
            registrars: [
              imports('Skipped', () => selector, skipped),
              imports('Kept', () => selector, kept),
            ],
          ),
        ]);
        expect(context.getBeanNamesForType(Feature), ['feature']);
        expect(context.containsBean('skipped'), isFalse);
      });
    },
  );
}
