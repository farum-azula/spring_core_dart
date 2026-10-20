import 'package:spring_core_dart/src/core/env/property_source.dart';

/// Operating-system environment variables with relaxed names, like Spring's
/// `SystemEnvironmentPropertySource`.
///
/// `my.prop-name` also matches `my_prop-name`, `my.prop_name`,
/// `my_prop_name`, their upper-case forms (`MY_PROP_NAME`) and the
/// dash-less upper-case form Spring Boot uses (`MY_PROPNAME`).
///
/// `StandardEnvironment` adds one automatically under [defaultName].
///
/// ```dart
/// final source = SystemEnvironmentPropertySource(
///   SystemEnvironmentPropertySource.defaultName,
///   {'SERVER_PORT': '9090'},
/// );
/// source.getProperty('server.port'); // '9090'
/// ```
///
/// Spring (Java):
/// ```java
/// var source = new SystemEnvironmentPropertySource(
///     StandardEnvironment.SYSTEM_ENVIRONMENT_PROPERTY_SOURCE_NAME,
///     Map.of("SERVER_PORT", "9090"));
/// source.getProperty("server.port"); // "9090"
/// ```
class SystemEnvironmentPropertySource extends MapPropertySource {
  /// Creates a source called [name] over the variables in [source].
  const SystemEnvironmentPropertySource(super.name, super.source);

  /// Default name of the system environment source.
  static const defaultName = 'systemEnvironment';

  /// Value of the first variable matching [name] in relaxed form.
  @override
  Object? getProperty(String name) {
    final actual = resolvePropertyName(name);
    return actual == null ? null : source[actual];
  }

  @override
  bool containsProperty(String name) => resolvePropertyName(name) != null;

  /// The variable name that matches [name], or `null`.
  ///
  /// ```dart
  /// source.resolvePropertyName('server.port'); // 'SERVER_PORT'
  /// ```
  String? resolvePropertyName(String name) {
    for (final candidate in _candidates(name)) {
      if (source.containsKey(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  // Candidate variable names in lookup order: exact first, then with `.`
  // and/or `-` replaced by `_`, then upper-case forms, then Spring Boot's
  // legacy form that drops dashes.
  Iterable<String> _candidates(String name) sync* {
    final variants = [
      name,
      name.replaceAll('.', '_'),
      name.replaceAll('-', '_'),
      name.replaceAll('.', '_').replaceAll('-', '_'),
    ];
    yield* variants;
    yield* variants.map((v) => v.toUpperCase());
    yield name.replaceAll('-', '').replaceAll('.', '_').toUpperCase();
  }
}
