/// The standard Java injection names (JSR-330 `Provider`, JSR-250
/// `@Resource` and `@Priority`) for code that prefers them to the Spring
/// ones.
///
/// They live in `package:spring_core_dart/jakarta.dart`, imported on its
/// own, because their names clash with other libraries: `Provider` with
/// `package:provider`, `Resource` with this package's own `Resource`.
/// Import it with a prefix where a name clashes. Applications that use
/// `ObjectProvider`, `@Autowired` and `@Order` do not need it.
library;

/// A handle that looks up a bean of [T] each time [get] is called: the
/// JSR-330 form of a lazy dependency (`jakarta.inject.Provider`).
///
/// An injection point of this type gets the same provider as an
/// `ObjectProvider<T>` (which implements it): each [get] resolves the bean
/// as if it were injected into the bean that holds the provider. Use it
/// for a bean needed fresh on every use, or to break a cycle;
/// `ObjectProvider<T>` offers more methods.
///
/// ```dart
/// // The clock is looked up on every call.
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
  /// The bean, looked up now. Throws `NoSuchBeanDefinitionException` when
  /// none matches and `NoUniqueBeanDefinitionException` when several match
  /// and none wins.
  T get();
}

/// Injects a field or setter with the bean of a given name: the JSR-250
/// annotation `jakarta.annotation.Resource`.
///
/// Where `@Autowired()` chooses by type, `@Resource` chooses by name, which
/// helps when many beans share a type (several `DataSource`s, say).
/// Without [name] the field or setter name is the bean name; when no bean
/// has that name the point is injected by type like `@Autowired` (Spring's
/// `fallbackToDefaultTypeMatch`). An explicit [name] must name a bean (an
/// alias or `&factory` works too) of the point's type. A nullable point
/// receives `null` when the bean is missing.
///
/// ```dart
/// import 'package:spring_core_dart/jakarta.dart' as jakarta;
///
/// // Two stores exist; the archive one is wanted here.
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
  /// Injects the bean named [name]; without it, the bean named like the
  /// field or setter, else a bean of its type.
  const Resource({this.name});

  /// The bean name; `null` uses the field or setter name, with a fallback
  /// to injection by type.
  final String? name;
}

/// Ranks a bean among others of the same type: the JSR-250 annotation
/// `jakarta.annotation.Priority`, on a bean class (or `@Bean` method).
///
/// It does two jobs. Among several candidates for an injection point or a
/// `getBean<T>()` without a primary or name match, the one with the lowest
/// [value] wins (two with that value are ambiguous). And it orders beans in
/// collections and listeners when they have neither `Ordered` nor
/// `@Order`, like Spring's `AnnotationAwareOrderComparator`. `@Primary()`
/// and `@Order` cover the same needs in Spring style.
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
  /// Gives the bean the priority [value]; lower values come first.
  const Priority(this.value);

  /// The priority; lower values win and sort first.
  final int value;
}
