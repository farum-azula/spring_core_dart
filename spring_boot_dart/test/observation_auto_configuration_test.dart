// ObservationAutoConfiguration: the observationRegistry bean with every
// ObservationHandler bean; an app's own registry wins; the advisor of
// @Observed is not in the app without its build module.
import 'package:spring_boot_dart/spring_auto_configuration.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

final class _Stopped extends ObservationHandler {
  final names = <String>[];

  @override
  void onStop(ObservationContext context) => names.add(context.name);
}

void main() {
  ConfigurableApplicationContext run(List<BeanDefinition<Object>> beans) =>
      SpringApplication(
        [BeanModule('app', beans)],
        autoConfigurations: [springBootAutoConfiguration],
        out: (_) {},
      ).run(const [], systemEnvironment: const {});

  test('the registry has the handler beans', () {
    final handler = _Stopped();
    final context = run([
      BeanDefinition<_Stopped>(
        name: 'stopped',
        types: const [_Stopped, ObservationHandler],
        create: (_) => handler,
      ),
    ]);
    addTearDown(context.close);
    context.getBean<ObservationRegistry>().observe('work', () => 1);
    expect(handler.names, ['work']);
    expect(context.containsBean('observedAdvisor'), isFalse);
  });

  test("an app's own registry wins", () {
    final own = ObservationRegistry();
    final context = run([
      BeanDefinition<ObservationRegistry>(name: 'own', create: (_) => own),
    ]);
    addTearDown(context.close);
    expect(identical(context.getBean<ObservationRegistry>(), own), isTrue);
    expect(context.containsBean('observationRegistry'), isFalse);
  });
}
