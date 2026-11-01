import 'package:spring_boot_dart/src/environment_post_processor.dart';
import 'package:spring_boot_dart/src/spring_application.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// Stops the start when a property still has the name Spring Boot gives it
/// and this project has renamed.
///
/// Some of Spring Boot's property names carry Java history that means
/// nothing in Dart (servlet, Jackson, Spring Cloud, Logback, Flyway), so
/// the properties are named after what they configure instead. An old name
/// that is silently ignored does harm: a forgotten
/// `server.servlet.session.*` would leave the sessions on their defaults.
/// [SpringApplication] always runs this post-processor, after the config
/// files are read, so applications and starters never create or register
/// it. Every key under an old prefix, in any property source (a config
/// file, the command line, `--dart-define`, an environment variable in its
/// relaxed form such as `SPRING_JACKSON_TIME_ZONE`), makes the start fail
/// with a [RenamedPropertiesException], which the failure report explains:
///
/// ```text
/// Description:
///
/// These properties have been renamed:
///
///   - SPRING_JACKSON_TIMEZONE is now SPRING_JSON_TIMEZONE
///   - spring.jackson.default-property-inclusion is now
///     spring.json.default-property-inclusion
/// ```
///
/// The table of the renames is [renamed], the only place that lists them;
/// it also holds the prefixes of starters this package does not depend on.
/// A new name that merely looks like an old one (`spring.json.*`,
/// `server.session.*`) is not reported.
///
/// Spring (Java): `spring-boot-properties-migrator`
/// (`PropertiesMigrationListener`), which only logs a warning and keeps
/// reading the old name; here the start fails.
final class RenamedPropertiesEnvironmentPostProcessor
    implements EnvironmentPostProcessor, Ordered {
  /// The post-processor; it has no settings.
  const RenamedPropertiesEnvironmentPostProcessor();

  /// The renamed properties: the old prefix (Spring Boot's name) and the
  /// prefix that replaces it. A key is renamed when it is below the old
  /// prefix at any depth; the rest of the key stays as it is.
  ///
  /// | Spring Boot | Here |
  /// |---|---|
  /// | `spring.cloud.openfeign` | `spring.feign` |
  /// | `spring.jackson` | `spring.json` |
  /// | `spring.servlet.multipart` | `spring.web.multipart` |
  /// | `server.servlet` | `server` |
  /// | `logging.logback.rollingpolicy` | `logging.file.rolling-policy` |
  /// | `spring.flyway` | `spring.sql.migration` |
  static const Map<String, String> renamed = {
    'spring.cloud.openfeign': 'spring.feign',
    'spring.jackson': 'spring.json',
    'spring.servlet.multipart': 'spring.web.multipart',
    'server.servlet': 'server',
    'logging.logback.rollingpolicy': 'logging.file.rolling-policy',
    'spring.flyway': 'spring.sql.migration',
  };

  @override
  int get order => EnvironmentPostProcessor.configDataOrder + 10;

  @override
  void postProcessEnvironment(
    ConfigurableEnvironment environment,
    SpringApplication application,
  ) {
    final found = findRenamedProperties(environment.propertySources);
    if (found.isNotEmpty) {
      throw RenamedPropertiesException(found);
    }
  }

  /// The keys of [sources] that are under an old prefix of [renamed], each
  /// as written in its source, with the key it is now (in the same style:
  /// an environment variable stays an environment variable). Sorted by
  /// the old key.
  ///
  /// ```dart
  /// findRenamedProperties(environment.propertySources);
  /// // {'spring.jackson.time-zone': 'spring.json.time-zone'}
  /// ```
  static Map<String, String> findRenamedProperties(
    Iterable<AbstractPropertySource<Object>> sources,
  ) {
    final prefixes = [
      for (final MapEntry(:key, :value) in renamed.entries)
        (
          old: key,
          name: ConfigurationPropertyName.of(key),
          current: value,
        ),
    ];
    final found = <String, String>{};
    for (final source in sources) {
      if (source is! EnumerablePropertySource<Object>) {
        continue;
      }
      final names = ConfigurationPropertySources.propertyNames(source);
      for (final MapEntry(key: name, value: keys) in names.entries) {
        for (final prefix in prefixes) {
          if (!prefix.name.isAncestorOf(name)) {
            continue;
          }
          for (final key in keys) {
            found[key] ??= _rename(
              key,
              name,
              prefix.old,
              prefix.name,
              prefix.current,
            );
          }
        }
      }
    }
    return Map.fromEntries(
      found.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  // The new spelling of [key] (which [name] reads as a property below
  // [old]): the prefix replaced as it is written, in a canonical key or in
  // an environment variable; else the canonical spelling.
  static String _rename(
    String key,
    ConfigurationPropertyName name,
    String old,
    ConfigurationPropertyName oldName,
    String current,
  ) {
    if (key.startsWith(old) && key.length > old.length) {
      final next = key[old.length];
      if (next == '.' || next == '[') {
        return '$current${key.substring(old.length)}';
      }
    }
    final oldVariable = _variable(old);
    if (!key.contains('.') && key.toUpperCase().startsWith('${oldVariable}_')) {
      return '${_variable(current)}${key.substring(oldVariable.length)}';
    }
    final rest = StringBuffer(current);
    for (var i = oldName.numberOfElements; i < name.numberOfElements; i++) {
      final element = name.getElement(i);
      rest.write(name.isIndexed(i) ? '[$element]' : '.$element');
    }
    return '$rest';
  }

  // `logging.file.rolling-policy` as an environment variable prefix:
  // `LOGGING_FILE_ROLLINGPOLICY`.
  static String _variable(String prefix) => prefix
      .split('.')
      .map((element) => element.replaceAll('-', ''))
      .join('_')
      .toUpperCase();
}

/// The start failed because properties still have a name that was renamed
/// (see [RenamedPropertiesEnvironmentPostProcessor.renamed]).
///
/// `SpringApplication` explains it in the `APPLICATION FAILED TO START`
/// report, one line per key.
final class RenamedPropertiesException implements Exception {
  /// An error for [properties], each old key with the key it is now.
  RenamedPropertiesException(Map<String, String> properties)
    : properties = Map.unmodifiable(properties);

  /// The old keys as the sources spell them, each with its new name.
  final Map<String, String> properties;

  /// The lines of the report: `<old> is now <new>`, one per key.
  String get description => [
    for (final MapEntry(:key, :value) in properties.entries)
      '  - $key is now $value',
  ].join('\n');

  @override
  String toString() =>
      'RenamedPropertiesException: the properties below were renamed:\n'
      '$description';
}
