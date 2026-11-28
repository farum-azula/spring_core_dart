/// Calls HTTP APIs from a Spring Boot application with `RestClient`: a
/// `RestClientBuilder` bean set up from `spring.http.clients.*`, HTTP
/// service groups from `spring.http.serviceclient.<group>.*`, and an
/// HTTP transport that calls only the addresses allowed by hand.
///
/// Add the starter to an application that calls other services, from a
/// server or a Flutter app. Inject the `RestClientBuilder` (a new one each
/// time), set a base URL and build a client; or name a group and inject
/// `HttpServiceGroups`. Every outgoing address is denied until it is on
/// `spring.http.clients.allowed-addresses` or is the host of a group's
/// base URL, private networks and loopback included.
///
/// This one import is enough: it re-exports `spring_web_dart` (the
/// `RestClient`, and the `@HttpExchange` and `@ImportHttpServices`
/// annotations) and
/// `spring_boot_starter_logging` (and through it `spring_boot_dart` and
/// `spring_core_dart`).
///
/// ```dart
/// @Service()
/// class Catalog {
///   Catalog(RestClientBuilder builder)
///     : _rest = builder.baseUrl('https://catalog.neon.books').build();
///   final RestClient _rest;
///
///   Future<Book> find(String isbn) =>
///       _rest.get().uri('/books/{isbn}', isbn).retrieve().body<Book>();
/// }
/// ```
///
/// Spring (Java), with `spring-boot-starter-restclient`:
/// ```java
/// @Service
/// class Catalog {
///   private final RestClient rest;
///   Catalog(RestClient.Builder builder) {
///     this.rest = builder.baseUrl("https://catalog.neon.books").build();
///   }
///   Book find(String isbn) {
///     return rest.get().uri("/books/{isbn}", isbn).retrieve().body(Book.class);
///   }
/// }
/// ```
library;

// Logging and spring_boot_dart (re-exported by the logging starter), so
// this starter is the only dependency an application needs.
export 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
export 'package:spring_web_dart/spring_web_dart.dart';

export 'src/allowed_addresses_contributor.dart';
export 'src/config/http_client_properties.dart';
export 'src/http_service_groups.dart';
export 'src/rest_client_auto_configuration.dart'
    show allowedAddressesOf, allowedAddressesRemedy, transportConnectTimeout;
export 'src/rest_client_customizer.dart';
