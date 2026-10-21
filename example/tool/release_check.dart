// Release-mode check, run in CI as minified JavaScript:
//
//   dart compile js -O4 -o /tmp/release_check.js tool/release_check.dart
//   node /tmp/release_check.js
//
// Minification renames classes, so anything that matched annotations by
// `runtimeType.toString()` would silently stop working here.
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/src/aop/aspects.dart';
import 'package:spring_core_dart_example/src/app.dart';
import 'package:spring_core_dart_example/src/tour_log.dart';

void main() {
  final environment = StandardEnvironment(systemEnvironment: {})
    ..propertySources.addFirst(
      MapPropertySource('release-check', {
        'app.name': 'NEON Books',
        'app.currency': 'EUR',
        'shop.delivery-time': '2d',
        'shop.tags': 'a,b',
        'payment.mode': 'sandbox',
        'db.url': 'memory://books',
        'legacy.greeting': 'hi',
        'feature.recommendations': 'true',
      }),
    );
  final context = AnnotationConfigApplicationContext([
    shopBeans,
  ], environment: environment);
  context.beanFactory.registerScope('basket', SimpleMapScope());
  context.refresh();
  tourLog.clear();
  context.getBean<PricingService>().quote('1', 2);
  if (!tourLog.any((line) => line.startsWith('timing: start'))) {
    throw StateError('@annotation(Timed) advice did not run: $tourLog');
  }
  context.close();
  print('release check passed');
}
