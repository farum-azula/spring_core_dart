// Stock: copies leave with orders and come back with deliveries; every
// change is a StockChanged event (published by Catalog.changeStock).
import 'package:neon_books_server/src/app.spring.dart';
import 'package:neon_books_server/src/catalog/book.dart';
import 'package:neon_books_server/src/catalog/catalog_service.dart';
import 'package:neon_books_server/src/orders/order.dart';
import 'package:neon_books_server/src/stock/stock_changed.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

@Service()
@Log()
class StockService {
  StockService(
    this._catalog, {
    @Value(r'${neon.stock.low-threshold:2}') this.lowThreshold = 2,
  });

  final Catalog _catalog;

  /// Books with fewer copies are restocked.
  final int lowThreshold;

  /// Runs first among the listeners of an order (`@Order(1)`): the copies
  /// are gone before anyone else reacts to the order. What it returns (not
  /// `null`) is published as an event in turn.
  @EventListener()
  @Order(1)
  LowStock? onOrderPlaced(OrderPlaced placed) {
    final low = [
      for (final line in placed.order.lines)
        if (_catalog.changeStock(line.isbn, -line.quantity).available <
            lowThreshold)
          line.isbn,
    ];
    return low.isEmpty ? null : LowStock(placed.order.id, low);
  }

  /// The books to restock.
  List<Book> lowStock() => [
    for (final book in _catalog.all())
      if (book.available < lowThreshold) book,
  ];

  /// [copies] arrived for [isbn].
  Book restock(String isbn, int copies) {
    final book = _catalog.changeStock(isbn, copies);
    log.info('restocked $book: ${book.available} copies');
    return book;
  }
}
