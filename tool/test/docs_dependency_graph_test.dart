// docs/dependencies.md follows the dependency graph of the pub workspace:
// every external package has a row in "Every package", every workspace
// package is described, and every exception of tool/check_dependencies.dart
// is listed. The Flutter packages resolve on their own (they need the
// Flutter SDK), so their rows are not checked here.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final doc = File(p.join('docs', 'dependencies.md')).readAsStringSync();
  late List<Map<String, Object?>> packages;

  setUpAll(() {
    final result = Process.runSync(Platform.resolvedExecutable, [
      'pub',
      'deps',
      '--json',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    packages =
        ((jsonDecode(result.stdout as String) as Map)['packages'] as List)
            .cast<Map<String, Object?>>();
  });

  /// The section of [doc] from the heading starting with [heading] to the
  /// next `## ` heading.
  String section(String heading) {
    final start = doc.indexOf('\n## $heading');
    expect(start, isNot(-1), reason: 'no section "$heading"');
    final end = doc.indexOf('\n## ', start + 1);
    return doc.substring(start, end == -1 ? doc.length : end);
  }

  test('every external package has a row in "Every package"', () {
    final table = section('9. Every package');
    final missing = [
      for (final package in packages)
        if (package['source'] == 'hosted' || package['source'] == 'sdk')
          if (!table.contains('| `${package['name']}` |')) package['name'],
    ];
    expect(missing, isEmpty);
  });

  test('every workspace package is in "The packages of this repository"', () {
    final table = section('3. The packages of this repository');
    final missing = [
      for (final package in packages)
        if (package['kind'] == 'root')
          if (!table.contains('`${package['name']}`')) package['name'],
    ];
    expect(missing, isEmpty);
  });

  test('every exception of check_dependencies.dart is in "Exceptions"', () {
    final tool = File(p.join('tool', 'check_dependencies.dart'))
        .readAsStringSync();
    final exceptions = [
      for (final match in RegExp(
        r"^  '([a-z0-9_]+)': AllowedPackage\(",
        multiLine: true,
      ).allMatches(tool))
        match[1]!,
    ];
    expect(exceptions, isNotEmpty);
    final table = section('2. Exceptions');
    expect([
      for (final name in exceptions)
        if (!table.contains('| `$name` |')) name,
    ], isEmpty);
  });
}
