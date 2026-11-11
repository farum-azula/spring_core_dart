// The function built for Supabase Edge Functions, run by Supabase's Edge
// Runtime behind its gateway: the Supabase CLI's stack
// (spring_boot_starter_supabase/test/stack), whose config.toml declares
// the functions `edge-test` and `edge-test-wasm`. Given by SUPABASE_URL;
// the functions are built into SUPABASE_FUNCTIONS (the stack's
// supabase/functions directory).
@Tags(['supabase-stack'])
library;

import 'dart:io';

import 'package:spring_boot_starter_edge/build.dart';
import 'package:test/test.dart';

import 'platform_checks.dart';
import 'platform_support.dart';

void main() {
  final url = Platform.environment['SUPABASE_URL'];
  final anonKey = Platform.environment['SUPABASE_ANON_KEY'];
  final functions =
      Platform.environment['SUPABASE_FUNCTIONS'] ??
      '$packageRoot/../spring_boot_starter_supabase/test/stack/supabase/functions';
  final skip = url == null || anonKey == null
      ? 'no Supabase stack (SUPABASE_URL, SUPABASE_ANON_KEY)'
      : null;
  late HttpFunctionClient client;
  late HttpFunctionClient wasm;

  setUpAll(() async {
    if (skip != null) {
      return;
    }
    await buildFunction(
      EdgePlatform.supabase,
      output: Directory('$functions/edge-test').absolute.path,
    );
    await buildFunction(
      EdgePlatform.supabase,
      name: 'edge-test-wasm',
      output: Directory('$functions/edge-test-wasm').absolute.path,
      target: EdgeTarget.wasm,
    );
    client = HttpFunctionClient(Uri.parse('$url/functions/v1/edge-test'));
    await client.ready('/hello');
    wasm = HttpFunctionClient(Uri.parse('$url/functions/v1/edge-test-wasm'));
    await wasm.ready('/hello');
  });

  tearDownAll(() {
    if (skip == null) {
      client.close();
      wasm.close();
    }
  });

  // config.toml of the stack lists the module among the function's
  // static files, which the Edge Runtime needs to read it.
  group('a Supabase Edge Function compiled to WebAssembly', skip: skip, () {
    platformChecks(
      () => wasm,
      platform: 'supabase',
      greeting: 'hello-from-env',
    );
  });

  group('a Supabase Edge Function', skip: skip, () {
    platformChecks(
      () => client,
      platform: 'supabase',
      // supabase/functions/.env of the stack.
      greeting: 'hello-from-env',
    );

    test('the name of the function is not part of the paths', () async {
      final answer = await client.get('/hello');
      expect((answer.json! as Map)['path'], '/hello');
    });

    test('the anon key as a bearer token is no token', () async {
      final open = await client.get(
        '/hello',
        headers: {'authorization': 'Bearer $anonKey', 'apikey': anonKey!},
      );
      expect(open.status, 200);
      final protected = await client.get(
        '/api/me',
        headers: {'authorization': 'Bearer $anonKey'},
      );
      expect(protected.status, 401);
    });

    test("the project's service role key is not a user's token", () async {
      final key = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
      if (key == null) {
        markTestSkipped('no SUPABASE_SERVICE_ROLE_KEY');
        return;
      }
      final answer = await client.get(
        '/api/me',
        headers: {'authorization': 'Bearer $key'},
      );
      expect(answer.status, 401);
    });
  });
}
