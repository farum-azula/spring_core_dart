// Logging in a Spring Boot application: add the starter and put @Log on a
// class; the generator writes its `log` getter and picks the starter up
// (example.spring.dart, from `dart run build_runner build`).
//
//   dart run example/example.dart
//   dart run example/example.dart --logging.level.shop=debug
//   LOGGING_LEVEL_SHOP=debug dart run example/example.dart

import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';

import 'example.spring.dart';

/// `@Log` generates the `log` getter (in example.spring.dart), like
/// Lombok's `@Slf4j`; without `topic` the logger would be
/// `spring_boot_starter_logging.Checkout`.
@Service()
@Log(topic: 'shop.checkout')
class Checkout {
  /// Logs with structured fields; the debug message is built only when
  /// `shop` (or `shop.checkout`) is at debug level.
  void pay(int order, double amount) {
    log.info('paid $amount', fields: {'order': order});
    log.debug(() => 'basket of order $order checked');
    if (amount > 100) {
      log.warning('large payment', fields: {'order': order});
    }
  }
}

/// The same logger without the annotation: a `SpringLog` you name
/// yourself, for code outside the scan (a library, a top-level function).
const _receipts = SpringLog('shop.receipts');

void printReceipt(int order) =>
    _receipts.info('receipt printed', fields: {'order': order});

/// Pays two orders, then reads the warnings back from the log buffer, the
/// list an in-app log screen shows.
@Component()
@Log(topic: 'shop.startup')
class PayOnStartup implements CommandLineRunner {
  PayOnStartup(this.checkout, this.logs);

  final Checkout checkout;
  final LogBuffer logs;

  @override
  void run(List<String> args) {
    // Fields for every line logged inside, like an MDC.
    SpringLog.withFields({'request': 'r-1'}, () {
      checkout
        ..pay(1, 12.5)
        ..pay(2, 250);
      printReceipt(2);
    });
    final warnings = logs.query(
      const LogQuery(minLevel: SpringLogLevel.warning),
    );
    log.info('${warnings.length} warning(s): ${warnings.single.message}');
  }
}

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
