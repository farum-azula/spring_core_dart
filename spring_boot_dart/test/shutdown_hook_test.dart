@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

// Starts the fixture and waits for its `ready` line. The fixture's path is
// resolved from the package, so the test runs from the workspace root too.
Future<(Process, Stream<String>)> _start(List<String> args) async {
  final lib = await Isolate.resolvePackageUri(
    Uri.parse('package:spring_boot_dart/'),
  );
  final fixture = lib!.resolve('../test/fixtures/shutdown_app.dart');
  final process = await Process.start(Platform.resolvedExecutable, [
    'run',
    fixture.toFilePath(),
    ...args,
  ]);
  final lines = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .asBroadcastStream();
  await lines.firstWhere((line) => line == 'ready');
  return (process, lines);
}

void main() {
  group('SpringApplication', () {
    Future<(int, String)> end(Process process, Stream<String> lines) async {
      final output = lines.toList();
      final code = await process.exitCode.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      return (code, (await output).join('\n'));
    }

    test('SIGTERM closes the context when the hook is registered', () async {
      final (process, lines) = await _start([]);
      process.kill();
      final (code, output) = await end(process, lines);
      expect(output, contains('closed'));
      expect(code, 143);
    });

    test('SIGINT closes the context when the hook is registered', () async {
      final (process, lines) = await _start([]);
      process.kill(ProcessSignal.sigint);
      final (code, output) = await end(process, lines);
      expect(output, contains('closed'));
      expect(code, 130);
    });

    for (final off in [
      '--no-hook',
      '--spring.main.register-shutdown-hook=false',
    ]) {
      test('$off: the signal is not handled', () async {
        final (process, lines) = await _start([off]);
        process.kill();
        final (code, output) = await end(process, lines);
        expect(output, isNot(contains('closed')));
        expect(code, isNot(143));
      });
    }

    test('the property wins over registerShutdownHook', () async {
      final (process, lines) = await _start([
        '--no-hook',
        '--spring.main.register-shutdown-hook=true',
      ]);
      process.kill();
      final (code, output) = await end(process, lines);
      expect(output, contains('closed'));
      expect(code, 143);
    });

    test(
      'a closed context leaves nothing that keeps the process alive',
      () async {
        final (process, lines) = await _start(['--close']);
        final (code, output) = await end(process, lines);
        expect(output, contains('closed'));
        expect(code, 0);
      },
    );
  }, timeout: const Timeout(Duration(seconds: 60)));
}
