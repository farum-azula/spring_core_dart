/// A bean that creates another object, like Spring's `FactoryBean`.
///
/// Looking up the bean by name or by the product type returns
/// [getObject]'s result; the factory itself is available under
/// `&beanName` or by its own type. Products of singleton factories are
/// cached. Products get `postProcessAfterInitialization` applied, but no
/// injection or init callbacks (like Spring).
///
/// The generator recognizes `FactoryBean` subclasses and fills in
/// `BeanDefinition.factoryObjectTypes`; by hand it looks like this:
///
/// ```dart
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
/// Unlike Spring there is no `getObjectType()`: the product types are known
/// at build time from the type argument.
abstract class FactoryBean<T extends Object> {
  /// Creates (or returns) the product.
  ///
  /// Called once for singleton factories (the result is cached by the
  /// container) and on every lookup when [isSingleton] is `false`.
  T getObject();

  /// Whether [getObject] returns the same instance every time; the
  /// container then caches it. Override with `false` for a new product on
  /// every lookup (Spring's `isSingleton()`).
  bool get isSingleton => true;
}

/// A [FactoryBean] that tells more about its product, like Spring's
/// `SmartFactoryBean`.
///
/// ```dart
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
/// Spring 7's `getObject(Class)` / `supportsType(Class)` have no
/// counterpart: product types are known at build time.
abstract class SmartFactoryBean<T extends Object> extends FactoryBean<T> {
  /// Whether every [getObject] call returns an independent instance, so
  /// `BeanFactory.isPrototype` is `true` for the product. A plain
  /// [FactoryBean] is a prototype exactly when it is not a singleton; with
  /// this getter a non-singleton product may be neither (e.g. scoped).
  bool get isPrototype => false;

  /// Whether the product of a non-lazy singleton factory is created at
  /// refresh (`preInstantiateSingletons`) instead of on first use.
  bool get isEagerInit => false;
}
