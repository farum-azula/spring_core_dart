/// An HTTP server for a Spring application: classes marked
/// `@RestController` answer requests, one method per mapping.
///
/// Add the starter to an application to serve a REST API, a backend for
/// a web page, or a local API inside a Flutter app. The starter maps
/// `@GetMapping`, `@PostMapping`, ... methods to paths, binds path
/// variables, query parameters, headers and JSON bodies to their
/// parameters, validates `@Valid()` bodies, writes results as JSON, and
/// answers errors as `ProblemDetail`s (customized with
/// `@ExceptionHandler`). It also covers server-sent events (`EventStream`,
/// `SseEmitter`), file uploads and downloads, sessions, filters,
/// interceptors and CORS. The server is `dart:io`'s `HttpServer`, set up
/// from `server.*`, and it starts and stops with the application.
///
/// This one import is enough: it re-exports `spring_boot_dart`,
/// `spring_web_dart` (the annotations, `ResponseEntity`, `ProblemDetail`)
/// and the logging starter.
///
/// ```dart
/// // GET /api/books/978-0 answers the book as JSON.
/// @RestController()
/// @RequestMapping('/api/books')
/// class BookController {
///   BookController(this.books);
///   final BookService books;
///
///   @GetMapping('/{isbn}')
///   Future<Book> find(@PathVariable() String isbn) => books.find(isbn);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @RestController
/// @RequestMapping("/api/books")
/// class BookController {
///   @GetMapping("/{isbn}")
///   Book find(@PathVariable String isbn) { ... }
/// }
/// ```
library;

// Logging and spring_boot_dart (re-exported by the logging starter), so
// this starter is the only dependency an application needs.
export 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
export 'package:spring_web_dart/spring_web_dart.dart';

export 'src/cors.dart' hide addVary;
export 'src/dispatcher.dart';
export 'src/form_parameters.dart';
export 'src/handler_method.dart';
export 'src/http_session.dart';
export 'src/multipart_resolver.dart';
export 'src/request_mapping.dart' hide absent, dispatcherCorsConfiguration;
export 'src/response_writer.dart';
export 'src/sse_emitter.dart';
export 'src/web_exceptions.dart';
export 'src/web_server.dart';
export 'src/web_server_lifecycle.dart';
