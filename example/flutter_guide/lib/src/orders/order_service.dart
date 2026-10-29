import 'package:neon_books_app/main.spring.dart';
import 'package:neon_books_app/src/api/models.dart';
import 'package:neon_books_app/src/api/shop_client.dart';
import 'package:neon_books_app/src/basket/basket.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// Ordering and the order list. Only for logged-in users:
/// `@PreAuthorize('isAuthenticated()')` fails the call before it is sent
/// (`AuthenticationCredentialsNotFoundException`), and the server would
/// answer 401 anyway.
@Service()
@Log(topic: 'neon.orders')
class OrderService {
  OrderService(this._shop, this._basket);

  final ShopClient _shop;
  final Basket _basket;

  /// Orders the basket: the server answers `201 Created` with the order
  /// (and its `Location`); the basket is empty afterwards.
  @PreAuthorize('isAuthenticated()')
  Future<ShopOrder> placeOrder() async {
    final response = await _shop.placeOrder();
    final order = response.body!;
    log.info(
      'order placed',
      fields: {'order': order.id, 'location': response.headers.location},
    );
    _basket.clear();
    return order;
  }

  /// The user's orders, the newest first.
  @PreAuthorize('isAuthenticated()')
  Future<List<ShopOrder>> orders() async {
    final orders = await _shop.orders();
    return orders.reversed.toList();
  }
}
