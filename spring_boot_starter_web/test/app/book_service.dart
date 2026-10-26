import 'dart:async';

import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

import 'models.dart';

@Service()
class BookService {
  final _books = <String, Book>{
    '1111': const Book(isbn: '1111', title: 'Dune', stock: 3),
    '2222': const Book(isbn: '2222', title: 'Cosmos', genre: Genre.science),
  };
  final _changes = StreamController<Book>.broadcast();
  final emitters = <SseEmitter>[];

  Future<Book> find(String isbn) async =>
      _books[isbn] ?? (throw BookNotFoundException(isbn));

  Future<List<Book>> search(String query, {int page = 0, Genre? genre}) async =>
      _books.values
          .where((b) => b.title.toLowerCase().contains(query.toLowerCase()))
          .where((b) => genre == null || b.genre == genre)
          .skip(page * 20)
          .take(20)
          .toList();

  Future<Book> create(NewBook book) async {
    if (_books.containsKey(book.isbn)) {
      throw StateError('Book ${book.isbn} exists');
    }
    final created = Book(isbn: book.isbn, title: book.title, stock: book.stock);
    _books[book.isbn] = created;
    _changes.add(created);
    for (final emitter in [...emitters]) {
      unawaited(
        emitter.send(ServerSentEvent<Object?>(created, event: 'created')),
      );
    }
    return created;
  }

  bool delete(String isbn) => _books.remove(isbn) != null;

  Stream<Book> changes() => _changes.stream;
}
