// The reaper: containers of a test process that was killed are removed.
@Tags(['docker'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:spring_boot_starter_test/containers.dart';
import 'package:test/test.dart';

import 'support/docker_support.dart';

Future<String> _packageRoot() async {
  final lib = await Isolate.resolvePackageUri(
    Uri.parse('package:spring_boot_starter_test/containers.dart'),
  );
  return File.fromUri(lib!).parent.parent.path;
}

void main() {
  test(
    'a container of a process killed with kill -9 is removed by the reaper',
    () async {
      final docker = await dockerClient();
      final root = await _packageRoot();
      final child = await Process.start(
        Platform.resolvedExecutable,
        ['run', 'test/containers/support/orphan_container.dart'],
        workingDirectory: root,
      );
      var childPid = child.pid;
      String? containerId;
      addTearDown(() async {
        child.kill(ProcessSignal.sigkill);
        if (containerId != null) {
          await docker.removeContainer(containerId!);
        }
      });
      final output = StringBuffer();
      final ready = Completer<void>();
      child.stderr.transform(utf8.decoder).listen(output.write);
      child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              output.writeln(line);
              if (line.startsWith('READY ')) {
                final parts = line.split(' ');
                childPid = int.parse(parts[1]);
                containerId = parts[2];
                ready.complete();
              }
            },
          );
      await ready.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () =>
            fail('the child did not start its container:\n$output'),
      );
      expect((await docker.inspectContainer(containerId!)).running, isTrue);

      // No goodbye: the process is gone, its connection to the reaper drops.
      Process.killPid(childPid, ProcessSignal.sigkill);
      child.kill(ProcessSignal.sigkill);
      await child.exitCode;

      // The reaper removes it after its reconnection timeout (10 s).
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      var gone = false;
      while (DateTime.now().isBefore(deadline)) {
        try {
          await docker.inspectContainer(containerId!);
        } on DockerException catch (e) {
          if (e.statusCode == 404) {
            gone = true;
            break;
          }
          rethrow;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      expect(gone, isTrue, reason: 'the container is still there after 60 s');
    },
    skip:
        dockerSkip ??
        (ContainerRuntimeEnvironment.reaperDisabled
            ? 'TESTCONTAINERS_RYUK_DISABLED is set'
            : null),
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

/// The environment switches of the reaper.
abstract final class ContainerRuntimeEnvironment {
  static bool get reaperDisabled =>
      (Platform.environment['TESTCONTAINERS_RYUK_DISABLED'] ?? '')
          .toLowerCase() ==
      'true';
}
