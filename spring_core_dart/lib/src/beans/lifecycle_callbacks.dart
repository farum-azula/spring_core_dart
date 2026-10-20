/// Called after injection, like Spring's `InitializingBean`.
///
/// Runs after `@PostConstruct` methods and before the custom init method.
/// Prefer `@PostConstruct()` in application code; this interface is handy
/// for framework classes and hand-written definitions.
///
/// ```dart
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
/// Spring (Java):
/// ```java
/// @Service
/// class Cache implements InitializingBean {
///   @Autowired Repository repository;
///   @Override public void afterPropertiesSet() { repository.warmUp(); }
/// }
/// ```
abstract interface class InitializingBean {
  /// Called once all dependencies are injected; throw to fail creation
  /// (wrapped in a `BeanCreationException`).
  void afterPropertiesSet();
}

/// Called when the bean is destroyed, like Spring's `DisposableBean`.
///
/// Singletons are destroyed when the context closes (dependents first);
/// custom-scoped beans when their scope ends. Prototypes are never
/// destroyed by the container.
///
/// ```dart
/// @Repository()
/// class Database implements DisposableBean {
///   final _connection = Connection.open();
///
///   @override
///   void destroy() => _connection.close();
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
  /// Releases resources; runs after `@PreDestroy` methods and before the
  /// custom destroy method. Errors are collected, not rethrown.
  void destroy();
}

/// Called once all eager singletons exist, like Spring's
/// `SmartInitializingSingleton`.
///
/// ```dart
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
  /// Called at the end of `preInstantiateSingletons`, in singleton creation
  /// order. Not called for lazy singletons created later.
  void afterSingletonsInstantiated();
}
