import 'package:spring_boot_actuator/src/info/info.dart';
import 'package:spring_boot_actuator/src/info/info_properties.dart';
import 'package:spring_boot_actuator/src/info/platform_info_stub.dart'
    if (dart.library.io) 'package:spring_boot_actuator/src/info/platform_info_io.dart'
    as platform;
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// How much of a properties file an info contributor shows.
///
/// Spring Boot (Java): `InfoPropertiesInfoContributor.Mode`.
enum InfoPropertiesMode {
  /// A summary (for git: the branch, the short commit id and its time).
  simple,

  /// Every key.
  full,
}

/// [entries] as nested maps, split at the dots of their keys
/// (`commit.id` is `{"commit": {"id": ...}}`), as Spring Boot's binder
/// makes of them. Where a key is both a value and a prefix (`commit.id`
/// and `commit.id.abbrev`), the value is kept under `full` next to the
/// longer keys.
Map<String, Object?> nestedInfo(Iterable<MapEntry<String, Object?>> entries) {
  final root = <String, Object?>{};
  for (final MapEntry(:key, :value) in entries) {
    final parts = key.split('.');
    var node = root;
    for (final part in parts.take(parts.length - 1)) {
      node = switch (node[part]) {
        final Map<String, Object?> map => map,
        null => node[part] = <String, Object?>{},
        final scalar => node[part] = <String, Object?>{'full': scalar},
      };
    }
    final last = parts.last;
    if (node[last] case final Map<String, Object?> map) {
      map['full'] = value;
    } else {
      node[last] = value;
    }
  }
  return root;
}

/// The `build` details of the `info` endpoint: every key of
/// `build-info.properties`, the time as an ISO-8601 instant.
///
/// ```json
/// {"build": {"artifact": "shop", "name": "shop", "version": "1.4.0",
///   "time": "2026-11-05T09:12:44Z", "group": "com.example"}}
/// ```
///
/// Spring Boot (Java): `BuildInfoContributor`.
class BuildInfoContributor implements InfoContributor {
  /// The contributor of [properties].
  BuildInfoContributor(this.properties);

  /// The build's information.
  final BuildProperties properties;

  @override
  void contribute(InfoBuilder builder) {
    final content = nestedInfo([
      for (final entry in properties)
        if (entry.key == 'time')
          MapEntry(
            'time',
            switch (properties.time) {
              final time? => InfoProperties.instantText(time),
              null => entry.value,
            },
          )
        else
          entry,
    ]);
    if (content.isNotEmpty) {
      builder.withDetail('build', content);
    }
  }
}

/// The `git` details of the `info` endpoint: with
/// `management.info.git.mode=simple` (the default) the branch, the short
/// commit id and the commit time; with `full` every key of
/// `git.properties`.
///
/// ```json
/// {"git": {"branch": "main",
///   "commit": {"id": "4faa522", "time": "2026-11-04T18:02:11Z"}}}
/// ```
///
/// Spring Boot (Java): `GitInfoContributor`.
class GitInfoContributor implements InfoContributor {
  /// The contributor of [properties] in [mode].
  GitInfoContributor(this.properties, {this.mode = InfoPropertiesMode.simple});

  /// The git information.
  final GitProperties properties;

  /// How much is shown.
  final InfoPropertiesMode mode;

  @override
  void contribute(InfoBuilder builder) {
    final entries = switch (mode) {
      InfoPropertiesMode.simple => <MapEntry<String, Object?>>[
        if (properties.branch case final branch?) MapEntry('branch', branch),
        if (properties.shortCommitId case final id?) MapEntry('commit.id', id),
        if (properties.get('commit.time') case final time?)
          MapEntry('commit.time', time),
      ],
      InfoPropertiesMode.full => [...properties],
    };
    final content = nestedInfo([
      for (final MapEntry(:key, :value) in entries)
        if (key == 'commit.time' || key == 'build.time')
          MapEntry(key, switch (properties.getInstant(key)) {
            final time? => InfoProperties.instantText(time),
            null => value,
          })
        else
          MapEntry(key, value),
    ]);
    if (content.isNotEmpty) {
      builder.withDetail('git', content);
    }
  }
}

/// The details of the `info.*` properties, without the prefix
/// (`info.app.name=shop` shows `{"app": {"name": "shop"}}`). Off by
/// default since Spring Boot 2.6: `management.info.env.enabled=true`.
///
/// ```properties
/// management.info.env.enabled=true
/// info.app.name=shop
/// info.app.owner=team-books
/// ```
///
/// Spring Boot (Java): `EnvironmentInfoContributor`.
class EnvironmentInfoContributor implements InfoContributor {
  /// The contributor of [environment]'s `info.*` properties.
  EnvironmentInfoContributor(this.environment);

  /// Where the properties come from.
  final ConfigurableEnvironment environment;

  @override
  void contribute(InfoBuilder builder) {
    final keys = <String>{
      for (final source in environment.propertySources)
        if (source is EnumerablePropertySource<Object>)
          for (final name in source.propertyNames)
            if (name.startsWith('info.') && name.length > 5) name,
    };
    final entries = [
      for (final key in keys.toList()..sort())
        if (environment.getProperty(key) case final value?)
          MapEntry<String, Object?>(key.substring(5), value),
    ];
    builder.withDetails(nestedInfo(entries));
  }
}

/// The `os` details: the operating system's name, version and
/// architecture. Off by default: `management.info.os.enabled=true`.
///
/// ```json
/// {"os": {"name": "linux", "version": "6.8.0-45-generic", "arch": "x64"}}
/// ```
///
/// The values are Dart's (`Platform.operatingSystem`, ...), not Java's
/// (`os.name`). Nothing on the web. Spring Boot (Java): `OsInfoContributor`.
class OsInfoContributor implements InfoContributor {
  @override
  void contribute(InfoBuilder builder) {
    if (platform.osInfo() case final info?) {
      builder.withDetail('os', info);
    }
  }
}

/// The `dart` details: the version of Dart running the application. Off
/// by default: `management.info.dart.enabled=true`.
///
/// ```json
/// {"dart": {"version": "3.13.7", "channel": "stable",
///   "runtime": {"name": "Dart VM",
///   "version": "3.13.7 (stable) (...) on \"linux_x64\""}}}
/// ```
///
/// Spring Boot (Java): `JavaInfoContributor` (`java`), renamed for Dart.
/// Nothing on the web.
class DartInfoContributor implements InfoContributor {
  @override
  void contribute(InfoBuilder builder) {
    if (platform.dartInfo() case final info?) {
      builder.withDetail('dart', info);
    }
  }
}
