// @Configurable: an object created with `new` (not by the container, like
// a Flutter State) gets its @Autowired / @Value members from the context
// through `autowireBean`.
import 'package:neon_books_server/src/stock/stock_service.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

@Configurable()
class StockReportPrinter {
  @Autowired()
  late final StockService stock;

  @Value(r'${neon.shop.name}')
  late final String shopName;

  String print() =>
      '$shopName, low on: '
      '${stock.lowStock().map((b) => b.title).join(', ')}';
}
