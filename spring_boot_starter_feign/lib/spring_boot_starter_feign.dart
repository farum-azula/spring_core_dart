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
/// }
/// ```
///
/// Re-exports `spring_boot_dart` and `spring_web_dart`.
library;

export 'package:spring_boot_dart/spring_boot_dart.dart';
export 'package:spring_web_dart/spring_web_dart.dart';

export 'src/feign_client.dart';
export 'src/feign_client_config.dart';
export 'src/feign_client_factory.dart';
export 'src/feign_exception.dart';
export 'src/feign_invocation_handler.dart';
export 'src/request_template.dart';
export 'src/retryer.dart';
