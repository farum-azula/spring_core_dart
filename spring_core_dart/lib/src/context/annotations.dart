import 'package:spring_core_dart/src/beans/scope.dart';

// Annotations are plain const classes; `spring_core_dart_generator` reads
// them at build time (Dart has no runtime reflection in Flutter/AOT).

// ---------------------------------------------------------------------------
// Stereotypes
// ---------------------------------------------------------------------------

/// Marks a class as a bean: an object the container creates once, injects
/// into others and closes at shutdown.
///
/// This is how most of an application's objects are declared. The
/// generator finds the annotated classes under a directory scanned by a
/// [ComponentScan] (or `@SpringBootApplication`), and the container calls
/// the constructor with the other beans it asks for. You never write
/// `new` for such a class or pass its dependencies by hand.
///
/// The bean name defaults to the class name in lowerCamelCase
/// (`AuthService` becomes `authService`; `URLService` stays as it is). An
/// explicit name must not be empty, blank or padded with spaces. Only
/// classes can be beans: on a mixin, enum, extension or extension type the
/// build fails. The scan skips abstract classes. [Service], [Repository]
/// and [Controller] work the same way and only say what the class is for;
/// subclass [Component] to make your own such annotation.
///
/// ```dart
/// @Component()
/// class Clock {
///   DateTime now() => DateTime.now();
/// }
///
/// // Named explicitly because another library looks it up by name; the
/// // container passes the Clock bean to the constructor.
/// @Component('auditLog')
/// class AuditLog {
///   AuditLog(this.clock);
///   final Clock clock;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class Clock { ... }
///
/// @Component("auditLog")
/// class AuditLog {
///   AuditLog(Clock clock) { ... }
/// }
/// ```
class Component {
  /// Declares the bean; [name] replaces the default bean name.
  const Component([this.name]);

  /// The bean name; `null` gives the class name in lowerCamelCase.
  final String? name;
}

/// Marks a class as a bean that holds business logic.
///
/// It does exactly what [Component] does. The different name tells the
/// reader which layer the class belongs to, and it can be used in scan
/// filters and pointcuts.
///
/// ```dart
/// // The repository bean is injected through the constructor.
/// @Service()
/// class OrderService {
///   OrderService(this.repository);
///   final OrderRepository repository;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Service
/// class OrderService {
///   OrderService(OrderRepository repository) { ... }
/// }
/// ```
class Service extends Component {
  /// Declares the bean; [name] replaces the default bean name.
  const Service([super.name]);
}

/// Marks a class as a bean that stores and loads data.
///
/// It does exactly what [Component] does; the name tells the reader that
/// the class is the data-access layer. Spring also translates database
/// exceptions for such beans; this package does not.
///
/// ```dart
/// @Repository()
/// class OrderRepository {
///   final _orders = <int, Order>{};
///   Order? findById(int id) => _orders[id];
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Repository
/// class OrderRepository {
///   Order findById(int id) { ... }
/// }
/// ```
class Repository extends Component {
  /// Declares the bean; [name] replaces the default bean name.
  const Repository([super.name]);
}

/// Marks a class as a bean of the presentation layer.
///
/// It does exactly what [Component] does. In this package it suits
/// objects that drive a user interface, such as Flutter view models; the
/// web starter gives it its request-handling meaning.
///
/// ```dart
/// // The login screen's logic, with the auth service injected.
/// @Controller()
/// class LoginController {
///   LoginController(this.auth);
///   final AuthService auth;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Controller
/// class LoginController {
///   LoginController(AuthService auth) { ... }
/// }
/// ```
class Controller extends Component {
  /// Declares the bean; [name] replaces the default bean name.
  const Controller([super.name]);
}

/// Marks a class whose [Bean] methods create beans.
///
/// Use it for objects you cannot annotate yourself (a class from another
/// package, a connection built from properties) or that need setup code:
/// each `@Bean` method returns one bean, and its parameters are injected.
/// The class itself is a bean too.
///
/// By default ([proxyBeanMethods] `true`) the container creates a
/// generated subclass whose `@Bean` methods return the container's bean.
/// So when one `@Bean` method calls another, it gets the existing
/// singleton, not a second object (a prototype-scoped `@Bean` still gives
/// a new instance per call). Static `@Bean` methods are not intercepted.
/// Because of the subclass, a class with instance `@Bean` methods must be
/// extendable (not `final`, `sealed` or `interface`) and have a public
/// generative constructor; otherwise the build fails. With
/// [proxyBeanMethods] `false` ("lite" mode) the methods run as written:
/// take other beans as method parameters instead of calling the methods.
///
/// `@Lazy`, `@Profile` and conditions on the class apply to all its
/// `@Bean` methods, unless a method says otherwise (`@Lazy(false)`).
///
/// ```dart
/// @Configuration()
/// class DataConfig {
///   // Opened with the URL from the configuration files.
///   @Bean(initMethod: 'connect')
///   Connection connection(@Value(r'${db.url}') String url) =>
///       Connection(url);
///
///   @Bean()
///   UserStore userStore(Connection connection) => UserStore(connection);
///
///   @Bean()
///   Clock clock() => SystemClock();
///
///   @Bean()
///   Scheduler scheduler() => Scheduler(clock()); // the clock singleton
/// }
///
/// @Configuration(proxyBeanMethods: false)
/// class LiteConfig {
///   @Bean()
///   Clock clock() => SystemClock();
/// }
/// ```
///
/// Spring (Java), where the subclass is made with CGLIB:
/// ```java
/// @Configuration
/// class DataConfig {
///   @Bean(initMethod = "connect")
///   Connection connection(@Value("${db.url}") String url) {
///     return new Connection(url);
///   }
///
///   @Bean
///   UserStore userStore(Connection connection) {
///     return new UserStore(connection);
///   }
///
///   @Bean Clock clock() { return new SystemClock(); }
///
///   @Bean Scheduler scheduler() { return new Scheduler(clock()); }
/// }
///
/// @Configuration(proxyBeanMethods = false)
/// class LiteConfig {
///   @Bean Clock clock() { return new SystemClock(); }
/// }
/// ```
class Configuration extends Component {
  /// Declares the configuration class; [name] replaces the default bean
  /// name.
  const Configuration({String? name, this.proxyBeanMethods = true})
    : super(name);

  /// Whether a generated subclass makes `@Bean` methods return the
  /// container's beans (default `true`). With `false` the methods are
  /// called as written, which avoids the subclass and its restrictions.
  final bool proxyBeanMethods;
}

// ---------------------------------------------------------------------------
// Bean declaration modifiers
// ---------------------------------------------------------------------------

/// Marks a method whose return value is a bean.
///
/// Use it when a class cannot carry [Component] itself (it comes from
/// another package, or needs constructor arguments that are not beans), or
/// when creating the object takes code. The method lives in a
/// [Configuration] class (or a `@Component`, in "lite" mode) or is static;
/// its parameters are injected like constructor parameters.
///
/// The bean name defaults to the method name. The bean type is what the
/// method returns: the static type of the returned expression when it is
/// more specific than the declared return type, so
/// `DataSource dataSource() => HikariDataSource()` is registered as a
/// `HikariDataSource` and all its supertypes (Spring only knows the
/// declared type until the bean is created). A method declared `T?` may
/// return `null`: the bean then exists by name but is absent for lookups
/// and injection by type. A function type or record type can be a bean too,
/// injected by that exact type.
///
/// ```dart
/// @Configuration()
/// class AppConfig {
///   // The pool size comes from the configuration, 4 when unset; open()
///   // runs once the pool is created.
///   @Bean(name: 'mainPool', aliases: ['pool'], initMethod: 'open')
///   Pool pool(@Value(r'${pool.size:4}') int size) => Pool(size);
///
///   @Bean(destroyMethod: '') // do not call Client.close() on shutdown
///   static Client client() => Client();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Configuration
/// class AppConfig {
///   @Bean(name = {"mainPool", "pool"}, initMethod = "open")
///   Pool pool(@Value("${pool.size:4}") int size) { return new Pool(size); }
///
///   @Bean(destroyMethod = "")
///   static Client client() { return new Client(); }
/// }
/// ```
class Bean {
  /// Declares the bean; every argument is optional.
  const Bean({
    this.name,
    this.aliases = const [],
    this.initMethod,
    this.destroyMethod = inferMethod,
    this.autowireCandidate = true,
    this.defaultCandidate = true,
  });

  /// The default of [destroyMethod]: at shutdown, call a public
  /// no-argument `close()`, `shutdown()` or `dispose()` method of the
  /// declared return type, if it has one. Spring infers `close` and
  /// `shutdown`; `dispose` is the Dart idiom.
  static const inferMethod = '(inferred)';

  /// The bean name; `null` gives the method name.
  final String? name;

  /// More names the bean can be found under. Spring puts them in the
  /// `name` array after the first.
  final List<String> aliases;

  /// A no-argument method of the bean called once it is injected, for
  /// objects that need a start call (`open`, `connect`) and that you cannot
  /// annotate with `@PostConstruct`.
  final String? initMethod;

  /// A no-argument method of the bean called when the context closes.
  /// Defaults to [inferMethod]; an empty string calls nothing, for an
  /// object whose `close()` must not run (for example one shared with code
  /// outside the container).
  final String? destroyMethod;

  /// Whether the bean can be injected by type at all (also with a
  /// qualifier). With `false` it is still found by name.
  final bool autowireCandidate;

  /// Whether the bean is injected where only its type is asked for. With
  /// `false` it is injected only where a qualifier (`@Qualifier`, the bean
  /// name or an alias) selects it, and `@ConditionalOnBean` /
  /// `@ConditionalOnMissingBean` ignore it. Use it for a second bean of a
  /// common type that must not get in the way of the main one (Spring
  /// 6.2's `@Bean(defaultCandidate = false)`).
  ///
  /// ```dart
  /// // Only injected where @Qualifier('audit') asks for it.
  /// @Bean(defaultCandidate: false)
  /// @Qualifier('audit')
  /// Executor auditExecutor() => Executor.single();
  /// ```
  final bool defaultCandidate;
}

/// Sets how many instances of a bean exist and how long each one lives.
///
/// Without it a bean is a singleton: one instance for the whole context.
/// [ScopeType.prototype] gives a new instance for every injection and
/// every lookup, for objects that hold per-use state. Other names refer
/// to custom scopes registered with `registerScope` on the bean factory
/// (for example a scope per screen or per request).
///
/// ```dart
/// // Each user of a cart gets their own instance.
/// @Component()
/// @Scope(ScopeType.prototype)
/// class ShoppingCart {
///   final items = <String>[];
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// @Scope(ConfigurableBeanFactory.SCOPE_PROTOTYPE)
/// class ShoppingCart { ... }
/// ```
class Scope {
  /// Puts the bean in the scope named [value].
  const Scope(this.value, {this.proxyMode = ScopedProxyMode.no});

  /// The scope name, such as [ScopeType.prototype] or the name of a
  /// registered custom scope.
  final String value;

  /// Whether a generated proxy is injected instead of the instance
  /// (default: no proxy). The proxy asks the scope for the current
  /// instance on every call, so a singleton can hold a bean of a shorter
  /// scope. See [ScopedProxyMode].
  final ScopedProxyMode proxyMode;
}

/// Delays the creation of a bean, or of what an injection point receives,
/// until it is first used.
///
/// On a bean class or `@Bean` method, the singleton is created on the
/// first lookup or injection instead of at startup: use it for expensive
/// beans that many runs never need. On a configuration class it applies
/// to all its `@Bean` methods.
///
/// On an injection point (constructor parameter, field, setter) a
/// generated proxy is injected instead of the bean; it finds the bean on
/// every call. This breaks dependency cycles and lets a bean call itself
/// through its AOP proxy, so that its advice applies (a call through
/// `this` skips it). The bean must still exist and be unique, which is
/// checked at startup. The type must be implementable from generated code
/// (an interface, or a class without private members; not generic) and
/// the point must not be nullable; use `ObjectProvider<T>` otherwise.
///
/// ```dart
/// @Component()
/// @Lazy()
/// class ReportGenerator { ... } // created on first getBean/injection
///
/// // Calls through _self go through the proxy, so @Cacheable applies.
/// @Service()
/// class BookService implements Books {
///   BookService(@Lazy() this._self);
///   final Books _self;
///
///   List<Book> findAll(List<String> isbns) =>
///       [for (final isbn in isbns) _self.find(isbn)];
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// @Lazy
/// class ReportGenerator { ... }
///
/// @Service
/// class BookService {
///   @Lazy @Autowired private BookService self;
/// }
/// ```
class Lazy {
  /// Makes the bean or injection point lazy; `@Lazy(false)` makes a bean
  /// eager where its configuration class or scan would make it lazy.
  const Lazy([this.value = true]);

  /// Whether the bean (or the injection point) is lazy.
  final bool value;
}

/// Makes this bean the one injected when several beans have the requested
/// type.
///
/// Without it, asking for a type that two beans have is an error. Mark
/// the usual implementation `@Primary()` and inject the others by
/// [Qualifier] where they are wanted.
///
/// ```dart
/// @Component()
/// @Primary()
/// class EnglishGreeter implements Greeter { ... }
///
/// @Component()
/// class FrenchGreeter implements Greeter { ... }
///
/// // context.getBean<Greeter>() returns the EnglishGreeter.
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// @Primary
/// class EnglishGreeter implements Greeter { ... }
/// ```
class Primary {
  /// Marks the bean as primary.
  const Primary();
}

/// Makes this bean the one used only when no other bean of the type is
/// there.
///
/// It is the opposite of [Primary]: a default that steps aside as soon as
/// another candidate exists, for example a real implementation that a
/// test profile replaces.
///
/// ```dart
/// @Component()
/// @Fallback()
/// class SystemClock implements Clock { ... }
///
/// @Component()
/// @Profile(['test'])
/// class FixedClock implements Clock { ... } // wins when present
/// ```
///
/// Spring (Java, 6.2+):
/// ```java
/// @Component
/// @Fallback
/// class SystemClock implements Clock { ... }
/// ```
class Fallback {
  /// Marks the bean as fallback.
  const Fallback();
}

/// Picks one bean among several of the same type, by a label or a bean
/// name.
///
/// On a bean declaration it gives the bean that label. On an injection
/// point it selects the bean with that label or name. Use it when several
/// beans share a type and the one to inject is not the [Primary] one.
///
/// ```dart
/// @Component()
/// @Qualifier('fr')
/// class FrenchGreeter implements Greeter { ... }
///
/// // This page is French, whatever the default greeter is.
/// @Service()
/// class Welcome {
///   Welcome(@Qualifier('fr') this.greeter);
///   final Greeter greeter;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// @Qualifier("fr")
/// class FrenchGreeter implements Greeter { ... }
///
/// @Service
/// class Welcome {
///   Welcome(@Qualifier("fr") Greeter greeter) { ... }
/// }
/// ```
class Qualifier {
  /// Labels the bean, or selects one at an injection point, with [value].
  const Qualifier(this.value);

  /// The label or bean name.
  final String value;
}

/// Names beans that must be created before this one and destroyed after
/// it.
///
/// The container already orders beans by their injected dependencies. Use
/// this only for a dependency it cannot see: a bean that relies on another
/// bean's side effect (a database schema created, a global set up) without
/// injecting it.
///
/// ```dart
/// @Component()
/// @DependsOn(['connection'])
/// class Migrations {
///   Migrations() {
///     // runs after the `connection` bean was created
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// @DependsOn("connection")
/// class Migrations { ... }
/// ```
class DependsOn {
  /// Declares the bean names this bean depends on.
  const DependsOn(this.value);

  /// Names of the beans created before this one.
  final List<String> value;
}

/// A human-readable description of a bean.
///
/// The text is stored in the bean definition for tools and diagnostics
/// that list beans. It changes nothing at runtime.
///
/// ```dart
/// @Component()
/// @Description('Sends transactional e-mails')
/// class Mailer { ... }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// @Description("Sends transactional e-mails")
/// class Mailer { ... }
/// ```
class Description {
  /// Describes the bean with [value].
  const Description(this.value);

  /// The description text.
  final String value;
}

// ---------------------------------------------------------------------------
// Injection
// ---------------------------------------------------------------------------

/// Asks the container to inject beans into a field, setter, method or
/// constructor.
///
/// Constructor parameters of a bean are injected without it. Use it:
///
/// - on a constructor, to choose it when the class has several. Several
///   constructors may be `@Autowired(required: false)`: the one with the
///   most parameters whose beans exist is used;
/// - on a field or setter, to assign it after construction. Fields must be
///   public and settable (`late final` or non-final);
/// - on a method, to call it after construction with injected arguments.
///
/// A nullable type makes the dependency optional. `List<T>`, `Set<T>` and
/// `Map<String, T>` receive all beans of `T` (ordered);
/// `ObjectProvider<T>` receives a handle that looks the bean up later.
///
/// ```dart
/// @Service()
/// class Checkout {
///   @Autowired()
///   late final PaymentGateway gateway;
///
///   @Autowired()
///   late final List<DiscountRule> rules; // every DiscountRule bean
///
///   @Autowired()
///   void init(Clock clock) => startedAt = clock.now();
///
///   DateTime? startedAt;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Service
/// class Checkout {
///   @Autowired PaymentGateway gateway;
///   @Autowired List<DiscountRule> rules;
///
///   @Autowired
///   void init(Clock clock) { startedAt = clock.now(); }
/// }
/// ```
class Autowired {
  /// Marks the injection point; [required] only matters on constructors.
  const Autowired({this.required = true});

  /// On a constructor, `false` makes it one of several candidates: the
  /// container calls the one with the most parameters it can satisfy. On
  /// fields, setters and methods a nullable type makes a dependency
  /// optional instead (`required: false` there fails the build).
  final bool required;
}

/// Marks a method that returns a bean of the container on every call.
///
/// A singleton receives its dependencies once. When it needs a fresh
/// prototype bean each time (a command, a unit of work), it declares a
/// `@Lookup` method: every call returns the bean named [value], else the
/// bean of the method's return type.
///
/// The bean is created as a generated subclass that overrides the method.
/// The method may be abstract (then the class may be abstract too: an
/// abstract `@Component` class with `@Lookup` methods is a bean, unlike
/// other abstract classes) or concrete (its body never runs). A nullable
/// return type gives `null` when no bean of the type exists.
///
/// Dart limits, checked at build time: the method must be public, take no
/// parameters (Spring passes them as constructor arguments to `getBean`)
/// and not be generic; the class must be extendable from the generated
/// library (not `final`, `sealed` or `interface`), have a public generative
/// constructor and not be a full-mode `@Configuration` class.
///
/// ```dart
/// @Component()
/// @Scope(ScopeType.prototype)
/// class Command {}
///
/// @Component()
/// abstract class CommandManager {
///   @Lookup()
///   Command createCommand(); // a new Command per call
///
///   @Lookup('auditLog')
///   AuditLog auditLog(); // the bean named `auditLog`
///
///   void process() => createCommand().run();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// public abstract class CommandManager {
///   @Lookup
///   protected abstract Command createCommand();
///
///   @Lookup("auditLog")
///   protected abstract AuditLog auditLog();
/// }
/// ```
class Lookup {
  /// Marks the lookup method; [value] names the bean to return.
  const Lookup([this.value]);

  /// The name (or alias) of the bean to return; `null` looks it up by the
  /// method's return type.
  final String? value;
}

/// Asks the container to inject a field, setter, method or constructor;
/// the standard Java (JSR-330) name for [Autowired].
///
/// It behaves like `@Autowired()`. It exists so that code ported from
/// Java that uses `@Inject` reads the same.
///
/// ```dart
/// @Named()
/// class Checkout {
///   @Inject()
///   late final PaymentGateway gateway;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Named
/// class Checkout {
///   @Inject PaymentGateway gateway;
/// }
/// ```
class Inject extends Autowired {
  /// Marks the injection point.
  const Inject();
}

/// Marks a class as a bean, or selects a bean at an injection point; the
/// standard Java (JSR-330) name for [Component] and [Qualifier].
///
/// On a class it behaves like `@Component`, on an injection point like
/// `@Qualifier`. It exists for code ported from Java that uses `@Named`.
///
/// ```dart
/// @Named('fastGateway')
/// class FastGateway implements PaymentGateway { ... }
///
/// // Checkout always pays through the fast gateway.
/// @Named()
/// class Checkout {
///   Checkout(@Named('fastGateway') this.gateway);
///   final PaymentGateway gateway;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Named("fastGateway")
/// class FastGateway implements PaymentGateway { ... }
///
/// @Named
/// class Checkout {
///   @Inject
///   Checkout(@Named("fastGateway") PaymentGateway gateway) { ... }
/// }
/// ```
class Named extends Component {
  /// Declares the bean, or selects one; [name] is the bean name or
  /// qualifier.
  const Named([super.name]);
}

/// Injects a value from the configuration (properties, environment
/// variables) or from an expression, instead of a bean.
///
/// Use it for settings such as a port, a URL or a feature switch.
/// `${key}` and `${key:default}` placeholders are resolved against the
/// environment's property sources (config files, environment variables,
/// command line); `#{...}` parts are evaluated as SpEL expressions, which
/// can read other beans. The result is converted to the target type
/// (`int`, `Duration`, `List<String>`, ...). A nullable target receives
/// `null` when a placeholder has no value; a non-nullable one without a
/// default fails the startup. For a group of related settings, a
/// `@ConfigurationProperties` class of `spring_boot_dart` is often clearer.
///
/// Write the value as a raw string (`r'...'`) so that Dart does not read
/// `$` as interpolation.
///
/// ```dart
/// @Service()
/// class Server {
///   // 8080 unless `server.port` is set.
///   Server(@Value(r'${server.port:8080}') this.port);
///   final int port;
///
///   @Value(r'${server.tags}') // "a,b,c" becomes a list
///   late final List<String> tags;
///
///   @Value('#{appSettings.title.toUpperCase()}') // from the appSettings bean
///   late final String banner;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Service
/// class Server {
///   Server(@Value("${server.port:8080}") int port) { ... }
///
///   @Value("${server.tags}") List<String> tags;
///   @Value("#{appSettings.title.toUpperCase()}") String banner;
/// }
/// ```
class Value {
  /// Injects the resolved [value].
  const Value(this.value);

  /// The text with `${...}` placeholders and/or `#{...}` expressions.
  final String value;
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/// Marks a method the container calls once a bean is fully injected,
/// before anyone uses it.
///
/// Use it for setup that needs the injected fields: warming a cache,
/// checking settings, opening a connection. The constructor is too early
/// for that when fields or setters are injected. The method takes no
/// arguments. It may return a `Future`; then the context must be started
/// with `refreshAsync` (or `runAsync`), which waits for it.
///
/// ```dart
/// @Component()
/// class Cache {
///   @PostConstruct()
///   void warmUp() { /* load entries */ }
/// }
/// ```
///
/// Spring (Java), the Jakarta annotation:
/// ```java
/// @Component
/// class Cache {
///   @PostConstruct
///   void warmUp() { ... }
/// }
/// ```
class PostConstruct {
  /// Marks the init method.
  const PostConstruct();
}

/// Marks a method the container calls when a bean is destroyed: when the
/// context closes for a singleton, when its scope ends for a scoped bean.
///
/// Use it to release what the bean holds: flush a buffer, close a file,
/// cancel a timer. The method takes no arguments. It may return a
/// `Future`, which `closeAsync` waits for (`close` logs it and goes on).
/// Prototype beans are not tracked, so their `@PreDestroy` methods are
/// never called (as in Spring).
///
/// ```dart
/// @Component()
/// class Cache {
///   @PreDestroy()
///   void flush() { /* write entries */ }
/// }
/// ```
///
/// Spring (Java), the Jakarta annotation:
/// ```java
/// @Component
/// class Cache {
///   @PreDestroy
///   void flush() { ... }
/// }
/// ```
class PreDestroy {
  /// Marks the destroy method.
  const PreDestroy();
}

// ---------------------------------------------------------------------------
// Conditions and configuration
// ---------------------------------------------------------------------------

/// Registers a bean only when the active profiles match.
///
/// Profiles name the situations an application runs in (`dev`, `test`,
/// `prod`). They are activated with the `spring.profiles.active` property
/// or `Environment.setActiveProfiles`. Use `@Profile` to swap
/// implementations between them, for example an in-memory mailer during
/// development. Each entry is a profile expression: `'dev'`, `'!prod'`,
/// `'eu & (dev | test)'`. The bean is registered when any entry matches.
/// On a configuration class it applies to all its `@Bean` methods and to
/// its `@PropertySource` files. Subclass it to name a set of profiles once:
/// `class Dev extends Profile { const Dev() : super(const ['dev']); }`.
///
/// ```dart
/// @Component()
/// @Profile(['dev', 'test'])
/// class InMemoryMailer implements Mailer { ... }
///
/// // The InMemoryMailer bean exists in this context only.
/// final env = StandardEnvironment()..setActiveProfiles(['dev']);
/// final context = ApplicationContext.run([appBeans], environment: env);
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// @Profile({"dev", "test"})
/// class InMemoryMailer implements Mailer { ... }
/// ```
class Profile {
  /// Restricts the bean to the profile expressions [value].
  const Profile(this.value);

  /// Profile expressions; the bean is registered if any of them matches.
  final List<String> value;
}

/// Registers a bean only when every listed `Condition` matches.
///
/// Use it when the rule is not a profile: an operating system, a property
/// combination, the presence of another bean. Each type in [value] must
/// implement `Condition` and have a no-argument constructor; the
/// container calls its `matches` while it loads the bean definitions,
/// before any bean is created. A const annotation class that implements
/// `Condition` can be used directly instead (this is how Spring Boot's
/// `@ConditionalOnProperty` works), and a subclass of [Conditional] names
/// a set of conditions once.
///
/// ```dart
/// class OnLinux implements Condition {
///   const OnLinux();
///
///   @override
///   bool matches(ConditionContext context) =>
///       context.environment.getProperty('os.name') == 'linux';
/// }
///
/// // Only on Linux machines, where systemd exists.
/// @Component()
/// @Conditional([OnLinux])
/// class SystemdNotifier { ... }
/// ```
///
/// Spring (Java):
/// ```java
/// class OnLinux implements Condition {
///   public boolean matches(ConditionContext ctx, AnnotatedTypeMetadata m) {
///     return "linux".equals(ctx.getEnvironment().getProperty("os.name"));
///   }
/// }
///
/// @Component
/// @Conditional(OnLinux.class)
/// class SystemdNotifier { ... }
/// ```
class Conditional {
  /// Restricts the bean to the `Condition` types [value].
  const Conditional(this.value);

  /// `Condition` implementations that all have to match.
  final List<Type> value;
}

/// Adds beans that the component scan does not find: configuration
/// classes from elsewhere, or code that registers beans.
///
/// Put it on a configuration class. Each listed type is either a
/// configuration (or component) class outside the scanned directories,
/// whose beans are added with the importing class, or a class that
/// registers beans in code: a `BeanRegistrar`, an `ImportSelector` (which
/// returns more modules) or an `ImportBeanDefinitionRegistrar`. The
/// generator creates those with their no-argument constructor. Imports
/// share the importing class's conditions: if the class is skipped, so is
/// what it imports.
///
/// ```dart
/// @Configuration()
/// @Import([LegacyConfig]) // declared outside the scanned directory
/// class AppConfig {}
/// ```
///
/// Spring (Java):
/// ```java
/// @Configuration
/// @Import(LegacyConfig.class)
/// class AppConfig {}
/// ```
class Import {
  /// Imports the classes [value].
  const Import(this.value);

  /// Configuration or component classes, `BeanRegistrar`s,
  /// `ImportSelector`s and `ImportBeanDefinitionRegistrar`s.
  final List<Type> value;
}

/// Adds property files to the environment, on top of the application's
/// configuration files.
///
/// Use it for a file that belongs to one part of the application (a
/// feature's defaults, a file outside the usual locations), so that its
/// keys are available to `@Value` and `${...}`. The files are read while
/// the bean definitions load, so later conditions and every bean see
/// them; they are read only when the declaring class's conditions
/// (`@Profile`, `@Conditional`, ...) match. Locations may contain `${...}`
/// placeholders and patterns (`file:config/*.properties`); when several
/// files define the same key, the last location wins. It reads
/// `.properties` files; give a [factory] for another format such as YAML.
///
/// ```dart
/// // The local override is optional: skipped when it does not exist.
/// @Configuration()
/// @PropertySource([
///   'file:config/app.properties',
///   r'file:config/app-${env:local}.properties',
/// ], ignoreResourceNotFound: true)
/// class AppConfig {}
/// ```
///
/// Spring (Java):
/// ```java
/// @Configuration
/// @PropertySource(
///     value = {"file:config/app.properties",
///              "file:config/app-${env:local}.properties"},
///     ignoreResourceNotFound = true)
/// class AppConfig {}
/// ```
class PropertySource {
  /// Adds the files at the resource locations [value].
  const PropertySource(
    this.value, {
    this.name,
    this.ignoreResourceNotFound = false,
    this.factory,
    this.encoding,
  });

  /// Resource locations of the property files (`file:`, `classpath:`,
  /// patterns).
  final List<String> value;

  /// Name of the resulting property source; derived from the location
  /// when `null`.
  final String? name;

  /// Whether a missing file is skipped (`true`) or fails the startup
  /// (`false`, the default).
  final bool ignoreResourceNotFound;

  /// A `PropertySourceFactory` type with a no-argument constructor, to read
  /// another format; `null` reads `.properties` files.
  final Type? factory;

  /// The charset of the files, such as `'ISO-8859-1'`; UTF-8 when `null`.
  final String? encoding;
}

/// Generates a module with every bean declared in the directory of the
/// annotated file and its subdirectories.
///
/// Dart cannot search the program for annotated classes at runtime, so
/// the generator does it at build time (`build_runner`). Put
/// `@ComponentScan()` on a top-level variable initialized with the
/// generated module, which has the same name prefixed with `$`, then pass
/// the variable to the context. A Spring Boot application uses
/// `@SpringBootApplication()` instead, which scans too. A subdirectory
/// with its own `@ComponentScan` belongs to that scan, and the enclosing
/// scan imports its module instead of scanning its files again.
///
/// ```dart
/// // lib/src/beans.dart: everything under lib/src/ is scanned.
/// import 'package:my_feature/src/beans.spring.dart';
///
/// @ComponentScan()
/// final BeanModule myFeatureBeans = $myFeatureBeans;
///
/// void main() {
///   final context = ApplicationContext.run([myFeatureBeans]);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Configuration
/// @ComponentScan("com.example.myfeature")
/// class MyFeatureConfig {}
///
/// var context = new AnnotationConfigApplicationContext(
///     MyFeatureConfig.class);
/// ```
///
/// Unlike Spring, which reads the classpath at startup, the filters are
/// evaluated at build time too:
///
/// ```dart
/// // Plugin classes are beans without @Component, stubs never are, and
/// // every bean is created on first use.
/// @ComponentScan(
///   includeFilters: [
///     Filter(type: FilterType.assignableType, classes: [Plugin]),
///   ],
///   excludeFilters: [Filter(type: FilterType.regex, pattern: ['.*Stub$'])],
///   lazyInit: true,
/// )
/// final BeanModule myFeatureBeans = $myFeatureBeans;
/// ```
class ComponentScan {
  /// Scans the annotated file's directory; the arguments change what
  /// counts as a bean.
  const ComponentScan({
    this.includeFilters = const [],
    this.excludeFilters = const [],
    this.useDefaultFilters = true,
    this.lazyInit = false,
  });

  /// Classes matching one of these are beans even without `@Component`
  /// (an abstract class never is).
  final List<Filter> includeFilters;

  /// Classes matching one of these are never beans, whatever else says;
  /// their `@Bean` methods are skipped with them.
  final List<Filter> excludeFilters;

  /// Whether `@Component` (and annotations extending it) marks a bean
  /// (default `true`); with `false` only [includeFilters] do.
  final bool useDefaultFilters;

  /// Whether the scanned beans (components and their `@Bean` methods) are
  /// created on first use unless annotated `@Lazy(false)` (default
  /// `false`).
  final bool lazyInit;
}

/// A rule that selects classes for [ComponentScan.includeFilters] or
/// [ComponentScan.excludeFilters].
///
/// ```dart
/// Filter(classes: [Plugin])                          // annotated @Plugin
/// Filter(type: FilterType.assignableType, classes: [Handler])
/// Filter(type: FilterType.regex, pattern: ['.*Repository'])
/// ```
///
/// Spring (Java): `@ComponentScan.Filter`.
class Filter {
  /// Creates a filter; [classes] serve [FilterType.annotation] and
  /// [FilterType.assignableType], [pattern] serves [FilterType.regex].
  const Filter({
    this.type = FilterType.annotation,
    this.classes = const [],
    this.pattern = const [],
  });

  /// How the filter matches; [FilterType.annotation] by default.
  final FilterType type;

  /// Annotation classes (also matched by their subclasses, like Spring's
  /// meta-annotations) or types the class must be assignable to.
  final List<Type> classes;

  /// Regular expressions matched against the class name.
  final List<String> pattern;
}

/// How a [Filter] decides whether a class matches.
///
/// Spring (Java): `FilterType` (without `ASPECTJ` and `CUSTOM`).
enum FilterType {
  /// The class is annotated with one of the filter's classes.
  annotation,

  /// The class is, extends, implements or mixes in one of the filter's
  /// classes.
  assignableType,

  /// The class name matches one of the filter's patterns.
  regex,
}

/// Lets the container inject an object it did not create, such as a
/// Flutter `State`.
///
/// Some objects are created by a framework, not by the container, yet need
/// beans and settings. Mark the class `@Configurable()`: the generator
/// writes an injector for its `@Autowired` and `@Value` members, and the
/// object calls `autowireBean` on itself once it exists. Spring weaves such
/// classes with AspectJ so that `new` triggers the injection; Dart has no
/// weaving, so the call is explicit.
///
/// ```dart
/// @Configurable()
/// class ProfileScreenState {
///   @Autowired()
///   late final UserService users;
///
///   @Value(r'${app.title}')
///   late final String title;
/// }
///
/// // Flutter created the state; fill in its beans and settings.
/// final state = ProfileScreenState();
/// context.autowireCapableBeanFactory.autowireBean(state);
/// ```
///
/// Spring (Java):
/// ```java
/// @Configurable
/// class ProfileScreenState {
///   @Autowired UserService users;
/// }
/// // with AspectJ weaving: new ProfileScreenState() is injected, or
/// context.getAutowireCapableBeanFactory().autowireBean(state);
/// ```
class Configurable {
  /// Marks the class as injectable from outside the container.
  const Configurable();
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

/// Marks a bean method that the context calls for each published event of
/// its parameter type.
///
/// Events let one part of an application react to what another did
/// without either knowing the other: a service publishes `OrderPlaced`
/// with `ApplicationEventPublisher.publishEvent`, and any bean with an
/// `@EventListener` method for `OrderPlaced` runs. This is the usual way
/// to listen; it also receives the context's own events, such as
/// `ContextRefreshedEvent` once every bean is ready.
///
/// The event type is the method's single parameter type; [classes] lists
/// the types instead, for a method without parameters or one whose
/// parameter is a common supertype. Any object can be an event. A non-null
/// return value is published as a new event (each element of an iterable
/// result separately, a `Future` result when it completes). Listeners run
/// synchronously in the publishing call, ordered by `@Order` on the
/// method; [Async] runs one on a task executor instead.
///
/// ```dart
/// bool isBigOrder(OrderPlaced order) => order.total >= 100;
///
/// @Component()
/// class Shipping {
///   // Every placed order is shipped; the result is published in turn.
///   @EventListener()
///   OrderShipped onPlaced(OrderPlaced order) => OrderShipped(this, order.id);
///
///   @EventListener(condition: isBigOrder)
///   @Order(1)
///   void onBigOrder(OrderPlaced order) { ... }
///
///   @EventListener(classes: [ContextRefreshedEvent, ContextClosedEvent])
///   void onContext() { ... }
/// }
///
/// context.publishEvent(OrderPlaced(1, 250));
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class Shipping {
///   @EventListener
///   OrderShipped onPlaced(OrderPlaced order) { ... }
///
///   @EventListener(condition = "#order.total >= 100")
///   @Order(1)
///   void onBigOrder(OrderPlaced order) { ... }
///
///   @EventListener({ContextRefreshedEvent.class, ContextClosedEvent.class})
///   void onContext() { ... }
/// }
/// ```
///
/// Unlike Spring, [condition] is a Dart function rather than a SpEL string.
class EventListener {
  /// Marks the listener method; every argument is optional.
  const EventListener({this.classes = const [], this.condition, this.id});

  /// The event types the method handles, when its parameter does not say
  /// it; empty by default.
  final List<Type> classes;

  /// A top-level or static `bool Function(E event)`; the method runs only
  /// when it returns `true`. It is called inside the multicaster's error
  /// handling, so an error it throws is treated like a listener's.
  final Function? condition;

  /// The listener's id, shown in logs and error messages; defaults to
  /// `Class.method`.
  final String? id;
}

/// Runs an `@EventListener` method on a `TaskExecutor` instead of in the
/// publishing call.
///
/// Use it for slow listeners (sending a mail, calling a remote service)
/// so that the code publishing the event does not wait. [value] names the
/// executor bean; without it the context uses the only (or `@Primary`)
/// `TaskExecutor` bean, else the one named `taskExecutor`.
///
/// It takes effect only when the context has a `TaskExecutor` bean, as
/// Spring's `@EnableAsync` switches it on. The scheduling starter
/// (`spring_boot_starter_scheduling`) registers one
/// (`applicationTaskExecutor`, alias `taskExecutor`). Without any, `@Async`
/// is ignored and the listener runs synchronously. A failure (thrown, or
/// from the returned `Future`) goes to the multicaster's error handler,
/// else it is logged; a result is published as an event, as for
/// synchronous listeners.
///
/// The generator accepts `@Async` on `@EventListener` methods only: there
/// are no runtime proxies for other methods.
///
/// ```dart
/// @Component()
/// class Mailer {
///   // The order is confirmed without the publisher waiting for the mail.
///   @EventListener()
///   @Async()
///   Future<void> onPlaced(OrderPlaced order) => sendConfirmation(order);
///
///   @EventListener()
///   @Async('mailExecutor')
///   void onShipped(OrderShipped order) { ... }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @EnableAsync
/// @Configuration
/// class AsyncConfig {}
///
/// @Component
/// class Mailer {
///   @Async @EventListener
///   CompletableFuture<Void> onPlaced(OrderPlaced order) { ... }
///
///   @Async("mailExecutor") @EventListener
///   void onShipped(OrderShipped order) { ... }
/// }
/// ```
class Async {
  /// Runs the listener asynchronously; [value] names the executor bean.
  const Async([this.value]);

  /// Name of the `TaskExecutor` bean; `null` for the default one.
  final String? value;
}

/// Marks an annotation class whose methods the runtime can find on beans.
///
/// Libraries that act on annotated bean methods (a scheduler running
/// `@Scheduled` methods, a message consumer) need to find and call them,
/// and Dart has no reflection for that. Put `@BeanMethodAnnotation()` on
/// such an annotation class: for every bean method carrying it, the
/// generator writes a `BeanMethod` into `BeanDefinition.annotatedMethods`
/// with the method's name, annotations and a closure that calls it.
/// Application code rarely needs it; library authors do.
///
/// ```dart
/// @BeanMethodAnnotation()
/// class Poll {
///   const Poll(this.every);
///   final Duration every;
/// }
///
/// @Component()
/// class Inbox {
///   @Poll(Duration(seconds: 30))
///   void check() { ... }
/// }
///
/// // In a BeanPostProcessor or lifecycle bean of the library: find the
/// // @Poll methods and call them on the bean.
/// for (final method in context.beanFactory
///     .getBeanDefinition('inbox')
///     .annotatedMethods) {
///   final poll = method.annotations.whereType<Poll>().first;
///   method.invoke(context.getBeanByName('inbox'), const []);
/// }
/// ```
///
/// Spring finds such methods by reflection
/// (`MethodIntrospector.selectMethods`), so it has no equivalent.
class BeanMethodAnnotation {
  /// Marks the annotation class.
  const BeanMethodAnnotation();
}
