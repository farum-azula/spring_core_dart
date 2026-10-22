import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Turns an abstract class into an HTTP client bean, like Spring Cloud
/// OpenFeign's `@FeignClient`: annotate its methods with `@GetMapping`,
/// `@PostMapping`, ... and inject it; the generator writes the
/// implementation (no reflection).
///
/// ```dart
/// @FeignClient('catalog', url: r'${catalog.url}')
/// abstract interface class CatalogClient {
///   @GetMapping('/books/{isbn}')
///   Future<Book> find(@PathVariable() String isbn);
///
///   @GetMapping('/books')
///   Future<List<Book>> search(@RequestParam('q') String query);
///
///   @PostMapping('/books')
///   Future<Book> create(@RequestBody() Book book);
/// }
///
/// @Service()
/// class Shop {
///   Shop(this.catalog);
///   final CatalogClient catalog;
/// }
/// ```
///
/// [name] keys the configuration
/// (`spring.cloud.openfeign.client.config.<name>.*`); [url] (placeholders allowed) wins over the configured
/// `url`; [path] prefixes every method's path; [fallback] is a bean class
/// implementing the same interface, called when a request fails.
///
/// Spring (Java):
/// ```java
/// @FeignClient(name = "catalog", url = "${catalog.url}", fallback = CatalogFallback.class)
/// interface CatalogClient {
///   @GetMapping("/books/{isbn}")
///   Book find(@PathVariable String isbn);
/// }
/// ```
@InterfaceProxy(primary: true)
class FeignClient {
  /// A client named [name].
  const FeignClient(this.name, {this.url, this.path = '', this.fallback});

  /// The client name (configuration key, logger name).
  final String name;

  /// The base URL, e.g. `https://api.neon.books` or `${catalog.url}`.
  final String? url;

  /// A path prefix for every method, e.g. `/v1`.
  final String path;

  /// A bean class implementing the interface, used when a call fails.
  final Type? fallback;
}
