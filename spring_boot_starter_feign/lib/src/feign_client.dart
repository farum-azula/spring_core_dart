import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Marks an abstract class as the description of a remote HTTP API, for
/// which the starter provides a working client bean.
///
/// Calling another service usually means building URLs, encoding JSON,
/// sending the request, checking the status and decoding the answer, for
/// every endpoint. With `@FeignClient` you only declare the endpoints: one
/// abstract method per call, with the same mapping annotations a
/// controller uses (`@GetMapping`, `@PathVariable()`, `@RequestBody()`,
/// ...). The generator writes the implementation; inject the interface
/// like any bean and call its methods. Methods return a `Future` (or an
/// `EventStream` for server-sent events); an error status throws a
/// `FeignException`.
///
/// Each client has a [name], which keys its configuration under
/// `spring.cloud.openfeign.client.config.<name>.*` (timeouts, logging,
/// default headers; `default` applies to all clients), and a base [url].
///
/// ```dart
/// // The catalog service's API, called by the shop.
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
///   Shop(this.catalog); // the generated client, injected
///   final CatalogClient catalog;
///
///   Future<String> title(String isbn) async =>
///       (await catalog.find(isbn)).title;
/// }
/// ```
///
/// Spring (Java), where methods return their result directly:
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
  /// A client named [name]; the other settings are optional.
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

  /// The name of the remote service, such as `catalog`. It is the
  /// configuration key unless [contextId] is set, and the `clientName`
  /// that request interceptors see.
  final String name;

  /// The base URL of the service, such as `https://api.neon.books`;
  /// `${...}` placeholders are resolved from the configuration
  /// (`r'${catalog.url}'`). When `null` or empty, the `url` property of
  /// the client's configuration is used. A URL without a scheme gets
  /// `http://`.
  final String? url;

  /// A path put before every method's path, such as `/v1`; empty by
  /// default.
  final String path;

  /// A bean class that implements the same interface and answers instead
  /// of the remote service when a call fails, after the retries, for any
  /// failure (a 404 too). It must be a bean, for example with
  /// `@Component()`. `null` (the default): failures throw.
  final Type? fallback;

  /// The configuration key instead of [name]
  /// (`spring.cloud.openfeign.client.config.<contextId>.*`), e.g. for two
  /// clients of one service with different settings.
  final String? contextId;

  /// More names that select the client bean with `@Qualifier(...)`,
  /// besides its bean name (the interface's name in lower camel case,
  /// such as `catalogClient`).
  final List<String> qualifiers;

  /// Whether the client bean is `@Primary`; `true` by default, so that
  /// a [fallback] implementing the same interface does not make injection
  /// ambiguous.
  final bool primary;

  /// Whether a 404 gives an empty result instead of a `FeignNotFound`:
  /// `null` for a nullable result, a `ResponseEntity` with the status for
  /// that result type. `void` methods still throw, as in Feign. `false`
  /// by default; the `dismiss404` property turns it on too.
  final bool dismiss404;

  /// Classes whose beans configure this client only: the `Retryer`,
  /// `ErrorDecoder` and `RequestInterceptor` beans their `@Bean` methods
  /// declare apply to the clients that list the class, and to no other.
  ///
  /// Use it when one service needs other credentials or retries than the
  /// rest. A listed class must be a `@Configuration()` bean as usual
  /// (Dart cannot create a class by reflection). Its `Retryer` and
  /// `ErrorDecoder` win over the application's, and its interceptors run
  /// together with the application's.
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

  /// The key of the client's configuration
  /// (`spring.cloud.openfeign.client.config.<key>.*`): [contextId] when
  /// set and not empty, else [name].
  String get configKey => switch (contextId) {
    final id? when id.isNotEmpty => id,
    _ => name,
  };
}
