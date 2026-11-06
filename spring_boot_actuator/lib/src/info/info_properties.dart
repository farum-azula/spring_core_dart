import 'dart:convert';

import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Key-value information about the application, read from a properties
/// file whose keys share a prefix (`build.`, `git.`), kept without it.
///
/// Spring Boot (Java): `InfoProperties`.
class InfoProperties extends Iterable<MapEntry<String, String>> {
  /// The information of [entries] (keys without the prefix).
  InfoProperties(Map<String, String> entries)
    : _entries = Map.unmodifiable(entries);

  final Map<String, String> _entries;

  /// The value of [key] (without the prefix), or `null`.
  String? get(String key) => _entries[key];

  /// The time of [key]: an ISO-8601 instant, or milliseconds since the
  /// epoch; `null` when it is missing or unreadable.
  DateTime? getInstant(String key) => parseInstant(get(key));

  @override
  Iterator<MapEntry<String, String>> get iterator => _entries.entries.iterator;

  /// [value] as a time: an ISO-8601 instant (`2026-11-05T09:12:44Z`,
  /// `2026-11-05T10:12:44+0100`) or milliseconds since the epoch; `null`
  /// when it is neither.
  static DateTime? parseInstant(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final text = value.trim();
    if (int.tryParse(text) case final millis?) {
      return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    }
    return DateTime.tryParse(text)?.toUtc();
  }

  /// [time] as Java's `Instant.toString()` writes it, as Spring Boot's
  /// JSON shows it: `2026-11-05T09:12:44Z`, with milliseconds only when
  /// there are some.
  static String instantText(DateTime time) {
    final utc = time.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final fraction = utc.millisecond == 0 && utc.microsecond == 0
        ? ''
        : utc.microsecond == 0
        ? '.${utc.millisecond.toString().padLeft(3, '0')}'
        : '.${utc.millisecond.toString().padLeft(3, '0')}'
              '${utc.microsecond.toString().padLeft(3, '0')}';
    return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-'
        '${two(utc.day)}T${two(utc.hour)}:${two(utc.minute)}:'
        '${two(utc.second)}${fraction}Z';
  }

  /// The entries of [properties] whose keys start with [prefix] and a dot,
  /// without it.
  static Map<String, String> withoutPrefix(
    Map<String, String> properties,
    String prefix,
  ) => {
    for (final MapEntry(:key, :value) in properties.entries)
      if (key.startsWith('$prefix.')) key.substring(prefix.length + 1): value,
  };
}

/// What the build wrote about the application: `build.name`,
/// `build.version`, `build.time`, `build.group`, `build.artifact` and any
/// other `build.*` key, from `resources:build-info.properties`
/// (`spring.info.build.location`).
///
/// The actuator starter declares it as a bean when the file exists, so
/// the application can show its version:
///
/// ```dart
/// final version = context.getBean<BuildProperties>().version;
/// ```
///
/// Spring Boot (Java): `BuildProperties`, from
/// `META-INF/build-info.properties`.
class BuildProperties extends InfoProperties {
  /// The build information of [entries] (keys without `build.`).
  BuildProperties(super.entries);

  /// Reads [resource], a properties file with `build.*` keys, decoded
  /// with [encoding].
  static Future<BuildProperties> load(
    Resource resource, {
    Encoding encoding = utf8,
  }) async => BuildProperties(
    InfoProperties.withoutPrefix(
      await PropertiesLoaderUtils.loadProperties(resource, encoding: encoding),
      'build',
    ),
  );

  /// Reads [resource] without waiting (an embedded or a file resource).
  static BuildProperties loadSync(
    Resource resource, {
    Encoding encoding = utf8,
  }) => BuildProperties(
    InfoProperties.withoutPrefix(
      PropertiesLoaderUtils.loadPropertiesSync(resource, encoding: encoding),
      'build',
    ),
  );

  /// `build.group`.
  String? get group => get('group');

  /// `build.artifact`.
  String? get artifact => get('artifact');

  /// `build.name`.
  String? get name => get('name');

  /// `build.version`.
  String? get version => get('version');

  /// `build.time`.
  DateTime? get time => getInstant('time');
}

/// What git said about the source of the application: `git.branch`,
/// `git.commit.id`, `git.commit.time` and the other `git.*` keys, from
/// `resources:git.properties` (`spring.info.git.location`), written by
/// the build.
///
/// Spring Boot (Java): `GitProperties`.
class GitProperties extends InfoProperties {
  /// The git information of [entries] (keys without `git.`).
  GitProperties(Map<String, String> entries) : super(_coerced(entries));

  /// Reads [resource], a properties file with `git.*` keys, decoded with
  /// [encoding].
  static Future<GitProperties> load(
    Resource resource, {
    Encoding encoding = utf8,
  }) async => GitProperties(
    InfoProperties.withoutPrefix(
      await PropertiesLoaderUtils.loadProperties(resource, encoding: encoding),
      'git',
    ),
  );

  /// Reads [resource] without waiting (an embedded or a file resource).
  static GitProperties loadSync(
    Resource resource, {
    Encoding encoding = utf8,
  }) => GitProperties(
    InfoProperties.withoutPrefix(
      PropertiesLoaderUtils.loadPropertiesSync(resource, encoding: encoding),
      'git',
    ),
  );

  // git writes its times in seconds since the epoch; they are kept in
  // milliseconds, as Spring Boot's GitProperties does.
  static Map<String, String> _coerced(Map<String, String> entries) => {
    for (final MapEntry(:key, :value) in entries.entries)
      key: (key == 'commit.time' || key == 'build.time')
          ? switch (int.tryParse(value.trim())) {
              final seconds? => '${seconds * 1000}',
              null => value,
            }
          : value,
  };

  /// `git.branch`.
  String? get branch => get('branch');

  /// `git.commit.id`.
  String? get commitId => get('commit.id');

  /// `git.commit.id.abbrev`, else the first 7 characters of [commitId].
  String? get shortCommitId {
    if (get('commit.id.abbrev') case final abbrev?) {
      return abbrev;
    }
    final id = commitId;
    return id == null || id.length <= 7 ? id : id.substring(0, 7);
  }

  /// `git.commit.time`.
  DateTime? get commitTime => getInstant('commit.time');
}
