// Line coverage of the published Dart packages: coverage:test_with_coverage
// in each of them (without the integration and differential tests, which
// need servers, node or the Spring application), the lcov files merged into
// coverage/lcov.info for CI's coverage gate, and the total printed.
//
//   dart pub global activate coverage
//   dart run tool/coverage.dart
import 'dart:io';

import 'version.dart' as family;

Future<void> main() async {
  Directory.current = File.fromUri(Platform.script).parent.parent;
  final packages = [
    for (final package in family.family)
      if (!package.startsWith('spring_boot_starter_flutter')) package,
  ];
  final merged = StringBuffer();
  for (final package in packages) {
    stdout.writeln('== $package');
    final process = await Process.start(
      Platform.resolvedExecutable,
      [
        'pub',
        'global',
        'run',
        'coverage:test_with_coverage',
        '--',
        '--exclude-tags',
        'integration || differential',
      ],
      workingDirectory: package,
      mode: ProcessStartMode.inheritStdio,
    );
    if (await process.exitCode != 0) {
      stderr.writeln('The tests of $package failed.');
      exit(1);
    }
    merged.write(File('$package/coverage/lcov.info').readAsStringSync());
  }
  File('coverage/lcov.info')
    ..createSync(recursive: true)
    ..writeAsStringSync('$merged');
  var found = 0;
  var hit = 0;
  for (final line in '$merged'.split('\n')) {
    if (line.startsWith('LF:')) found += int.parse(line.substring(3));
    if (line.startsWith('LH:')) hit += int.parse(line.substring(3));
  }
  stdout.writeln(
    'Line coverage: ${(hit * 100 / found).toStringAsFixed(2)} % '
    '($hit of $found lines, coverage/lcov.info)',
  );
}
