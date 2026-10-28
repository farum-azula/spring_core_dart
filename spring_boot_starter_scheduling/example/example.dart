// Scheduled tasks in a Spring Boot application: @Scheduled methods on a
// bean; the generator registers them and picks the starter up
// (example.spring.dart, from `dart run build_runner build`).
//
//   dart run example/example.dart
//   dart run example/example.dart --heartbeat.rate=500ms

import 'dart:async';

import 'package:spring_boot_starter_scheduling/spring_boot_starter_scheduling.dart';

import 'example.spring.dart';

/// A logger for code outside the beans, such as `main`; the beans below get
/// theirs from `@Log`.
const _log = SpringLog('example');

@Component()
@Log(topic: 'example')
class Heartbeat {
  int beats = 0;

  /// Every second, or `heartbeat.rate`.
  @Scheduled(fixedRateString: r'${heartbeat.rate:1s}')
  void beat() => log.info('beat ${++beats}');

  /// Every 2 seconds, by a cron expression (with seconds).
  @Scheduled(cron: '*/2 * * * * *')
  Future<void> report() async => log.info('report at ${DateTime.now()}');
}

/// Code can schedule work too, through the `TaskScheduler` bean.
@Component()
@Log(topic: 'example')
class Reminder implements CommandLineRunner {
  Reminder(this.scheduler);

  final TaskScheduler scheduler;

  @override
  void run(List<String> args) => scheduler.schedule(
    () => log.info('one-off after 1.5 s'),
    OneShotTrigger(scheduler.now().add(const Duration(milliseconds: 1500))),
  );
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  // Scheduled tasks keep an application running; this one stops after
  // three seconds. Closing the context cancels every task.
  final context = runApplication(args);
  await Future<void>.delayed(const Duration(seconds: 3));
  // Logged before closing: closing the context also ends the starter's
  // logging.
  _log.info('${context.getBean<Heartbeat>().beats} beats');
  await context.closeAsync();
}
