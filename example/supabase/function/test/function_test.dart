// The function without a platform and without a project: the application
// behind FetchApplication, as a platform's entry file calls it.
import 'dart:convert';

import 'package:spring_boot_starter_edge/spring_boot_starter_edge.dart';
import 'package:test/test.dart';

import '../bin/spring_gen/main.spring.dart';

void main() {
  const anonKey = 'anon-key';
  final function = FetchApplication(
    () => springApplication,
    runtime: 'supabase',
    properties: const {'logging.level.root': 'off'},
  );

  Future<FetchResponse> call(
    String method,
    String path, {
    Map<String, String> headers = const {},
  }) => function.fetch(
    FetchRequest(
      method,
      // The platform gives the path with the name of the function.
      Uri.parse('https://abcd.supabase.co/api$path'),
      headers: [
        for (final MapEntry(:key, :value) in headers.entries) (key, value),
      ],
    ),
    environment: const {
      'SERVER_CONTEXT_PATH': '/api',
      'SUPABASE_URL': 'https://abcd.supabase.co',
      'SUPABASE_ANON_KEY': anonKey,
      'SUPABASE_SERVICE_ROLE_KEY': 'service-key',
    },
  );

  tearDownAll(function.close);

  test('the open endpoint answers, also to the anon key', () async {
    for (final headers in [
      const <String, String>{},
      const {'authorization': 'Bearer $anonKey'},
    ]) {
      final response = await call('GET', '/health', headers: headers);
      expect(response.status, 200);
      expect(jsonDecode(utf8.decode(await response.readBytes())), {
        'status': 'UP',
        'runtime': 'supabase',
      });
    }
  });

  test('everything else needs a token of the project', () async {
    for (final path in [
      '/todos?list=a',
      '/me',
      '/admin',
      '/stats',
      '/no-such',
    ]) {
      expect((await call('GET', path)).status, 401, reason: path);
      expect(
        (await call(
          'GET',
          path,
          headers: const {'authorization': 'Bearer $anonKey'},
        )).status,
        401,
        reason: '$path with the anon key',
      );
    }
    expect((await call('POST', '/todos')).status, 401);
  });

  test('the project is the environment of the function', () async {
    await call('GET', '/health');
    final environment = function.context!.getBean<Environment>();
    expect(
      environment.getProperty(
        'spring.security.oauth2.resourceserver.jwt.jwk-set-uri',
      ),
      'https://abcd.supabase.co/auth/v1/.well-known/jwks.json',
    );
    expect(environment.getProperty('spring.data.store'), 'supabase');
    // The counters of the rate limiter are in the project's database.
    expect(
      function.context!.getBean<RateLimitStore>(),
      isNot(isA<InMemoryRateLimitStore>()),
    );
    expect(
      function.context!.getBean<EdgeWarnings>().found.join('\n'),
      isNot(
        contains('rate limiter'),
      ),
    );
  });
}
