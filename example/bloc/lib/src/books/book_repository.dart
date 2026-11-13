import 'package:bloc_showcase/src/books/book.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

/// Where the books are kept: in memory here, a server in a real app. A
/// bean like any other; the blocs get it by injection, and a test puts
/// its own in its place (`BeanOverride`).
@Service()
class BookRepository {
  final List<Book> _books = [const Book('Dune'), const Book('Neuromancer')];

  /// Every book, after a moment (as a request would take).
  Future<List<Book>> all() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return List.unmodifiable(_books);
  }

  /// Adds a book titled [title]. Fails for a title already there.
  Future<void> add(String title) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (_books.any((book) => book.title == title)) {
      throw StateError('"$title" is on the shelf already');
    }
    _books.add(Book(title));
  }
}
