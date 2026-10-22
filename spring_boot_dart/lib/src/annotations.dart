import 'package:spring_core_dart/spring_core_dart.dart';

/// Marks the application's `main` function, like Spring Boot's
/// `@SpringBootApplication`.
///
/// `spring_core_dart_generator` scans the whole package (`lib/` and the
/// directory of `main`) and writes `main.beans.dart` next to it, with the
/// beans and a `runApplication(args)` function:
///
/// ```dart
/// import 'main.beans.dart';
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
class SpringBootApplication {
  /// Marks the annotated `main` function.
  const SpringBootApplication();
}

/// Binds the properties under [prefix] to the annotated class, like Spring
/// Boot's `@ConfigurationProperties`.
///
/// The class becomes a bean and gets introspection metadata (no separate
/// `@Component` / `@Introspected` needed). Property `maxSize` is read from
/// `prefix.max-size` (or `prefix.maxSize`, or the environment variables
/// `PREFIX_MAX_SIZE` / `PREFIX_MAXSIZE`); nested `@Introspected` objects are
/// bound from `prefix.nested.*`. Values are converted to the field types
/// and validated with the constraint annotations (`@NotBlank`, `@Min`, ...).
///
/// ```dart
/// @ConfigurationProperties('db')
/// class DbProperties {
///   @NotBlank()
///   String url = '';
///   int maxSize = 10;
///   Duration timeout = const Duration(seconds: 5);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @ConfigurationProperties("db") @Validated
/// public class DbProperties { String url; int maxSize = 10; Duration timeout; }
/// ```
class ConfigurationProperties extends Component implements Introspected {
  /// Binds the properties under [prefix]; [name] overrides the bean name.
  const ConfigurationProperties(
    this.prefix, {
    String? name,
    this.validate = true,
  }) : super(name);

  /// Property prefix, e.g. `db` for `db.url`.
  final String prefix;

  /// Whether constraint annotations are checked after binding (Boot's
  /// `@Validated`).
  final bool validate;

  /// No extra classes to introspect (see `Introspected.classes`).
  @override
  List<Type> get classes => const [];
}

/// A configuration class provided by a library ("starter"), like Spring
/// Boot's `@AutoConfiguration`.
///
/// Auto-configuration modules are registered after the application's own
/// beans (see `SpringApplication.autoConfigurations`), so conditions such as
/// [ConditionalOnMissingBean] back off when the application declares its own
/// bean.
class AutoConfiguration extends Configuration {
  /// Marks an auto-configuration class.
  const AutoConfiguration([super.name]);
}

/// Marks a top-level `BeanModule` of a library as its auto-configuration,
/// like Spring Boot's `META-INF/spring/...AutoConfiguration.imports`.
///
/// Put it in `lib/spring_auto_configuration.dart` of the library (the
/// "starter"); the generator of every application that depends on the
/// library (directly or transitively) finds it and passes it to
/// `SpringApplication` as an auto-configuration — nothing to list by hand.
/// Lower [order] values are registered first.
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
  const AutoConfigurationModule({this.order = 0, this.requires});

  /// Registration order among auto-configuration modules.
  final int order;

  /// Compatible `spring_boot_dart` versions; `null` means any.
  final String? requires;
}
