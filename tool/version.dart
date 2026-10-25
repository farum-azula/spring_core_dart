// Lockstep versioning of the spring_* family (like Spring's release
// trains): every package has the same version and depends on its siblings
// with `^<that version>`, so starters and the core always come from one
// compatible set.
//
//   dart run tool/version.dart 0.2.0       # set the version everywhere
//   dart run tool/version.dart --check     # verify (CI)
//   dart run tool/version.dart --fix-docs  # only the snippets in the docs
//
// Everywhere includes the install snippets of the READMEs, the examples'
// READMEs and doc comments (`spring_boot_dart: ^0.2.0`), so pub.dev never
// shows an older version than the release it belongs to.
//
// The check also keeps each published package's description within the
// 60–180 characters pub.dev asks for (otherwise it costs 10 pub points).
import 'dart:io';

/// Published packages released together.
const family = [
  'spring_core_dart',
  'spring_core_dart_generator',
  'spring_boot_dart',
  'spring_web_dart',
  'spring_boot_starter_logging',
  'spring_boot_starter_scheduling',
  'spring_boot_starter_cache',
  'spring_boot_starter_feign',
  'spring_boot_starter_websocket',
  'spring_boot_starter_test',
  // Flutter: outside the pub workspace, published with `flutter pub`.
  'spring_boot_starter_flutter',
];

/// Packages that only depend on the family (not published).
const dependents = [
  'example/spring_core_tour',
  'example/spring_boot_feign',
  'example/flutter_counter',
  'example/flutter_themes',
  'extensions/language_server',
];

const _versionFile = 'spring_boot_dart/lib/src/version.dart';

/// Editor extensions: same version as the family they support (not
/// published to pub.dev).
const extensions = [
  'extensions/zed/dart_spring/extension.toml',
  'extensions/zed/dart_spring/Cargo.toml',
  'extensions/language_server/pubspec.yaml',
];

/// The Zed extension's Cargo.lock: its own `dart_spring` package entry
/// carries the version of Cargo.toml (cargo rewrites it on every build).
const _cargoLock = 'extensions/zed/dart_spring/Cargo.lock';

/// The `dart_spring` entry of [_cargoLock]; group 2 is its version.
final _cargoLockVersion = RegExp(
  r'^(\[\[package\]\]\nname = "dart_spring"\nversion = ")([^"]*)"',
  multiLine: true,
);

final _extensionVersion = RegExp(r'^version = "(.*)"$', multiLine: true);
final _pubspecVersion = RegExp(r'^version: (.*)$', multiLine: true);

RegExp _versionPattern(String path) =>
    path.endsWith('pubspec.yaml') ? _pubspecVersion : _extensionVersion;

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln(
      'usage: dart run tool/version.dart <version> | --check | --fix-docs',
    );
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
  if (args.single == '--fix-docs') {
    final version = _version(family.first);
    _setDocVersions(version);
    stdout.writeln('docs set to ^$version');
    return;
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
  _setDocVersions(version);
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
  _edit(
    _cargoLock,
    (text) =>
        text.replaceFirstMapped(_cargoLockVersion, (m) => '${m[1]}$version"'),
  );
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
  final lock = File(_cargoLock);
  if (lock.existsSync()) {
    final own = _cargoLockVersion
        .firstMatch(lock.readAsStringSync().replaceAll('\r\n', '\n'))
        ?.group(2);
    if (own != version) {
      problems.add('$_cargoLock: dart_spring is $own, expected $version');
    }
  }
  for (final path in _docFiles()) {
    final text = File(path).readAsStringSync();
    for (final match in _docConstraint.allMatches(text)) {
      if (match[2] != '^$version') {
        final line = '\n'.allMatches(text.substring(0, match.start)).length + 1;
        problems.add(
          '$path:$line: ${match[1]!.replaceAll('///', '').trim()} '
          '${match[2]}, expected ^$version '
          '(dart run tool/version.dart --fix-docs)',
        );
      }
    }
  }
  for (final package in family) {
    final length = description(package).length;
    if (length < 60 || length > 180) {
      problems.add(
        '$package: the pubspec description has $length characters; pub.dev '
        'wants 60-180 (10 pub points)',
      );
    }
  }
  return problems;
}

/// Sets [version] in the install snippets of the docs
/// (`spring_boot_dart: ^0.2.0`).
void _setDocVersions(String version) {
  for (final path in _docFiles()) {
    _edit(
      path,
      (text) =>
          text.replaceAllMapped(_docConstraint, (m) => '${m[1]}^$version'),
    );
  }
}

/// A family package's version in a documentation snippet: a YAML line
/// (also inside a `///` doc comment) like `  spring_boot_dart: ^0.2.0`;
/// group 1 is everything before the version, group 2 the version.
final _docConstraint = RegExp(
  '^((?:\\s*///)?\\s*(?:${family.join('|')}): *)(\\^?[0-9][^\\s#]*)',
  multiLine: true,
);

/// The Markdown files (but CHANGELOGs, which are history) and Dart
/// libraries of the repository root, the family and the dependents, where
/// install snippets name family versions.
List<String> _docFiles() {
  final files = <String>[
    'README.md',
    for (final package in [...family, ...dependents])
      for (final entity in Directory(package).listSync(recursive: true))
        if (entity is File &&
            !entity.path.contains('/.dart_tool/') &&
            !entity.path.contains('/build/') &&
            ((entity.path.endsWith('.md') &&
                    !entity.path.endsWith('CHANGELOG.md')) ||
                (entity.path.endsWith('.dart') &&
                    !entity.path.endsWith('.spring.dart'))))
          entity.path,
  ];
  return files..sort();
}

/// The `description:` of [package]'s pubspec as pub.dev reads it: a plain,
/// quoted or folded (`>-`) value, whitespace collapsed.
String description(String package) {
  final lines = File('$package/pubspec.yaml').readAsLinesSync();
  final start = lines.indexWhere((line) => line.startsWith('description:'));
  if (start < 0) {
    return '';
  }
  var value = lines[start].substring('description:'.length).trim();
  if (value.startsWith('>') || value.startsWith('|')) {
    value = lines
        .skip(start + 1)
        .takeWhile((line) => line.startsWith(' ') || line.trim().isEmpty)
        .join(' ');
  }
  value = value.trim();
  if (value.length >= 2 &&
      (value.startsWith('"') && value.endsWith('"') ||
          value.startsWith("'") && value.endsWith("'"))) {
    value = value.substring(1, value.length - 1);
  }
  return value.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
}

String _version(String package) => RegExp(r'^version: (.*)$', multiLine: true)
    .firstMatch(File('$package/pubspec.yaml').readAsStringSync())!
    .group(1)!
    .trim();

void _edit(String path, String Function(String text) change) {
  final file = File(path);
  if (file.existsSync()) {
    final text = file.readAsStringSync();
    final changed = change(text);
    if (changed != text) {
      file.writeAsStringSync(changed);
    }
  }
}
