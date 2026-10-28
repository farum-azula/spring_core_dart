import 'dart:convert';

import 'package:spring_boot_dart/src/spring_application.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// Code that changes the application's properties or profiles before any
/// bean is created.
///
/// Beans cannot do this: by the time a bean exists, `@Value` and
/// `@ConfigurationProperties` of other beans may already have been read.
/// A post-processor runs while the environment is prepared, so it can add
/// property sources (secrets from a vault, settings from a server),
/// activate profiles, or add `spring.config.import` locations, and
/// everything the application reads later sees the result. Pass them to
/// `SpringApplication(environmentPostProcessors: [...])`. Most
/// applications do not need one: config files, environment variables and
/// command-line arguments cover the usual cases.
///
/// Post-processors run sorted by `Ordered` (lowest precedence when not
/// `Ordered`), in two groups around the reading of the config files. One
/// whose order is smaller than [configDataOrder] runs before the files are
/// read, so the imports, profiles and sources it sets decide which files
/// are loaded. The others run after the files are read, before
/// `ApplicationEnvironmentPreparedEvent`, and see their properties.
///
/// ```dart
/// // Runs before the config files are read, so the secret files the
/// // operators mount in ./secrets/ are imported like any config file.
/// class LocalSecrets implements EnvironmentPostProcessor, Ordered {
///   @override
///   int get order => EnvironmentPostProcessor.configDataOrder - 1;
///
///   @override
///   void postProcessEnvironment(
///     ConfigurableEnvironment environment,
///     SpringApplication application,
///   ) {
///     environment.propertySources.addLast(
///       MapPropertySource('secrets', {
///         'spring.config.import': 'optional:file:./secrets/',
///       }),
///     );
///   }
/// }
///
/// final app = SpringApplication(
///   [appBeans],
///   environmentPostProcessors: [LocalSecrets()],
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// class LocalSecrets implements EnvironmentPostProcessor, Ordered { ... }
/// // META-INF/spring.factories:
/// // org.springframework.boot.EnvironmentPostProcessor=com.example.LocalSecrets
/// ```
///
/// Spring Boot finds post-processors in `META-INF/spring.factories`; Dart
/// has no class path to scan, so they are passed to the constructor.
abstract interface class EnvironmentPostProcessor {
  /// The place of the config file reading among the post-processors
  /// (`Ordered.highestPrecedence + 10`, Spring Boot's
  /// `ConfigDataEnvironmentPostProcessor.ORDER`).
  ///
  /// Return a smaller order to run before the config files are read;
  /// anything else runs after.
  static const int configDataOrder = Ordered.highestPrecedence + 10;

  /// Changes [environment], the environment being prepared for
  /// [application].
  ///
  /// Called once per run. [application] gives access to settings such as
  /// [SpringApplication.additionalProfiles]. An error thrown here fails the
  /// start with the usual failure report.
  void postProcessEnvironment(
    ConfigurableEnvironment environment,
    SpringApplication application,
  );
}

/// Reads properties given as one JSON document, in the
/// `SPRING_APPLICATION_JSON` environment variable or the
/// `spring.application.json` property.
///
/// Some platforms make it easier to pass one JSON value than many
/// separate variables. [SpringApplication] always runs this
/// post-processor, before the config files are read, so applications
/// never create it; they only set the variable.
///
/// Nested objects become dotted names and arrays indexed names:
/// `{"app": {"hosts": ["a"]}}` is `app.hosts[0]=a`. The resulting property
/// source goes right above the OS environment variables, below the
/// command line and the `--dart-define` values. The JSON comes from the
/// first property source that has either name. JSON that cannot be parsed,
/// or that is not an object, fails the start with a `StateError`.
///
/// ```shell
/// SPRING_APPLICATION_JSON='{"server":{"port":9090}}' dart run
/// dart run bin/main.dart --spring.application.json='{"app":{"hosts":["a","b"]}}'
/// ```
///
/// Spring (Java): `SpringApplicationJsonEnvironmentPostProcessor`, with
/// the same names.
final class SpringApplicationJsonEnvironmentPostProcessor
    implements EnvironmentPostProcessor, Ordered {
  /// The post-processor; it has no settings.
  const SpringApplicationJsonEnvironmentPostProcessor();

  /// The property that can hold the JSON, `spring.application.json`.
  static const springApplicationJsonProperty = 'spring.application.json';

  /// The environment variable that can hold the JSON,
  /// `SPRING_APPLICATION_JSON`.
  static const springApplicationJsonEnvironmentVariable =
      'SPRING_APPLICATION_JSON';

  /// The name of the property source the JSON properties are put in.
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
