// Data access stand-in for orders (in memory, lost on restart).
import 'package:neon_books_server/src/app.spring.dart';
import 'package:neon_books_server/src/orders/order.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

@Repository()
@Log()
class OrderRepository {
  final _orders = <int, CustomerOrder>{};
  var _lastId = 0;

  int nextId() => ++_lastId;

  CustomerOrder save(CustomerOrder order) => _orders[order.id] = order;

  CustomerOrder? findById(int id) => _orders[id];

  List<CustomerOrder> findAll() => _orders.values.toList();

  /// Called when the context closes (before the bean is dropped).
  @PreDestroy()
  void shutdown() {
    if (_orders.isNotEmpty) {
      log.info('${_orders.length} orders kept in memory are dropped');
    }
  }
}
