@TestOn('vm')
@Tags(['integration'])
library;

// A connection on a worker isolate that nobody closed must not keep the
// process alive: the isolate's port only holds it while a call is pending.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  for (final args in [
    <String>[],
    ['--close'],
  ]) {
    test(
      'the process ends ${args.isEmpty ? 'without' : 'after'} a close',
      () async {
        final lib = await Isolate.resolvePackageUri(
          Uri.parse('package:spring_boot_starter_data/'),
        );
        final fixture = lib!.resolve(
          '../test/sqlite/fixtures/idle_worker_app.dart',
        );
        final process = await Process.start(Platform.resolvedExecutable, [
          'run',
          fixture.toFilePath(),
          ...args,
        ]);
        final output = process.stdout
            .transform(const SystemEncoding().decoder)
            .join();
        unawaited(process.stderr.drain<void>());
        final code = await process.exitCode.timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
        expect(await output, contains('rows 1'));
        expect(code, 0, reason: 'a code of -1 means it was still running');
      },
    );
  }
}
