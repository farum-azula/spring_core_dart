// The stock group's interfaces, which the application imports with
// basePackageClasses: every interface of this directory, found by the
// build. Their API versions go into the API-Version header
// (spring.http.serviceclient.stock.apiversion.insert.header).
import 'package:spring_boot_starter_restclient/spring_boot_starter_restclient.dart';

@HttpExchange('/stock')
abstract interface class StockService {
  /// The group's default version (apiversion.default).
  @GetExchange('/{sku}')
  Future<String> level(@PathVariable() String sku);

  /// A version of its own.
  @GetExchange.of(url: '/{sku}/history', version: '2.0')
  Future<String> history(@PathVariable() String sku);
}

/// Every method asks for the version of the interface.
@HttpExchange.of(url: '/alerts', version: '3.1')
abstract interface class StockAlerts {
  @GetExchange()
  Future<String> all();
}
