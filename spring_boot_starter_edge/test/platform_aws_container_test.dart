// The function built for AWS Lambda, run by AWS's own Lambda runtime
// image (its Node.js runtime and runtime interface emulator) in Docker.
@Tags(['edge-docker', 'docker'])
library;

import 'dart:io';

import 'package:spring_boot_starter_edge/build.dart';
import 'package:spring_boot_starter_test/containers.dart';
import 'package:test/test.dart';

import 'platform_checks.dart';
import 'platform_support.dart';

void main() {
  final skip = TestContainers.skipReason();
  final directories = <Directory>[];
  final containers = <GenericContainer>[];
  late LambdaFunctionClient client;
  late LambdaFunctionClient wasm;

  Future<LambdaFunctionClient> lambda(EdgeTarget target) async {
    final directory = await buildFunction(EdgePlatform.aws, target: target);
    directories.add(directory);
    final container = GenericContainer('public.ecr.aws/lambda/nodejs:22')
        .withExposedPorts([8080])
        .withEnv('GREETING', 'from-lambda')
        .withCommand(['index.handler'])
        .withStartupTimeout(const Duration(minutes: 5));
    for (final file in directory.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      container.withCopyFile(file.path, '/var/task/$name');
    }
    await container.start();
    containers.add(container);
    final client = LambdaFunctionClient(
      Uri.parse(
        'http://${container.host}:${container.mappedPort(8080)}'
        '/2015-03-31/functions/function/invocations',
      ),
    );
    await client.ready('/hello');
    return client;
  }

  setUpAll(() async {
    if (skip != null) {
      return;
    }
    client = await lambda(EdgeTarget.js);
    wasm = await lambda(EdgeTarget.wasm);
  });

  tearDownAll(() async {
    for (final container in containers) {
      await container.stop();
    }
    for (final directory in directories) {
      directory.deleteSync(recursive: true);
    }
  });

  group("AWS's Lambda runtime", skip: skip, () {
    platformChecks(() => client, platform: 'aws', greeting: 'from-lambda');
  });

  // Node.js 22 of the runtime image has WasmGC.
  group("AWS's Lambda runtime, compiled to WebAssembly", skip: skip, () {
    platformChecks(() => wasm, platform: 'aws', greeting: 'from-lambda');
  });
}
