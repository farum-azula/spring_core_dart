/// The names of the two built-in scopes, for `@Scope(...)` and
/// `BeanDefinition.scope`.
///
/// A scope decides how many instances of a bean exist. By default a bean is
/// a [singleton]: one shared instance. Choose [prototype] for a bean that
/// holds state for a single use, such as a builder; anything else is the
/// name of a custom scope registered with `registerScope`.
///
/// ```dart
/// // Every lookup gets a fresh builder.
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
  /// One shared instance per container, created at startup unless lazy.
  /// The default.
  static const singleton = 'singleton';

  /// A new instance for every injection and every lookup. The container
  /// does not track prototypes, so their destroy callbacks never run (like
  /// Spring).
  static const prototype = 'prototype';
}

/// Whether a bean of a custom (or prototype) scope is injected directly or
/// through a scoped proxy (`@Scope(proxyMode:)`).
///
/// A singleton keeps what it was injected with, so a screen-scoped bean
/// injected directly stays the first screen's instance forever (the
/// container logs a warning). With a proxy, every injection point and
/// lookup gets one shared object implementing the bean's class; each call
/// on it asks the scope for the current instance. The generator writes
/// the proxy class (the type must be implementable from generated code,
/// like for `@Lazy` injection points); by hand it is
/// `BeanDefinition.scopedProxy`. An `ObjectProvider<T>` is the other way
/// to reach the current instance.
///
/// ```dart
/// // A singleton that always talks to the state of the current screen.
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
  /// No proxy: the instance is injected directly. The default.
  no,

  /// A proxy implementing the bean's type (Spring's JDK interface proxy).
  interfaces,

  /// A proxy implementing the bean's class (Spring's CGLIB proxy).
  targetClass,
}

/// A place that keeps bean instances for a span of your choosing, such as
/// a screen, a session or a job, and so defines a custom bean scope.
///
/// Singletons live as long as the container and prototypes not at all.
/// When beans should live exactly as long as something else, implement a
/// scope, register it with `ConfigurableBeanFactory.registerScope` and
/// declare the beans with `@Scope('name')`. The container calls [get] on
/// every lookup of such a bean and hands over its destroy callbacks through
/// [registerDestructionCallback]; the scope runs them when it ends.
/// [SimpleMapScope] is a ready-made one. Spring calls this interface
/// `Scope`; here that name is the annotation.
///
/// ```dart
/// // A scope that keeps one instance per name until removed.
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
  /// The instance of the bean [name] in the current span, created with
  /// [objectFactory] when the scope does not hold one yet. Throw a
  /// `StateError` when the scope is not active right now (no screen open):
  /// the container reports it as a `ScopeNotActiveException`.
  Object get(String name, Object Function() objectFactory);

  /// Removes and returns the instance of the bean [name], or `null`. Its
  /// destruction callback must not run: the caller owns the object now
  /// (`destroyScopedBean` removes it and then destroys it).
  Object? remove(String name);

  /// Keeps [callback], which runs the destroy callbacks of the instance of
  /// the bean [name]; the scope calls it when it destroys that instance.
  void registerDestructionCallback(String name, void Function() callback);

  /// An id of the current span (a session id, say), or `null`.
  String? get conversationId;
}

/// A ready-made [CustomScope] that keeps its instances in a map until you
/// call [destroy].
///
/// Use it when you control the start and end of the span yourself: a
/// screen, a wizard, a test. Register one instance per scope name; after
/// [destroy] it starts again empty.
///
/// ```dart
/// // Beans in the 'screen' scope live until the checkout screen closes.
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
  /// Creates an empty scope; [conversationId] is an optional id for it.
  SimpleMapScope({this.conversationId});

  @override
  final String? conversationId;

  final _objects = <String, Object>{};
  final _callbacks = <String, void Function()>{};

  /// The bean names whose instances the scope holds now.
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

  /// Runs the destroy callbacks of every instance, newest first (later
  /// beans may use earlier ones), and empties the scope. The scope stays
  /// usable: the next lookup creates fresh instances.
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
