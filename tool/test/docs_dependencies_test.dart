// The docs follow roadmap/dependencies.md: an install snippet lists the
// starter alone (never the packages that come with it), and nothing tells
// an application to import spring_web_dart's mocks directly (they come
// with spring_boot_starter_test).
import 'dart:io';

import 'package:test/test.dart';

const _comesWithStarters = {
  'spring_boot_dart',
  'spring_core_dart',
  'spring_web_dart',
};

List<String> _markdown() {
  final result = Process.runSync('git', ['ls-files', '*.md']);
  return [
    for (final line in (result.stdout as String).split('\n'))
      if (line.isNotEmpty && !line.endsWith('CHANGELOG.md')) line,
  ];
}

/// The names under `dependencies:` (not dev) of a YAML snippet.
List<String> _dependencies(String yaml) {
  final names = <String>[];
  var inside = false;
  for (final line in yaml.split('\n')) {
    if (line.trim() == 'dependencies:') {
      inside = true;
    } else if (!line.startsWith(' ') && line.trim().isNotEmpty) {
      inside = false;
    } else if (inside) {
      final match = RegExp(r'^  ([a-z_][a-z0-9_]*):').firstMatch(line);
      if (match != null) {
        names.add(match[1]!);
      }
    }
  }
  return names;
}

void main() {
  final files = _markdown();

  test('an install snippet with a starter lists nothing that comes with it', () {
    final problems = <String>[];
    for (final path in files) {
      final text = File(path).readAsStringSync();
      for (final block in RegExp(
        r'```ya?ml\n(.*?)```',
        dotAll: true,
      ).allMatches(text)) {
        final names = _dependencies(block[1]!);
        final starters = names.where(
          (n) => n.startsWith('spring_boot_starter_'),
        );
        if (starters.isEmpty) {
          continue;
        }
        final line = '\n'.allMatches(text.substring(0, block.start)).length + 1;
        for (final name in names) {
          if (_comesWithStarters.contains(name)) {
            problems.add('$path:$line: $name next to ${starters.join(', ')}');
          }
        }
        if (starters.length > 1 &&
            starters.contains('spring_boot_starter_logging')) {
          problems.add(
            '$path:$line: spring_boot_starter_logging comes with '
            '${starters.where((s) => s != 'spring_boot_starter_logging').join(', ')}',
          );
        }
      }
    }
    expect(problems, isEmpty);
  });

  test('applications are not told to import spring_web_dart/testing.dart', () {
    final problems = [
      for (final path in files)
        if (!path.startsWith('spring_web_dart/') &&
            !path.startsWith('roadmap/') &&
            File(path)
                .readAsStringSync()
                .contains('spring_web_dart/testing.dart'))
          path,
    ];
    expect(problems, isEmpty);
  });
}
