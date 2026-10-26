// A REST API in a Spring Boot application: write the controller, the
// generator registers it and writes its request handlers (example.spring.dart,
// from `dart run build_runner build`). JSON goes through the ObjectMapper,
// `@Valid` checks request bodies, errors are answered as ProblemDetail.
//
//   dart run example/example.dart
//   curl localhost:8080/api/books/978-0
//   curl -N localhost:8080/api/books/added       # server-sent events
//   curl -i localhost:8080/api/books -H 'Content-Type: application/json' \
//       -d '{"isbn": "978-1", "title": "Emma"}'
import 'dart:async';

import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

import 'example.spring.dart';

class Book {
  const Book({required this.isbn, required this.title});
  final String isbn;
  final String title;
}

class NewBook {
  const NewBook({required this.isbn, required this.title});

  @NotBlank()
  @Size(min: 4, max: 13)
  final String isbn;

  @NotBlank()
  final String title;
}

class BookNotFound implements Exception {
  BookNotFound(this.isbn);
  final String isbn;
}

@Service()
class BookService {
  final _books = <String, Book>{};
  final _added = StreamController<Book>.broadcast();

  @PostConstruct()
  void init() {
    _books['978-0'] = const Book(isbn: '978-0', title: 'Dune');
  }

  Book find(String isbn) => _books[isbn] ?? (throw BookNotFound(isbn));

  Book add(NewBook book) {
    final added = _books[book.isbn] = Book(isbn: book.isbn, title: book.title);
    _added.add(added);
    return added;
  }

  Stream<Book> get added => _added.stream;
}

@RestController()
@RequestMapping('/api/books')
class BookController {
  BookController(this.books);
  final BookService books;

  @GetMapping('/{isbn}')
  Book find(@PathVariable() String isbn) => books.find(isbn);

  /// 201 with a `Location` header; an invalid body is a 400 ProblemDetail.
  @PostMapping()
  ResponseEntity<Book> create(@RequestBody() @Valid() NewBook book) {
    final added = books.add(book);
    return ResponseEntity.created(Uri.parse('/api/books/${added.isbn}'))
        .body(added);
  }

  /// Each added book as a server-sent event (`text/event-stream`).
  @GetMapping('/added')
  EventStream<Book> added() => EventStream(
    () => books.added.map((book) => ServerSentEvent(book, id: book.isbn)),
  );

  /// `application/problem+json`: `{"status": 404, "detail": ...}`.
  @ExceptionHandler()
  @ResponseStatus(HttpStatus.notFound)
  ProblemDetail notFound(BookNotFound e) => ProblemDetail.forStatusAndDetail(
    HttpStatus.notFound,
    'No book ${e.isbn}',
  );
}

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
