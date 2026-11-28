import 'package:neon_books_app/src/api/models.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// The basket and the orders of the logged-in user (the server keeps the
/// basket in the HTTP session).
@HttpExchange('/api')
abstract interface class ShopClient {
  @GetExchange('/basket')
  Future<ServerBasket> basket();

  /// `PUT /api/basket/items/{isbn}` `{"quantity": 2}`; 0 removes the line.
  @PutExchange('/basket/items/{isbn}')
  Future<void> setQuantity(
    @PathVariable() String isbn,
    @RequestBody() Quantity quantity,
  );

  /// `POST /api/orders`: orders the basket; `201 Created` with the order
  /// and its `Location`.
  @PostExchange('/orders')
  Future<ResponseEntity<ShopOrder>> placeOrder();

  /// The user's orders (an admin sees everyone's).
  @GetExchange('/orders')
  Future<List<ShopOrder>> orders();
}
