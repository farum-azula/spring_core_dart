import 'package:spring_core_dart/src/beans/scope.dart';

// Annotations are plain const classes; `spring_core_dart_generator` reads
// them at build time (Dart has no runtime reflection in Flutter/AOT).

// ---------------------------------------------------------------------------
// Stereotypes
// ---------------------------------------------------------------------------

/// Marks a class as a bean, like Spring's `@Component`.
///
/// The bean name defaults to the class name in lowerCamelCase
/// (`AuthService` → `authService`, `URLService` stays). Subclass
/// [Component] to create your own stereotypes.
///
/// The class must live under a directory scanned by a [ComponentScan]
/// module; its constructor parameters are injected.
///
/// ```dart
/// @Component()
/// class Clock {
///   DateTime now() => DateTime.now();
/// }
///
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
  /// Creates the annotation; [name] overrides the default bean name.
  const Component([this.name]);

  /// Bean name. Defaults to the lowerCamelCase class name.
  final String? name;
}

/// Stereotype for service-layer beans, like Spring's `@Service`.
///
/// Behaves exactly like [Component]; the name documents intent.
///
/// ```dart
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
  /// Creates the annotation; [name] overrides the default bean name.
  const Service([super.name]);
}

/// Stereotype for data-access beans, like Spring's `@Repository`.
///
/// Behaves exactly like [Component] (there is no exception translation as
/// in Spring).
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
  /// Creates the annotation; [name] overrides the default bean name.
  const Repository([super.name]);
}

/// Stereotype for controllers, like Spring's `@Controller`.
///
/// Behaves exactly like [Component]; useful for presentation-layer beans
/// (for example Flutter view models).
///
/// ```dart
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
  /// Creates the annotation; [name] overrides the default bean name.
  const Controller([super.name]);
}

/// A bean that declares other beans through [Bean] methods, like Spring's
/// `@Configuration`.
///
/// Unlike Spring, configuration classes are not proxied: calling one `@Bean`
/// method from another creates a new object. Take other beans as method
/// parameters instead.
///
/// ```dart
/// @Configuration()
/// class DataConfig {
///   @Bean(initMethod: 'connect')
///   Connection connection(@Value(r'${db.url}') String url) =>
///       Connection(url);
///
///   @Bean()
///   UserStore userStore(Connection connection) => UserStore(connection);
/// }
/// ```
///
/// Spring (Java):
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
/// }
/// ```
class Configuration extends Component {
  /// Creates the annotation; [name] overrides the default bean name.
  const Configuration([super.name]);
}

// ---------------------------------------------------------------------------
// Bean declaration modifiers
// ---------------------------------------------------------------------------

/// Declares a bean produced by a method, like Spring's `@Bean`:
/// `@Bean()`, `@Bean(name: 'x', initMethod: 'open')`.
///
/// The bean type is the method's declared return type, the name defaults
/// to the method name, and method parameters are injected. Methods may be
/// instance methods of a [Configuration] class or static methods.
///
/// ```dart
/// @Configuration()
/// class AppConfig {
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
  /// Creates the annotation; every argument is optional.
  const Bean({
    this.name,
    this.aliases = const [],
    this.initMethod,
    this.destroyMethod = inferMethod,
    this.autowireCandidate = true,
  });

  /// Default for [destroyMethod]: call a public no-argument `close()`,
  /// `shutdown()` or `dispose()` method of the declared return type, like
  /// Spring's inferred destroy method (plus the Dart `dispose` idiom).
  static const inferMethod = '(inferred)';

  /// Bean name. Defaults to the method name.
  final String? name;

  /// Extra names for the bean (Spring puts them into the `name` array).
  final List<String> aliases;

  /// Name of a no-argument method called after injection.
  final String? initMethod;

  /// Name of a no-argument method called when the context closes; an empty
  /// string disables the inferred method.
  final String? destroyMethod;

  /// Whether the bean is a candidate for injection by type.
  final bool autowireCandidate;
}

/// Sets the bean scope, like Spring's `@Scope`. Without it a bean is a
/// singleton. See [ScopeType] for built-in names; custom scopes are
/// registered on the bean factory.
///
/// ```dart
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
  /// Creates the annotation for the scope named [value].
  const Scope(this.value);

  /// The scope name, such as [ScopeType.prototype].
  final String value;
}

/// Delays creation, like Spring's `@Lazy`.
///
/// On a bean class or `@Bean` method the singleton is created on first use
/// instead of at refresh; on a configuration class it applies to all its
/// `@Bean` methods.
///
/// On an injection point (constructor parameter, field, setter) a
/// generated lazy proxy is injected instead of the bean: it finds the bean
/// on every call. This breaks cycles and lets a bean call itself through
/// its AOP proxy (self-invocation through `this` skips advice). The bean
/// must still exist and be unique, which is checked at refresh. The type
/// must be implementable from generated code (an interface, or a class
/// without private members; not generic) and the point must not be
/// nullable — use `ObjectProvider<T>` otherwise.
///
/// ```dart
/// @Component()
/// @Lazy()
/// class ReportGenerator { ... } // created on first getBean/injection
///
/// @Service()
/// class BookService implements Books {
///   BookService(@Lazy() this._self);
///   final Books _self;          // the proxy: @Cacheable, @Timed... apply
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
  /// Creates the annotation; `@Lazy(false)` forces eager creation.
  const Lazy([this.value = true]);

  /// Whether the bean (or the injection point) is lazy.
  final bool value;
}

/// Prefers this bean when several beans match a type, like Spring's
/// `@Primary`.
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
  /// Creates the annotation.
  const Primary();
}

/// Uses this bean only when no other candidate matches, like Spring's
/// `@Fallback`.
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
  /// Creates the annotation.
  const Fallback();
}

/// Selects a bean by name or qualifier at an injection point, or adds a
/// qualifier to a bean declaration, like Spring's `@Qualifier`.
///
/// ```dart
/// @Component()
/// @Qualifier('fr')
/// class FrenchGreeter implements Greeter { ... }
///
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
  /// Creates the annotation with the qualifier or bean name [value].
  const Qualifier(this.value);

  /// The qualifier value or bean name.
  final String value;
}

/// Beans that must be created (and destroyed after) this one, like Spring's
/// `@DependsOn`.
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
  /// Creates the annotation with the bean names this bean depends on.
  const DependsOn(this.value);

  /// Names of the beans created before this one.
  final List<String> value;
}

/// Human-readable description of a bean, like Spring's `@Description`.
///
/// The text is stored in the bean definition (useful for tooling and
/// diagnostics) and has no runtime effect.
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
  /// Creates the annotation with the description text [value].
  const Description(this.value);

  /// The description text.
  final String value;
}

// ---------------------------------------------------------------------------
// Injection
// ---------------------------------------------------------------------------

/// Marks an injection point, like Spring's `@Autowired`.
///
/// - Constructor: the constructor used to create the bean (only needed when
///   a class has several constructors).
/// - Field or setter: assigned after construction; fields must be public
///   and settable (`late final` or non-final).
/// - Method: called after construction with injected arguments.
///
/// A nullable type makes the dependency optional. `List<T>`, `Set<T>` and
/// `Map<String, T>` inject all beans of `T` (ordered); `ObjectProvider<T>`
/// injects a lazy handle.
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
  /// Creates the annotation.
  const Autowired();
}

/// JSR-330 alias of [Autowired].
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
  /// Creates the annotation.
  const Inject();
}

/// JSR-330 alias of [Component] on classes and [Qualifier] at injection
/// points.
///
/// ```dart
/// @Named('fastGateway')
/// class FastGateway implements PaymentGateway { ... }
///
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
  /// Creates the annotation; [name] is the bean name or qualifier.
  const Named([super.name]);
}

/// Injects a value from the environment, like Spring's `@Value`.
///
/// `${key}` / `${key:default}` placeholders are resolved against property
/// sources (config files, environment variables, ...); `#{...}` parts are
/// evaluated as expressions when an expression resolver is installed. The
/// result is converted to the target type with the conversion service.
/// A nullable target receives `null` when a placeholder has no value.
///
/// ```dart
/// @Service()
/// class Server {
///   Server(@Value(r'${server.port:8080}') this.port);
///   final int port;
///
///   @Value(r'${server.tags}')
///   late final List<String> tags;
///
///   @Value('#{appSettings.title.toUpperCase()}')
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
///
/// Use a raw string (`r'...'`) so Dart does not treat `$` as
/// interpolation.
class Value {
  /// Creates the annotation with the placeholder/expression [value].
  const Value(this.value);

  /// The text with `${...}` placeholders and/or `#{...}` expressions.
  final String value;
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/// Called after injection, like Jakarta's `@PostConstruct`.
///
/// The method must take no arguments; it runs after all fields, setters and
/// `@Autowired` methods were injected.
///
/// ```dart
/// @Component()
/// class Cache {
///   @PostConstruct()
///   void warmUp() { /* load entries */ }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class Cache {
///   @PostConstruct
///   void warmUp() { ... }
/// }
/// ```
class PostConstruct {
  /// Creates the annotation.
  const PostConstruct();
}

/// Called when the context closes (singletons) or the scope ends, like
/// Jakarta's `@PreDestroy`.
///
/// Prototype beans are not tracked, so their `@PreDestroy` methods are not
/// called (same as Spring).
///
/// ```dart
/// @Component()
/// class Cache {
///   @PreDestroy()
///   void flush() { /* write entries */ }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class Cache {
///   @PreDestroy
///   void flush() { ... }
/// }
/// ```
class PreDestroy {
  /// Creates the annotation.
  const PreDestroy();
}

// ---------------------------------------------------------------------------
// Conditions and configuration
// ---------------------------------------------------------------------------

/// Registers the bean only when the profile expressions match, like
/// Spring's `@Profile` (`'dev'`, `'!prod'`, `'eu & (dev | test)'`).
///
/// The bean is registered when any of the expressions matches. Profiles
/// are activated with `spring.profiles.active` or
/// `Environment.setActiveProfiles`.
///
/// ```dart
/// @Component()
/// @Profile(['dev', 'test'])
/// class InMemoryMailer implements Mailer { ... }
///
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
  /// Creates the annotation with profile expressions.
  const Profile(this.value);

  /// Profile expressions; the bean is registered if any matches.
  final List<String> value;
}

/// Registers the bean only when every condition matches, like Spring's
/// `@Conditional`. Each type must implement `Condition` and have a
/// no-argument constructor.
///
/// A const annotation class that implements `Condition` can also be used
/// directly (see `Condition`).
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
  /// Creates the annotation with `Condition` types.
  const Conditional(this.value);

  /// `Condition` implementations that all have to match.
  final List<Type> value;
}

/// Adds configuration classes (and their `@Bean` methods) that are not
/// under the component scan, like Spring's `@Import`.
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
  /// Creates the annotation with the imported classes.
  const Import(this.value);

  /// Configuration (or component) classes to register.
  final List<Type> value;
}

/// Adds property files to the environment, like Spring's `@PropertySource`.
///
/// Locations may contain `${...}` placeholders. When several files define
/// the same key, the last location wins. The files are loaded before the
/// module's conditions are evaluated.
///
/// ```dart
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
  /// Creates the annotation for the resource locations [value].
  const PropertySource(
    this.value, {
    this.name,
    this.ignoreResourceNotFound = false,
    this.factory,
  });

  /// Resource locations of the property files.
  final List<String> value;

  /// Name of the resulting property source; derived from the location
  /// when `null`.
  final String? name;

  /// Whether a missing file is skipped instead of failing the refresh.
  final bool ignoreResourceNotFound;

  /// A `PropertySourceFactory` type with a no-argument constructor; the
  /// default reads `.properties` files.
  final Type? factory;
}

/// Generates a module with every bean declared in the directory of the
/// annotated file and its subdirectories, like Spring's `@ComponentScan`.
///
/// Put it on a top-level variable initialized with the generated module,
/// which has the same name prefixed with `$`:
///
/// ```dart
/// import 'package:my_feature/src/beans.beans.dart';
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
/// Unlike Spring, scanning happens at build time (`build_runner`), not by
/// reading the classpath at startup.
class ComponentScan {
  /// Creates the annotation.
  const ComponentScan();
}

/// Lets `autowireBean` inject a class the container does not create (for
/// example a Flutter `State`), like Spring's `@Configurable`.
///
/// Spring weaves `@Configurable` classes with AspectJ so `new` triggers
/// injection; here the generator emits a configurer and you call
/// `autowireBean` explicitly.
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
  /// Creates the annotation.
  const Configurable();
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

/// Marks a method as an application event listener, like Spring's
/// `@EventListener`.
///
/// The event type is the method's single parameter type, or [classes] for
/// methods without parameters (or with a common supertype parameter). A
/// non-null return value is published as a new event (each element of an
/// iterable result is published separately). Listeners run synchronously;
/// use `@Order` on the method to order them.
///
/// ```dart
/// bool isBigOrder(OrderPlaced order) => order.total >= 100;
///
/// @Component()
/// class Shipping {
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
  /// Creates the annotation; every argument is optional.
  const EventListener({this.classes = const [], this.condition, this.id});

  /// Event types handled by the method.
  final List<Type> classes;

  /// A `bool Function(E event)` top-level or static function; the listener
  /// runs only when it returns `true`.
  final Function? condition;

  /// Listener id; defaults to `Class.method`.
  final String? id;
}

/// Marks an annotation class whose methods the runtime looks up on beans.
///
/// There is no reflection, so the generator writes, for every bean method
/// carrying such an annotation, a `BeanMethod` in
/// `BeanDefinition.annotatedMethods`: its name, annotations and a closure
/// calling it. Starters use this to find their methods, e.g. `@Scheduled`
/// of `spring_boot_starter_scheduling`.
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
/// // A BeanPostProcessor, a lifecycle bean, ...:
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
  /// Creates the marker.
  const BeanMethodAnnotation();
}
