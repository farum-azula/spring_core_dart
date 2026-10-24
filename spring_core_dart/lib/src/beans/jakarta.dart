/// Jakarta / JSR-330 / JSR-250 names whose Dart counterparts would clash
/// with other libraries (`Provider` with `package:provider`, `Resource`
/// with `spring_core_dart`'s own `Resource`), so they live in
/// `package:spring_core_dart/jakarta.dart`, imported on its own (with a
/// prefix where a name clashes).
library;

/// JSR-330's `Provider<T>` (`jakarta.inject.Provider`): an injection point
/// of this type gets a lazy provider resolving the bean on every [get],
/// on behalf of the injecting bean, like an `ObjectProvider<T>` (which
/// implements it).
///
/// ```dart
/// import 'package:spring_core_dart/jakarta.dart' as jakarta;
///
/// @Named()
/// class Checkout {
///   Checkout(this.clock);
///   final jakarta.Provider<Clock> clock;
///
///   DateTime now() => clock.get().now();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Named
/// class Checkout {
///   @Inject Provider<Clock> clock;
///   Instant now() { return clock.get().instant(); }
/// }
/// ```
abstract interface class Provider<T extends Object> {
  /// The bean; throws when none or several match.
  T get();
}

/// JSR-250's `@Resource` (`jakarta.annotation.Resource`) on a field or
/// setter: injection by bean name.
///
/// Without [name] the field or setter name is the bean name; when no bean
/// has that name the point is injected by type like `@Autowired` (Spring's
/// `fallbackToDefaultTypeMatch`). An explicit [name] must name a bean (an
/// alias or `&factory` works too) of the point's type. A nullable point
/// receives `null` when the bean is missing.
///
/// ```dart
/// import 'package:spring_core_dart/jakarta.dart' as jakarta;
///
/// @Service()
/// class Reports {
///   @jakarta.Resource()
///   late final DataSource dataSource;        // bean 'dataSource', else by type
///
///   @jakarta.Resource(name: 'archiveStore')
///   late final Store store;                  // exactly the bean 'archiveStore'
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Service
/// class Reports {
///   @Resource DataSource dataSource;
///   @Resource(name = "archiveStore") Store store;
/// }
/// ```
///
/// Differences from Spring: fields and setters only (no `@Resource`
/// methods with other names, no `type`, `lookup` or JNDI attributes).
class Resource {
  /// Injects the bean named [name] (default: the field or setter name).
  const Resource({this.name});

  /// The bean name; `null` uses the field or setter name.
  final String? name;
}

/// JSR-250's `@Priority` (`jakarta.annotation.Priority`) on a bean class
/// (or `@Bean` method): among several candidates for an injection point or
/// a `getBean<T>()` without a primary or name match, the one with the
/// lowest [value] wins (two with that value are ambiguous); and it orders
/// beans in collections and listeners after `Ordered` and `@Order`, like
/// Spring's `AnnotationAwareOrderComparator`.
///
/// ```dart
/// import 'package:spring_core_dart/jakarta.dart' as jakarta;
///
/// @Component()
/// @jakarta.Priority(1)
/// class FastStore implements Store { ... }
///
/// @Component()
/// @jakarta.Priority(5)
/// class SlowStore implements Store { ... }
/// // Store is FastStore; List<Store> is [FastStore, SlowStore].
/// ```
///
/// Spring (Java):
/// ```java
/// @Component @Priority(1) class FastStore implements Store { ... }
/// ```
class Priority {
  /// A bean with priority [value] (lower is higher priority).
  const Priority(this.value);

  /// The priority; lower values win.
  final int value;
}
