// The packages a change affects: those with changed files and every
// package that depends on them (directly or not, `dev_dependencies`
// included), so CI runs only their tests. A change to spring_core_dart
// affects everything; one to spring_boot_starter_cache only that starter.
//
//   dart run tool/affected.dart --base origin/main      # print the list
//   dart run tool/affected.dart --base <sha> --github-output
//
// Everything is affected when the base cannot be compared (a new branch,
// a force push) or a shared file changed: tool/, the root pubspec.yaml
// and pubspec.lock, analysis_options.yaml, dart_test.yaml, the CI
// workflows. Documentation (`*.md`, roadmap/) and the Zed extension affect
// no package. With --github-output the result goes to $GITHUB_OUTPUT:
//
//   packages         workspace packages to test (comma-separated)
//   core             spring_core_dart affected (its tests on node)
//   server_guide     example/server_guide affected (it runs, also as
//                    minified JavaScript)
//   security         spring_boot_starter_security affected (compared with
//                    Spring Security itself)
//   flutter_starter  spring_boot_starter_flutter affected
//   flutter_guide    example/flutter_guide affected, or the server guide
//                    its end-to-end tests run against (incl. goldens)
//   flutter          any Flutter package
//   family           a published Dart package of the family (the
//                    applications of tool/check_app_dependencies.dart)
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'test_all.dart' show workspacePackages;
import 'version.dart' as version;

/// Flutter packages outside the pub workspace.
const flutterPackages = [
  'spring_boot_starter_flutter',
  'example/flutter_guide',
];

/// Changed paths (prefixes) that affect every package.
const _everything = [
  'tool/',
  'pubspec.yaml',
  'pubspec.lock',
  'analysis_options.yaml',
  'dart_test.yaml',
  '.github/workflows/',
];

/// Files outside a package that a package's tests check (a package's
/// dependents are affected too: spring_core_dart means everything).
const _testedBy = {
  // Its examples are loaded by spring_core_dart's and the Flutter
  // starter's tests.
  'docs/configuration.md': 'spring_core_dart',
  'extensions/zed/dart_spring/snippets/yaml.json':
      'spring_boot_starter_flutter',
  'extensions/zed/dart_spring/snippets/properties.json':
      'spring_boot_starter_flutter',
};

/// Changed paths that affect no package.
bool _ignored(String path) =>
    path.endsWith('.md') ||
    path.startsWith('roadmap/') ||
    path.startsWith('extensions/zed/') ||
    const {'LICENSE', 'NOTICE', '.gitignore'}.contains(path.split('/').last);

Future<void> main(List<String> args) async {
  Directory.current = File.fromUri(Platform.script).parent.parent;
  final base = args.contains('--base')
      ? args[args.indexOf('--base') + 1]
      : null;
  final packages = [...workspacePackages(), ...flutterPackages];
  final changed = base == null ? null : _changedFiles(base);
  final affected = changed == null
      ? packages.toSet()
      : affectedPackages(changed, packages, localDependencies(packages));
  final ordered = [
    for (final package in packages)
      if (affected.contains(package)) package,
  ];

  stdout
    ..writeln(
      changed == null
          ? 'Everything is affected (no base to compare with).'
          : '${changed.length} changed files since $base.',
    )
    ..writeln(
      ordered.isEmpty
          ? 'No package affected.'
          : 'Affected: ${ordered.join(', ')}',
    );

  if (args.contains('--github-output')) {
    final output = Platform.environment['GITHUB_OUTPUT'];
    if (output == null) {
      stderr.writeln('GITHUB_OUTPUT is not set.');
      exit(64);
    }
    bool has(String package) => affected.contains(package);
    final starter = has('spring_boot_starter_flutter');
    final server = has('example/server_guide');
    // The app's end-to-end tests run against the server guide: a change of
    // the server tests the app too.
    final app = has('example/flutter_guide') || server;
    final dartPackages = ordered
        .where((p) => !flutterPackages.contains(p))
        .join(',');
    File(output).writeAsStringSync(
      [
        'packages=$dartPackages',
        'core=${has('spring_core_dart')}',
        'server_guide=$server',
        'security=${has('spring_boot_starter_security')}',
        'flutter_starter=$starter',
        'flutter_guide=$app',
        'flutter=${starter || app}',
        'family=${familyAffected(affected)}',
        '',
      ].join('\n'),
      mode: FileMode.append,
    );
  }
}

/// Whether [affected] holds a published Dart package of the family: the
/// applications of tool/check_app_dependencies.dart use them all (by path).
bool familyAffected(Set<String> affected) => version.family.any(
  (package) =>
      package != 'spring_boot_starter_flutter' && affected.contains(package),
);

/// The packages [changed] affects, given each package's local
/// [dependencies] (package directory → directories it depends on).
Set<String> affectedPackages(
  List<String> changed,
  List<String> packages,
  Map<String, Set<String>> dependencies,
) {
  final direct = <String>{};
  for (final path in changed) {
    if (_everything.any(
      (prefix) =>
          prefix.endsWith('/') ? path.startsWith(prefix) : path == prefix,
    )) {
      return packages.toSet();
    }
    // The theme snippets are checked by the starter's tests.
    if (_testedBy.entries
            .where((e) => path.startsWith(e.key))
            .map((e) => e.value)
            .firstOrNull
        case final package?) {
      direct.add(package);
      continue;
    }
    if (_ignored(path)) {
      continue;
    }
    // The innermost package holding the file (example/x before example/).
    String? owner;
    for (final package in packages) {
      if (path.startsWith('$package/') &&
          (owner == null || package.length > owner.length)) {
        owner = package;
      }
    }
    if (owner != null) {
      direct.add(owner);
    }
  }
  // Add the dependents until nothing changes.
  final affected = {...direct};
  var grew = true;
  while (grew) {
    grew = false;
    for (final package in packages) {
      if (!affected.contains(package) &&
          (dependencies[package] ?? const {}).any(affected.contains)) {
        grew = affected.add(package);
      }
    }
  }
  return affected;
}

/// Files changed between [base] and HEAD (from their merge base, as a pull
/// request shows them), or `null` when they cannot be compared.
List<String>? _changedFiles(String base) {
  if (RegExp(r'^0+$').hasMatch(base)) {
    return null; // GitHub's "before" of a new branch
  }
  final result = Process.runSync('git', [
    'diff',
    '--name-only',
    '$base...HEAD',
  ]);
  if (result.exitCode != 0) {
    stderr.writeln('git diff $base...HEAD failed: ${result.stderr}');
    return null;
  }
  return [
    for (final line in (result.stdout as String).split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
}

/// For each package directory, the directories of the [packages] its
/// tests depend on: every package it lists under `dependencies:`, and a
/// `dev_dependencies:` one when [testsUse] says the tests use it. Paths are
/// relative to [root].
Map<String, Set<String>> localDependencies(
  List<String> packages, {
  String root = '.',
}) {
  final byName = <String, String>{};
  final pubspecs = <String, YamlMap>{};
  for (final package in packages) {
    final file = File(p.join(root, package, 'pubspec.yaml'));
    if (!file.existsSync()) {
      continue;
    }
    final pubspec = loadYaml(file.readAsStringSync());
    if (pubspec is! YamlMap) {
      continue;
    }
    pubspecs[package] = pubspec;
    if (pubspec['name'] case final String name) {
      byName[name] = package;
    }
  }
  Set<String> names(Object? section) =>
      section is YamlMap ? {for (final key in section.keys) '$key'} : {};
  return {
    for (final MapEntry(key: package, value: pubspec) in pubspecs.entries)
      package: {
        for (final name in {
          ...names(pubspec['dependencies']),
          for (final name in names(pubspec['dev_dependencies']))
            if (testsUse(p.join(root, package), name)) name,
        })
          if (byName[name] case final directory? when directory != package)
            directory,
      },
  };
}

/// Whether the tests of the package at [directory] use its dev dependency
/// [name]: a Dart file under `test/` or `integration_test/` imports or
/// exports one of its libraries, or [name] is the generator and writes
/// code the tests run.
///
/// The generator does not when the package's `build.yaml` limits it to
/// `example/` (`generate_for` of `spring_core_dart_generator:spring_core_dart`
/// only under `example/`) and turns its test builder off
/// (`spring_core_dart_generator:spring_test`, `enabled: false`): then it
/// only writes the package's example, which no test runs.
bool testsUse(String directory, String name) {
  if (name == 'spring_core_dart_generator') {
    return !_generatorOnlyForExample(directory);
  }
  final directive = RegExp(
    '^\\s*(import|export)\\s+[\'"]package:${RegExp.escape(name)}/',
    multiLine: true,
  );
  for (final folder in ['test', 'integration_test']) {
    final tests = Directory(p.join(directory, folder));
    if (!tests.existsSync()) {
      continue;
    }
    for (final entity in tests.listSync(recursive: true)) {
      if (entity is File &&
          entity.path.endsWith('.dart') &&
          directive.hasMatch(entity.readAsStringSync())) {
        return true;
      }
    }
  }
  return false;
}

bool _generatorOnlyForExample(String directory) {
  final file = File(p.join(directory, 'build.yaml'));
  if (!file.existsSync()) {
    return false;
  }
  final builders = switch (loadYaml(file.readAsStringSync())) {
    {'targets': {r'$default': {'builders': final YamlMap builders}}} =>
      builders,
    _ => null,
  };
  if (builders == null) {
    return false;
  }
  final main = builders['spring_core_dart_generator:spring_core_dart'];
  final tests = builders['spring_core_dart_generator:spring_test'];
  final onlyExample = switch (main) {
    {'generate_for': final YamlList globs} =>
      globs.isNotEmpty && globs.every((g) => '$g'.startsWith('example/')),
    _ => false,
  };
  final testsOff = switch (tests) {
    {'enabled': false} => true,
    _ => false,
  };
  return onlyExample && testsOff;
}
