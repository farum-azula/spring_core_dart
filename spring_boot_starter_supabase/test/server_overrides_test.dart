@Tags(['supabase'])
library;

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:test/test.dart';

import 'server_support.dart';

// What the application sets itself: the switch of the starter's part in
// Spring Security, properties of the resource server that replace the
// starter's defaults, and the issuer of a project behind another address.
void main() {
  final keys = testKeys;

  late KeyServer project;
  TestServer? server;

  setUp(() async => project = await KeyServer.project(keys));

  tearDown(() async {
    await server?.close();
    server = null;
    await project.close();
  });

  Future<TestServer> start(List<String> properties) async =>
      server = await TestServer.start(
        projectUrl: project.url,
        properties: properties,
      );

  String token({Map<String, Object?> changes = const {}}) =>
      sign(keys, userClaims(project.issuer, changes: changes));

  group('spring.supabase.auth.enabled=false', () {
    test('no resource server: no decoder, none of its properties, and a '
        "user's token is no login", () async {
      final app = await start(['spring.supabase.auth.enabled=false']);
      expect(app.context.containsBean('jwtDecoder'), isFalse);
      expect(
        app.context.getBeanProvider<JwtDecoder>().getIfAvailable(),
        isNull,
      );
      final environment = app.context.getBean<Environment>();
      for (final name in [
        'jwk-set-uri',
        'secret-key',
        'issuer-uri',
        'jws-algorithms',
        'audiences',
        'required-claims.role',
        'authorities-claim-name',
        'authority-prefix',
      ]) {
        expect(environment.getProperty('$jwtProperties.$name'), isNull);
      }
      // The security starter's own default: the generated user.
      expect(app.context.containsBean('inMemoryUserDetailsManager'), isTrue);
      expect((await app.me(token())).status, 401);
      expect((await app.me(null)).status, 401);
      expect(project.requests, isEmpty);
    });

    test('with a legacy secret too: the secret is given to no '
        'decoder', () async {
      final app = await start([
        'spring.supabase.auth.enabled=false',
        'spring.supabase.auth.jwt-secret=a-legacy-secret-of-32-characters',
      ]);
      expect(app.context.containsBean('jwtDecoder'), isFalse);
      final environment = app.context.getBean<Environment>();
      expect(environment.getProperty('$jwtProperties.secret-key'), isNull);
    });

    test("the application's own resource server is left as it is "
        'written', () async {
      final jwks = '${project.url}/auth/v1/.well-known/jwks.json';
      final app = await start([
        'spring.supabase.auth.enabled=false',
        '$jwtProperties.jwk-set-uri=$jwks',
      ]);
      // RS256, the default of jwk-set-uri: nothing of the starter is added
      // (no issuer, no audience, no role, no ES256).
      final own = sign(keys, {
        'sub': 'someone',
        'exp': TokenFactory.now() + 3600,
        'scope': 'read',
      }, alg: 'RS256');
      final answer = await app.me(own);
      expect(answer.status, 200, reason: answer.text);
      expect(answer.json, {
        'name': 'someone',
        'authorities': ['SCOPE_read'],
      });
      expectRefused(await app.me(token()), because: Because.algorithmOrKey);
    });
  });

  test("the application's own audiences replace authenticated", () async {
    final app = await start(['$jwtProperties.audiences=my-api']);
    expectRefused(await app.me(token()), because: Because.audience);
    final answer = await app.me(token(changes: {'aud': 'my-api'}));
    expect(answer.status, 200, reason: answer.text);
    // The rest of the starter's checks stays.
    expectRefused(
      await app.me(token(changes: {'aud': 'my-api', 'role': 'anon'})),
      because: Because.role,
    );
    expectRefused(
      await app.me(token(changes: {'aud': 'my-api', 'iss': 'supabase'})),
      because: Because.issuer,
    );
  });

  test("the application's own algorithms replace ES256 and RS256", () async {
    final app = await start(['$jwtProperties.jws-algorithms=ES256']);
    expect((await app.me(token())).status, 200);
    expectRefused(
      await app.me(sign(keys, userClaims(project.issuer), alg: 'RS256')),
      because: Because.algorithmOrKey,
    );
  });

  test('spring.supabase.auth.issuer is the issuer of the tokens, and of '
      'those passed on to the project', () async {
    const issuer = 'https://auth.example.com/auth/v1';
    final app = await start(['spring.supabase.auth.issuer=$issuer']);
    expectRefused(await app.me(token()), because: Because.issuer);
    final custom = token(changes: {'iss': issuer});
    final answer = await app.me(custom);
    expect(answer.status, 200, reason: answer.text);
    // The keys still come from the project's address.
    expect(project.requests, isNotEmpty);
    expect(project.requests, everyElement('/auth/v1/.well-known/jwks.json'));
    app.transport
        .when(HttpMethod.get, '/rest/v1/todos')
        .respond(200, json: <Object?>[]);
    expect((await app.get('/api/todos', bearer: custom)).status, 200);
    final sent = app.transport.requests.single;
    expect(sent.url.origin, project.url);
    expect(sent.headers['Authorization'], 'Bearer $custom');
    expect(sent.headers['apikey'], anonKey);
  });
}
