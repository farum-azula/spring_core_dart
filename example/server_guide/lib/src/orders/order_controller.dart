import 'package:neon_books_server/src/orders/basket_service.dart';
import 'package:neon_books_server/src/orders/order.dart';
import 'package:neon_books_server/src/orders/order_service.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

@RestController()
@RequestMapping('/api/orders')
class OrderController {
  OrderController(this.orders, this.baskets);

  final OrderService orders;
  final BasketService baskets;

  /// Orders the session's basket: 201 with `Location: /api/orders/{id}`;
  /// the basket is empty afterwards. `Authentication`: the logged-in user.
  @PostMapping()
  ResponseEntity<CustomerOrder> place(
    Authentication authentication,
    ServerHttpRequest request,
  ) {
    final session = request.getSession()!;
    final order = orders.place(authentication.name, baskets.contentOf(session));
    baskets.clear(session);
    return ResponseEntity.created(Uri.parse('/api/orders/${order.id}'))
        .body(order);
  }

  /// The caller's orders (all of them for admins), newest first.
  @GetMapping()
  List<CustomerOrder> all() => orders.all();

  /// One order; 403 for an order of someone else.
  @GetMapping('/{id}')
  CustomerOrder find(@PathVariable() int id) => orders.find(id);
}
