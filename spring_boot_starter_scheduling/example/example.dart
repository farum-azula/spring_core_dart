// In an app built with spring_core_dart_generator you only write the
// @Component class with @Scheduled methods; the generator registers it and
// the starter is picked up automatically. This example writes the bean
// definition the generator would produce, so it runs without code
// generation.
import 'dart:async';

import 'package:spring_boot_starter_scheduling/spring_auto_configuration.dart';
import 'package:spring_boot_starter_scheduling/spring_boot_starter_scheduling.dart';

@Component()
class Heartbeat {
  var beats = 0;

  @Scheduled(fixedRateString: r'${heartbeat.rate:1s}')
  void beat() => print('beat ${++beats}');

  @Scheduled(cron: '*/2 * * * * *') // every 2 seconds
  Future<void> report() async => print('report at ${DateTime.now()}');
}

// Written by the generator for `Heartbeat` (in main.spring.dart).
final heartbeatDefinition = BeanDefinition<Heartbeat>(
  name: 'heartbeat',
  create: (_) => Heartbeat(),
  annotatedMethods: [
    BeanMethod<Heartbeat>(
      'beat',
      invoke: (bean, arguments) => Function.apply(bean.beat, arguments),
      annotations: const [Scheduled(fixedRateString: r'${heartbeat.rate:1s}')],
    ),
    BeanMethod<Heartbeat>(
      'report',
      invoke: (bean, arguments) => Function.apply(bean.report, arguments),
      annotations: const [Scheduled(cron: '*/2 * * * * *')],
    ),
  ],
);

Future<void> main() async {
  final context = AnnotationConfigApplicationContext([
    BeanModule('app', [heartbeatDefinition]),
    springBootStarterSchedulingAutoConfiguration,
  ])..refresh(); // @Scheduled methods start here

  // Code can schedule work too.
  final scheduler = context.getBean<TaskScheduler>();
  scheduler.schedule(
    () => print('one-off after 1.5 s'),
    OneShotTrigger(scheduler.now().add(const Duration(milliseconds: 1500))),
  );

  await Future<void>.delayed(const Duration(seconds: 3));
  final heartbeat = context.getBean<Heartbeat>();
  context.close(); // cancels every task
  print('${heartbeat.beats} beats');
}
