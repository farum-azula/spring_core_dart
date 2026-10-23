// Started by shutdown_hook_test.dart: a running application whose context
// prints `closed` when it is closed.
import 'dart:async';
import 'dart:io';

import 'package:spring_boot_dart/spring_boot_dart.dart';

class Probe {}

void main(List<String> args) {
  final context =
      SpringApplication(
        [
          BeanModule('app', [
            BeanDefinition<Probe>(
              name: 'probe',
              create: (_) => Probe(),
              preDestroy: (_) => stdout.writeln('closed'),
            ),
          ]),
        ],
        registerShutdownHook: !args.contains('--no-hook'),
        out: (_) {},
      ).run([
        for (final arg in args)
          if (!arg.startsWith('--no-') && arg != '--close') arg,
      ], systemEnvironment: const {});
  stdout.writeln('ready');
  if (args.contains('--close')) {
    context.close();
    return;
  }
  // Keeps the process running, as a server would.
  Timer.periodic(const Duration(seconds: 1), (_) {});
}
