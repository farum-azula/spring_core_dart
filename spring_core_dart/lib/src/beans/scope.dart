/// Built-in scope names, like Spring's `ConfigurableBeanFactory.SCOPE_*`.
///
/// ```dart
/// @Service()
/// @Scope(ScopeType.prototype)
/// class ReportBuilder {}
///
/// // or by hand:
/// BeanDefinition<ReportBuilder>(
///   name: 'reportBuilder',
///   scope: ScopeType.prototype,
///   create: (_) => ReportBuilder(),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// @Service
/// @Scope(ConfigurableBeanFactory.SCOPE_PROTOTYPE)
/// class ReportBuilder {}
/// ```
abstract final class ScopeType {
  /// One shared instance per container. The default.
  static const singleton = 'singleton';

  /// A new instance for every injection and every lookup. The container
  /// does not track prototypes, so their destroy callbacks never run (like
  /// Spring).
  static const prototype = 'prototype';
}

/// Whether a bean of a custom (or prototype) scope is injected through a
/// scoped proxy, like Spring's `ScopedProxyMode` (`@Scope(proxyMode:)`).
///
/// With a proxy, every injection point and lookup gets one shared object
/// implementing the bean's class; each call on it asks the scope for the
/// current instance, so a singleton can hold a request- or screen-scoped
/// bean. The generator writes the proxy class (the type must be
/// implementable from generated code, like for `@Lazy` injection points);
/// by hand it is `BeanDefinition.scopedProxy`.
///
/// ```dart
/// @Component()
/// @Scope('screen', proxyMode: ScopedProxyMode.targetClass)
/// class ScreenState { ... }
///
/// @Service()
/// class Analytics {
///   Analytics(this.state); // the proxy: the current screen's state
///   final ScreenState state;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// @Scope(value = "screen", proxyMode = ScopedProxyMode.TARGET_CLASS)
/// class ScreenState { ... }
/// ```
///
/// Differences from Spring: there is no `DEFAULT` (a Dart keyword; [no] is
/// the default); [interfaces] and [targetClass] both generate a class
/// implementing the bean's type (Dart classes are interfaces too); the
/// target is not registered as a separate `scopedTarget.` bean.
enum ScopedProxyMode {
  /// No proxy: the instance is injected directly.
  no,

  /// A proxy implementing the bean's type (Spring's JDK interface proxy).
  interfaces,

  /// A proxy implementing the bean's class (Spring's CGLIB proxy).
  targetClass,
}

/// A custom bean scope, like Spring's `Scope` SPI (renamed because `@Scope`
/// is the annotation).
///
/// Register it with `ConfigurableBeanFactory.registerScope` and use it with
/// `@Scope('name')`. The container calls [get] on every lookup of a bean in
/// this scope and registers destroy callbacks through
/// [registerDestructionCallback].
///
/// ```dart
/// class ZoneScope implements CustomScope {
///   final _objects = <String, Object>{};
///
///   @override
///   Object get(String name, Object Function() objectFactory) =>
///       _objects[name] ??= objectFactory();
///
///   @override
///   Object? remove(String name) => _objects.remove(name);
///
///   @override
///   void registerDestructionCallback(String name, void Function() cb) {}
///
///   @override
///   String? get conversationId => null;
/// }
///
/// factory.registerScope('zone', ZoneScope());
///
/// @Service()
/// @Scope('zone')
/// class RequestState {}
/// ```
///
/// Spring (Java):
/// ```java
/// class ZoneScope implements Scope {
///   private final Map<String, Object> objects = new HashMap<>();
///   public Object get(String name, ObjectFactory<?> factory) {
///     return objects.computeIfAbsent(name, n -> factory.getObject());
///   }
///   public Object remove(String name) { return objects.remove(name); }
///   public void registerDestructionCallback(String name, Runnable cb) {}
///   public Object resolveContextualObject(String key) { return null; }
///   public String getConversationId() { return null; }
/// }
///
/// beanFactory.registerScope("zone", new ZoneScope());
/// ```
abstract interface class CustomScope {
  /// The scoped instance named [name], created with [objectFactory] when
  /// the scope does not hold one yet.
  Object get(String name, Object Function() objectFactory);

  /// Removes and returns the instance named [name], if any. Its destruction
  /// callback is not run (the caller owns the object now).
  Object? remove(String name);

  /// Runs [callback] when the instance named [name] is destroyed with the
  /// scope.
  void registerDestructionCallback(String name, void Function() callback);

  /// Identifier of the current scope instance (e.g. a session id), if any.
  String? get conversationId;
}

/// A [CustomScope] backed by a map, ended explicitly with [destroy] (for
/// example a screen, a session or a test).
///
/// ```dart
/// final screen = SimpleMapScope(conversationId: 'checkout');
/// context.beanFactory.registerScope('screen', screen);
///
/// final cart = context.getBean<CartState>(); // @Scope('screen')
/// // ... when the screen closes:
/// screen.destroy(); // runs @PreDestroy of CartState
/// ```
///
/// Spring (Java): closest is `SimpleThreadScope` (or a hand-written
/// `Scope` backed by a map):
/// ```java
/// beanFactory.registerScope("thread", new SimpleThreadScope());
/// ```
class SimpleMapScope implements CustomScope {
  /// Creates an empty scope; [conversationId] identifies it (optional).
  SimpleMapScope({this.conversationId});

  @override
  final String? conversationId;

  final _objects = <String, Object>{};
  final _callbacks = <String, void Function()>{};

  /// Names of the instances currently held.
  Iterable<String> get names => _objects.keys;

  @override
  Object get(String name, Object Function() objectFactory) =>
      _objects[name] ??= objectFactory();

  @override
  Object? remove(String name) {
    _callbacks.remove(name);
    return _objects.remove(name);
  }

  @override
  void registerDestructionCallback(String name, void Function() callback) =>
      _callbacks[name] = callback;

  /// Destroys every instance (newest first) and empties the scope.
  ///
  /// The scope stays usable: the next lookup creates fresh instances.
  void destroy() {
    // Reverse insertion order: beans created later may depend on earlier
    // ones, so they go first.
    final names = _objects.keys.toList().reversed;
    for (final name in names) {
      _callbacks.remove(name)?.call();
      _objects.remove(name);
    }
  }
}
