/// A bean whose job is to make another object: the container hands out
/// what [getObject] returns, not the factory itself.
///
/// Use it when building the object takes logic that a library wants to
/// keep behind one bean: a client set up from many settings, a proxy, an
/// object from a builder API. In application code a `@Bean` method is
/// usually simpler.
///
/// Looking the bean up by name or by the product type returns the product;
/// the factory itself is available under `&beanName` or by its own type.
/// The product of a singleton factory is created once and cached. Products
/// get `postProcessAfterInitialization` applied, but no injection or init
/// callbacks (like in Spring).
///
/// The generator recognizes `FactoryBean` subclasses and fills in
/// `BeanDefinition.factoryObjectTypes`; by hand it looks like this:
///
/// ```dart
/// // An HttpClient that every bean gets already configured.
/// class ClientFactory extends FactoryBean<HttpClient> {
///   @override
///   HttpClient getObject() => HttpClient()..idleTimeout = Duration.zero;
/// }
///
/// final definition = BeanDefinition<ClientFactory>(
///   name: 'client',
///   types: const [ClientFactory, FactoryBean<HttpClient>],
///   factoryObjectTypes: const [HttpClient],
///   create: (_) => ClientFactory(),
/// );
///
/// factory.registerBeanDefinition(definition);
/// factory.getBean<HttpClient>();        // the product
/// factory.getBeanByName('client');      // the product
/// factory.getBeanByName('&client');     // the ClientFactory itself
/// ```
///
/// Spring (Java):
/// ```java
/// @Component("client")
/// class ClientFactory implements FactoryBean<HttpClient> {
///   @Override
///   public HttpClient getObject() { return HttpClient.newHttpClient(); }
///   @Override
///   public Class<?> getObjectType() { return HttpClient.class; }
/// }
///
/// HttpClient client = context.getBean(HttpClient.class);
/// ClientFactory factory = (ClientFactory) context.getBean("&client");
/// ```
///
/// The product types of a definition are known at build time from the
/// type argument; [objectType] (Spring's `getObjectType()`) is used for a
/// factory given to `registerSingleton`.
abstract class FactoryBean<T extends Object> {
  /// Creates (or returns) the product.
  ///
  /// Called once for a singleton factory (the container caches the result)
  /// and on every lookup when [isSingleton] is `false`. What it throws
  /// becomes a `BeanCreationException` of this bean.
  T getObject();

  /// Whether [getObject] returns the same instance every time; the
  /// container then caches it. Override with `false` for a new product on
  /// every lookup (Spring's `isSingleton()`).
  bool get isSingleton => true;

  /// The product type, [T] by default (Spring's `getObjectType()`): a
  /// factory registered with `registerSingleton` is found by it.
  Type get objectType => T;
}

/// A [FactoryBean] that tells the container more about its product:
/// whether it is a prototype, whether to create it at startup, and which
/// other types it can serve.
///
/// Extend it instead of [FactoryBean] when the product must exist as soon
/// as the application has started ([isEagerInit]), or when one factory
/// serves products of several types. Most factories do not need it.
///
/// ```dart
/// // The connection is opened at startup, not on first use.
/// class ConnectionFactory extends SmartFactoryBean<Connection> {
///   @override
///   Connection getObject() => Connection.open();
///
///   @override
///   bool get isEagerInit => true; // create the product at refresh
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class ConnectionFactory implements SmartFactoryBean<Connection> {
///   public Connection getObject() { return Connection.open(); }
///   public Class<?> getObjectType() { return Connection.class; }
///   public boolean isEagerInit() { return true; }
/// }
/// ```
///
/// Like in Spring 7, a smart factory may serve more product types than its
/// declared ones: once the factory exists, a lookup by a type it
/// [supportsType] gets [getObjectForType] (Spring's `getObject(Class)`).
///
/// ```dart
/// // One factory serves a plain and a retrying client.
/// class ClientFactory extends SmartFactoryBean<HttpClient> {
///   @override
///   HttpClient getObject() => HttpClient();
///
///   @override
///   bool supportsType(Type type) =>
///       type == HttpClient || type == RetryingClient;
///
///   @override
///   Object? getObjectForType(Type type) =>
///       type == RetryingClient ? RetryingClient(getObject()) : getObject();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// public boolean supportsType(Class<?> type) { ... }
/// public <S> S getObject(Class<S> type) throws Exception { ... }
/// ```
abstract class SmartFactoryBean<T extends Object> extends FactoryBean<T> {
  /// Whether every [getObject] call returns an independent instance, so
  /// `BeanFactory.isPrototype` is `true` for the product. A plain
  /// [FactoryBean] is a prototype exactly when it is not a singleton; with
  /// this getter a non-singleton product may be neither (e.g. scoped).
  bool get isPrototype => false;

  /// Whether the product of a non-lazy singleton factory is created at
  /// refresh (`preInstantiateSingletons`) instead of on first use.
  bool get isEagerInit => false;

  /// Whether this factory serves a product for lookups by [type]; by
  /// default its [objectType] (and `Object`), like Spring 7's
  /// `supportsType(Class)`. Consulted once the factory is created.
  bool supportsType(Type type) => type == objectType || type == Object;

  /// The product for a lookup by [type] (Spring 7's `getObject(Class)`):
  /// [getObject] when [supportsType], else `null`, which fails the lookup
  /// with a `BeanNotOfRequiredTypeException`. The products of a singleton
  /// factory are cached per type.
  Object? getObjectForType(Type type) =>
      supportsType(type) ? getObject() : null;
}
