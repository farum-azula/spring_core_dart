import 'dart:async';

/// A bean that wants a call once all its dependencies are injected, to
/// finish its setup.
///
/// A constructor cannot use field-injected or setter-injected dependencies
/// yet; [afterPropertiesSet] can. It runs after the `@PostConstruct`
/// methods and before the custom init method. In application code
/// `@PostConstruct()` on a method does the same without an interface; this
/// one suits framework classes and hand-written definitions, which have no
/// generated callbacks.
///
/// ```dart
/// // The repository is injected into a field, so warm up afterwards.
/// @Service()
/// class Cache implements InitializingBean {
///   @Autowired()
///   late final Repository repository;
///
///   @override
///   void afterPropertiesSet() => repository.warmUp();
/// }
/// ```
///
/// A `Future<void> afterPropertiesSet() async` is awaited by
/// `refreshAsync()` (the synchronous `refresh()` fails for it).
///
/// Spring (Java):
/// ```java
/// @Service
/// class Cache implements InitializingBean {
///   @Autowired Repository repository;
///   @Override public void afterPropertiesSet() { repository.warmUp(); }
/// }
/// ```
abstract interface class InitializingBean {
  /// Finishes the setup; called once, after all dependencies are injected.
  /// Throw to fail the bean's creation (wrapped in a
  /// `BeanCreationException`). A returned `Future` is awaited by
  /// `refreshAsync()`.
  FutureOr<void> afterPropertiesSet();
}

/// A bean that wants a call when the container discards it, to release
/// what it holds: connections, files, timers, subscriptions.
///
/// Singletons are destroyed when the context closes (dependents first);
/// custom-scoped beans when their scope ends. Prototypes are never
/// destroyed by the container. In application code `@PreDestroy()` on a
/// method does the same without an interface; this one suits framework
/// classes and hand-written definitions.
///
/// ```dart
/// // The connection is closed when the application shuts down.
/// @Repository()
/// class Database implements DisposableBean {
///   final _connection = Connection.open();
///
///   @override
///   Future<void> destroy() => _connection.close(); // awaited by closeAsync()
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Repository
/// class Database implements DisposableBean {
///   private final Connection connection = Connection.open();
///   @Override public void destroy() { connection.close(); }
/// }
/// ```
abstract interface class DisposableBean {
  /// Releases what the bean holds; runs after the `@PreDestroy` methods and
  /// before the custom destroy method. What it throws is logged and
  /// collected, not rethrown, so the shutdown goes on. A returned `Future`
  /// is awaited by `closeAsync()` (the synchronous `close()` logs a warning
  /// and goes on).
  FutureOr<void> destroy();
}

/// A singleton that wants a call once every non-lazy singleton has been
/// created, at the end of startup.
///
/// Use it for work that needs the other beans to exist, such as
/// registering every handler bean in a registry: during its own creation
/// a bean cannot be sure the others are ready. It is mostly for framework
/// code; an application can also listen for `ContextRefreshedEvent`.
///
/// ```dart
/// // Register all handler beans once they exist.
/// @Service()
/// class HandlerRegistry implements SmartInitializingSingleton {
///   HandlerRegistry(this.handlers);
///   final ObjectProvider<Handler> handlers;
///
///   @override
///   void afterSingletonsInstantiated() => handlers.forEach(register);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Service
/// class HandlerRegistry implements SmartInitializingSingleton {
///   private final ObjectProvider<Handler> handlers;
///   HandlerRegistry(ObjectProvider<Handler> handlers) {
///     this.handlers = handlers;
///   }
///   @Override public void afterSingletonsInstantiated() {
///     handlers.forEach(this::register);
///   }
/// }
/// ```
abstract interface class SmartInitializingSingleton {
  /// Called once at the end of `preInstantiateSingletons`, in the order
  /// the bean definitions were registered (not the creation order). Not
  /// called for a lazy singleton created later, nor for an object added
  /// with `registerSingleton`.
  void afterSingletonsInstantiated();
}
