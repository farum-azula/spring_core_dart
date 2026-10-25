// Scheduling (spring_boot_starter_scheduling): @Scheduled methods run
// with a fixed delay (from properties) or at cron times, and stop with the
// context.
//
// Spring (Java): @Scheduled(fixedDelayString = "${shop.stock-refresh}").
import 'package:spring_boot_starter_scheduling/spring_boot_starter_scheduling.dart';

@Component()
class StockJobs {
  /// How often [refreshStock] ran.
  int refreshes = 0;

  /// Every `shop.stock-refresh` (20ms in application.properties), counted
  /// from the end of the previous run.
  @Scheduled(fixedDelayString: r'${shop.stock-refresh:1m}')
  void refreshStock() => refreshes++;

  /// At 03:00 every night.
  @Scheduled(cron: '0 0 3 * * *')
  void nightlyReport() {}
}
