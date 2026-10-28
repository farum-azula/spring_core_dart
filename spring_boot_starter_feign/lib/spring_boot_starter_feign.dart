/// Declarative HTTP clients: describe a remote API as an abstract class,
/// and get a working client bean to inject.
///
/// Add the starter to an application that calls other services over
/// HTTP, from a server or a Flutter app. Annotate an abstract class with
/// `@FeignClient` and its methods with the mapping annotations a
/// controller uses (`@GetMapping`, `@PathVariable()`, `@RequestBody()`,
/// ...). The generator writes the implementation: arguments become the
/// path, query, headers and body, JSON goes through the `ObjectMapper`,
/// error statuses become `FeignException`s, and server-sent events
/// arrive as an `EventStream`. Timeouts, logging, retries, interceptors
/// and fallbacks are configured per client.
///
/// This one import is enough: it re-exports `spring_web_dart` and
/// `spring_boot_starter_logging` (and through it `spring_boot_dart` and
/// `spring_core_dart`).
///
/// ```dart
/// // The catalog service, as the shop calls it.
/// @FeignClient('catalog', url: r'${catalog.url}')
/// abstract interface class CatalogClient {
///   @GetMapping('/books/{isbn}')
///   Future<Book> find(@PathVariable() String isbn);
///
///   @GetMapping('/books/events')
///   EventStream<BookEvent> events(); // server-sent events
/// }
/// ```
///
/// Spring (Java), with Spring Cloud OpenFeign:
/// ```java
/// @FeignClient(name = "catalog", url = "${catalog.url}")
/// interface CatalogClient {
///   @GetMapping("/books/{isbn}")
///   Book find(@PathVariable String isbn);
/// }
/// ```
library;

// Logging and spring_boot_dart (re-exported by the logging starter), so
// this starter is the only dependency an application needs.
export 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
export 'package:spring_web_dart/spring_web_dart.dart';

export 'src/feign_client.dart';
export 'src/feign_client_config.dart';
export 'src/feign_client_factory.dart';
export 'src/feign_exception.dart';
export 'src/feign_invocation_handler.dart';
export 'src/request_template.dart' hide appendQuery;
export 'src/retryer.dart';
