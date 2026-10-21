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

  test('withBean adds or replaces a bean; runners are immutable', () {
    final withFake = runner.withBean<Greeter>(FakeGreeter());
    withFake.run((context) {
      expect(context, hasSingleBean<Greeter>());
      expect(context.getBean<Greeter>(), isA<FakeGreeter>());
    });
    runner.run((context) {
      expect(context.getBean<Greeter>(), isA<RealGreeter>());
    });
    base.withBean(Counter()..value = 3).run((context) {
      expect(context.getBean<Counter>().value, 3);
      expect(context, hasBeanNamed('counter'));
    });
  });

  test('an ambiguous override fails clearly', () {
    base.withUserConfiguration(appModule()).withBean<Mailer>(FakeMailer()).run((
      context,
    ) {
      expect(context, hasFailed());
      expect('${context.startupFailure}', contains('smtpMailer, sesMailer'));
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
          (context) => context.beanFactory.registerSingleton(
            'extra',
            'value',
            types: const [String],
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
