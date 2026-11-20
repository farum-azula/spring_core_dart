import 'dart:io';

/// One key of a config file, or a property a test sets for its own
/// context, with its value and the position of its key: what go to
/// definition jumps to and what a hover lists.
final class PropertyEntry {
  /// An entry for [key] whose key sits at [line], [keyStart]..[keyEnd] of
  /// [path].
  const PropertyEntry({
    required this.path,
    required this.key,
    required this.value,
    required this.line,
    required this.keyStart,
    required this.keyEnd,
    this.environment = false,
    this.provider,
    this.profile,
  });

  /// The profile expression the entry is read under, from the YAML document
  /// it is in (`spring.config.activate.on-profile: prod`, or the older
  /// `spring.profiles`); null for an entry of every profile. A file named
  /// for a profile (`application-prod.yaml`) says so with its name instead
  /// ([fileName]).
  final String? profile;

  /// For a property a `@ServiceConnection` container provides: which one,
  /// as `PostgresContainer postgres`. Hovers show it instead of a value.
  final String? provider;

  /// Whether [key] is an environment variable (`SHOP_MAX_BASKET_SIZE`, from
  /// a test's `@TestEnvironment`), matched the way Spring maps property
  /// names to variables.
  final bool environment;

  /// The file that defines the entry.
  final String path;

  /// The key as written in a properties file, or flattened from YAML
  /// (`shop.servers[0].host`).
  final String key;

  /// The value as text, trimmed, with the continuation lines of a properties
  /// file joined. For a property of a test, the source of the value
  /// expression.
  final String value;

  /// The zero-based line of the key.
  final int line;

  /// The zero-based column where the key starts, in UTF-16 units.
  final int keyStart;

  /// The column just after the key.
  final int keyEnd;

  /// This entry, read under the profile expression [profile].
  PropertyEntry withProfile(String profile) => PropertyEntry(
    path: path,
    key: key,
    value: value,
    line: line,
    keyStart: keyStart,
    keyEnd: keyEnd,
    environment: environment,
    provider: provider,
    profile: profile,
  );

  /// The file's name without directory and extension: `application-prod`
  /// for `.../application-prod.properties` (or `.yml`, `.yaml`). Hovers show
  /// it, and `application` files sort first.
  String get fileName {
    final name = path.split(Platform.pathSeparator).last;
    for (final extension in ['.properties', '.yml', '.yaml']) {
      if (name.endsWith(extension)) {
        return name.substring(0, name.length - extension.length);
      }
    }
    return name;
  }
}
