import 'package:spring_core_dart/spring_core_dart.dart';

/// The copies in stock of a book changed: published as an event (a plain
/// object: Spring wraps it in a `PayloadApplicationEvent`), streamed to
/// clients as `{"isbn": "...", "available": 3}`.
class StockChanged {
  const StockChanged({required this.isbn, required this.available});

  final String isbn;
  final int available;

  @override
  String toString() => 'StockChanged($isbn: $available)';
}

/// Books an order left with few copies: the result of a listener,
/// published in turn (see `StockService.onOrderPlaced`), streamed to
/// admins as JSON.
@Introspected()
class LowStock {
  const LowStock(this.orderId, this.isbns);

  final int orderId;
  final List<String> isbns;
}
