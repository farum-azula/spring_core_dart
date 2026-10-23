import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Adds properties whose values are known only when the test runs (a
/// server's port, a temporary directory), like Spring's
/// `DynamicPropertyRegistry`; see `springBootTest(dynamicProperties:)`.
///
/// ```dart
/// late HttpServer server;
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
  /// Adds the property [name]; [valueSupplier] is called each time the
  /// property is read, so it sees the current value.
  void add(String name, Object? Function() valueSupplier);
}

/// The property source of a [DynamicPropertyRegistry]: every lookup calls
/// the supplier, like Spring's `DynamicValuesPropertySource`. It has the
/// highest precedence (above `springBootTest(properties:)`).
final class DynamicValuesPropertySource
    extends EnumerablePropertySource<Map<String, Object? Function()>>
    implements DynamicPropertyRegistry {
  /// An empty source; fill it with [add].
  DynamicValuesPropertySource([String name = sourceName])
    : super(name, <String, Object? Function()>{});

  /// The name of the source in the environment.
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
