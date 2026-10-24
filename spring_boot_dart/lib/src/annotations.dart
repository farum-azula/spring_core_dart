import 'package:spring_core_dart/spring_core_dart.dart';

/// Marks the application's `main` function, like Spring Boot's
/// `@SpringBootApplication`.
///
/// `spring_core_dart_generator` scans the whole package (`lib/` and the
/// directory of `main`) and writes `main.spring.dart` next to it, with the
/// beans and a `runApplication(args)` function:
///
/// ```dart
/// import 'main.spring.dart';
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
/// [exclude] / [excludeName] switch auto-configurations off, like Boot's:
/// by class (`exclude: [CacheAutoConfiguration]`, an `@AutoConfiguration`
/// class) or by the name of the class or of the module
/// (`excludeName: ['springBootStarterCacheAutoConfiguration']`); the
/// property `spring.autoconfigure.exclude` (comma-separated) adds more. An
/// excluded auto-configuration is removed before its conditions run.
class SpringBootApplication {
  /// Marks the annotated `main` function.
  const SpringBootApplication({
    this.exclude = const [],
    this.excludeName = const [],
  });

  /// Auto-configuration classes to exclude.
  final List<Type> exclude;

  /// Names of auto-configuration classes or modules to exclude.
  final List<String> excludeName;
}

/// Binds the properties under [prefix] to the annotated class, like Spring
/// Boot's `@ConfigurationProperties`.
///
/// The class becomes a bean and gets introspection metadata (no separate
/// `@Component` / `@Introspected` needed). Property `maxSize` is read from
/// `prefix.max-size` in any relaxed form (`prefix.maxSize`,
/// `prefix.max_size`, the environment variable `PREFIX_MAXSIZE`), from the
/// first property source that has it. Values are converted to the field
/// types; lists and sets bind from comma lists or indexed keys
/// (`prefix.hosts[0]`, YAML lists, `PREFIX_HOSTS_0_`), maps from the keys
/// below them (`prefix.headers.x-a`, `prefix.headers[x.y]`), nested
/// `@Introspected` objects from `prefix.nested.*` — also inside lists and
/// maps (`prefix.servers[0].name`, `prefix.backends.eu.url`). A list from a
/// higher-precedence source replaces the whole list; map entries are
/// merged per key (see `Binder`).
///
/// Mutable classes are bound through their setters:
///
/// ```dart
/// @ConfigurationProperties('db')
/// @Validated()
/// class DbProperties {
///   @NotBlank()
///   String url = '';
///   int maxSize = 10;
///   Duration timeout = const Duration(seconds: 5);
///   List<String> hosts = [];
/// }
/// ```
///
/// A class whose only constructor has parameters is bound through that
/// constructor (constructor binding): a parameter without a property takes
/// its [DefaultValue], else its Dart default value, else `null` when it is
/// nullable; otherwise the start fails naming the property.
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
/// With `@Validated()` on the class the constraint annotations
/// (`@NotBlank`, `@Min`, ...) are checked after binding, as in Spring Boot.
///
/// Spring (Java):
/// ```java
/// @ConfigurationProperties("db") @Validated
/// public class DbProperties { String url; int maxSize = 10; Duration timeout; }
///
/// @ConfigurationProperties("db")
/// public record DbProperties(String url, @DefaultValue("10") int maxSize) {}
/// ```
class ConfigurationProperties extends Component implements Introspected {
  /// Binds the properties under [prefix]; [name] overrides the bean name.
  const ConfigurationProperties(this.prefix, {String? name}) : super(name);

  /// Property prefix in canonical form (lower case, `-` between words),
  /// e.g. `db` for `db.url` or `my-app`.
  final String prefix;

  /// No extra classes to introspect (see `Introspected.classes`).
  @override
  List<Type> get classes => const [];
}

/// The value a constructor-bound `@ConfigurationProperties` parameter
/// takes when its property is not set, like Spring Boot's `@DefaultValue`:
/// a `String` (converted like a property value), a `List<String>` for
/// collections, or nothing — an empty collection, or a nested object
/// created with its own defaults.
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
/// A Dart default value (`{this.port = 8080}`) works the same.
///
/// Spring (Java):
/// ```java
/// public record AppProperties(@DefaultValue("8080") int port,
///     @DefaultValue({"a", "b"}) List<String> hosts, @DefaultValue Pool pool) {}
/// ```
class DefaultValue {
  /// The default: a `String`, a `List<String>` or nothing.
  const DefaultValue([this.value = const <String>[]]);

  /// The default value(s), converted like a property value.
  final Object value;
}

/// A configuration class provided by a library ("starter"), like Spring
/// Boot's `@AutoConfiguration`.
///
/// Auto-configuration modules are registered after the application's own
/// beans (see `SpringApplication.autoConfigurations`), so conditions such as
/// [ConditionalOnMissingBean] back off when the application declares its own
/// bean. Like Boot's, its `@Bean` methods are not intercepted
/// (`proxyBeanMethods: false`): take other beans as method parameters.
class AutoConfiguration extends Configuration {
  /// Marks an auto-configuration class.
  const AutoConfiguration([String? name])
    : super(name: name, proxyBeanMethods: false);
}

/// Marks a top-level `BeanModule` of a library as its auto-configuration,
/// like Spring Boot's `META-INF/spring/...AutoConfiguration.imports`.
///
/// Put it in `lib/spring_auto_configuration.dart` of the library (the
/// "starter"); the generator of every application that depends on the
/// library (directly or transitively) finds it and passes it to
/// `SpringApplication` as an auto-configuration — nothing to list by hand.
///
/// Registration order is Boot's `AutoConfigurationSorter`: by module name,
/// then by [order] (`@AutoConfigureOrder`; lower values first), then by the
/// [before] / [after] constraints (`@AutoConfiguration(before:, after:)`);
/// a cycle fails the start. A module is named like its `BeanModule` (by
/// convention the variable); an `@AutoConfiguration` class inside it can be
/// named too.
///
/// ```dart
/// // lib/spring_auto_configuration.dart of package `neon_cache`
/// @AutoConfigurationModule()
/// final BeanModule neonCacheAutoConfiguration = $neonCacheBeans;
/// ```
///
/// [requires] is the range of `spring_boot_dart` versions the starter works
/// with (pub syntax: `^0.4.0`, `'>=0.4.0 <0.6.0'`). The generator checks it
/// against the Boot version in use and stops the build with an explanation
/// when they don't match — the job Spring Boot's BOM and Spring Cloud's
/// compatibility verifier do in Java.
///
/// ```dart
/// @AutoConfigurationModule(requires: '^0.4.0')
/// final BeanModule neonCacheAutoConfiguration = $neonCacheBeans;
/// ```
class AutoConfigurationModule {
  /// Marks the annotated module variable.
  const AutoConfigurationModule({
    this.order = 0,
    this.requires,
    this.before = const [],
    this.after = const [],
  });

  /// Registration order among auto-configuration modules (before the
  /// constraints), like `@AutoConfigureOrder`.
  final int order;

  /// Modules (or `@AutoConfiguration` classes) registered after this one.
  final List<String> before;

  /// Modules (or `@AutoConfiguration` classes) registered before this one.
  final List<String> after;

  /// Compatible `spring_boot_dart` versions; `null` means any.
  final String? requires;
}

/// The property a `@ConfigurationProperties` field or constructor parameter
/// is bound from, when its Dart name cannot be used, like Spring Boot's
/// `@Name` (the value is read in dashed form).
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
  /// Binds from the property [value].
  const Name(this.value);

  /// The property name (one element, e.g. `import` or `max-size`).
  final String value;
}

/// The unit of a `Duration` property written as a plain number, like Spring
/// Boot's `@DurationUnit` (milliseconds otherwise). Values with a unit
/// (`10s`) or in ISO-8601 (`PT10S`) are not affected.
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
  /// Plain numbers are in [value].
  const DurationUnit(this.value);

  /// The unit of plain numbers.
  final ChronoUnit value;
}

/// The unit of a `DataSize` property written as a plain number, like
/// Spring Boot's `@DataSizeUnit` (bytes otherwise).
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
  /// Plain numbers are in [value].
  const DataSizeUnit(this.value);

  /// The unit of plain numbers.
  final DataUnit value;
}
