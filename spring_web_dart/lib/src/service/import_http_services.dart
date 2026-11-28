/// Imports HTTP service interfaces (with `@HttpExchange` methods) into a
/// group: each becomes a bean whose calls go through the group's
/// `RestClient`, set by `spring.http.serviceclient.<group>.*` (its base
/// URL, default headers, timeouts) and the
/// `RestClientHttpServiceGroupConfigurer` beans.
///
/// Put it on the application's `main` or on a bean class, usually a
/// `@Configuration()` class; several of them, one per group, on the same
/// one. An interface belongs to one group. The generator writes the
/// implementations. As in Spring, a class's interfaces are imported only
/// when the class is registered: its conditions (`@Profile`,
/// `@ConditionalOnProperty`, those of a class importing it with
/// `@Import`) apply to their beans and their group. On a class that is no
/// bean it fails the build.
///
/// ```dart
/// @SpringBootApplication()
/// @ImportHttpServices(group: 'catalog', types: [BookService, AuthorService])
/// @ImportHttpServices(group: 'payments', types: [PaymentService])
/// class ShopApplication {}
/// ```
///
/// ```yaml
/// spring:
///   http:
///     serviceclient:
///       catalog:
///         base-url: https://catalog.neon.books
///       payments:
///         base-url: https://pay.neon.books
///         read-timeout: 5s
/// ```
///
/// Spring (Java):
/// `org.springframework.web.service.registry.ImportHttpServices`
/// (repeatable; `basePackages` and `clientType` have no counterpart):
/// ```java
/// @ImportHttpServices(group = "catalog",
///     types = {BookService.class, AuthorService.class})
/// ```
class ImportHttpServices {
  /// The interfaces [types] in [group] (`default` when not given).
  const ImportHttpServices({this.group = defaultGroup, this.types = const []});

  /// The name of the group of interfaces imported without one.
  static const String defaultGroup = 'default';

  /// The group: the key of its properties,
  /// `spring.http.serviceclient.<group>.*`.
  final String group;

  /// The HTTP service interfaces of the group.
  final List<Type> types;
}
