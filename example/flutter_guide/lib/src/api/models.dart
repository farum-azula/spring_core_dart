import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

// The JSON of the server's API (see "API" in the README). The app and the
// server share no Dart package: these classes are the app's own view of
// the contract. `@Introspected()` gives the ObjectMapper what it needs to
// read and write them (no fromJson / toJson); the Feign clients'
// parameter and result types are introspected anyway.

/// A book of the catalog:
/// `{"isbn": "978-0441013593", "title": "Dune", "author": "Frank Herbert",
/// "price": 12.5, "available": 3}`.
@Introspected()
class Book {
  const Book({
    required this.isbn,
    required this.title,
    this.author = '',
    this.price = 0,
    this.available = 0,
  });

  final String isbn;
  final String title;
  final String author;
  final double price;

  /// Copies in stock, as the server knew it when it answered; the Live
  /// stock screen has the newer numbers.
  final int available;
}

/// One page of the catalog: `{"items": [...], "page": 0, "size": 20,
/// "total": 42}` (`page` counts from 0, `total` is the number of books).
@Introspected()
class PageOfBooks {
  const PageOfBooks({
    this.items = const [],
    this.page = 0,
    this.size = 0,
    this.total = 0,
  });

  final List<Book> items;
  final int page;

  /// Books per page; without it, the length of the first page.
  final int size;
  final int total;

  /// How many pages there are.
  int get pages {
    final perPage = size > 0 ? size : items.length;
    return perPage == 0 ? 1 : (total / perPage).ceil();
  }
}

/// The body of `POST /api/books` (the Admin screen), checked before it is
/// sent (chapter 9). Mutable, so the Admin form binds its text fields onto
/// it with a `DataBinder`; the constraints are those the server checks
/// with `@Valid`.
@Introspected()
class NewBook {
  /// An ISBN-13 without dashes (978 or 979, then 10 digits), as the
  /// server requires.
  @NotBlank()
  @Matches(r'^97[89]\d{10}$')
  String isbn = '';

  @NotBlank()
  @SizeConstraint(max: 120)
  String title = '';

  @NotBlank()
  @SizeConstraint(max: 80)
  String author = '';

  @Positive()
  @Max(1000)
  double price = 0;
}

/// A server-sent event of `GET /api/stock/events`:
/// `{"isbn": "978-0441013593", "available": 2}`.
@Introspected()
class StockChanged {
  const StockChanged({required this.isbn, required this.available});

  final String isbn;
  final int available;
}

/// What `GET /api/me` says about the logged-in user:
/// `{"name": "ada", "roles": ["USER"]}`.
@Introspected()
class Me {
  const Me({required this.name, this.roles = const []});

  final String name;

  /// `USER`, `ADMIN` (a `ROLE_` prefix is accepted too).
  final List<String> roles;
}

/// One line of the server's basket.
@Introspected()
class BasketLine {
  const BasketLine({required this.isbn, this.title = '', this.quantity = 0});

  final String isbn;
  final String title;
  final int quantity;
}

/// `GET /api/basket`: `{"items": [{"isbn": "...", "quantity": 2}]}`.
@Introspected()
class ServerBasket {
  const ServerBasket({this.items = const []});

  final List<BasketLine> items;
}

/// The body of `PUT /api/basket/items/{isbn}`: `{"quantity": 2}`.
@Introspected()
class Quantity {
  const Quantity(this.quantity);

  final int quantity;
}

/// An order: `{"id": "7", "user": "ada", "lines": [...], "total": 25.0,
/// "placedAt": "2026-10-27T09:30:00.000Z"}`.
@Introspected()
class ShopOrder {
  const ShopOrder({
    required this.id,
    this.user = '',
    this.lines = const [],
    this.total = 0,
    this.placedAt,
  });

  /// A number or a text, whatever the server uses.
  final Object id;
  final String user;
  final List<BasketLine> lines;
  final double total;
  final DateTime? placedAt;
}

/// A message of the support chat (`/ws/support`), both ways:
/// `{"from": "ada", "text": "Where is my order?", "at": "2026-..."}`.
@Introspected()
class ChatMessage {
  const ChatMessage({required this.from, required this.text, this.at});

  final String from;
  final String text;
  final DateTime? at;
}
