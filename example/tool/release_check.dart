// Release-mode check, run in CI as minified JavaScript:
//
//   dart compile js -O4 -o /tmp/release_check.js tool/release_check.dart
//   node /tmp/release_check.js
//
// Minification renames classes, so anything that matched annotations by
// `runtimeType.toString()` would silently stop working here.
import 'package:spring_boot_dart/spring_auto_configuration.dart';
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/src/aop/aspects.dart';
import 'package:spring_core_dart_example/src/app.dart';
import 'package:spring_core_dart_example/src/tour_log.dart';

void main() {
  // Config comes from the embedded classpath resources (lib/resources/),
  // so it works without any file system — here under node.
  final modules = [shopBeans, springBootAutoConfiguration];
  final environment = StandardEnvironment(systemEnvironment: {});
  ConfigDataEnvironment(environment).processAndApplySync();
  final context = AnnotationConfigApplicationContext(
    modules,
    environment: environment,
  );
  context.beanFactory.registerScope('basket', SimpleMapScope());
  context.refresh();
  tourLog.clear();
  context.getBean<PricingService>().quote('1', 2);
  if (!tourLog.any((line) => line.startsWith('timing: start'))) {
    throw StateError('@annotation(Timed) advice did not run: $tourLog');
  }
  if (context.getMessage('greeting', args: ['x'], locale: 'ru') !=
      'Добро пожаловать в x!') {
    throw StateError('classpath messages were not found');
  }
  context.close();
  print('release check passed');
}
