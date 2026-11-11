// The function built for Deno Deploy and for Netlify Edge Functions, run
// by Deno (`npx deno`): Deno Deploy's entry as it is, Netlify's behind a
// stand-in for what Netlify gives a function (test/js/netlify_runtime.ts;
// not run on Netlify itself). Needs Node and, the first time, the network
// (npx downloads Deno); on with EDGE_DENO=true.
@Tags(['edge-deno', 'integration'])
library;

import 'dart:io';

import 'package:spring_boot_starter_edge/build.dart';
import 'package:test/test.dart';

import 'platform_checks.dart';
import 'platform_support.dart';

void main() {
  final skip = Platform.environment['EDGE_DENO'] != 'true'
      ? 'set EDGE_DENO=true to run the function in Deno'
      : hasNode
      ? null
      : 'node is not installed';
  final directories = <Directory>[];
  final processes = <Background>[];
  late HttpFunctionClient deploy;
  late HttpFunctionClient wasm;
  late HttpFunctionClient netlify;
  late String netlifyPath;

  Future<HttpFunctionClient> deno(
    List<String> arguments,
    Map<String, String> environment,
  ) async {
    final (process, match) = await Background.start(
      'npx',
      ['--yes', 'deno', 'run', '-A', '--no-check', ...arguments],
      ready: RegExp(r'(?:LISTENING |Listening on .*:)(\d+)(?: (\S+))?'),
      environment: environment,
    );
    processes.add(process);
    if (match.group(2) case final path?) {
      netlifyPath = path;
    }
    final client = HttpFunctionClient(
      Uri.parse('http://127.0.0.1:${match.group(1)}'),
    );
    await client.ready('/hello');
    return client;
  }

  setUpAll(() async {
    if (skip != null) {
      return;
    }
    final js = await buildFunction(EdgePlatform.deno);
    final module = await buildFunction(
      EdgePlatform.deno,
      target: EdgeTarget.wasm,
    );
    final edge = await buildFunction(EdgePlatform.netlify);
    directories.addAll([js, module, edge]);
    deploy = await deno(
      ['${js.path}/main.ts'],
      {'GREETING': 'from-deno', 'PORT': '${await freePort()}'},
    );
    wasm = await deno(
      ['${module.path}/main.ts'],
      {'GREETING': 'from-deno', 'PORT': '${await freePort()}'},
    );
    netlify = await deno(
      ['$packageRoot/test/js/netlify_runtime.ts', edge.path],
      {'GREETING': 'from-netlify', 'PORT': '${await freePort()}'},
    );
  });

  tearDownAll(() async {
    for (final process in processes) {
      await process.stop();
    }
    for (final directory in directories) {
      directory.deleteSync(recursive: true);
    }
  });

  group('Deno Deploy', skip: skip, () {
    platformChecks(() => deploy, platform: 'deno', greeting: 'from-deno');
  });

  group('Deno Deploy, compiled to WebAssembly', skip: skip, () {
    platformChecks(() => wasm, platform: 'deno', greeting: 'from-deno');
  });

  group('a Netlify Edge Function', skip: skip, () {
    platformChecks(
      () => netlify,
      platform: 'netlify',
      greeting: 'from-netlify',
    );

    test('it answers every path by default', () {
      expect(netlifyPath, '/*');
    });
  });
}
