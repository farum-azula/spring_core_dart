// Plain classes: introspected because the controllers use them.
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

enum Genre { fiction, science, poetry }

class Book {
  const Book({
    required this.isbn,
    required this.title,
    this.stock = 0,
    this.genre = Genre.fiction,
  });

  final String isbn;
  final String title;
  final int stock;
  final Genre genre;
}

class NewBook {
  const NewBook({required this.isbn, required this.title, this.stock = 0});

  @NotBlank()
  @Size(min: 4, max: 13)
  final String isbn;

  @NotBlank()
  final String title;

  @PositiveOrZero()
  final int stock;
}

class BookNotFoundException implements Exception {
  BookNotFoundException(this.isbn);

  final String isbn;
}
