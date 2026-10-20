/// Lazy, optional access to beans of [T], like Spring's `ObjectProvider`.
///
/// Inject `ObjectProvider<T>` instead of `T` to defer creation, to accept a
/// missing bean, or to get every candidate. A provider dependency does not
/// count for cycle detection, so it can break circular references.
/// Iterating the provider yields all matching beans in order.
///
/// ```dart
/// @Service()
/// class Reports {
///   Reports(this.exporters);
///   final ObjectProvider<Exporter> exporters;
///
///   void export() => exporters.ifAvailable((e) => e.run());
///   void exportAll() => exporters.forEach((e) => e.run());
/// }
///
/// // Programmatic:
/// final greeter = factory.getBeanProvider<Greeter>().getIfUnique();
/// ```
///
/// Spring (Java):
/// ```java
/// @Service
/// class Reports {
///   private final ObjectProvider<Exporter> exporters;
///   Reports(ObjectProvider<Exporter> exporters) {
///     this.exporters = exporters;
///   }
///   void export() { exporters.ifAvailable(Exporter::run); }
///   void exportAll() { exporters.orderedStream().forEach(Exporter::run); }
/// }
/// ```
abstract interface class ObjectProvider<T extends Object>
    implements Iterable<T> {
  /// The single matching bean; throws when none or several match.
  ///
  /// ```dart
  /// final clock = provider.getObject();
  /// ```
  T getObject();

  /// The matching bean, [defaultSupplier]'s result, or `null` when none
  /// matches. Throws when several match without a primary.
  ///
  /// ```dart
  /// final clock = clocks.getIfAvailable(SystemClock.new)!;
  /// ```
  T? getIfAvailable([T Function()? defaultSupplier]);

  /// The matching bean, or [defaultSupplier]'s result (or `null`) when none
  /// or several match.
  T? getIfUnique([T Function()? defaultSupplier]);

  /// Calls [consumer] with the bean if one is available.
  void ifAvailable(void Function(T bean) consumer);

  /// Calls [consumer] with the bean if exactly one matches.
  void ifUnique(void Function(T bean) consumer);

  /// All matching beans in `@Order` order (Spring's `orderedStream()`);
  /// empty when none match.
  List<T> orderedList();
}
