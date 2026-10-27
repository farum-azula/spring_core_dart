import 'package:neon_books_app/main.spring.dart';
import 'package:neon_books_app/src/account/session.dart';
import 'package:neon_books_app/src/api/models.dart';
import 'package:neon_books_app/src/api/shop_client.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_security_core/spring_security_core.dart';

/// One line of the basket.
class BasketItem {
  const BasketItem(this.isbn, this.title, this.price, this.quantity);

  final String isbn;
  final String title;
  final double price;
  final int quantity;

  double get total => price * quantity;
}

/// The basket: state in a bean instead of a `State`, so the book screen
/// adds to it, the app bar's badge counts it and the Basket screen lists
/// it. `@ChangeNotifierComponent`: no `extends ChangeNotifier`, no
/// `notifyListeners()`; the bean's proxy notifies after every method.
/// `@BuildContextAccess()`: widgets reach it as `context.basket`.
///
/// Anonymous users fill it in the app; once logged in, every change goes
/// to the server too (which keeps the basket in the session and orders
/// from it).
@ChangeNotifierComponent()
@BuildContextAccess()
@Log(topic: 'neon.basket')
class Basket {
  Basket(this._shop);

  final ShopClient _shop;
  final _items = <String, BasketItem>{};

  /// The lines, in the order they were added.
  List<BasketItem> get items => List.unmodifiable(_items.values);

  /// How many books (the badge).
  int get count => _items.values.fold(0, (sum, item) => sum + item.quantity);

  double get total => _items.values.fold(0, (sum, item) => sum + item.total);

  /// One more copy of [book].
  Future<void> add(Book book) => setQuantity(
    book.isbn,
    (_items[book.isbn]?.quantity ?? 0) + 1,
    book: book,
  );

  /// Sets the copies of [isbn]; 0 removes the line.
  Future<void> setQuantity(String isbn, int quantity, {Book? book}) async {
    final known = _items[isbn];
    if (quantity <= 0) {
      _items.remove(isbn);
    } else {
      _items[isbn] = BasketItem(
        isbn,
        book?.title ?? known?.title ?? isbn,
        book?.price ?? known?.price ?? 0,
        quantity,
      );
    }
    if (_loggedIn) {
      await _shop.setQuantity(isbn, Quantity(quantity < 0 ? 0 : quantity));
    }
  }

  /// Empties the basket (after an order, on logout).
  void clear() => _items.clear();

  /// After a login the app's lines go to the server's basket, then the
  /// server's lines come back (with what the user put there before).
  @EventListener()
  Future<void> onLogin(LoggedIn event) async {
    for (final item in _items.values) {
      await _shop.setQuantity(item.isbn, Quantity(item.quantity));
    }
    final server = await _shop.basket();
    for (final line in server.items) {
      final known = _items[line.isbn];
      _items[line.isbn] = BasketItem(
        line.isbn,
        line.title.isEmpty ? (known?.title ?? line.isbn) : line.title,
        known?.price ?? 0,
        line.quantity,
      );
    }
    log.info('basket synchronized', fields: {'lines': _items.length});
  }

  @EventListener()
  void onLogout(LoggedOut event) => clear();

  static bool get _loggedIn =>
      SecurityContextHolder.getContext().authentication?.isAuthenticated ??
      false;
}
