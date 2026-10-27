// Orders: method security with SpEL (chapter 4), an event for every order
// (chapter 6), shipping scheduled in code with the TaskScheduler
// (chapter 8), log fields for everything logged while placing an order
// (chapter 11).
import 'package:neon_books_server/src/app.spring.dart';
import 'package:neon_books_server/src/orders/basket_service.dart';
import 'package:neon_books_server/src/orders/order.dart';
import 'package:neon_books_server/src/orders/order_repository.dart';
import 'package:neon_books_server/src/shop/clock.dart';
import 'package:neon_books_server/src/shop/payments.dart';
import 'package:spring_boot_starter_scheduling/spring_boot_starter_scheduling.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

@Service()
@Log()
class OrderService {
  OrderService(
    this._orders,
    this._baskets,
    this._events,
    this._scheduler, {
    @Value(r'${neon.orders.shipping-delay:5s}')
    this.shippingDelay = const Duration(seconds: 5),
  });

  final OrderRepository _orders;
  final BasketService _baskets;
  final ApplicationEventPublisher _events;
  final TaskScheduler _scheduler;

  /// How long after the order it ships.
  final Duration shippingDelay;

  /// Field injection.
  @Autowired()
  late final Checkout checkout;

  late Clock _clock;

  /// Setter injection.
  @Autowired()
  // Write-only on purpose: nothing reads it back from outside.
  // ignore: avoid_setters_without_getters
  set clock(Clock clock) => _clock = clock;

  /// Orders [basket] for [customer]. `hasRole('USER')`: admins may order
  /// too, through the role hierarchy (`ROLE_ADMIN > ROLE_USER`).
  @PreAuthorize("hasRole('USER')")
  CustomerOrder place(String customer, Map<String, int> basket) {
    final priced = _baskets.price(basket);
    if (priced.items.isEmpty) {
      throw const EmptyBasketException();
    }
    final id = _orders.nextId();
    // Every line logged inside (here, by the listeners of OrderPlaced and
    // by the advice around this method) carries these fields.
    return SpringLog.withFields({'order': id, 'customer': customer}, () {
      var order = CustomerOrder(
        id: id,
        customer: customer,
        lines: priced.items,
        total: priced.total,
        placedAt: _clock.now(),
      );
      order = _orders.save(
        CustomerOrder(
          id: order.id,
          customer: order.customer,
          lines: order.lines,
          total: order.total,
          placedAt: order.placedAt,
          payment: checkout.pay(order),
        ),
      );
      log.info('order placed: ${priced.count} books, ${order.total} EUR');
      _events.publishEvent(OrderPlaced(order));
      _scheduler.scheduleAt(
        () => ship(order.id),
        DateTime.now().add(shippingDelay),
      );
      return order;
    });
  }

  /// The order [id]: only for its customer and admins (the
  /// `PermissionEvaluator` decides, after the method returned).
  @PostAuthorize("hasPermission(returnObject, 'read')")
  CustomerOrder find(int id) =>
      _orders.findById(id) ??
      (throw ResponseStatusException(HttpStatus.notFound, 'No order $id'));

  /// Every order the caller may see: their own, all of them for admins.
  @PostFilter(
    "filterObject.customer == authentication.name or hasRole('ADMIN')",
  )
  List<CustomerOrder> all() =>
      _orders.findAll()..sort((a, b) => b.placedAt.compareTo(a.placedAt));

  /// Marks the order [id] shipped (called by the TaskScheduler).
  void ship(int id) {
    final order = _orders.findById(id);
    if (order == null || order.status == OrderStatus.shipped) {
      return;
    }
    final shipped = _orders.save(order.withStatus(OrderStatus.shipped));
    log.info('order $id shipped', fields: {'customer': order.customer});
    _events.publishEvent(OrderShipped(this, shipped));
  }
}
