import 'dart:convert';

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
  static const int configDataOrder = Ordered.highestPrecedence + 10;

  /// Post-processes [environment] of [application].
  void postProcessEnvironment(
    ConfigurableEnvironment environment,
    SpringApplication application,
  );
}

/// Adds the JSON of `spring.application.json` (or the
/// `SPRING_APPLICATION_JSON` environment variable) as a property source,
/// like Spring Boot's `SpringApplicationJsonEnvironmentPostProcessor`:
/// nested objects become `a.b`, arrays `a[0]`. The source goes below the
/// command line and above the OS environment; the first property source
/// that has either property wins. [SpringApplication] always runs it,
/// before config data.
///
/// ```shell
/// SPRING_APPLICATION_JSON='{"server":{"port":9090}}' dart run
/// dart run bin/main.dart --spring.application.json='{"app":{"hosts":["a","b"]}}'
/// ```
final class SpringApplicationJsonEnvironmentPostProcessor
    implements EnvironmentPostProcessor, Ordered {
  /// Creates the post-processor.
  const SpringApplicationJsonEnvironmentPostProcessor();

  /// The property holding the JSON.
  static const springApplicationJsonProperty = 'spring.application.json';

  /// The environment variable holding the JSON.
  static const springApplicationJsonEnvironmentVariable =
      'SPRING_APPLICATION_JSON';

  /// Name of the property source it adds.
  static const propertySourceName = 'spring.application.json';

  @override
  int get order => Ordered.highestPrecedence + 5;

  @override
  void postProcessEnvironment(
    ConfigurableEnvironment environment,
    SpringApplication application,
  ) {
    final sources = environment.propertySources;
    String? json;
    for (final source in sources) {
      if (source is ConfigurationPropertySourcesPropertySource) {
        continue;
      }
      final value =
          source.getProperty(springApplicationJsonProperty) ??
          source.getProperty(springApplicationJsonEnvironmentVariable);
      if (value != null) {
        json = '$value';
        break;
      }
    }
    if (json == null || json.trim().isEmpty) {
      return;
    }
    final Object? parsed;
    try {
      parsed = jsonDecode(json);
    } on FormatException catch (error) {
      throw StateError(
        'Cannot parse JSON of $springApplicationJsonProperty: ${error.message}',
      );
    }
    if (parsed is! Map<String, Object?>) {
      throw StateError(
        'The JSON of $springApplicationJsonProperty must be an object, was '
        '${parsed.runtimeType}',
      );
    }
    final properties = <String, Object?>{};
    void extract(String name, Object? value) {
      switch (value) {
        case final Map<String, Object?> map when map.isNotEmpty:
          map.forEach((key, value) => extract('$name.$key', value));
        case final List<Object?> list when list.isNotEmpty:
          for (final (index, item) in list.indexed) {
            extract('$name[$index]', item);
          }
        default:
          properties[name] = value;
      }
    }

    parsed.forEach(extract);
    final source = MapPropertySource(propertySourceName, properties);
    if (sources.containsSource(SystemEnvironmentPropertySource.defaultName)) {
      sources.addBefore(SystemEnvironmentPropertySource.defaultName, source);
    } else {
      sources.addFirst(source);
    }
  }
}
