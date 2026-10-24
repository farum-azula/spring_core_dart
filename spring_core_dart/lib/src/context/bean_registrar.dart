import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/beans/scope.dart';
import 'package:spring_core_dart/src/context/bean_module.dart';
import 'package:spring_core_dart/src/core/env/environment.dart';

/// Registers beans programmatically, like Spring 7's `BeanRegistrar`.
///
/// Used through `@Import([MyRegistrar])` on a configuration class (the
/// generator creates it with its no-argument constructor when the
/// importing class is registered) or `context.register(MyRegistrar())`
/// before refresh. [register] runs while the modules are loaded, in
/// registration order (after the definitions of the importing module), so
/// it can read the environment, including `@PropertySource` files.
///
/// ```dart
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
  /// Registers beans in [registry]; [environment] is the context's.
  void register(BeanRegistry registry, Environment environment);
}

/// The registry a [BeanRegistrar] registers its beans in, like Spring 7's
/// `BeanRegistry`; see [registerBean].
abstract interface class BeanRegistry {
  /// Registers a bean of type [T] made by [supplier] and returns its name.
  ///
  /// Without reflection, the supplier is required (Spring's
  /// `Spec.supplier`); it gets the dependencies from the resolver
  /// (Spring's `SupplierContext`: `context.dependency<Clock>()`). Without
  /// a [name] the bean is named `T#0` (`T#1`, ... if taken; Spring's
  /// `uniqueBeanName`). The options follow Spring's `Spec`: [types] (the
  /// lookup types, `[T]` by default; `targetType`), [scope] (`prototype`),
  /// [lazy] (`lazyInit`), [primary], [fallback], [autowireCandidate]
  /// (`notAutowirable` when `false`), [defaultCandidate], [order],
  /// [description], plus [aliases] and [dependsOn].
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

  /// Registers [alias] for the bean [name].
  void registerAlias(String name, String alias);

  /// Runs another [registrar] on this registry.
  void register(BeanRegistrar registrar);
}

/// Selects modules to import, like Spring's `ImportSelector`.
///
/// Put the class in `@Import([...])` (it needs a no-argument constructor)
/// or pass an instance to `context.register(...)`. It may implement
/// `EnvironmentAware`, `BeanFactoryAware` and `ResourceLoaderAware`
/// (called before [selectImports]). The selected modules are loaded before
/// the definitions of the importing module, with their own conditions.
///
/// ```dart
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
  /// The modules to import.
  List<BeanModule> selectImports();
}

/// An [ImportSelector] that runs after every other module and component
/// has been loaded, like Spring's `DeferredImportSelector` (Spring Boot
/// imports its auto-configurations with one): its modules can back off
/// when the application already registered a bean. Deferred selectors run
/// in `Ordered` / `@Order` order (registration order otherwise); one
/// selected by a deferred import runs right away.
///
/// ```dart
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

/// Registers bean definitions for an `@Import`, like Spring's
/// `ImportBeanDefinitionRegistrar`.
///
/// Put the class in `@Import([...])` (it needs a no-argument constructor)
/// or pass an instance to `context.register(...)`. It may implement
/// `EnvironmentAware`, `BeanFactoryAware` and `ResourceLoaderAware`
/// (called first). Runs after the definitions of the importing module.
/// [BeanRegistrar] is the more convenient API.
///
/// ```dart
/// class AuditRegistrar implements ImportBeanDefinitionRegistrar {
///   const AuditRegistrar();
///
///   @override
///   void registerBeanDefinitions(BeanDefinitionRegistry registry) {
///     if (!registry.containsBeanDefinition('auditLog')) {
///       registry.registerBeanDefinition(
///         BeanDefinition<AuditLog>(name: 'auditLog', create: (_) => AuditLog()),
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
  /// Registers definitions in [registry].
  void registerBeanDefinitions(BeanDefinitionRegistry registry);
}
