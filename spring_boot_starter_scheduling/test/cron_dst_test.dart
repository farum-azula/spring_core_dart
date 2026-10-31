// Starts a process: CI runs it in the integration job.
@Tags(['integration'])
@TestOn('vm && !windows')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// Daylight saving changes need a local time zone that has them: runs
/// `test/support/berlin_dst.dart` with TZ=Europe/Berlin.
void main() {
  test(
    'cron expressions across daylight saving changes, like Spring',
    () async {
      final library = Isolate.resolvePackageUriSync(
        Uri.parse(
          'package:spring_boot_starter_scheduling/'
          'spring_boot_starter_scheduling.dart',
        ),
      )!;
      final root = library.resolve('..').toFilePath();
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'test/support/berlin_dst.dart'],
        workingDirectory: root,
        environment: {'TZ': 'Europe/Berlin'},
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
