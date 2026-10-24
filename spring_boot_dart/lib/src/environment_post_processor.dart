import 'package:spring_boot_dart/src/spring_application.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// Customizes the environment of a [SpringApplication] before the context
/// is created, like Spring Boot's `EnvironmentPostProcessor`: add property
/// sources, set profiles, add `spring.config.import` locations.
///
/// Passed to `SpringApplication(environmentPostProcessors: [...])` (Boot
/// finds them in `META-INF/spring.factories`; Dart has no class path to
/// scan). They run in order (`Ordered`, lowest precedence by default),
/// around config data loading like Boot's
/// `ConfigDataEnvironmentPostProcessor` ([configDataOrder]): one with a
/// smaller order runs before the config files are read, so what it sets
/// (imports, profiles, sources) is seen by config data; the others run
/// after, before `ApplicationEnvironmentPreparedEvent`.
///
/// ```dart
/// class VaultSecrets implements EnvironmentPostProcessor, Ordered {
///   @override
///   int get order => EnvironmentPostProcessor.configDataOrder - 1;
///
///   @override
///   void postProcessEnvironment(
///     ConfigurableEnvironment environment,
///     SpringApplication application,
///   ) {
///     environment.propertySources.addLast(
///       MapPropertySource('vault', {'spring.config.import': 'optional:file:./secrets/'}),
///     );
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class VaultSecrets implements EnvironmentPostProcessor, Ordered { ... }
/// // META-INF/spring.factories:
/// // org.springframework.boot.EnvironmentPostProcessor=com.example.VaultSecrets
/// ```
abstract interface class EnvironmentPostProcessor {
  /// The order of config data loading (Spring Boot's
  /// `ConfigDataEnvironmentPostProcessor.ORDER`): post-processors with a
  /// smaller order run before the config files are read.
  static const configDataOrder = Ordered.highestPrecedence + 10;

  /// Post-processes [environment] of [application].
  void postProcessEnvironment(
    ConfigurableEnvironment environment,
    SpringApplication application,
  );
}
