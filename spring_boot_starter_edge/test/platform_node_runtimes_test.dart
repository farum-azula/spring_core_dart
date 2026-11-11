// The function built for Vercel, run by Node behind a stand-in for
// Vercel's runtime (test/js/vercel_runtime.mjs): the `fetch` export is
// called with web requests, as Vercel calls it. Not run on Vercel itself.
@Tags(['edge-node', 'integration'])
library;

import 'dart:io';

import 'package:spring_boot_starter_edge/build.dart';
import 'package:test/test.dart';

import 'platform_checks.dart';
import 'platform_support.dart';

void main() {
  final skip = hasNode ? null : 'node is not installed';
  late Directory directory;
  late HttpFunctionClient client;
  Background? node;

  setUpAll(() async {
    if (skip != null) {
      return;
    }
    directory = await buildFunction(EdgePlatform.vercel);
    final (process, match) = await Background.start(
      'node',
      ['$packageRoot/test/js/vercel_runtime.mjs', directory.path],
      ready: RegExp(r'LISTENING (\d+)'),
      environment: {'GREETING': 'from-vercel'},
    );
    node = process;
    client = HttpFunctionClient(
      Uri.parse('http://127.0.0.1:${match.group(1)}'),
    );
    await client.ready('/hello');
  });

  tearDownAll(() async {
    await node?.stop();
    if (skip == null) {
      client.close();
      directory.deleteSync(recursive: true);
    }
  });

  group('a Vercel Function (the fetch export)', skip: skip, () {
    platformChecks(() => client, platform: 'vercel', greeting: 'from-vercel');

    test('the address of the client is x-real-ip, which Vercel sets', () async {
      final answer = await client.get(
        '/hello',
        headers: {'x-real-ip': '198.51.100.1'},
      );
      // The stand-in replaces what the client sent, as Vercel does.
      expect((answer.json! as Map)['remote'], '127.0.0.1');
    });
  });
}
