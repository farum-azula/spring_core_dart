import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Collects test properties whose values are known only when the tests
/// run, such as the port of a server or a temporary directory.
///
/// A test cannot write such values into `properties:`, which is fixed when
/// `springBootTest` is called. Instead it registers a function per
/// property; the application calls it whenever it reads the property, so
/// it sees the value of the moment. The registry is handed to the
/// `dynamicProperties:` callback of `springBootTest`, or to a
/// `@DynamicPropertySource()` method of a test class. The values win over
/// every other property source.
///
/// ```dart
/// late HttpServer server;
/// // Declared before springBootTest, so the server is up when it starts.
/// setUpAll(() async => server = await HttpServer.bind('localhost', 0));
///
/// final app = springBootTest(
///   springApplication,
///   dynamicProperties: (registry) => registry
///     ..add('catalog.url', () => 'http://localhost:${server.port}'),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// @DynamicPropertySource
/// static void properties(DynamicPropertyRegistry registry) {
///   registry.add("catalog.url", server::baseUrl);
/// }
/// ```
abstract interface class DynamicPropertyRegistry {
  /// Adds the property [name]. [valueSupplier] is called each time the
  /// property is read, so it returns the current value; adding the same
  /// name again replaces the supplier.
  void add(String name, Object? Function() valueSupplier);
}

/// The property source behind a [DynamicPropertyRegistry]: it keeps the
/// registered suppliers and calls one on every lookup of its property.
///
/// `springBootTest` creates it, lets `dynamicProperties:` fill it, and puts
/// it first in the environment, so its values win over every other source,
/// `springBootTest(properties:)` included. Tests use it through the
/// registry and rarely name this class. Spring's
/// `DynamicValuesPropertySource`.
final class DynamicValuesPropertySource
    extends EnumerablePropertySource<Map<String, Object? Function()>>
    implements DynamicPropertyRegistry {
  /// An empty source called [name] (by default [sourceName]); fill it with
  /// [add].
  DynamicValuesPropertySource([String name = sourceName])
    : super(name, <String, Object? Function()>{});

  /// The source's default name, under which it shows in the environment's
  /// list of property sources.
  static const sourceName = 'Dynamic Test Properties';

  @override
  void add(String name, Object? Function() valueSupplier) =>
      source[name] = valueSupplier;

  @override
  Object? getProperty(String name) => source[name]?.call();

  @override
  bool containsProperty(String name) => source.containsKey(name);

  @override
  List<String> get propertyNames => List.unmodifiable(source.keys);
}
