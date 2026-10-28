import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/beans/scope.dart';
import 'package:spring_core_dart/src/context/bean_module.dart';
import 'package:spring_core_dart/src/core/env/environment.dart';

/// Code that registers beans, written by hand instead of with annotations.
///
/// Annotations declare a fixed set of beans. A registrar decides in code:
/// how many beans, which ones, under which names, based on the
/// configuration. Use it in a library that registers one bean per
/// configured entry, or that picks an implementation from a property.
/// Most applications do not need one.
///
/// Put the class in `@Import([MyRegistrar])` on a configuration class (the
/// generator creates it with its no-argument constructor), or pass an
/// instance to `context.register` before the refresh. [register] runs
/// right after the importing class's `@Bean` methods are registered, and
/// only when that class is registered: its conditions, including
/// `registerBean`-phase ones such as Boot's `@ConditionalOnBean`, are
/// decided once for the class and its imports. Every later class and
/// auto-configuration sees the beans, so their
/// `@ConditionalOnMissingBean` backs off. The registrar can read the
/// environment, including the `@PropertySource` files loaded so far.
///
/// ```dart
/// // An SMTP mailer only when a mail host is configured.
/// class MessagingRegistrar implements BeanRegistrar {
///   const MessagingRegistrar();
///
///   @override
///   void register(BeanRegistry registry, Environment env) {
///     registry.registerBean<Clock>((_) => SystemClock(), name: 'clock');
///     if (env.containsProperty('mail.host')) {
///       registry.registerBean<Mailer>(
///         (context) => SmtpMailer(context.dependency<Clock>()),
///         name: 'mailer',
///         primary: true,
///         lazy: true,
///         description: 'SMTP mailer',
///       );
///     }
///   }
/// }
///
/// @Configuration()
/// @Import([MessagingRegistrar])
/// class AppConfig {}
/// ```
///
/// Spring (Java):
/// ```java
/// class MessagingRegistrar implements BeanRegistrar {
///   public void register(BeanRegistry registry, Environment env) {
///     registry.registerBean("clock", SystemClock.class);
///     if (env.containsProperty("mail.host")) {
///       registry.registerBean("mailer", Mailer.class, spec -> spec
///           .supplier(context -> new SmtpMailer(context.bean(Clock.class)))
///           .primary().lazyInit().description("SMTP mailer"));
///     }
///   }
/// }
///
/// @Configuration
/// @Import(MessagingRegistrar.class)
/// class AppConfig {}
/// ```
abstract interface class BeanRegistrar {
  /// Registers beans in [registry], deciding with the help of the
  /// context's [environment]. Called once, while the modules load; no bean
  /// exists yet.
  void register(BeanRegistry registry, Environment environment);
}

/// Where a [BeanRegistrar] registers its beans: a short API that turns
/// each call into a bean definition of the context.
///
/// A registrar receives it in [BeanRegistrar.register]; you do not create
/// one. `AnnotationConfigApplicationContext.registerBean` offers the same
/// options outside a registrar.
///
/// Spring (Java): Spring 7's `BeanRegistry`.
abstract interface class BeanRegistry {
  /// Registers a bean of type [T] created by [supplier] and returns its
  /// name.
  ///
  /// The [supplier] creates the instance when the bean is needed; it gets
  /// the bean's own dependencies from its argument
  /// (`context.dependency<Clock>()`). Dart has no reflection to call a
  /// constructor, so the supplier is required (Spring's `Spec.supplier`).
  /// Without a [name] the bean is named `T#0` (`T#1`, ... if taken, as
  /// Spring's `uniqueBeanName`).
  ///
  /// The options mean what the annotations mean, and follow Spring's
  /// `Spec`: [types] are the types the bean is found by (`[T]` by default;
  /// `targetType`), [scope] its scope (`prototype`), [lazy] creation on
  /// first use (`lazyInit`), [primary] and [fallback] as `@Primary` and
  /// `@Fallback`, [autowireCandidate] `false` keeps it out of injection by
  /// type (`notAutowirable`), [defaultCandidate] `false` injects it only
  /// where a qualifier selects it, [order] its position in collections,
  /// [description] a text for tools, [aliases] more names, and [dependsOn]
  /// beans created before it.
  String registerBean<T extends Object>(
    T Function(DependencyResolver context) supplier, {
    String? name,
    List<Type>? types,
    String scope = ScopeType.singleton,
    bool lazy = false,
    bool primary = false,
    bool fallback = false,
    bool autowireCandidate = true,
    bool defaultCandidate = true,
    int? order,
    String? description,
    List<String> aliases = const [],
    List<String> dependsOn = const [],
  });

  /// Makes the bean [name] also available as [alias].
  void registerAlias(String name, String alias);

  /// Runs another [registrar] on this registry, to compose registrars.
  void register(BeanRegistrar registrar);
}

/// Code that chooses, at startup, which modules of beans to add.
///
/// Use it when a whole group of beans depends on the configuration, for
/// example S3 storage or disk storage depending on a property. Each
/// alternative is a [BeanModule] (a `@ComponentScan` of its own
/// directory), and the selector returns the ones to load. Most
/// applications use `@Profile` or conditions instead.
///
/// Put the class in `@Import([...])` (it needs a no-argument constructor)
/// or pass an instance to `context.register(...)`. It may implement
/// `EnvironmentAware`, `BeanFactoryAware` and `ResourceLoaderAware`; those
/// are called before [selectImports]. It runs while the importing class is
/// parsed, once that class's parse-phase conditions have matched. The
/// selected modules are parsed at once, and their classes are read before
/// the importing class, with their own conditions. They are not registered
/// when the importing class is skipped in the `registerBean` phase, unless
/// another kept class imports them too.
///
/// ```dart
/// // The storage beans follow the `storage` property.
/// class StorageSelector implements ImportSelector, EnvironmentAware {
///   late Environment _environment;
///
///   @override
///   void setEnvironment(Environment environment) =>
///       _environment = environment;
///
///   @override
///   List<BeanModule> selectImports() =>
///       _environment.getProperty('storage') == 's3' ? [s3Beans] : [diskBeans];
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class StorageSelector implements ImportSelector, EnvironmentAware {
///   public String[] selectImports(AnnotationMetadata metadata) {
///     return new String[] {"s3".equals(env.getProperty("storage"))
///         ? S3Config.class.getName() : DiskConfig.class.getName()};
///   }
/// }
/// ```
///
/// Unlike Spring it returns modules (there is no class loading by name)
/// and gets no annotation metadata of the importing class.
abstract interface class ImportSelector {
  /// Returns the modules to load; an empty list adds nothing.
  List<BeanModule> selectImports();
}

/// An [ImportSelector] that runs after every other module and component
/// has been loaded.
///
/// Because it runs last, the modules it returns can back off when the
/// application already declared a bean (`@ConditionalOnMissingBean`).
/// This is how defaults are provided that an application can replace;
/// Spring Boot imports its auto-configurations this way. Deferred
/// selectors run in `Ordered` / `@Order` order, registration order
/// otherwise; a deferred selector imported by a deferred selector runs
/// right away.
///
/// ```dart
/// // A default clock module, loaded after the application's beans.
/// class DefaultsSelector implements DeferredImportSelector, Ordered {
///   const DefaultsSelector();
///
///   @override
///   int get order => Ordered.lowestPrecedence;
///
///   @override
///   List<BeanModule> selectImports() => [defaultClockModule];
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class DefaultsSelector implements DeferredImportSelector, Ordered {
///   public String[] selectImports(AnnotationMetadata metadata) {
///     return new String[] {DefaultClockConfig.class.getName()};
///   }
/// }
/// ```
abstract interface class DeferredImportSelector implements ImportSelector {}

/// Code that registers full bean definitions, with access to the ones
/// already registered.
///
/// It is the older, lower-level form of [BeanRegistrar]: it works with
/// `BeanDefinition` objects and the `BeanDefinitionRegistry`, so it can
/// look at, replace or remove definitions. Prefer [BeanRegistrar] unless
/// you need that.
///
/// Put the class in `@Import([...])` (it needs a no-argument constructor)
/// or pass an instance to `context.register(...)`. It may implement
/// `EnvironmentAware`, `BeanFactoryAware` and `ResourceLoaderAware`; those
/// are called first. It runs at the same moment as a [BeanRegistrar]:
/// right after the importing class's `@Bean` methods are registered, and
/// only when that class is.
///
/// ```dart
/// // An audit log unless the application declared its own.
/// class AuditRegistrar implements ImportBeanDefinitionRegistrar {
///   const AuditRegistrar();
///
///   @override
///   void registerBeanDefinitions(BeanDefinitionRegistry registry) {
///     if (!registry.containsBeanDefinition('auditLog')) {
///       registry.registerBeanDefinition(
///         BeanDefinition<AuditLog>(
///           name: 'auditLog',
///           create: (_) => AuditLog(),
///         ),
///       );
///     }
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class AuditRegistrar implements ImportBeanDefinitionRegistrar {
///   public void registerBeanDefinitions(AnnotationMetadata metadata,
///       BeanDefinitionRegistry registry) {
///     registry.registerBeanDefinition("auditLog",
///         new RootBeanDefinition(AuditLog.class));
///   }
/// }
/// ```
abstract interface class ImportBeanDefinitionRegistrar {
  /// Registers bean definitions in [registry], which also answers what
  /// is registered so far. Called once, while the modules load.
  void registerBeanDefinitions(BeanDefinitionRegistry registry);
}
