import 'dart:typed_data';

import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

import 'book_service.dart';
import 'models.dart';

@RestController()
@RequestMapping('/api/books')
class BookController {
  BookController(this.books);

  final BookService books;

  @GetMapping('/{isbn}')
  Future<Book> find(@PathVariable() String isbn) => books.find(isbn);

  @GetMapping()
  Future<List<Book>> search(
    @RequestParam('q') String query, {
    @RequestParam('page') int page = 0,
    @RequestParam('genre') Genre? genre,
  }) => books.search(query, page: page, genre: genre);

  @PostMapping('/form')
  String form(
    @RequestParam('title') String title,
    @RequestParam('count') int count,
  ) => '$title x$count';

  // A missing parameter takes the Dart default, a nullable one null.
  @GetMapping('/sample/defaults')
  String sample({
    @RequestParam('size') int size = 3,
    @RequestParam() String sort = 'title',
    @RequestParam('tag') String? tag,
    @RequestParam('limit') int? limit,
    @RequestHeader('X-Lang') String? lang,
  }) => '$size by $sort, $tag, $limit, $lang';

  @PostMapping()
  Future<ResponseEntity<Book>> create(
    @RequestBody() @Valid() NewBook book,
  ) async {
    final created = await books.create(book);
    return ResponseEntity.created(Uri.parse('/api/books/${created.isbn}'))
        .body(created);
  }

  @DeleteMapping('/{isbn}')
  @ResponseStatus(HttpStatus.noContent)
  void delete(@PathVariable() String isbn) {
    if (!books.delete(isbn)) {
      throw ResponseStatusException(HttpStatus.notFound, 'No book $isbn');
    }
  }

  @GetMapping('/changes')
  EventStream<Book> changes() => EventStream(
    () => books.changes().map((b) => ServerSentEvent(b, id: b.isbn)),
  );

  @GetMapping('/notifications')
  SseEmitter notifications() {
    final emitter = SseEmitter();
    books.emitters.add(emitter);
    emitter.onCompletion(() => books.emitters.remove(emitter));
    return emitter;
  }

  @ExceptionHandler()
  @ResponseStatus(HttpStatus.notFound)
  ProblemDetail notFound(BookNotFoundException e, ServerHttpRequest request) =>
      ProblemDetail.forStatusAndDetail(HttpStatus.notFound, 'No book ${e.isbn}')
        ..setProperty('isbn', e.isbn);
}

@RestController()
@RequestMapping('/misc')
class MiscController {
  @GetMapping('/text')
  String text() => 'hello';

  @GetMapping('/slow')
  Future<String> slow() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return 'done';
  }

  @GetMapping.of(path: '/bytes', produces: 'application/octet-stream')
  Uint8List bytes() => Uint8List.fromList([1, 2, 3]);

  @GetMapping('/echo-header')
  String echoHeader(@RequestHeader('X-Name') String name) => 'hi $name';

  @GetMapping('/cookie')
  String cookie(@CookieValue('session') String session) => session;

  @GetMapping('/ids')
  List<int> ids(@RequestParam('id') List<int> ids) => ids;

  @GetMapping('/files/{*path}')
  String file(@PathVariable() String path) => path;

  @PostMapping.of(path: '/json-only', consumes: 'application/json')
  Map<String, Object?> jsonOnly(@RequestBody() Map<String, Object?> body) =>
      body;

  @GetMapping('/state')
  String state() => throw StateError('broken');

  @GetMapping('/boom')
  String boom() => throw UnsupportedError('boom');

  @GetMapping('/request')
  String request(ServerHttpRequest request) =>
      '${request.method.value} ${request.path}';

  @GetMapping.of(path: '/ndjson', produces: 'application/x-ndjson')
  Stream<Book> ndjson() => Stream.fromIterable(const [
    Book(isbn: '1', title: 'A'),
    Book(isbn: '2', title: 'B'),
  ]);
}

@RestControllerAdvice()
class ApiErrors {
  @ExceptionHandler()
  ResponseEntity<ProblemDetail> conflict(StateError error) =>
      ResponseEntity.status(HttpStatus.conflict).body(
        ProblemDetail.forStatusAndDetail(HttpStatus.conflict, error.message),
      );
}
