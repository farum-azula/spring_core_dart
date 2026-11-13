import 'package:bloc_showcase/src/books/book.dart';

/// Where the shelf is.
sealed class BooksState {
  const BooksState();
}

/// Being loaded.
final class BooksLoading extends BooksState {
  /// The loading state.
  const BooksLoading();

  @override
  String toString() => 'BooksLoading';
}

/// Loaded: [books], and what went wrong with the last addition, if it did.
final class BooksLoaded extends BooksState {
  /// The shelf with [books].
  const BooksLoaded(this.books, {this.problem});

  /// The books.
  final List<Book> books;

  /// Why the last book was not added, `null` when it was.
  final String? problem;

  @override
  String toString() =>
      'BooksLoaded(${books.length}${problem == null ? '' : ', $problem'})';
}
