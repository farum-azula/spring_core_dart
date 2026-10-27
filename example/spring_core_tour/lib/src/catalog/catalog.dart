// Declaring beans and every injection style.
//
// Spring (Java) counterpart: @Repository / @Service / @Component classes
// with constructor, field, setter and method injection.
import 'package:spring_core_dart/spring_core_dart.dart';

@Introspected()
class Book {
  Book(this.isbn, this.title, this.price, {this.tags = const []});

  final String isbn;
  final String title;
  final double price;
  final List<String> tags;

  @override
  String toString() => title;
}

abstract interface class BookRepository {
  List<Book> findAll();
  Book? find(String isbn);
}

/// A stereotype: registered under its own type and its interfaces.
@Repository()
class InMemoryBookRepository implements BookRepository {
  final _books = [
    Book('1', 'Dune', 12.5, tags: ['fiction']),
    Book('2', 'Cosmos', 15, tags: ['science']),
    Book('3', 'Leaves of Grass', 8, tags: ['poetry']),
  ];

  @override
  List<Book> findAll() => List.unmodifiable(_books);

  @override
  Book? find(String isbn) => _books.where((b) => b.isbn == isbn).firstOrNull;
}

/// Collection injection: every Discount, sorted by @Order.
abstract interface class Discount {
  String get name;
  int percentFor(Book book);
}

@Component()
@Order(2)
class LoyaltyDiscount implements Discount {
  @override
  String get name => 'loyalty';
  @override
  int percentFor(Book book) => 5;
}

@Component()
@Order(1)
class PoetryDiscount implements Discount {
  @override
  String get name => 'poetry';
  @override
  int percentFor(Book book) => book.tags.contains('poetry') ? 20 : 0;
}

/// A composite that is itself a Discount: it receives the *other*
/// discounts (Spring's self-reference exclusion) and, being @Primary, wins
/// when a single Discount is injected.
@Component()
@Primary()
class BestDiscount implements Discount {
  BestDiscount(this.all);

  final List<Discount> all;

  @override
  String get name => 'best of ${all.map((d) => d.name).join('/')}';

  @override
  int percentFor(Book book) => all
      .map((d) => d.percentFor(book))
      .fold(0, (best, p) => p > best ? p : best);
}

/// Nobody implements Plugin: a single constructor gets an empty list.
abstract interface class Plugin {}

abstract interface class Clock {
  DateTime now();
}

@Service()
class CatalogService {
  CatalogService(
    this.books,
    this.discount,
    this.plugins, {
    @Value(r'${app.currency}') required this.currency,
    @Value(r'${catalog.page-size:20}') this.pageSize = 20,
    this.retries = 3,
  });

  final BookRepository books;
  final Discount discount;
  final List<Plugin> plugins;
  final int pageSize;
  final String currency;

  /// No `int` bean exists: the Dart default value is kept.
  final int retries;

  /// Field injection, with conversion from the property's text.
  @Value(r'${shop.delivery-time}')
  late final Duration deliveryTime;

  @Value(r'${shop.tags}')
  late final List<String> tags;

  /// SpEL in @Value (`#{...}` reads the `appInfo` bean) mixed with a
  /// placeholder (resolved first).
  @Value(r'#{appInfo.name.toUpperCase()} (${payment.mode})')
  late final String banner;

  /// A missing optional value: null, not an error.
  @Value(r'${shop.motto}')
  String? motto;

  /// Optional with an initializer: kept when the property is missing.
  @Value(r'${shop.slogan}')
  String? slogan = 'Books for night owls';

  Clock? _clock;

  /// Setter injection.
  @Autowired()
  set clock(Clock value) => _clock = value;
  Clock? get clock => _clock;

  /// Method injection, after fields and setters.
  String? wiredWith;
  @Autowired()
  void wire(Environment environment, ApplicationEventPublisher publisher) =>
      wiredWith = '${environment.runtimeType} + ${publisher.runtimeType}';

  double priceOf(Book book) =>
      book.price * (100 - discount.percentFor(book)) / 100;

  List<Book> firstPage() => books.findAll().take(pageSize).toList();
}
