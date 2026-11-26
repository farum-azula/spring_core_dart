// Whether code is in the build, by a property of the application's
// configuration read when the generator runs: an auto-configuration module
// with `AutoConfigurationModule(build: AutoConfigurationBuild(...))`, and a
// package's part of the module build with `PackageGeneration.build`. Both
// read the property here, so they decide alike and say the same.
import 'dart:convert';

import 'package:analyzer/dart/constant/value.dart';
import 'package:build/build.dart' show log;
import 'package:path/path.dart' as p;
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/builder/build_environment.dart';
import 'package:yaml/yaml.dart';

/// Where code decided by a build key goes: in every build, in debug
/// builds only, or in none. The generator's side of `BuildInclusion`
/// (`spring_boot_dart`), whose values it mirrors.
enum BuildInclusion {
  /// In every build.
  always,

  /// In debug builds only; a profile or a release build compiles it away
  /// ([debugOnlyCondition]), so it ships none of its code. A profile
  /// build gets it only from a switch set to `true`.
  debugOnly,

  /// In no build: the generator writes none of its code.
  never,
}

/// The constant the code of debug builds only is under: a release build
/// (`dart.vm.product`) and a profile build (`dart.vm.profile`, Flutter's
/// `kProfileMode`) compile it away, with everything only that code
/// reaches.
const debugOnlyCondition =
    "!const bool.fromEnvironment('dart.vm.product') && "
    "!const bool.fromEnvironment('dart.vm.profile')";

/// A build switch: where code goes by [property] of the application's
/// configuration (`true`: in every build; `false`: in none; not set:
/// [whenMissing]), or, with [name], by whether the list [property] names
/// [name] or holds `*`; and only as far as every one of [parents] lets it
/// in. The generator's side of `AutoConfigurationBuild` (`spring_boot_dart`)
/// and of `PackageGeneration.build`.
///
/// ```dart
/// const BuildSwitch(
///   'spring.flutter.debug.flutter-tools.enabled',
///   parents: [BuildSwitch('spring.flutter.debug.enabled')],
/// ); // never with `spring.flutter.debug.enabled: false`
/// ```
class BuildSwitch {
  /// The switch [property]; [whenMissing] when it is not set; within
  /// [parents].
  const BuildSwitch(
    this.property, {
    this.whenMissing = BuildInclusion.debugOnly,
    this.parents = const [],
  }) : name = null;

  /// The switch by the list [property]: in when it names [name] or holds
  /// `*`, out when it is set without either, [whenMissing] when it is not
  /// set; within [parents].
  const BuildSwitch.named(
    this.property,
    String this.name, {
    required this.whenMissing,
    this.parents = const [],
  });

  /// The switch an `AutoConfigurationBuild` ([build], the value of an
  /// `AutoConfigurationModule`'s `build`) declares, its parents included.
  factory BuildSwitch.fromAnnotation(ConstantReader build) {
    final property = build.read('property').stringValue;
    final whenMissing = switch (build
        .read('whenMissing')
        .objectValue
        .variable
        ?.name) {
      'always' => BuildInclusion.always,
      'never' => BuildInclusion.never,
      _ => BuildInclusion.debugOnly,
    };
    final parents = [
      for (final parent
          in build.peek('parents')?.listValue ?? const <DartObject>[])
        BuildSwitch.fromAnnotation(ConstantReader(parent)),
    ];
    return switch (build.peek('name')) {
      final name? when !name.isNull => BuildSwitch.named(
        property,
        name.stringValue,
        whenMissing: whenMissing,
        parents: parents,
      ),
      _ => BuildSwitch(property, whenMissing: whenMissing, parents: parents),
    };
  }

  /// The property that decides.
  final String property;

  /// The item of the list [property] that lets the code in; `null`: the
  /// property is `true` or `false`.
  final String? name;

  /// Where the code goes when [property] is not set.
  final BuildInclusion whenMissing;

  /// The switches the code is inside: each must let it in too.
  final List<BuildSwitch> parents;
}

/// The narrowest of [inclusions]: in no build when one says so, else in
/// debug builds only when one says so, else in every build.
BuildInclusion narrowestInclusion(Iterable<BuildInclusion> inclusions) =>
    inclusions.contains(BuildInclusion.never)
    ? BuildInclusion.never
    : inclusions.contains(BuildInclusion.debugOnly)
    ? BuildInclusion.debugOnly
    : BuildInclusion.always;

/// The widest of [inclusions]: in every build when one says so, else in
/// debug builds only when one says so, else in none.
BuildInclusion widestInclusion(Iterable<BuildInclusion> inclusions) =>
    inclusions.contains(BuildInclusion.always)
    ? BuildInclusion.always
    : inclusions.contains(BuildInclusion.debugOnly)
    ? BuildInclusion.debugOnly
    : BuildInclusion.never;

/// The build keys of one build against the application's configuration:
/// `application.yml` and `application.properties` without a profile, read
/// once, when a key is first asked for (a build without keys does not
/// read it at all).
///
/// ```dart
/// final keys = BuildKeys(() => configuration);
/// keys.decide(
///   'spring.flutter.debug.enabled',
///   whenMissing: BuildInclusion.debugOnly,
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

  /// The value of [key] in the configuration without a profile, trimmed
  /// and in lower case; `null` when it is not set. Throws what the reading
  /// of the configuration throws (a placeholder without a default, a file
  /// that does not parse).
  String? property(String key) {
    return _lookup(key)?.trim().toLowerCase();
  }

  // The configuration without a profile, read when a key is first asked
  // for.
  late final String? Function(String key) _lookup = readPlatformEnvironment(
    baseConfiguration(configuration).files,
    profiles: const [],
  ).getProperty;

  /// The [files] the build decides by: the configuration without any
  /// profile. The profile files (`application-dev.yml`) and the documents
  /// of a file that `spring.config.activate.on-profile` limits to a profile
  /// are left out, with them what `spring.profiles.active`, `include` and
  /// groups would activate; `profileDocuments` holds those documents by a
  /// name for the warnings (`application.yml (on-profile dev)`).
  static ({Map<String, String> files, Map<String, String> profileDocuments})
  baseConfiguration(Map<String, String> files) {
    final base = <String, String>{};
    final profileDocuments = <String, String>{};
    for (final MapEntry(key: path, value: text) in files.entries) {
      final name = p.basename(path);
      if (_profileFile.hasMatch(name)) {
        continue;
      }
      final properties = name.endsWith('.properties');
      final separator = properties
          ? RegExp(r'^#---\s*$', multiLine: true)
          : RegExp(r'^---\s*$', multiLine: true);
      final documents = text.split(separator);
      final kept = <String>[];
      for (final document in documents) {
        final profile = _onProfile.firstMatch(document)?[1];
        if (profile == null) {
          kept.add(document);
        } else {
          profileDocuments['$name (on-profile ${profile.trim()})'] = document;
        }
      }
      base[path] = kept.join(properties ? '\n#---\n' : '\n---\n');
    }
    return (files: base, profileDocuments: profileDocuments);
  }

  static final _profileFile = RegExp(
    r'^application-[^.]+\.(ya?ml|properties)$',
  );

  // `spring.config.activate.on-profile` in a document, as a property line
  // or nested YAML (`on-profile: dev` under `activate:`).
  static final _onProfile = RegExp(
    r'^\s*(?:spring\.config\.activate\.)?on-profile\s*[:=]\s*(.+)$',
    multiLine: true,
  );

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
    // Spring's StringToBooleanConverter reads these as true and false.
    switch (value) {
      case 'true' || 'yes' || 'on' || '1':
        return BuildInclusion.always;
      case 'false' || 'no' || 'off' || '0':
        return BuildInclusion.never;
      case null || '':
        if (profileSetting(configuration, key) case final file?) {
          // Not set, a debug build only: what the profile's file sets has
          // nothing to act on in a profile-mode or a release build.
          final release = whenMissing == BuildInclusion.debugOnly
              ? ': in debug builds only, so in a profile-mode or a release '
                    'build what $file sets has no code to act on. Set $key: '
                    'true without a profile to keep the $noun in every build'
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

  /// Where the code [buildSwitch] decides goes: its own key as [decide]
  /// (or [decideNamed] for a list) says, narrowed by each of its parents,
  /// so code inside a feature leaves the build with the feature.
  BuildInclusion decideSwitch(
    BuildSwitch buildSwitch, {
    required String subject,
    String noun = 'module',
  }) {
    final own = switch (buildSwitch.name) {
      null => decide(
        buildSwitch.property,
        whenMissing: buildSwitch.whenMissing,
        subject: subject,
        noun: noun,
      ),
      final name => decideNamed(
        buildSwitch.property,
        name,
        whenMissing: buildSwitch.whenMissing,
        subject: subject,
        noun: noun,
      ),
    };
    if (own == BuildInclusion.never) {
      return own;
    }
    return narrowestInclusion([
      own,
      for (final parent in buildSwitch.parents)
        decideSwitch(parent, subject: subject, noun: noun),
    ]);
  }

  /// Where the code goes that the list [key] lets in by [name]: in every
  /// build when the list names it or holds `*`, in none when it is set
  /// without either, [whenMissing] when it is not set. [subject] and
  /// [noun] as for [decide].
  BuildInclusion decideNamed(
    String key,
    String name, {
    required BuildInclusion whenMissing,
    required String subject,
    String noun = 'module',
  }) {
    final List<String>? items;
    try {
      items = list(key);
    } on Object catch (error) {
      throw InvalidGenerationSourceError(
        '$subject: the build reads $key to decide whether the $noun is '
        'built, and could not: $error',
        todo:
            'Give $key a value the build can read in application.yml or '
            'application.properties.',
      );
    }
    if (items == null) {
      if (profileSetting(configuration, key) case final file?) {
        log.warning(
          '$subject: $key is set only in $file, which the build does not '
          'read: it decides by application.yml or application.properties '
          'without a profile. The $noun is built as when it is not set.',
        );
      }
      return whenMissing;
    }
    return items.contains(name) || items.contains('*')
        ? BuildInclusion.always
        : BuildInclusion.never;
  }

  /// The list [key] in the configuration without a profile, its items
  /// trimmed: a YAML list (`key[0]`, `key[1]`...) or one value split at
  /// its commas (`fps, filter`); empty for an empty list; `null` when it
  /// is not set.
  List<String>? list(String key) {
    final whole = _lookup(key);
    if (whole != null) {
      return [
        for (final item in whole.split(','))
          if (item.trim() case final trimmed when trimmed.isNotEmpty) trimmed,
      ];
    }
    final items = <String>[];
    for (String? item; (item = _lookup('$key[${items.length}]')) != null;) {
      items.add(item!.trim());
    }
    return items.isEmpty ? null : items;
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

    final candidates = {
      for (final MapEntry(key: path, value: text) in files.entries)
        if (_profileFile.hasMatch(p.basename(path))) path: text,
      ...baseConfiguration(files).profileDocuments,
    };
    for (final MapEntry(key: path, value: text) in candidates.entries) {
      final name = p.basename(path);
      try {
        final set = name.contains('.properties')
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
