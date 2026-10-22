// Lockstep versioning of the spring_* family (like Spring's release
// trains): every package has the same version and depends on its siblings
// with `^<that version>`, so starters and the core always come from one
// compatible set.
//
//   dart run tool/version.dart 0.2.0   # set the version everywhere
//   dart run tool/version.dart --check # verify (CI)
import 'dart:io';

/// Published packages released together.
const family = [
  'spring_core_dart',
  'spring_core_dart_generator',
  'spring_boot_dart',
  'spring_boot_starter_logging',
  'spring_boot_starter_scheduling',
  'spring_boot_starter_cache',
  'spring_boot_starter_test',
];

/// Packages that only depend on the family (not published).
const dependents = ['example', 'extensions/language_server'];

const _versionFile = 'spring_boot_dart/lib/src/version.dart';

/// Editor extensions: same version as the family they support (not
/// published to pub.dev).
const extensions = [
  'extensions/zed/dart_spring/extension.toml',
  'extensions/zed/dart_spring/Cargo.toml',
  'extensions/language_server/pubspec.yaml',
];

final _extensionVersion = RegExp(r'^version = "(.*)"$', multiLine: true);
final _pubspecVersion = RegExp(r'^version: (.*)$', multiLine: true);

RegExp _versionPattern(String path) =>
    path.endsWith('pubspec.yaml') ? _pubspecVersion : _extensionVersion;

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/version.dart <version> | --check');
    exit(64);
  }
  if (args.single == '--check') {
    final problems = check();
    if (problems.isEmpty) {
      stdout.writeln('versions ok: ${_version('spring_core_dart')}');
      return;
    }
    problems.forEach(stderr.writeln);
    exit(1);
  }
  final version = args.single;
  if (!RegExp(r'^\d+\.\d+\.\d+([-+].*)?$').hasMatch(version)) {
    stderr.writeln('not a version: $version');
    exit(64);
  }
  setVersion(version);
  final problems = check();
  problems.forEach(stderr.writeln);
  stdout.writeln('set $version in ${family.join(', ')}');
}

/// Sets [version] in every family pubspec, the sibling constraints of all
/// pubspecs, `springBootVersion`, and turns `## Unreleased` changelog
/// headings into `## <version>`.
void setVersion(String version) {
  for (final package in family) {
    _edit(
      '$package/pubspec.yaml',
      (text) => text.replaceFirst(
        RegExp(r'^version: .*$', multiLine: true),
        'version: $version',
      ),
    );
    _edit(
      '$package/CHANGELOG.md',
      (text) => text.replaceFirst(
        RegExp(r'^## Unreleased$', multiLine: true),
        '## $version',
      ),
    );
  }
  for (final package in [...family, ...dependents]) {
    _edit('$package/pubspec.yaml', (text) {
      var result = text;
      for (final sibling in family) {
        result = result.replaceAll(
          RegExp('^(  $sibling): .*\$', multiLine: true),
          '\$1: ^$version'.replaceFirst(r'$1', '  $sibling'),
        );
      }
      return result;
    });
  }
  _edit(
    _versionFile,
    (text) => text.replaceFirst(
      RegExp(r"const springBootVersion = '.*';"),
      "const springBootVersion = '$version';",
    ),
  );
  for (final manifest in extensions) {
    _edit(
      manifest,
      (text) => text.replaceFirst(
        _versionPattern(manifest),
        manifest.endsWith('pubspec.yaml')
            ? 'version: $version'
            : 'version = "$version"',
      ),
    );
  }
}

/// Problems with the current versions (empty when consistent).
List<String> check() {
  final problems = <String>[];
  final version = _version(family.first);
  for (final package in family) {
    final own = _version(package);
    if (own != version) {
      problems.add('$package is $own, expected $version (lockstep)');
    }
  }
  for (final package in [...family, ...dependents]) {
    final text = File('$package/pubspec.yaml').readAsStringSync();
    for (final sibling in family) {
      final match = RegExp(
        '^  $sibling: (.*)\$',
        multiLine: true,
      ).firstMatch(text);
      if (match != null && match.group(1)!.trim() != '^$version') {
        problems.add(
          '$package depends on $sibling ${match.group(1)!.trim()}, '
          'expected ^$version',
        );
      }
    }
  }
  final constant = RegExp(r"const springBootVersion = '(.*)';")
      .firstMatch(File(_versionFile).readAsStringSync())
      ?.group(1);
  if (constant != version) {
    problems.add('springBootVersion is $constant, expected $version');
  }
  for (final manifest in extensions) {
    final file = File(manifest);
    final own = file.existsSync()
        ? _versionPattern(manifest)
              .firstMatch(file.readAsStringSync())
              ?.group(1)
              ?.trim()
        : null;
    if (own != version) {
      problems.add('$manifest is $own, expected $version (lockstep)');
    }
  }
  return problems;
}

String _version(String package) => RegExp(r'^version: (.*)$', multiLine: true)
    .firstMatch(File('$package/pubspec.yaml').readAsStringSync())!
    .group(1)!
    .trim();

void _edit(String path, String Function(String text) change) {
  final file = File(path);
  if (file.existsSync()) {
    file.writeAsStringSync(change(file.readAsStringSync()));
  }
}
