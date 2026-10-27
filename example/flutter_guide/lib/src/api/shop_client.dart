import 'package:neon_books_app/src/api/models.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

/// The basket and the orders of the logged-in user (the server keeps the
/// basket in the HTTP session).
@FeignClient('shop', url: r'${api.base-url}', path: '/api')
abstract interface class ShopClient {
  @GetMapping('/basket')
  Future<ServerBasket> basket();

  /// `PUT /api/basket/items/{isbn}` `{"quantity": 2}`; 0 removes the line.
  @PutMapping('/basket/items/{isbn}')
  Future<void> setQuantity(
    @PathVariable() String isbn,
    @RequestBody() Quantity quantity,
  );

  /// `POST /api/orders`: orders the basket; `201 Created` with the order
  /// and its `Location`.
  @PostMapping('/orders')
  Future<ResponseEntity<ShopOrder>> placeOrder();

  /// The user's orders (an admin sees everyone's).
  @GetMapping('/orders')
  Future<List<ShopOrder>> orders();
}
