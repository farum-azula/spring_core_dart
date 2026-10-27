// Orders and the events around them (chapter 6). The JSON classes are
// immutable: the ObjectMapper writes their fields and reads them back
// through the constructor.
import 'package:spring_core_dart/spring_core_dart.dart';

enum OrderStatus {
  placed('PLACED'),
  shipped('SHIPPED');

  OrderStatus(this.json);

  @JsonValue()
  final String json;
}

/// A line of a basket or an order: `quantity` copies of a book at `price`
/// each, `discount` percent off, `total` to pay.
class OrderLine {
  const OrderLine({
    required this.isbn,
    required this.title,
    required this.price,
    required this.quantity,
    required this.total,
    this.discount = 0,
  });

  final String isbn;
  final String title;
  final double price;
  final int quantity;
  final int discount;
  final double total;
}

/// The basket of the session: `{"items": [...], "count": 3, "total":
/// 27.5}`.
@Introspected()
class Basket {
  const Basket({required this.items, required this.count, required this.total});

  static const empty = Basket(items: [], count: 0, total: 0);

  final List<OrderLine> items;

  /// Copies of all books together.
  final int count;
  final double total;
}

/// An order: `{"id": 1, "user": "ada", "lines": [...], "total": 27.5,
/// "status": "PLACED", "placedAt": "2026-10-27T10:00:00.000Z",
/// "payment": "sandbox-1"}`.
@Introspected()
class CustomerOrder {
  const CustomerOrder({
    required this.id,
    required this.customer,
    required this.lines,
    required this.total,
    required this.placedAt,
    this.status = OrderStatus.placed,
    this.payment,
  });

  final int id;

  /// The user name of who ordered; `user` in JSON.
  @JsonProperty('user')
  final String customer;
  final List<OrderLine> lines;
  final double total;
  final OrderStatus status;
  final DateTime placedAt;

  /// The payment reference of the gateway.
  final String? payment;

  CustomerOrder withStatus(OrderStatus status) => CustomerOrder(
    id: id,
    customer: customer,
    lines: lines,
    total: total,
    placedAt: placedAt,
    status: status,
    payment: payment,
  );
}

/// An order was placed: a plain object published as an event (listeners
/// take `OrderPlaced`; Spring wraps it in a `PayloadApplicationEvent`).
class OrderPlaced {
  const OrderPlaced(this.order);

  final CustomerOrder order;
}

/// An order left the warehouse: a classic `ApplicationEvent`.
class OrderShipped extends ApplicationEvent {
  OrderShipped(super.source, this.order);

  final CustomerOrder order;
}

/// Ordering an empty basket: a 409 (see `ApiErrors`).
class EmptyBasketException implements Exception {
  const EmptyBasketException();

  @override
  String toString() => 'EmptyBasketException: the basket is empty';
}

/// The body of `PUT /api/basket/items/{isbn}`: `{"quantity": 2}` (0
/// removes the book).
@Introspected()
class QuantityRequest {
  const QuantityRequest({this.quantity = 1});

  @Min(0)
  @Max(10)
  final int quantity;
}
