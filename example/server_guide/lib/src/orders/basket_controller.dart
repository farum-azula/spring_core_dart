import 'package:neon_books_server/src/orders/basket_service.dart';
import 'package:neon_books_server/src/orders/order.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// The basket of the logged-in user's session.
@RestController()
@RequestMapping('/api/basket')
class BasketController {
  BasketController(this.baskets);

  final BasketService baskets;

  @GetMapping()
  Basket basket(ServerHttpRequest request) =>
      baskets.price(baskets.contentOf(request.getSession()!));

  /// `{"quantity": 2}`; 0 removes the book. Answers the whole basket.
  @PutMapping('/items/{isbn}')
  Basket setQuantity(
    @PathVariable() String isbn,
    @RequestBody() @Valid() QuantityRequest quantityRequest,
    ServerHttpRequest request,
  ) => baskets.setQuantity(
    request.getSession()!,
    isbn,
    quantityRequest.quantity,
  );
}
