// A bare @ConditionalOnMissingBean() on a @Bean method looks for beans of
// the method's declared return type (FP-1), as Spring Boot's
// OnBeanCondition deduces it: `Clock clock() => SystemClock()` backs off
// for an application's own Clock.
import 'package:spring_boot_dart/spring_auto_configuration.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

abstract class Clock {}

class SystemClock implements Clock {}

class FixedClock implements Clock {}

BeanModule _auto({Type? declared}) => BeanModule('autoClock', [
  BeanDefinition<SystemClock>(
    name: 'clock',
    types: const [SystemClock, Clock],
    source: 'package:x/x.dart#ClockAutoConfiguration.clock',
    factoryMethodName: 'clock',
    factoryMethodReturnType: declared,
    conditions: const [ConditionalOnMissingBean()],
    create: (_) => SystemClock(),
  ),
]);

ConfigurableApplicationContext _run(
  List<BeanModule> modules,
  BeanModule auto,
) =>
    SpringApplication(
      modules,
      autoConfigurations: [springBootAutoConfiguration, auto],
    ).run(
      const [],
      properties: {
        'spring.main.banner-mode': 'off',
        'logging.level.root': 'warn',
      },
    );

void main() {
  final user = BeanModule('user', [
    BeanDefinition<FixedClock>(
      name: 'fixedClock',
      types: const [FixedClock, Clock],
      create: (_) => FixedClock(),
    ),
  ]);

  test(
    'the declared return type decides: the auto-configured one backs off',
    () {
      final context = _run([user], _auto(declared: Clock));
      addTearDown(context.close);
      expect(context.getBeanNamesForType(Clock), ['fixedClock']);
      expect(context.getBean<Clock>(), isA<FixedClock>());
    },
  );

  test('without another Clock it is made', () {
    final context = _run([], _auto(declared: Clock));
    addTearDown(context.close);
    expect(context.getBean<Clock>(), isA<SystemClock>());
  });
}
