// The basket lives in the HttpSession (chapter 3): the client holds only
// the session cookie (JSESSIONID), the books and quantities stay on the
// server.
import 'package:neon_books_server/src/catalog/catalog_service.dart';
import 'package:neon_books_server/src/orders/order.dart';
import 'package:neon_books_server/src/shop/pricing.dart';
import 'package:neon_books_server/src/shop/shop_properties.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

@Service()
class BasketService {
  BasketService(this._catalog, this._pricing, this._shop);

  final Catalog _catalog;

  /// The `@Primary` rule: `BestDiscount`.
  final PriceRule _pricing;
  final ShopProperties _shop;

  static const _attribute = 'neon.basket';

  /// ISBN → copies, kept in [session].
  Map<String, int> contentOf(HttpSession session) =>
      (session.getAttribute(_attribute) as Map<String, int>?) ?? {};

  /// Sets the copies of [isbn] (0 removes it).
  Basket setQuantity(HttpSession session, String isbn, int quantity) {
    final book = _catalog.get(isbn);
    final content = {...contentOf(session)}..remove(isbn);
    if (quantity > 0) {
      if (quantity > book.available) {
        throw ResponseStatusException(
          HttpStatus.conflict,
          'Only ${book.available} copies of ${book.title} are in stock',
        );
      }
      final count = content.values.fold(quantity, (sum, n) => sum + n);
      if (count > _shop.maxBasketSize) {
        throw ResponseStatusException(
          HttpStatus.conflict,
          'A basket holds at most ${_shop.maxBasketSize} books',
        );
      }
      content[isbn] = quantity;
    }
    session.setAttribute(_attribute, content);
    return price(content);
  }

  /// Empties the basket of [session].
  void clear(HttpSession session) => session.removeAttribute(_attribute);

  /// The lines of [content] with today's prices and discounts.
  Basket price(Map<String, int> content) {
    final lines = [
      for (final book in _catalog.findAll(content.keys))
        _line(
          book.isbn,
          book.title,
          book.price,
          content[book.isbn]!,
          _pricing.discountPercent(book, content[book.isbn]!),
        ),
    ];
    return Basket(
      items: lines,
      count: lines.fold(0, (sum, line) => sum + line.quantity),
      total: _round(lines.fold(0, (sum, line) => sum + line.total)),
    );
  }

  static OrderLine _line(
    String isbn,
    String title,
    double price,
    int quantity,
    int discount,
  ) => OrderLine(
    isbn: isbn,
    title: title,
    price: price,
    quantity: quantity,
    discount: discount,
    total: _round(price * quantity * (100 - discount) / 100),
  );

  static double _round(num value) => (value * 100).round() / 100;
}
