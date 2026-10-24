import 'package:spring_core_dart/src/beans/jakarta.dart';

/// A factory of one object of [T], like Spring's `ObjectFactory`.
///
/// An `ObjectFactory<T>` injection point receives an [ObjectProvider]: the
/// bean is looked up on every [getObject] call.
///
/// ```dart
/// @Service()
/// class Reports {
///   Reports(this.sessions);
///   final ObjectFactory<Session> sessions;
///
///   void run() => sessions.getObject().print();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Service
/// class Reports {
///   Reports(ObjectFactory<Session> sessions) { ... }
/// }
/// ```
abstract interface class ObjectFactory<T extends Object> {
  /// The object; throws when it cannot be provided.
  T getObject();
}

/// Lazy, optional access to beans of [T], like Spring's `ObjectProvider`.
///
/// Inject `ObjectProvider<T>` instead of `T` to defer creation, to accept a
/// missing bean, or to get every candidate. A provider dependency does not
/// count for cycle detection, so it can break circular references.
/// Iterating the provider creates the matching beans one by one, in
/// registration order (Spring's `stream()`); [orderedList] sorts them.
/// `toString`, `isEmpty` and `length` create no beans.
///
/// An injected provider resolves on behalf of the bean it was injected
/// into, like that bean's other injection points: the bean itself (and the
/// beans of its own `@Bean` methods) are left out, the parameter or field
/// name selects among several candidates, only autowire candidates take
/// part, and the beans it returns are registered as dependencies (so they
/// are destroyed after it). A `@Primary` decorator or composite can thus
/// reach the other beans of its own type through it. The provider of
/// `getBeanProvider` is a plain lookup: [getObject] works like
/// `BeanFactory.getBean`, and iteration includes every bean of the type,
/// also from parent factories.
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
    implements ObjectFactory<T>, Provider<T>, Iterable<T> {
  /// The single matching bean; throws when none or several match.
  ///
  /// ```dart
  /// final clock = provider.getObject();
  /// ```
  @override
  T getObject();

  /// The same as [getObject] (JSR-330's `Provider.get`).
  @override
  T get();

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
