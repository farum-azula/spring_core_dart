import 'package:spring_core_dart/spring_core_dart.dart';

/// Marks the `main` function of an application, so that the generator
/// writes everything needed to start it.
///
/// This is the one annotation every application has. When
/// `dart run build_runner build` sees it, `spring_core_dart_generator`
/// scans the whole package (`lib/` and the directory of `main`) for beans
/// and writes `main.spring.dart` next to `main`. That file holds the bean
/// definitions, the files of `lib/resources/`, the auto-configuration of
/// every dependency that is a starter, and the functions that start the
/// application: `runApplication(args)`, `runApplicationAsync(args)` (which
/// waits for the runners and reads Flutter assets), and the hot reload
/// helpers. No `@ComponentScan` and no list of modules is needed.
///
/// ```dart
/// // bin/main.dart (lib/main.dart in Flutter)
/// import 'package:spring_boot_dart/spring_boot_dart.dart';
///
/// import 'main.spring.dart'; // generated
///
/// @SpringBootApplication()
/// void main(List<String> args) => runApplication(args);
/// ```
///
/// Spring (Java):
/// ```java
/// @SpringBootApplication
/// public class App {
///   public static void main(String[] args) {
///     SpringApplication.run(App.class, args);
///   }
/// }
/// ```
///
/// [exclude] and [excludeName] switch off auto-configuration that a
/// starter would add, for example to replace it completely. The property
/// `spring.autoconfigure.exclude` (a comma list or a YAML list) adds more
/// names without a rebuild. An excluded auto-configuration is removed
/// before its conditions are checked.
class SpringBootApplication {
  /// Marks `main`; both lists are empty by default.
  const SpringBootApplication({
    this.exclude = const [],
    this.excludeName = const [],
  });

  /// `@AutoConfiguration` classes whose beans are not registered, such as
  /// `[CacheAutoConfiguration]`. A type that is not an auto-configuration
  /// class fails the start.
  final List<Type> exclude;

  /// Auto-configuration to leave out, by name: the name of an
  /// `@AutoConfiguration` class (`'CacheAutoConfiguration'`), or of a
  /// whole module (`'springBootStarterCacheAutoConfiguration'`), which
  /// removes everything the starter adds. Unknown names are ignored, so a
  /// name can stay after the starter is removed.
  final List<String> excludeName;
}

/// Turns a class into a typed view of a group of settings: every field is
/// filled from the property of the same name under [prefix].
///
/// Reading settings one by one with `@Value(r'${db.url}')` spreads property
/// names and conversions over the code. With this annotation the settings
/// of one area (a database pool, an API client) live in one class with
/// typed fields and defaults, and other beans inject that class. The class
/// becomes a bean and gets introspection metadata by itself, without
/// `@Component()` or `@Introspected()`.
///
/// Field `maxSize` is read from `prefix.max-size` in any relaxed spelling
/// (`prefix.maxSize`, `prefix.max_size`, the environment variable
/// `PREFIX_MAXSIZE`), from the first property source that has it, and
/// converted to the field's type. Lists and sets bind from a comma list
/// or indexed keys (`prefix.hosts[0]`, YAML lists, `PREFIX_HOSTS_0_`),
/// maps from the keys below them (`prefix.headers.x-a`,
/// `prefix.headers[x.y]`), nested `@Introspected` objects from
/// `prefix.nested.*`, also inside lists and maps
/// (`prefix.servers[0].name`, `prefix.backends.eu.url`). A list from a
/// higher-precedence source replaces the whole list; map entries are
/// merged per key. `Binder` describes these rules in full.
///
/// A mutable class is bound through its setters:
///
/// ```dart
/// // From db.url, db.max-size, db.timeout and db.hosts.
/// @ConfigurationProperties('db')
/// @Validated()
/// class DbProperties {
///   @NotBlank()
///   String url = '';
///   int maxSize = 10;
///   Duration timeout = const Duration(seconds: 5);
///   List<String> hosts = [];
/// }
///
/// @Component()
/// class ConnectionPool {
///   ConnectionPool(this.properties); // already bound and validated
///   final DbProperties properties;
/// }
/// ```
///
/// A class whose only constructor has parameters is created through that
/// constructor instead (constructor binding), which suits immutable
/// classes. A parameter without a property takes its [DefaultValue], else
/// its Dart default value, else `null` when it is nullable; otherwise the
/// start fails naming the property.
///
/// ```dart
/// @ConfigurationProperties('db')
/// class DbProperties {
///   const DbProperties(this.url, {@DefaultValue('10') required this.maxSize,
///       this.timeout = const Duration(seconds: 5)});
///   final String url;
///   final int maxSize;
///   final Duration timeout;
/// }
/// ```
///
/// With `@Validated()` on the class, the constraint annotations
/// (`@NotBlank()`, `@Min(1)`, ...) are checked after binding, and a
/// violation fails the start with a message naming the property.
///
/// The annotation can also go on a `@Bean` method, to bind the object the
/// method returns, for example a class of another package.
///
/// Spring (Java):
/// ```java
/// @ConfigurationProperties("db") @Validated
/// public class DbProperties {
///   String url; int maxSize = 10; Duration timeout;
/// }
///
/// @ConfigurationProperties("db")
/// public record DbProperties(String url, @DefaultValue("10") int maxSize) {}
/// ```
class ConfigurationProperties extends Component implements Introspected {
  /// Binds the properties under [prefix]. [name] sets the bean name
  /// instead of the one derived from the class.
  const ConfigurationProperties(
    this.prefix, {
    String? name,
    this.ignoreInvalidFields = false,
    this.ignoreUnknownFields = true,
  }) : super(name);

  /// The common start of the property names, in canonical form (lower
  /// case, `-` between words): `db` for `db.url`, or `my-app`.
  final String prefix;

  /// Whether a value that cannot be converted is ignored, so the field
  /// keeps its default, instead of failing the start. Off by default:
  /// a typo in a value should be noticed.
  final bool ignoreInvalidFields;

  /// Whether properties under [prefix] that match no field are ignored,
  /// which is the default.
  ///
  /// Set it to `false` to catch misspelled property names: the start then
  /// fails with `The elements [db.urll] were left unbound.` OS environment
  /// variables are not checked.
  final bool ignoreUnknownFields;

  /// No other class is introspected because of this annotation: only the
  /// annotated class gets metadata (`Introspected.classes` is empty).
  @override
  List<Type> get classes => const [];
}

/// The value a constructor parameter of a `@ConfigurationProperties` class
/// takes when its property is not set.
///
/// It is written as a property value would be, so it is converted the
/// same way: `@DefaultValue('10s')` for a `Duration`. Use a `String` for
/// a single value and a `List<String>` for a collection. Without an
/// argument it gives an empty collection, or a nested object created with
/// its own defaults rather than `null`. A Dart default value
/// (`{this.port = 8080}`) does the same for values that can be `const`.
///
/// ```dart
/// @ConfigurationProperties('app')
/// class AppProperties {
///   AppProperties(
///     @DefaultValue('8080') this.port,
///     @DefaultValue(['a', 'b']) this.hosts,
///     @DefaultValue() this.pool,
///   );
///   final int port;
///   final List<String> hosts;
///   final Pool pool;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// public record AppProperties(@DefaultValue("8080") int port,
///     @DefaultValue({"a", "b"}) List<String> hosts,
///     @DefaultValue Pool pool) {}
/// ```
class DefaultValue {
  /// A default of [value]: a `String`, a `List<String>`, or nothing for an
  /// empty collection or a nested object with its own defaults.
  const DefaultValue([this.value = const <String>[]]);

  /// The default as written: a `String` or a `List<String>`, converted to
  /// the parameter's type like a property value.
  final Object value;
}

/// Marks a class of a library (a "starter") whose `@Bean` methods give
/// applications default beans, unless an application declares its own.
///
/// A library that wants to add beans to every application using it (a
/// cache, an HTTP client, a log setup) writes them as `@Bean` methods of
/// an `@AutoConfiguration` class, usually guarded by conditions such as
/// `@ConditionalOnMissingBean()`. Its module is registered after the
/// application's own beans, so the application can replace any of them
/// by declaring its own bean. Applications themselves use
/// `@Configuration()`.
///
/// Its `@Bean` methods are not intercepted (`proxyBeanMethods: false`):
/// a method that needs another bean takes it as a parameter rather than
/// calling the other method.
///
/// ```dart
/// // lib/src/cache.dart of the starter `neon_cache`
/// @AutoConfiguration()
/// class CacheAutoConfiguration {
///   @Bean()
///   @ConditionalOnMissingBean() // the application's own Cache wins
///   Cache cache(@Value(r'${neon.cache.size:100}') int size) =>
///       InMemoryCache(size);
/// }
/// ```
///
/// The module that holds the class is marked with
/// [AutoConfigurationModule].
///
/// Spring (Java):
/// ```java
/// @AutoConfiguration
/// public class CacheAutoConfiguration {
///   @Bean @ConditionalOnMissingBean
///   Cache cache(@Value("${neon.cache.size:100}") int size) {
///     return new InMemoryCache(size);
///   }
/// }
/// ```
class AutoConfiguration extends Configuration {
  /// Marks an auto-configuration class; [name] sets its bean name instead
  /// of the one derived from the class.
  const AutoConfiguration([String? name])
    : super(name: name, proxyBeanMethods: false);
}

/// Marks the module of beans a library (a "starter") adds to every
/// application that depends on it.
///
/// This is what makes a starter work without any code in the
/// application: adding the package to `pubspec.yaml` and rebuilding is
/// enough. The annotation goes on a public top-level `BeanModule` variable
/// in the library's `lib/spring_auto_configuration.dart` (the file name is
/// fixed). When an application with `@SpringBootApplication()` is built,
/// the generator walks every package it depends on, directly or not,
/// finds these modules and passes them to the generated
/// `springApplication`. They are registered after the application's own
/// beans.
///
/// ```dart
/// // lib/spring_auto_configuration.dart of package `neon_cache`
/// import 'package:spring_boot_dart/spring_boot_dart.dart';
/// import 'src/cache.spring.dart';
///
/// @AutoConfigurationModule(requires: '^0.4.0')
/// final BeanModule neonCacheAutoConfiguration = $neonCacheBeans;
/// ```
///
/// When starters depend on each other's beans, [order], [before] and
/// [after] set the order in which their modules are registered. The
/// modules are sorted by [order], then by name, then [before] and [after]
/// move them; a cycle among those fails the start. A module is named after
/// its `BeanModule` (by convention the variable name); an
/// `@AutoConfiguration` class inside it can be named too.
///
/// [requires] is the range of `spring_boot_dart` versions the starter
/// works with, in pub syntax (`^0.4.0`, `'>=0.4.0 <0.6.0'`). The generator
/// checks it against the version in use and stops the build with an
/// explanation when they do not match: the job Spring Boot's BOM and
/// Spring Cloud's compatibility verifier do in Java.
///
/// Spring (Java): the `META-INF/spring/...AutoConfiguration.imports` file
/// of a starter, plus `@AutoConfigureOrder` and
/// `@AutoConfiguration(before = ..., after = ...)`. Spring Boot reads the
/// file from the class path at startup; here the generator reads it at
/// build time, so a new starter needs a rebuild.
class AutoConfigurationModule {
  /// Marks the module variable; by default it has order `0`, no
  /// constraints and no version check.
  const AutoConfigurationModule({
    this.order = 0,
    this.requires,
    this.before = const [],
    this.after = const [],
  });

  /// The position among the auto-configuration modules, lower first;
  /// `0` by default. [before] and [after] are applied afterwards. Spring
  /// Boot's `@AutoConfigureOrder`.
  final int order;

  /// Modules, or `@AutoConfiguration` classes by their short name, that
  /// must be registered after this one, so their conditions see its beans.
  /// Unknown names are ignored.
  final List<String> before;

  /// Modules, or `@AutoConfiguration` classes by their short name, that
  /// must be registered before this one, so its conditions see their
  /// beans: `['springBootAutoConfiguration']`. Unknown names are ignored.
  final List<String> after;

  /// The `spring_boot_dart` versions this starter works with, as a pub
  /// version range; `null` (the default) accepts any version.
  final String? requires;
}

/// Gives a `@ConfigurationProperties` field or constructor parameter a
/// property name other than its Dart name.
///
/// Needed when the property name is a Dart keyword (`import`, `default`)
/// or when the field should have a clearer name than the property. The
/// value is one element of the name, turned to dashed form like a Dart
/// name (`maxSize` reads `max-size`).
///
/// ```dart
/// @ConfigurationProperties('app')
/// class AppProperties {
///   AppProperties(@Name('import') this.importSettings);
///   final String importSettings; // app.import
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// public record AppProperties(@Name("import") String importSettings) {}
/// ```
class Name {
  /// Binds the field from the property [value] under the prefix.
  const Name(this.value);

  /// The property name, one element without dots, such as `import` or
  /// `max-size`.
  final String value;
}

/// The unit of a `Duration` property written as a plain number.
///
/// A `Duration` property can be written with a unit (`30s`, `5m`) or in
/// ISO-8601 (`PT30S`). A plain number such as `60` is read as
/// milliseconds unless the field carries this annotation, which makes
/// properties that are naturally in seconds or minutes easy to write.
/// Values with a unit or in ISO-8601 are not affected.
///
/// ```dart
/// @ConfigurationProperties('app')
/// class AppProperties {
///   @DurationUnit(ChronoUnit.seconds)
///   Duration timeout = const Duration(seconds: 30); // app.timeout=60 → 60 s
/// }
/// ```
///
/// Spring (Java):
/// `@DurationUnit(ChronoUnit.SECONDS) private Duration timeout;`
class DurationUnit {
  /// Plain numbers of the field are read in [value].
  const DurationUnit(this.value);

  /// The unit a plain number is read in.
  final ChronoUnit value;
}

/// The unit of a `DataSize` property written as a plain number.
///
/// A `DataSize` property can be written with a unit (`10MB`, `512KB`). A
/// plain number such as `4` is read as bytes unless the field carries this
/// annotation. Values with a unit are not affected.
///
/// ```dart
/// @ConfigurationProperties('app')
/// class AppProperties {
///   @DataSizeUnit(DataUnit.megabytes)
///   DataSize bufferSize = DataSize.ofMegabytes(2); // app.buffer-size=4 → 4 MB
/// }
/// ```
///
/// Spring (Java):
/// `@DataSizeUnit(DataUnit.MEGABYTES) private DataSize bufferSize;`
class DataSizeUnit {
  /// Plain numbers of the field are read in [value].
  const DataSizeUnit(this.value);

  /// The unit a plain number is read in.
  final DataUnit value;
}
