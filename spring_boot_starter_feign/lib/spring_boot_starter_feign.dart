/// Feign clients for `spring_boot_dart`, like Spring Cloud OpenFeign:
/// annotate an abstract class with `@FeignClient` and its methods with
/// `@GetMapping`, `@PostMapping`, ...; inject it like any bean. The
/// generator writes the implementation; requests and responses go through
/// the `ObjectMapper`.
///
/// ```dart
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
/// Re-exports `spring_web_dart` and `spring_boot_starter_logging` (and
/// through it `spring_boot_dart` and `spring_core_dart`): the starter is the
/// only dependency an application lists.
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
