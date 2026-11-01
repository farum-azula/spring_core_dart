// Started by reaper_test.dart as a process of its own: starts a container,
// says so, and waits to be killed with kill -9, without cleaning up.
import 'dart:async';
import 'dart:io';

import 'package:spring_boot_starter_test/containers.dart';

Future<void> main() async {
  final container = GenericContainer('busybox:1.37').withCommand([
    'sleep',
    '600',
  ]);
  await container.start();
  stdout.writeln('READY $pid ${container.containerId}');
  await stdout.flush();
  await Completer<void>().future;
}
