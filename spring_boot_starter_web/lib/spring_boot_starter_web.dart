/// Spring MVC for Dart: `@RestController` classes with `@GetMapping`,
/// `@PostMapping`, ... on `dart:io`'s `HttpServer` (behind a replaceable
/// `WebServerFactory`), JSON through the `ObjectMapper`, `@Valid` bodies,
/// `ProblemDetail` errors with `@ExceptionHandler`, server-sent events
/// (`EventStream`, `SseEmitter`), filters, interceptors and CORS.
///
/// ```dart
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
library;

// Logging and spring_boot_dart (re-exported by the logging starter), so
// this starter is the only dependency an application needs.
export 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
export 'package:spring_web_dart/spring_web_dart.dart';

export 'src/cors.dart';
export 'src/dispatcher.dart';
export 'src/handler_method.dart';
export 'src/multipart_resolver.dart';
export 'src/request_mapping.dart' hide absent;
export 'src/response_writer.dart';
export 'src/sse_emitter.dart';
export 'src/web_exceptions.dart';
export 'src/web_server.dart';
export 'src/web_server_lifecycle.dart';
