// A Flutter app with reactive state in its beans: a basket whose total
// follows its items and coupon, saved by an effect, and a catalog loaded
// again when its genre changes. The generator writes example.spring.dart
// (`dart run build_runner build`).
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';

import 'spring_gen/example.spring.dart';

/// A book of the catalog.
class Book {
  /// The book titled [title], at [price].
  const Book(this.title, this.price);

  /// Its title.
  final String title;

  /// Its price.
  final double price;
}

/// Where baskets are kept between runs: in memory here.
@Service()
class BasketStorage {
  /// What was written, newest last.
  final List<int> saved = [];

  /// Keeps the basket of [count] books.
  void write(int count) => saved.add(count);
}

/// The basket: plain fields, followed.
@Component()
class Basket {
  /// The basket kept in [storage].
  Basket(this.storage);

  /// Where it is saved.
  final BasketStorage storage;

  /// The books in it. An assignment is a change, and so is a change in
  /// place: the list is handed out as one that follows itself.
  @Signal()
  List<Book> items = [];

  /// A coupon: ten percent off.
  @Signal()
  String? coupon;

  /// Kept until [items] or [coupon] changes.
  @Computed()
  double get total =>
      items.fold(0.0, (sum, book) => sum + book.price) *
      (coupon == null ? 1 : 0.9);

  /// Runs when the basket is made and each time [items] changes; the
  /// coupon is read without being followed.
  @Effect()
  void save() {
    untracked(() => coupon);
    storage.write(items.length);
  }

  /// Puts [book] in: a change in place.
  void add(Book book) => items.add(book);

  /// Takes the books titled [title] out.
  void remove(String title) => items = [
    for (final book in items)
      if (book.title != title) book,
  ];

  /// Empties the basket: two changes, told as one.
  void clear() {
    items.clear();
    coupon = null;
  }
}

/// The catalog's source: a server in a real app.
@Service()
class CatalogClient {
  /// How often the books were asked for.
  int requests = 0;

  /// The books of [genre].
  Future<List<Book>> byGenre(String genre) async {
    requests++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return [Book('$genre one', 10), Book('$genre two', 12)];
  }

  /// The price of the day for [genre], as it moves.
  Stream<double> prices(String genre) async* {
    yield genre.length.toDouble();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    yield genre.length * 2.0;
  }
}

/// The catalog: asynchronous state, loaded again when [genre] changes.
@Component()
class Catalog {
  /// The catalog read through [client].
  Catalog(this.client);

  /// Where the books come from.
  final CatalogClient client;

  /// The genre shown.
  @Signal()
  String genre = 'fiction';

  /// The books of [genre]: one request until the genre changes. The
  /// genre is read before the first `await`, so it is followed.
  @Computed()
  Future<List<Book>> get books => client.byGenre(genre);

  /// The price of [genre] as it moves: the state is its last event.
  @Computed()
  Stream<double> get price => client.prices(genre);
}

/// The page: the catalog with its state, and the basket's total.
class Shop extends StatelessWidget {
  /// The shop.
  const Shop({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = context.bean<Catalog>();
    final basket = context.bean<Basket>();
    return Column(
      children: [
        // Rebuilt when the state of the load moves, and when the genre
        // (and so the future) changes.
        AsyncView(
          () => catalog.books,
          loading: (context) => const Text('Loading'),
          data: (context, books) => Column(
            children: [
              for (final book in books)
                GestureDetector(
                  onTap: () => basket.add(book),
                  child: Text(book.title),
                ),
            ],
          ),
        ),
        // Rebuilt when the total changes, not for anything else.
        Watch((context) => Text('Total: ${basket.total}')),
      ],
    );
  }
}

/// A Spring widget: it gets the basket as a bean and follows its own
/// `build`, so it is built again when the coupon changes and for nothing
/// else of the basket.
class CouponLabel extends SpringStatelessWidget<(Basket,)> {
  /// The label.
  const CouponLabel({super.key});

  @override
  Widget build(BuildContext context) {
    final (basket,) = beans;
    return Text('Coupon: ${basket.coupon ?? 'none'}');
  }
}

@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    home: const Shop(),
  ),
);
