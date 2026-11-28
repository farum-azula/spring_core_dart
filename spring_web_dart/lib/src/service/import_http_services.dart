/// Imports HTTP service interfaces (with `@HttpExchange` methods) into a
/// group: each becomes a bean whose calls go through the group's
/// `RestClient`, set by `spring.http.serviceclient.<group>.*` (its base
/// URL, default headers, API version, timeouts) and the
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
/// The interfaces are listed in [types], found by the build in
/// [basePackages] and [basePackageClasses], or both:
///
/// ```dart
/// @SpringBootApplication()
/// @ImportHttpServices(group: 'catalog', types: [BookService, AuthorService])
/// @ImportHttpServices(group: 'payments', basePackageClasses: [PaymentService])
/// void main(List<String> args) => runApplication(args);
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
/// (repeatable; `clientType` has no counterpart, and `value`, an alias of
/// `types`, is not repeated):
/// ```java
/// @ImportHttpServices(group = "catalog",
///     types = {BookService.class, AuthorService.class})
/// @ImportHttpServices(group = "payments",
///     basePackageClasses = PaymentService.class)
/// ```
class ImportHttpServices {
  /// The interfaces [types], and those found in [basePackages] and
  /// [basePackageClasses], in [group] (`default` when not given).
  const ImportHttpServices({
    this.group = defaultGroup,
    this.types = const [],
    this.basePackages = const [],
    this.basePackageClasses = const [],
  });

  /// The name of the group of interfaces imported without one.
  static const String defaultGroup = 'default';

  /// The group: the key of its properties,
  /// `spring.http.serviceclient.<group>.*`.
  final String group;

  /// The HTTP service interfaces of the group.
  final List<Type> types;

  /// Where the build looks for more interfaces of the group: library URI
  /// prefixes of the package being built (`'package:shop/src/catalog/'`;
  /// the directory below it too, as a Java package's subpackages). Every
  /// class there with an exchange annotation (on the class or a method) is
  /// imported. A prefix of another package fails the build: the build
  /// lists only the files of its own package, so list that package's
  /// interfaces in [types]. A prefix that finds no interface fails the
  /// build too.
  ///
  /// Spring (Java): `basePackages`, Java package names
  /// (`"com.shop.catalog"`), scanned on the classpath when the application
  /// starts.
  final List<String> basePackages;

  /// Like [basePackages], with the directory of each type's library: with
  /// `[BookService]` declared in `lib/src/catalog/book_service.dart`, the
  /// interfaces of `lib/src/catalog/` and below. It works for a library
  /// outside `lib/` too (`bin/`, `test/`).
  ///
  /// Spring (Java): `basePackageClasses`, the packages of the classes.
  final List<Type> basePackageClasses;
}
