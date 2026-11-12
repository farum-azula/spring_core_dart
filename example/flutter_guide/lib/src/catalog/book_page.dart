import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:neon_books_app/spring_gen/main.spring.dart';
import 'package:neon_books_app/src/api/models.dart';
import 'package:neon_books_app/src/app/messages.dart';
import 'package:neon_books_app/src/basket/basket.dart';
import 'package:neon_books_app/src/catalog/catalog_service.dart';
import 'package:neon_books_app/src/stock/live_stock.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// The beans of [BookPage].
typedef BookPageBeans = (
  CatalogService,
  Basket,
);

/// The Book screen: the cover, the details, the stock and "Add to basket".
/// Both reads go through `CatalogService`, so they are cached: opening the
/// book again shows it without a request.
@ScreenRoute('/books/{isbn}', title: '#{book.title}')
class BookPage extends SpringStatefulWidget<BookPageBeans> {
  const BookPage({this.isbn, super.key});

  /// The book shown; `null` (the screen of the route): the route's `isbn`.
  final String? isbn;

  /// Opens the book [isbn] over everything (`/books/{isbn}`).
  static Future<void> open(BuildContext context, String isbn) =>
      RouteTemplate.read(context).push<void>(BookPageRoute.to(isbn: isbn));

  @override
  State<BookPage> createState() => _BookPageState();
}

class _BookPageState extends SpringState<BookPage, BookPageBeans> {
  late final Future<Book?> _book;
  late final Future<Uint8List?> _cover;

  @override
  void initState() {
    super.initState();
    final (
      catalog,
      _,
    ) = beans;
    final String isbn =
        widget.isbn ?? RouteTemplate.read(context).get(BookPageRoute.isbn);
    _book = catalog.find(isbn);
    _cover = catalog.cover(isbn);
  }

  Future<void> _add(Book book) async {
    final (
      _,
      basket,
    ) = beans;
    final messenger = ScaffoldMessenger.of(context);
    final added = context.messages.basket.added(book.title);
    await basket.add(book);
    messenger.showSnackBar(SnackBar(content: Text(added)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.messages.book.title)),
      body: FutureBuilder(
        future: _book,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(errorMessage(context, snapshot.error!)));
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: ThemeLoader(context.theme.loaders.bar));
          }
          final book = snapshot.data;
          if (book == null) {
            return Center(
              child: Text(
                context.messages.book.notFound(widget.isbn),
              ),
            );
          }
          return ListView(
            padding: EdgeInsets.all(theme.spacing.m),
            children: [
              Center(child: _Cover(_cover)),
              SizedBox(height: theme.spacing.m),
              Text(book.title, style: text.headlineMedium),
              Text(book.author, style: text.titleMedium),
              SizedBox(height: theme.spacing.s),
              Text('ISBN ${book.isbn}', style: theme.typography.code),
              Text(price(book.price), style: text.titleLarge),
              _Stock(book),
              SizedBox(height: theme.spacing.m),
              FilledButton.icon(
                onPressed: () => _add(book),
                icon: const Icon(Icons.add_shopping_cart),
                label: Text(context.messages.basket.add),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover(this.cover);

  final Future<Uint8List?> cover;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 240,
    child: FutureBuilder(
      future: cover,
      builder: (context, snapshot) => switch (snapshot.data) {
        final bytes? => ClipRRect(
          borderRadius: BorderRadius.circular(
            SpringTheme.of(context).shape('small'),
          ),
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
        null => const Icon(Icons.menu_book, size: 120),
      },
    ),
  );
}

/// The copies in stock: the newest number the live stock events brought,
/// else what the server said with the book. Rebuilds on each event.
class _Stock extends SpringStatelessWidget<(LiveStock,)> {
  const _Stock(this.book);

  final Book book;

  @override
  Widget build(BuildContext context) {
    final (stock,) = beans;
    final available = stock.available[book.isbn] ?? book.available;
    return Text(
      available > 0
          ? context.messages.book.inStock(available)
          : context.messages.book.soldOut,
    );
  }
}
