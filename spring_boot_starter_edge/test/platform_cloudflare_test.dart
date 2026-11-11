// The function built for Cloudflare Workers, run by Cloudflare's own
// runtime (workerd) through `npx wrangler dev`, with a KV namespace, a D1
// database and a cron trigger of its local simulator. Needs Node and, the
// first time, the network (npx downloads wrangler); on with
// EDGE_CLOUDFLARE=true.
@Tags(['edge-cloudflare', 'integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:spring_boot_starter_edge/build.dart';
import 'package:test/test.dart';

import 'platform_checks.dart';
import 'platform_support.dart';

// The Worker of the tests: its bindings, and the rate limiter in D1.
const _wrangler = '''
name = "edge-test"
main = "worker.mjs"
compatibility_date = "2026-11-01"

[vars]
GREETING = "from-worker"
SPRING_EDGE_CLOUDFLARE_RATE_LIMIT_DATABASE = "DB"

[[kv_namespaces]]
binding = "SETTINGS"
id = "local-settings"

[[d1_databases]]
binding = "DB"
database_name = "edge-test"
database_id = "00000000-0000-0000-0000-000000000000"

[triggers]
crons = ["*/5 * * * *"]
''';

void main() {
  final skip = Platform.environment['EDGE_CLOUDFLARE'] != 'true'
      ? 'set EDGE_CLOUDFLARE=true to run the function in workerd'
      : hasNode
      ? null
      : 'node is not installed';
  final directories = <Directory>[];
  final processes = <Background>[];
  late HttpFunctionClient client;
  late HttpFunctionClient wasm;

  Future<HttpFunctionClient> worker(EdgeTarget target) async {
    final directory = Directory.systemTemp.createTempSync('spring_edge_cf_');
    directories.add(directory);
    // Written before the build, which keeps a wrangler.toml it finds.
    File('${directory.path}/wrangler.toml').writeAsStringSync(_wrangler);
    await buildFunction(
      EdgePlatform.cloudflare,
      output: directory.path,
      target: target,
    );
    final port = await freePort();
    final (process, _) = await Background.start(
      'npx',
      [
        '--yes',
        'wrangler@4',
        'dev',
        '--port',
        '$port',
        '--ip',
        '127.0.0.1',
        '--test-scheduled',
      ],
      ready: RegExp('Ready on'),
      workingDirectory: directory.path,
      environment: {'WRANGLER_SEND_METRICS': 'false', 'CI': 'true'},
    );
    processes.add(process);
    final client = HttpFunctionClient(Uri.parse('http://127.0.0.1:$port'));
    await client.ready('/hello');
    return client;
  }

  setUpAll(() async {
    if (skip != null) {
      return;
    }
    client = await worker(EdgeTarget.js);
    wasm = await worker(EdgeTarget.wasm);
  });

  tearDownAll(() async {
    for (final process in processes) {
      await process.stop();
    }
    for (final directory in directories) {
      directory.deleteSync(recursive: true);
    }
  });

  void bindings(HttpFunctionClient Function() client) {
    test('a KV namespace: put, get, keys', () async {
      final key = 'theme-${DateTime.now().microsecondsSinceEpoch}';
      final put = await client().send(
        'PUT',
        '/kv/$key',
        headers: {'content-type': 'text/plain'},
        body: utf8.encode('neon'),
      );
      expect(put.json, [key]);
      expect((await client().get('/kv/$key')).json, {
        'value': 'neon',
        'missing': null,
        'bound': [true, false],
      });
    });

    test('a D1 database: statements with parameters, rows as maps', () async {
      final text = 'note ${DateTime.now().microsecondsSinceEpoch}';
      final answer = await client().send(
        'POST',
        '/d1/notes',
        headers: {'content-type': 'text/plain'},
        body: utf8.encode(text),
      );
      expect(answer.json, {
        'changed': 1,
        'notes': [
          {'text': text, 'pinned': null},
        ],
      });
    });

    test(
      'the rate limiter counts in D1, one count for every instance',
      () async {
        final id = 'd1-${DateTime.now().microsecondsSinceEpoch}';
        final statuses = [
          for (var i = 0; i < 3; i++)
            (await client().get('/limited', headers: {'x-client': id})).status,
        ];
        expect(statuses, [200, 200, 429]);
        final buckets = (await client().get('/d1/buckets')).json! as List;
        expect(
          buckets.where((b) => '${(b as Map)['key']}'.contains(id)),
          hasLength(1),
        );
      },
    );

    test('a cron trigger runs the handlers of the application', () async {
      final run = await client().get('/__scheduled?cron=*/5+*+*+*+*');
      expect(run.status, 200);
      expect(
        (await client().get('/scheduled')).json,
        contains('cloudflare:*/5 * * * *'),
      );
    });
  }

  group('a Worker', skip: skip, () {
    platformChecks(
      () => client,
      platform: 'cloudflare',
      greeting: 'from-worker',
    );
    bindings(() => client);

    test('the address of the client is CF-Connecting-IP', () async {
      // Cloudflare's network sets the header itself and replaces what a
      // client sends in it; the local runtime has no such network in
      // front, so only the header's use is checked here.
      final answer = await client.get('/hello');
      expect((answer.json! as Map)['remote'], '127.0.0.1');
    });

    test('no in-memory rate limiter is warned about', () async {
      // Its counters are in D1: the /limited check above ran on it.
      expect((await client.get('/d1/buckets')).status, 200);
    });
  });

  group('a Worker compiled to WebAssembly', skip: skip, () {
    platformChecks(() => wasm, platform: 'cloudflare', greeting: 'from-worker');
    bindings(() => wasm);
  });

  test('a new wrangler.toml names the Worker and its entry', () {
    final config = wranglerConfig('shop', '2026-11-11');
    expect(config, contains('name = "shop"'));
    expect(config, contains('main = "worker.mjs"'));
    expect(config, contains('compatibility_date = "2026-11-11"'));
  });
}
