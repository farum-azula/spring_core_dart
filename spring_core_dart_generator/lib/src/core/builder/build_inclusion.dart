// Whether code is in the build, by a property of the application's
// configuration read when the generator runs: an auto-configuration module
// with `AutoConfigurationModule(build: AutoConfigurationBuild(...))`, and a
// package's part of the module build with `PackageGeneration.build`. Both
// read the property here, so they decide alike and say the same.
import 'dart:convert';

import 'package:build/build.dart' show log;
import 'package:path/path.dart' as p;
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/builder/build_environment.dart';
import 'package:yaml/yaml.dart';

/// Where code decided by a build key goes: in every build, in debug and
/// profile builds only, or in none. The generator's side of
/// `BuildInclusion` (`spring_boot_dart`), whose values it mirrors.
enum BuildInclusion {
  /// In every build.
  always,

  /// In debug and profile builds; a release build compiles it away
  /// ([notInReleaseCondition]), so it ships none of its code.
  notInRelease,

  /// In no build: the generator writes none of its code.
  never,
}

/// The constant the code of a debug and profile build only is under: a
/// release build (`dart.vm.product`) compiles it away, with everything
/// only that code reaches.
const notInReleaseCondition = "!const bool.fromEnvironment('dart.vm.product')";

/// The build keys of one build against the application's configuration:
/// `application.yml` and `application.properties` without a profile, read
/// once, when a key is first asked for (a build without keys does not
/// read it at all).
///
/// ```dart
/// final keys = BuildKeys(() => configuration);
/// keys.decide(
///   'spring.flutter.debug.enabled',
///   whenMissing: BuildInclusion.notInRelease,
///   subject: 'spring_boot_starter_flutter.debugAutoConfiguration',
/// ); // BuildInclusion.never with `enabled: false`
/// ```
final class BuildKeys {
  /// The keys read from the configuration files [files] gives (their text
  /// by path below `lib/resources/`), when a key is first asked for: the
  /// files the application has by then.
  BuildKeys(Map<String, String> Function() files) : _files = files;

  final Map<String, String> Function() _files;

  /// The configuration files, by path below `lib/resources/`.
  late final Map<String, String> configuration = _files();

  String? Function(String key)? _lookup;

  /// The value of [key] in the configuration without a profile, trimmed
  /// and in lower case; `null` when it is not set. Throws what the reading
  /// of the configuration throws (a placeholder without a default, a file
  /// that does not parse).
  String? property(String key) {
    _lookup ??= readPlatformEnvironment(
      configuration,
      profiles: const [],
    ).getProperty;
    return _lookup!(key)?.trim().toLowerCase();
  }

  /// Where the code [key] decides goes: `true` in every build, `false` in
  /// none, not set (or neither) as [whenMissing] says. [subject] names
  /// what is decided in the messages (`package.variable` for a module) and
  /// [noun] says what it is (`module`).
  ///
  /// A key the build cannot read fails the build; one set only in a
  /// profile's file, which the build does not read, and a value other than
  /// `true` or `false` are warned about.
  BuildInclusion decide(
    String key, {
    required BuildInclusion whenMissing,
    required String subject,
    String noun = 'module',
  }) {
    final String? value;
    try {
      value = property(key);
    } on Object catch (error) {
      throw InvalidGenerationSourceError(
        '$subject: the build reads $key to decide whether the $noun is '
        'built, and could not: $error',
        todo:
            'Give $key a value the build can read in application.yml or '
            'application.properties, or a placeholder with a default '
            r'(${FLAG:true}): '
            'environment variables and --dart-define values do not exist '
            'at build time.',
      );
    }
    switch (value) {
      case 'true':
        return BuildInclusion.always;
      case 'false':
        return BuildInclusion.never;
      case null || '':
        if (profileSetting(configuration, key) case final file?) {
          // Not set, a debug and profile build only: what the profile
          // sets has nothing to act on in a release build.
          final release = whenMissing == BuildInclusion.notInRelease
              ? ': in debug and profile builds only, so in a release build '
                    'what $file sets has no code to act on. Set $key: true '
                    'without a profile to keep the $noun in every build'
              : '';
          log.warning(
            '$subject: $key is set only in $file, which the build does not '
            'read: it decides by application.yml or application.properties '
            'without a profile. The $noun is built as when it is not '
            'set$release.',
          );
        }
        return whenMissing;
      default:
        log.warning(
          "$subject: $key is '$value', not true or false; the $noun is "
          'built as when it is not set.',
        );
        return whenMissing;
    }
  }

  /// The profile's configuration file among [files] (`application-web.yml`)
  /// that sets [key], which the build does not read; `null` when none
  /// does.
  static String? profileSetting(Map<String, String> files, String key) {
    final parts = key.split('.');
    bool sets(Object? node, List<String> rest) {
      if (rest.isEmpty) {
        return node != null;
      }
      if (node is! Map) {
        return false;
      }
      for (var i = 1; i <= rest.length; i++) {
        final name = rest.take(i).join('.');
        if (node.containsKey(name) && sets(node[name], rest.sublist(i))) {
          return true;
        }
      }
      return false;
    }

    for (final MapEntry(key: path, value: text) in files.entries) {
      final name = p.basename(path);
      if (!RegExp(r'^application-[^.]+\.(ya?ml|properties)$').hasMatch(name)) {
        continue;
      }
      try {
        final set = name.endsWith('.properties')
            ? LineSplitter.split(text).any(
                (line) => RegExp(
                  '^\\s*${RegExp.escape(key)}\\s*[=:]',
                ).hasMatch(line),
              )
            : loadYamlDocuments(text).any((doc) => sets(doc.contents, parts));
        if (set) {
          return name;
        }
      } on Object {
        continue; // the configuration's own reading reports a broken file
      }
    }
    return null;
  }
}
