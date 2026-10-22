// With spring_boot_dart the starter is picked up automatically: add the
// dependency and log through SpringLog. This example installs the logging
// system by hand, so it runs without code generation.
import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';

const log = SpringLog('shop.checkout');

void main() {
  final environment = StandardEnvironment(systemEnvironment: const {})
    ..propertySources.addFirst(
      MapPropertySource('example', {
        'logging.level.shop': 'debug',
        'logging.pattern.console': '%d{HH:mm:ss} %-5p [%logger] %m%X',
      }),
    );
  SpringApplication.applyLoggingLevels(environment);
  final logging = LoggingSystem.instance
    ..configure(environment)
    ..install();

  log.info('order placed', fields: {'order': 42});
  log.debug(() => 'basket checked'); // built only when debug is enabled
  SpringLog.withFields({'request': 'r-1'}, () => log.warning('slow payment'));

  // What an in-app log screen would show: a filtered snapshot.
  final warnings = logging.buffer.query(
    const LogQuery(minLevel: SpringLogLevel.warning),
  );
  print('${warnings.length} warning(s): ${warnings.single.message}');
  logging.uninstall();
}
