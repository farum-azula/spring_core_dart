import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  const base = ApplicationContextRunner();
  final runner = base.withAutoConfiguration(greeterAutoConfiguration);

  test('auto-configuration applies without an application bean', () {
    runner.run((context) {
      expect(context, hasSingleBean<Greeter>());
      expect(context, hasBeanNamed('defaultGreeter'));
      expect(context.getBean<Greeter>().greet('Ada'), 'Hi, Ada');
      expect(context.getBeanNamesForType<Greeter>(), ['defaultGreeter']);
    });
  });

  test('backs off for the application bean (user configuration first)', () {
    runner.withUserConfiguration(appModule()).run((context) {
      expect(context, hasSingleBean<Greeter>());
      expect(context.containsBean('defaultGreeter'), isFalse);
      expect(context.getBean<Greeter>().greet('Ada'), 'Hello, Ada');
    });
  });

  test('properties and the environment', () {
    runner
        .withPropertyValues(['greeting.prefix=Yo', 'flag'])
        .withSystemEnvironment({'APP_MODE': 'ci'})
        .run((context) {
          expect(context.getBean<Greeter>().greet('Ada'), 'Yo, Ada');
          expect(context.environment.getProperty('flag'), '');
          expect(context.environment.getProperty('app.mode'), 'ci');
        });
    runner.withPropertyValues(['greeter.enabled=false']).run((context) {
      expect(context, doesNotHaveBean<Greeter>());
    });
  });

  test('properties as key:value, trimmed, like TestPropertyValues', () {
    runner
        .withPropertyValues([
          'greeting.prefix: Hey ',
          'app.url=http://localhost:8080',
          'app.time:12:30',
          ' app.flag ',
        ])
        .run((context) {
          expect(context.getBean<Greeter>().greet('Ada'), 'Hey, Ada');
          final environment = context.environment;
          expect(environment.getProperty('app.url'), 'http://localhost:8080');
          expect(environment.getProperty('app.time'), '12:30');
          expect(environment.getProperty('app.flag'), '');
        });
  });

  group('withBean registers a bean before the configurations', () {
    test('auto-configuration backs off; runners are immutable', () {
      runner.withBean<Greeter>(FakeGreeter.new).run((context) {
        expect(context, hasSingleBean<Greeter>());
        expect(context, hasBeanNamed('greeter'));
        expect(context.containsBean('defaultGreeter'), isFalse);
        expect(context.getBean<Greeter>(), isA<FakeGreeter>());
      });
      runner.run((context) {
        expect(context.getBean<Greeter>(), isA<RealGreeter>());
      });
      base.withBean(() => Counter()..value = 3).run((context) {
        expect(context.getBean<Counter>().value, 3);
        expect(context, hasBeanNamed('counter'));
      });
      // Spring's names: `URLService` stays as it is.
      base.withBean(URLService.new).run((context) {
        expect(context, hasBeanNamed('URLService'));
      });
    });

    test('each run gets a new instance from the supplier', () {
      final created = <Counter>[];
      base.withBean(() {
          final counter = Counter();
          created.add(counter);
          return counter;
        })
        ..run((context) => context.getBean<Counter>().value = 7)
        ..run((context) {
          // Not the instance the first (closed) context destroyed.
          expect(context.getBean<Counter>().value, isNot(7));
        });
      expect(created, hasLength(2));
      expect(identical(created[0], created[1]), isFalse);
    });

    test('also when the configuration was added first', () {
      base
          .withAutoConfiguration(greeterAutoConfiguration)
          .withBean<Greeter>(FakeGreeter.new, name: 'fake')
          .run((context) {
            expect(context, hasSingleBean<Greeter>());
            expect(context.getBeanNamesForType<Greeter>(), ['fake']);
          });
    });

    test('a missing back-off shows up as a second bean', () {
      base
          .withAutoConfiguration(greeterWithoutBackOff)
          .withBean<Greeter>(FakeGreeter.new)
          .run((context) {
            expect(context, isNot(hasSingleBean<Greeter>()));
            expect(context.getBeanNamesForType<Greeter>(), [
              'greeter',
              'eagerGreeter',
            ]);
          });
    });

    test('it never replaces a bean', () {
      base
          .withUserConfiguration(appModule())
          .withBean<Mailer>(FakeMailer.new)
          .run((context) {
            expect(context.getBeanNamesForType<Mailer>(), [
              'mailer',
              'smtpMailer',
              'sesMailer',
            ]);
          });
      // The same name as a bean of the configurations: the start fails.
      base
          .withUserConfiguration(appModule())
          .withBean<Greeter>(FakeGreeter.new)
          .run((context) {
            expect(context, hasFailed(isA<BeanDefinitionOverrideException>()));
          });
    });
  });

  group('withBeanOverride replaces a bean (like @TestBean)', () {
    test('keeps the name and qualifiers', () {
      base
          .withUserConfiguration(appModule())
          .withBeanOverride<Mailer>(FakeMailer(), name: 'smtpMailer')
          .run((context) {
            expect(context.getBeanNamesForType<Mailer>(), [
              'sesMailer',
              'smtpMailer',
            ]);
            expect(
              context.getBean<Mailer>(qualifier: 'primaryMail'),
              isA<FakeMailer>(),
            );
            expect(
              context.getBean<Notifier>().notify('Ada'),
              'fake: Hello, Ada',
            );
          });
    });

    test('an ambiguous override fails clearly', () {
      base
          .withUserConfiguration(appModule())
          .withBeanOverride<Mailer>(FakeMailer())
          .run((context) {
            expect(context, hasFailed());
            expect(
              '${context.startupFailure}',
              contains('smtpMailer, sesMailer'),
            );
          });
    });

    BeanModule mailers({bool sesPrimary = false, bool smtpPrimary = false}) =>
        BeanModule('mailers', [
          BeanDefinition<SmtpMailer>(
            name: 'smtpMailer',
            types: const [SmtpMailer, Mailer],
            primary: smtpPrimary,
            create: (_) => SmtpMailer(),
          ),
          BeanDefinition<SesMailer>(
            name: 'sesMailer',
            types: const [SesMailer, Mailer],
            primary: sesPrimary,
            aliases: const ['amazonMailer'],
            create: (_) => SesMailer(),
          ),
        ]);

    test('by type: the single @Primary bean is replaced', () {
      base
          .withUserConfiguration(mailers(sesPrimary: true))
          .withBeanOverride<Mailer>(FakeMailer())
          .run((context) {
            expect(context.hasFailed, isFalse);
            expect(context.getBeanByName('sesMailer'), isA<FakeMailer>());
            expect(context.getBeanByName('smtpMailer'), isA<SmtpMailer>());
            expect(context.getBean<Mailer>(), isA<FakeMailer>());
          });
      base
          .withUserConfiguration(mailers(sesPrimary: true, smtpPrimary: true))
          .withBeanOverride<Mailer>(FakeMailer())
          .run((context) => expect(context, hasFailed()));
    });

    test('by name: an alias replaces the bean it names', () {
      base
          .withUserConfiguration(mailers())
          .withInitializer(
            ApplicationContextInitializer.of(
              (context) =>
                  context.beanFactory.registerAlias('sesMailer', 'cloudMail'),
            ),
          )
          .withBeanOverride<Mailer>(FakeMailer(), name: 'amazonMailer')
          .run((context) {
            expect(context.hasFailed, isFalse);
            expect(context.getBeanNamesForType<Mailer>(), [
              'smtpMailer',
              'sesMailer',
            ]);
            expect(context.getBeanByName('sesMailer'), isA<FakeMailer>());
            expect(context.getBeanByName('amazonMailer'), isA<FakeMailer>());
            expect(context.getBeanByName('cloudMail'), isA<FakeMailer>());
          });
    });
  });

  test('a failed start is passed to the body', () {
    base.withUserConfiguration(failingModule).run((context) {
      expect(context.hasFailed, isTrue);
      expect(context, hasFailed(isA<BeanCreationException>()));
      expect(context, isNot(hasBean<Counter>()));
      expect(() => context.context, throwsStateError);
    });
    runner.run((context) {
      expect(context, isNot(hasFailed()));
    });
  });

  test('initializers run before the refresh; the context is closed', () {
    late ConfigurableApplicationContext seen;
    base
        .withInitializer(
          ApplicationContextInitializer.of(
            (context) => context.beanFactory.registerSingleton(
              'extra',
              'value',
              types: const [String],
            ),
          ),
        )
        .run((context) {
          seen = context.context;
          expect(context.getBeanByName('extra'), 'value');
        });
    expect(seen.isActive, isFalse);
  });

  test('mismatch descriptions name the beans found', () {
    runner.withUserConfiguration(appModule()).run((context) {
      final description = StringDescription();
      hasSingleBean<Mailer>().describeMismatch(context, description, {}, false);
      expect('$description', 'has beans of Mailer: smtpMailer, sesMailer');
    });
  });
}
