import 'package:spring_core_dart/src/core/env/property_source.dart';

/// The property source over the operating system's environment variables,
/// which finds `server.port` in the variable `SERVER_PORT`.
///
/// Environment variable names cannot contain dots and are written in
/// upper case by convention, so a direct lookup would never find a
/// property. This source tries the usual spellings: `my.prop-name` also
/// matches `my_prop-name`, `my.prop_name`, `my_prop_name`, their
/// upper-case forms (`MY_PROP_NAME`) and the upper-case form without
/// dashes that Spring Boot uses (`MY_PROPNAME`).
///
/// An application does not create it: `StandardEnvironment` adds one
/// under [defaultName], which is why `SERVER_PORT=9090` works. On the web
/// the map is empty. Create one yourself only to fake variables, though
/// passing `systemEnvironment:` to `StandardEnvironment` is simpler.
///
/// ```dart
/// // In a test: a variable set as a container would set it.
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
  /// Creates a source called [name] over the variables in [source]
  /// (variable name to value).
  const SystemEnvironmentPropertySource(super.name, super.source);

  /// The name `StandardEnvironment` gives its environment variable source:
  /// `systemEnvironment`.
  static const defaultName = 'systemEnvironment';

  /// The value of the first variable whose name is one of the spellings
  /// of [name], tried in the order of [resolvePropertyName].
  @override
  Object? getProperty(String name) {
    final actual = resolvePropertyName(name);
    return actual == null ? null : source[actual];
  }

  @override
  bool containsProperty(String name) => resolvePropertyName(name) != null;

  /// The name of the variable that holds the property [name], or `null`.
  ///
  /// The exact name is tried first, then with `.`, `-` or both replaced by
  /// `_`, then all of these in upper case, then upper case without dashes.
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
