import 'package:spring_core_dart/src/beans/jakarta.dart';

/// Something that returns an object of [T] when asked: the smallest form
/// of a lazy dependency.
///
/// Inject an `ObjectFactory<T>` instead of a `T` when the bean must be
/// looked up at the moment of use rather than when your bean is created:
/// a prototype you want new each time, a scoped bean whose current
/// instance changes. The injection point receives an [ObjectProvider],
/// which looks the bean up on every [getObject] call. [ObjectProvider]
/// offers more (optional and multiple beans); prefer it in new code.
///
/// ```dart
/// // Each report run gets the current session.
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
  /// The object, looked up now; throws when it cannot be provided (for a
  /// bean: none or several match).
  T getObject();
}

/// A handle on the beans of [T] that looks them up only when asked: one
/// bean, the bean if there is one, or all of them.
///
/// Inject `ObjectProvider<T>` instead of `T` to create the bean later (or
/// never), to accept that it is missing, or to go through every
/// candidate. A provider does not count as a dependency for cycle
/// detection, so it also breaks circular references. Iterating the
/// provider creates the matching beans one by one, in registration order
/// (Spring's `stream()`); [orderedList] sorts them. `toString`, `isEmpty`
/// and `length` create no beans.
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
/// // Exporters are optional plug-ins: there may be none, one or several.
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
  /// The matching bean, created if needed. Throws
  /// `NoSuchBeanDefinitionException` when none matches and
  /// `NoUniqueBeanDefinitionException` when several match and none wins
  /// (`@Primary`, ...).
  ///
  /// ```dart
  /// final clock = provider.getObject();
  /// ```
  @override
  T getObject();

  /// The same as [getObject], under the name of JSR-330's `Provider.get`.
  @override
  T get();

  /// The matching bean; when none matches, [defaultSupplier]'s result, or
  /// `null` without one. A bean whose scope is not active right now counts
  /// as missing. Still throws when several match and none wins.
  ///
  /// ```dart
  /// // Use the configured clock, or the system clock when there is none.
  /// final clock = clocks.getIfAvailable(SystemClock.new)!;
  /// ```
  T? getIfAvailable([T Function()? defaultSupplier]);

  /// The matching bean; [defaultSupplier]'s result (or `null`) when none
  /// matches, or several match and none wins. Never throws for those.
  T? getIfUnique([T Function()? defaultSupplier]);

  /// Calls [consumer] with the bean when [getIfAvailable] finds one; does
  /// nothing otherwise.
  void ifAvailable(void Function(T bean) consumer);

  /// Calls [consumer] with the bean when [getIfUnique] finds one; does
  /// nothing when none or several match.
  void ifUnique(void Function(T bean) consumer);

  /// Every matching bean, created if needed and sorted: `PriorityOrdered`
  /// first, then by `Ordered.order`, `@Order` or `@Priority`, then by
  /// registration. Empty when none match. Spring: `orderedStream()`.
  List<T> orderedList();
}
