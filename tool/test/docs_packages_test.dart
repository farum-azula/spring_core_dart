// docs/packages.md says what each package of the family re-exports: its
// table "What each package brings" must match the `export` directives of
// the packages' main libraries (followed through their own files and into
// the packages they export), and every package with a main library has a
// row.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The packages of the repository with a main library (`lib/<name>.dart`),
/// the generator left out (a build tool, not imported by applications).
List<String> familyPackages() => [
  for (final entity in Directory.current.listSync())
    if (entity is Directory)
      if (p.basename(entity.path) case final name
          when name.startsWith('spring_') &&
              name != 'spring_core_dart_generator' &&
              File(p.join(name, 'lib', '$name.dart')).existsSync())
        name,
]..sort();

/// The libraries (`package/path.dart`) of other packages that
/// [package]'s library at [path] exports, directly or through what it
/// exports.
Set<String> exportedLibraries(
  String package,
  String path, [
  Set<String>? visited,
]) {
  final seen = visited ?? <String>{};
  if (!seen.add('$package/$path')) {
    return {};
  }
  final file = File(p.join(package, 'lib', path));
  if (!file.existsSync()) {
    return {};
  }
  final result = <String>{};
  final exports = RegExp(
    "^export '([^']+)'",
    multiLine: true,
  ).allMatches(file.readAsStringSync());
  for (final match in exports) {
    final uri = match[1]!;
    if (uri.startsWith('dart:')) {
      continue;
    }
    if (uri.startsWith('package:')) {
      final slash = uri.indexOf('/');
      final other = uri.substring('package:'.length, slash);
      final otherPath = uri.substring(slash + 1);
      if (other != package) {
        result.add('$other/$otherPath');
      }
      result.addAll(exportedLibraries(other, otherPath, seen));
    } else {
      final relative = p.url.normalize(
        p.url.join(p.url.dirname(path), uri),
      );
      result.addAll(exportedLibraries(package, relative, seen));
    }
  }
  return result;
}

/// The packages [package] re-exports whole: their main library is among
/// what its main library exports.
Set<String> reExportedPackages(String package) => {
  for (final library in exportedLibraries(package, '$package.dart'))
    if (library.split('/') case [final name, final path]
        when path == '$name.dart')
      name,
};

void main() {
  final doc = File(p.join('docs', 'packages.md')).readAsStringSync();
  final start = doc.indexOf('\n## What each package brings');
  final end = doc.indexOf('\n## ', start + 1);
  final table = doc.substring(start, end);

  /// The packages of the "Re-exports" column of [package]'s row.
  Set<String>? documented(String package) {
    final row = RegExp(
      '^\\| `${RegExp.escape(package)}` \\| ([^|]*) \\|',
      multiLine: true,
    ).firstMatch(table);
    if (row == null) {
      return null;
    }
    return {
      for (final name in RegExp('`([a-z_0-9]+)`').allMatches(row[1]!)) name[1]!,
    };
  }

  test('the table has a row for every package of the family', () {
    expect(
      [
        for (final package in familyPackages())
          if (documented(package) == null) package,
      ],
      isEmpty,
    );
  });

  for (final package in familyPackages()) {
    test('$package re-exports what the table says', () {
      expect(documented(package), reExportedPackages(package));
    });
  }
}
