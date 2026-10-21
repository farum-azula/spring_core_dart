// Spring Boot: @ConfigurationProperties and a CommandLineRunner.
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_core_dart_example/src/catalog/catalog.dart';
import 'package:spring_core_dart_example/src/payments/payments.dart';

const _log = SpringLog('neon.shop');

/// Bound from `shop.*` (config files, `--shop.opening-hours=...`, or the
/// environment variable `SHOP_OPENING_HOURS`).
@ConfigurationProperties('shop')
class ShopProperties {
  @NotBlank()
  String name = 'NEON Books';

  String openingHours = '10-20';

  Duration deliveryTime = const Duration(days: 3);

  @Min(1)
  int maxBasketSize = 10;
}

/// Runs once the application has started (before ConsoleLogScreen:
/// runners of both kinds are ordered together).
@Component()
@Order(1)
class OpeningAnnouncement implements CommandLineRunner {
  OpeningAnnouncement(this.properties, this.catalog, this.checkout);

  final ShopProperties properties;
  final CatalogService catalog;
  final Checkout checkout;

  @override
  void run(List<String> args) {
    _log.info(
      '${properties.name} is open ${properties.openingHours}, '
      'delivery in ${properties.deliveryTime.inDays} days, '
      'basket up to ${properties.maxBasketSize} books, '
      '${catalog.books.findAll().length} titles in stock.',
    );
    // Fields from the zone are added to every record inside (like MDC).
    SpringLog.withFields({'order': 1}, () => checkout.pay(12.5));
  }
}
