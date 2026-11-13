/// What can be asked of the shelf.
sealed class BooksEvent {
  const BooksEvent();
}

/// Load the books.
final class BooksRequested extends BooksEvent {
  /// The request.
  const BooksRequested();

  @override
  String toString() => 'BooksRequested';
}

/// Put a book titled [title] on the shelf.
final class BookAdded extends BooksEvent {
  /// The addition of [title].
  const BookAdded(this.title);

  /// The new book's title.
  final String title;

  @override
  String toString() => 'BookAdded($title)';
}
