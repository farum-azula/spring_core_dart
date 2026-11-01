import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/schema/schema_exceptions.dart';

/// Reads the settings of one data source from an [Environment]: every key
/// is the [prefix] followed by the key below, so the settings of the
/// default data source are read with the prefix `spring.` (`spring.sql.
/// init.mode`) and those of the data source `main` of `spring.datasources`
/// with `spring.datasources.main.` (`spring.datasources.main.sql.init.
/// mode`).
final class SettingsReader {
  /// A reader of [environment] for the keys that start with [prefix]; a
  /// prefix that is not empty ends with a dot.
  const SettingsReader(this.environment, this.prefix);

  /// The environment the values come from.
  final Environment environment;

  /// What each key starts with.
  final String prefix;

  /// The full name of [key].
  String name(String key) => '$prefix$key';

  /// The value of [key], null when it is not set or empty.
  String? string(String key) {
    final value = environment.getProperty(name(key));
    return value == null || value.trim().isEmpty ? null : value.trim();
  }

  /// The value of [key] as given, spaces kept, null when it is not set;
  /// for a separator or a placeholder, where a space may be meant.
  String? raw(String key) => environment.getProperty(name(key));

  /// The boolean [key]; [fallback] when it is not set.
  bool boolean(String key, {required bool fallback}) {
    final value = string(key);
    if (value == null) {
      return fallback;
    }
    return switch (value.toLowerCase()) {
      'true' => true,
      'false' => false,
      _ => throw SchemaException(
        "The property ${name(key)} must be true or false, not '$value'",
      ),
    };
  }

  /// The whole number [key]; [fallback] when it is not set.
  int integer(String key, {required int fallback}) {
    final value = string(key);
    if (value == null) {
      return fallback;
    }
    return int.tryParse(value) ??
        (throw SchemaException(
          "The property ${name(key)} must be a number, not '$value'",
        ));
  }

  /// The comma-separated list [key], empty when it is not set.
  List<String> list(String key) => [
    for (final part in (string(key) ?? '').split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  /// The duration [key], written `500ms`, `10s`, `2m`, `1h` or a number of
  /// seconds; [fallback] when it is not set.
  Duration duration(String key, {required Duration fallback}) {
    final value = string(key);
    if (value == null) {
      return fallback;
    }
    final match = RegExp(
      r'^(\d+)\s*(ms|s|m|h)?$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) {
      throw SchemaException(
        'The property ${name(key)} must be a duration such as 500ms, 10s '
        "or 2m, not '$value'",
      );
    }
    final amount = int.parse(match.group(1)!);
    return switch (match.group(2)?.toLowerCase()) {
      'ms' => Duration(milliseconds: amount),
      'm' => Duration(minutes: amount),
      'h' => Duration(hours: amount),
      _ => Duration(seconds: amount),
    };
  }

  /// The properties below `<prefix><key>.`, by the rest of their name
  /// (`placeholders.env=prod` read with the key `placeholders` gives
  /// `{env: prod}`); needs an environment that lists its properties.
  Map<String, String> subProperties(String key) {
    final start = '${name(key)}.';
    final found = <String, String>{};
    final env = environment;
    if (env is! ConfigurableEnvironment) {
      return found;
    }
    // The first source that has a name wins, as in the environment.
    for (final source in env.propertySources) {
      if (source is! EnumerablePropertySource<Object>) {
        continue;
      }
      for (final property in source.propertyNames) {
        if (property.startsWith(start) && property.length > start.length) {
          final rest = property.substring(start.length);
          if (!found.containsKey(rest)) {
            final value = environment.getProperty(property);
            if (value != null) {
              found[rest] = value;
            }
          }
        }
      }
    }
    return found;
  }
}

/// A resolver of resource patterns over [loader]: [loader] itself when it
/// is one, else the one that lists the classpath and the files with it.
ResourcePatternResolver patternResolverOf(ResourceLoader? loader) =>
    loader is ResourcePatternResolver
    ? loader
    : PathMatchingResourcePatternResolver(resourceLoader: loader);

/// Runs [action] on a connection of [dataSource] and gives it back, also
/// when [action] fails.
Future<T> withConnection<T>(
  DataSource dataSource,
  Future<T> Function(JdbcConnection connection) action,
) async {
  final connection = await dataSource.getConnection();
  try {
    return await action(connection);
  } finally {
    await dataSource.releaseConnection(connection);
  }
}
