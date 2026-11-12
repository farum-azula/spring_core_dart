import 'package:material_ui/material_ui.dart';
import 'package:neon_books_app/spring_gen/main.spring.dart';
import 'package:neon_books_app/src/api/models.dart';
import 'package:neon_books_app/src/app/messages.dart';
import 'package:neon_books_app/src/catalog/book_page.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// A book in the list: a tap opens it, the button puts it into the basket
/// (`context.basket`, the getter `@BuildContextAccess` generates; a call,
/// not a read, so the tile does not listen to the basket).
class BookTile extends StatelessWidget {
  const BookTile(this.book, {super.key});

  final Book book;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: CircleAvatar(child: Text(book.title.characters.first)),
    title: Text(book.title),
    subtitle: Text('${book.author} · ${price(book.price)}'),
    onTap: () => BookPage.open(context, book.isbn),
    trailing: IconButton(
      onPressed: () => context.basket.add(book),
      tooltip: context.message('basket.add'),
      icon: const Icon(Icons.add_shopping_cart),
    ),
  );
}

/// The shape of [BookTile]s while the books are on their way: `count` rows
/// in the colour a [ThemeSkeleton] paints them in.
class BookTilePlaceholder extends StatelessWidget {
  const BookTilePlaceholder({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    const fill = Color(0xFFFFFFFF);
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < count; i++)
          ListTile(
            leading: const CircleAvatar(backgroundColor: fill),
            title: Align(
              alignment: Alignment.centerLeft,
              child: Container(height: 14, width: 160, color: fill),
            ),
            subtitle: Align(
              alignment: Alignment.centerLeft,
              child: Container(height: 10, width: 220, color: fill),
            ),
          ),
      ],
    );
  }
}
