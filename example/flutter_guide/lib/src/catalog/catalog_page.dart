import 'package:flutter/material.dart';
import 'package:neon_books_app/src/app/messages.dart';
import 'package:neon_books_app/src/catalog/book_tile.dart';
import 'package:neon_books_app/src/catalog/catalog.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The Catalog screen: a search field and the books.
///
/// The page only calls `catalog.search`, it reads no state, so a new
/// answer does not rebuild it (nor the text field in it): only
/// [CatalogList] rebuilds, the widget that reads `catalog.books`.
class CatalogPage extends SpringStatefulWidget<(Catalog,)> {
  const CatalogPage({super.key});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends SpringState<CatalogPage, (Catalog,)> {
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The whole catalog when the screen opens: from the cache after the
    // first time. A call, not a read: this page does not listen to the
    // catalog (reading `catalog.query` here would make it).
    beans.$1.search('');
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (catalog,) = beans;
    final space = SpringTheme.of(context).space('m');
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(space, space, space, 0),
          child: TextField(
            key: const Key('catalog-search'),
            controller: _query,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: context.message('catalog.search'),
            ),
            onSubmitted: catalog.search,
          ),
        ),
        const Expanded(child: CatalogList()),
      ],
    );
  }
}

/// The books of the page, and the pages. Reads the `Catalog` bean's state
/// in build: rebuilt after every search or page change.
class CatalogList extends SpringStatelessWidget<(Catalog,)> {
  const CatalogList({super.key});

  @override
  Widget build(BuildContext context) {
    final (catalog,) = beans;
    final books = catalog.books;
    final error = catalog.error;
    if (error != null) {
      return _Message(
        icon: Icons.cloud_off,
        text: errorMessage(context, error),
        action: TextButton(
          onPressed: catalog.reload,
          child: Text(context.message('catalog.retry')),
        ),
      );
    }
    if (books == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (books.items.isEmpty) {
      return _Message(
        icon: Icons.search_off,
        text: context.message('catalog.empty'),
      );
    }
    final pages = books.pages;
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [for (final book in books.items) BookTile(book)],
          ),
        ),
        if (pages > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: books.page > 0
                    ? () => catalog.showPage(books.page - 1)
                    : null,
                tooltip: context.message('catalog.previous'),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                context.message('catalog.page', args: [books.page + 1, pages]),
              ),
              IconButton(
                onPressed: books.page + 1 < pages
                    ? () => catalog.showPage(books.page + 1)
                    : null,
                tooltip: context.message('catalog.next'),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          ?action,
        ],
      ),
    ),
  );
}
