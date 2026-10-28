import 'package:spring_core_dart/src/beans/bean_definition.dart';
import 'package:spring_core_dart/src/beans/default_listable_bean_factory.dart';
import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/context/bean_registrar.dart';
import 'package:spring_core_dart/src/context/condition.dart';
import 'package:spring_core_dart/src/core/env/config/property_source_factory.dart';
import 'package:spring_core_dart/src/core/io/classpath_resources.dart';

/// One `@PropertySource` annotation, recorded in a [BeanModule]: which
/// property files to add to the environment, and when.
///
/// The generator writes one per annotation. You only create one when you
/// build a module by hand, for example in a test.
///
/// ```dart
/// // A module that only adds an optional property file.
/// final module = BeanModule(
///   'settings',
///   const [],
///   propertySources: const [
///     PropertySourceDeclaration(
///       ['file:config/app.properties'],
///       ignoreResourceNotFound: true,
///     ),
///   ],
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// @Configuration
/// @PropertySource(value = "file:config/app.properties",
///     ignoreResourceNotFound = true)
/// class Settings {}
/// ```
final class PropertySourceDeclaration {
  /// Declares the property files at the resource [locations].
  const PropertySourceDeclaration(
    this.locations, {
    this.name,
    this.ignoreResourceNotFound = false,
    this.factory = const DefaultPropertySourceFactory(),
    this.conditions = const [],
    this.encoding,
  });

  /// The conditions of the declaring class; the files are loaded only
  /// when all of them match. So a `@Profile(['prod'])` class does not load
  /// its `@PropertySource` in other profiles, as in Spring.
  final List<Condition> conditions;

  /// Resource locations (`file:`, `classpath:`, patterns); may contain
  /// `${...}` placeholders.
  final List<String> locations;

  /// Name of the property source; derived from the location when `null`.
  final String? name;

  /// Whether a missing file is skipped (`true`) or fails the refresh
  /// (`false`, the default).
  final bool ignoreResourceNotFound;

  /// Turns each file into a property source; the default reads
  /// `.properties` files.
  final PropertySourceFactory factory;

  /// The charset name the files are read in (UTF-8 when `null`).
  final String? encoding;
}

/// One entry of `@Import` that names code registering beans (a
/// [BeanRegistrar], [ImportSelector] or [ImportBeanDefinitionRegistrar]),
/// recorded in [BeanModule.registrars].
///
/// The generator writes one per imported class; you only create one when
/// you build a module by hand. It tells the context how to create the
/// registrar and when to run it.
///
/// [create] calls the class's no-argument constructor while the importing
/// class is parsed, and only when the parse-phase [conditions] (those of
/// the importing class) match. Then, as in Spring's configuration class
/// parser and reader: a selector runs while the class is parsed, and the
/// classes it selects are read before the importing class; a registrar
/// runs right after the importing class's `@Bean` methods are registered,
/// so later classes see its beans. The importing class is decided once,
/// by its `registerBean`-phase conditions (such as Boot's
/// `@ConditionalOnBean`) in class order, for itself, its `@Bean` methods
/// and its imports. A skipped class runs no registrar, and the modules it
/// selects are parsed but not registered, unless a kept class selects them
/// too.
///
/// ```dart
/// // A hand-written module whose only content is a registrar.
/// final module = BeanModule(
///   'app',
///   const [],
///   registrars: [ImportDeclaration(MessagingRegistrar.new)],
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// @Configuration
/// @Import(MessagingRegistrar.class)
/// class AppConfig {}
/// ```
final class ImportDeclaration {
  /// Declares an import whose registrar or selector is made by [create].
  const ImportDeclaration(
    this.create, {
    this.conditions = const [],
    this.importer,
  });

  /// Creates the registrar or selector; called once, when it is needed.
  final Object Function() create;

  /// The conditions of the importing class; nothing is created when they
  /// do not match.
  final List<Condition> conditions;

  /// The importing class as `library#Class` (the `source` of its bean
  /// definition), which places the import among the module's classes.
  /// When `null`, the key of the [ConditionGroup] in [conditions] does.
  /// Without either, selectors run before the module's classes and
  /// registrars after them.
  final String? importer;
}

/// Everything the generator found in one scanned directory: the bean
/// definitions, plus the property files, imports and embedded resources
/// that come with them.
///
/// Dart cannot scan a program for annotated classes at runtime, so
/// `@ComponentScan` makes the generator write a module at build time, and
/// the application passes its modules to the context. A context is built
/// from a list of modules; a library ships its beans as a module of its
/// own.
///
/// You normally never construct one: annotate a top-level variable with
/// `@ComponentScan()` and pass it to the context. Write one by hand for a
/// few beans in a test or a plugin. When the context loads a module, it
/// first loads its [imports], then adds its [propertySources] to the
/// environment, then registers each definition whose conditions match and
/// runs its [registrars]. [configurers] let `autowireBean` inject
/// `@Configurable` classes, [introspections] go to the context's
/// `BeanIntrospector`, and [resources] become `classpath:` files.
///
/// ```dart
/// @ComponentScan()
/// final BeanModule appBeans = $appBeans;
///
/// final context = ApplicationContext.run([coreBeans, appBeans]);
///
/// // A hand-written module with a fixed clock, for a test:
/// final testBeans = BeanModule('testBeans', [
///   BeanDefinition<Clock>(
///     name: 'clock',
///     types: const [Clock],
///     create: (_) => FixedClock(),
///   ),
/// ]);
/// ```
///
/// Spring (Java) has no direct counterpart: a module is what classpath
/// scanning plus `@Configuration` parsing would register.
/// ```java
/// var context = new AnnotationConfigApplicationContext();
/// context.scan("com.example.app");          // ≈ appBeans
/// context.registerBean("clock", Clock.class, FixedClock::new);
/// context.refresh();
/// ```
final class BeanModule {
  /// Creates a module named [name] from [definitions]; the collections are
  /// copied into unmodifiable lists and maps.
  ///
  /// The [resources] are registered as `classpath:` files right away, so
  /// configuration files read before the context starts can find them.
  BeanModule(
    this.name,
    Iterable<BeanDefinition<Object>> definitions, {
    List<PropertySourceDeclaration> propertySources = const [],
    List<BeanModule> imports = const [],
    List<ImportDeclaration> registrars = const [],
    Map<Type, BeanConfigurer> configurers = const {},
    Map<Type, void Function(Object bean)> configurablePostConstruct = const {},
    Map<Type, void Function(Object bean)> configurablePreDestroy = const {},
    List<BeanIntrospection<Object>> introspections = const [],
    Map<String, EmbeddedResource> resources = const {},
  }) : definitions = List.unmodifiable(definitions),
       introspections = List.unmodifiable(introspections),
       propertySources = List.unmodifiable(propertySources),
       imports = List.unmodifiable(imports),
       registrars = List.unmodifiable(registrars),
       configurers = Map.unmodifiable(configurers),
       configurablePostConstruct = Map.unmodifiable(configurablePostConstruct),
       configurablePreDestroy = Map.unmodifiable(configurablePreDestroy),
       resources = Map.unmodifiable(resources) {
    // Embedded `lib/resources/` files become `classpath:` resources as soon
    // as the module exists (before config files are read).
    ClasspathResources.registerAll(resources, owner: name);
  }

  /// The files of the package's `lib/resources/`, embedded by the
  /// generator and keyed by path; they are served as `classpath:`
  /// resources (see [ClasspathResources]), which works in AOT, Flutter and
  /// the web too.
  final Map<String, EmbeddedResource> resources;

  /// The module name, by convention the name of the annotated variable;
  /// shown in logs and errors.
  final String name;

  /// The bean definitions; each is registered only if its conditions
  /// match.
  final List<BeanDefinition<Object>> definitions;

  /// The `@PropertySource` declarations of the module's classes, loaded
  /// before the module's definitions are decided, so their conditions see
  /// the properties.
  final List<PropertySourceDeclaration> propertySources;

  /// Modules loaded before this one, such as those of imported
  /// configuration classes or of nested `@ComponentScan` directories.
  final List<BeanModule> imports;

  /// The `@Import`ed `BeanRegistrar`, `ImportSelector` and
  /// `ImportBeanDefinitionRegistrar` classes. A selector's modules are read
  /// before the importing class, registrars run right after its `@Bean`
  /// methods, and all are decided with the importing class (see
  /// [ImportDeclaration]).
  final List<ImportDeclaration> registrars;

  /// The generated injectors of the `@Configurable` classes, keyed by
  /// class; `autowireBean` uses them.
  final Map<Type, BeanConfigurer> configurers;

  /// The `@PostConstruct` methods of the `@Configurable` classes, keyed by
  /// class; `initializeBean` runs them (the job of Spring's
  /// `CommonAnnotationBeanPostProcessor`).
  final Map<Type, void Function(Object bean)> configurablePostConstruct;

  /// The `@PreDestroy` methods of the `@Configurable` classes, keyed by
  /// class; `destroyBean` runs them.
  final Map<Type, void Function(Object bean)> configurablePreDestroy;

  /// The generated descriptions of the `@Introspected` classes (their
  /// properties and methods), used by data binding, validation and SpEL
  /// instead of reflection.
  final List<BeanIntrospection<Object>> introspections;

  @override
  String toString() => "BeanModule('$name', ${definitions.length} beans)";
}
