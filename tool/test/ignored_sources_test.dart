// No source of a package is ignored by git: a directory named like an
// ignored one (`build/`, `coverage/`) under `lib/`, `bin/` or `test/`
// is on the developer's disk, so everything passes there, and is neither
// in the repository nor in the package pub.dev gets.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final root = p.dirname(p.dirname(p.dirname(Platform.script.toFilePath())));
  final workspace = Directory('tool').existsSync() ? '.' : root;

  test('git ignores no Dart source under lib/, bin/, test/ or tool/', () {
    final result = Process.runSync('git', const [
      'ls-files',
      '--others',
      '--ignored',
      '--exclude-standard',
    ], workingDirectory: workspace);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final sources = RegExp(r'(^|/)(lib|bin|test|tool)/.*\.dart$');
    // What a build writes, which is ignored on purpose.
    final written = RegExp(
      r'(^|/)(\.dart_tool|ephemeral|\.symlinks|Pods)/|(^|/)build/|'
      'generated_plugin_registrant|GeneratedPluginRegistrant',
    );
    final ignored = [
      for (final path in '${result.stdout}'.split('\n'))
        if (sources.hasMatch(path) &&
            // `build/` at the start of a path, or right under a package:
            // an output. Under lib/, bin/, test/ or tool/ it is a source.
            (!written.hasMatch(path) ||
                RegExp('/(lib|bin|test|tool)/(.*/)?build/').hasMatch(path)))
          path,
    ];
    expect(
      ignored,
      isEmpty,
      reason:
          'These sources are ignored by .gitignore, so they are not in the '
          'repository: rename their directory.',
    );
  });
}
