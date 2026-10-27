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
/// (`spring.cloud.openfeign.client.config.<name>.*`) unless [contextId]
/// is given; [url] (placeholders allowed) wins over the configured `url`;
/// [path] prefixes every method's path; [fallback] is a bean class
/// implementing the same interface, called when a request fails. The
/// client bean is `@Primary` unless [primary] is `false`, and `@Qualifier`
/// selects it by each of [qualifiers] too; [dismiss404] turns a 404 into
/// an empty result like the `dismiss404` property; [configuration] lists
/// classes whose beans configure this client only.
///
/// Spring (Java):
/// ```java
/// @FeignClient(name = "catalog", url = "${catalog.url}",
///     fallback = CatalogFallback.class)
/// interface CatalogClient {
///   @GetMapping("/books/{isbn}")
///   Book find(@PathVariable String isbn);
/// }
/// ```
@InterfaceProxy(primary: true)
class FeignClient {
  /// A client named [name].
  const FeignClient(
    this.name, {
    this.url,
    this.path = '',
    this.fallback,
    this.contextId,
    this.qualifiers = const [],
    this.primary = true,
    this.dismiss404 = false,
    this.configuration = const [],
  });

  /// The client name (configuration key unless [contextId] is set; the
  /// `clientName` interceptors see).
  final String name;

  /// The base URL, e.g. `https://api.neon.books` or `${catalog.url}`.
  final String? url;

  /// A path prefix for every method, e.g. `/v1`.
  final String path;

  /// A bean class implementing the interface, used when a call fails.
  final Type? fallback;

  /// The configuration key instead of [name]
  /// (`spring.cloud.openfeign.client.config.<contextId>.*`), e.g. for two
  /// clients of one service with different settings.
  final String? contextId;

  /// Extra names that select the client bean with `@Qualifier(...)`.
  final List<String> qualifiers;

  /// Whether the client bean is `@Primary` (default `true`, so a fallback
  /// implementing the same interface does not make injection ambiguous).
  final bool primary;

  /// Whether a 404 gives an empty result (`null` for a nullable result, a
  /// `ResponseEntity` with the status) instead of a `FeignNotFound`;
  /// `void` methods still throw, like Feign. The `dismiss404` property
  /// turns it on too.
  final bool dismiss404;

  /// Configuration classes of this client, like Spring Cloud OpenFeign's
  /// `@FeignClient(configuration = ...)`: the `Retryer`, `ErrorDecoder`
  /// and `RequestInterceptor` beans their `@Bean` methods declare apply
  /// to the clients that list the class only. A listed class is a
  /// `@Configuration()` bean as usual (Dart creates no classes by
  /// reflection); its `Retryer` / `ErrorDecoder` win over the
  /// application's, its interceptors run with the application's, and
  /// none of its beans reaches clients that do not list it.
  ///
  /// ```dart
  /// @FeignClient('catalog', configuration: [CatalogFeignConfig])
  /// abstract interface class CatalogClient { ... }
  ///
  /// @Configuration()
  /// class CatalogFeignConfig {
  ///   @Bean()
  ///   Retryer catalogRetryer() => const DefaultRetryer(maxAttempts: 3);
  ///
  ///   @Bean()
  ///   RequestInterceptor catalogAuth() =>
  ///       BasicAuthRequestInterceptor('shop', 's3cret');
  /// }
  /// ```
  final List<Type> configuration;

  /// The configuration key: [contextId], or [name] without one.
  String get configKey => switch (contextId) {
    final id? when id.isNotEmpty => id,
    _ => name,
  };
}
