// Started by start_failure_test.dart as a process of its own, with
// DOCKER_HOST at the test's fake daemon: starts a container the daemon
// refuses (`network`: its network, `container`: the container itself),
// says how that ended, and then stays alive, so that what the test sees
// closed was closed by the failed start and not by the process's end.
import 'dart:async';
import 'dart:io';

import 'package:spring_boot_starter_test/containers.dart';

Future<void> main(List<String> args) async {
  final container = GenericContainer('busybox:1.37');
  if (args.first == 'network') {
    container.withNetwork(Network.newNetwork());
  }
  try {
    await container.start();
    stdout.writeln('STARTED');
  } on DockerException catch (error) {
    stdout.writeln('FAILED ${error.message}');
  }
  await stdout.flush();
  await Completer<void>().future;
}
