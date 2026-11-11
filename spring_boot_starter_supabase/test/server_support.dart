// A server as an application gets it from the web starter, the security
// starter and this starter, on a port of the loopback interface, beside a
// Supabase project that serves its public keys there too. The server's
// calls to the project's REST API go to a MockHttpTransport; its keys are
// fetched over HTTP, as in production.
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_boot_starter_security/spring_auto_configuration.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_supabase/spring_auto_configuration.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

// The keys and the token signer of the security starter's own tests.
import '../../spring_boot_starter_security/test/app/jwt/keys.dart';
import 'server_app/web/web.dart';
import 'spring_gen/app/supabase_app.spring.dart';

export 'package:spring_boot_starter_security/spring_boot_starter_security.dart'
    show HttpMethod;
export 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show MockHttpTransport;

export '../../spring_boot_starter_security/test/app/jwt/keys.dart';

/// The prefix of the resource server's properties.
const jwtProperties = 'spring.security.oauth2.resourceserver.jwt';

/// The keys the application sends to the project.
const anonKey = 'anon-KEY-9f3a71c2';
const serviceRoleKey = 'service-KEY-5be04d17';

/// The id of the user of the tokens (a token's `sub`).
const userId = '6f1c2d0e-8a51-4b7e-9c33-0d5a4be7f210';

/// A key set served on the loopback interface: a Supabase project (its
/// keys at `/auth/v1/.well-known/jwks.json` only) or an attacker's host
/// (its keys at every path).
final class KeyServer {
  KeyServer._(this._server, this.body);

  /// A project with the public halves of [keys].
  static Future<KeyServer> project(TokenFactory keys) => _start(
    jsonEncode({
      'keys': [
        // As Supabase publishes them.
        {
          ...keys.ec.jwk,
          'alg': 'ES256',
          'use': 'sig',
          'key_ops': ['verify'],
          'ext': true,
        },
        {
          ...keys.rsa.jwk,
          'alg': 'RS256',
          'key_ops': ['verify'],
          'ext': true,
        },
      ],
    }),
    only: '/auth/v1/.well-known/jwks.json',
  );

  /// A host answering every request with [jwks].
  static Future<KeyServer> attacker(List<Map<String, Object?>> jwks) =>
      _start(jsonEncode({'keys': jwks}));

  static Future<KeyServer> _start(String body, {String? only}) async {
    final server = await io.HttpServer.bind(
      io.InternetAddress.loopbackIPv4,
      0,
    );
    final keys = KeyServer._(server, body);
    server.listen((request) {
      keys.requests.add(request.uri.path);
      final response = request.response
        ..headers.contentType = io.ContentType.json;
      if (only == null || request.uri.path == only) {
        response.write(body);
      } else {
        response.statusCode = io.HttpStatus.notFound;
      }
      unawaited(response.close());
    });
    return keys;
  }

  final io.HttpServer _server;

  /// The key set, as served.
  final String body;

  /// The paths asked for so far.
  final requests = <String>[];

  /// `spring.supabase.url` of the project.
  String get url => 'http://127.0.0.1:${_server.port}';

  /// The `iss` of the project's tokens.
  String get issuer => '$url/auth/v1';

  Future<void> close() => _server.close(force: true);
}

/// The claims of a user's access token of the project whose issuer is
/// [issuer], as Supabase Auth writes them, with [changes] on top and
/// [without] taken out.
Map<String, Object?> userClaims(
  String issuer, {
  Map<String, Object?> changes = const {},
  List<String> without = const [],
}) {
  final now = TokenFactory.now();
  return {
    'iss': issuer,
    'sub': userId,
    'aud': 'authenticated',
    'role': 'authenticated',
    'iat': now,
    'exp': now + 3600,
    'email': 'ada@example.com',
    'phone': '',
    'app_metadata': {
      'provider': 'email',
      'providers': ['email'],
    },
    'user_metadata': {'email_verified': true},
    'aal': 'aal1',
    'amr': [
      {'method': 'password', 'timestamp': now},
    ],
    'session_id': '0b0f3d0a-52f4-4c8e-8a39-4f7b1f6c2e11',
    'is_anonymous': false,
    ...changes,
  }..removeWhere((name, _) => without.contains(name));
}

/// The claims of the project's legacy anon or service role key (a JWT
/// signed like a user's token).
Map<String, Object?> apiKeyClaims(String role) {
  final now = TokenFactory.now();
  return {
    'iss': 'supabase',
    'ref': 'abcdefghijklmnopqrst',
    'role': role,
    'iat': now - 86400,
    'exp': now + 10 * 365 * 86400,
  };
}

/// A token with exactly [claims], signed by [keys] with [alg]. Its header
/// is `alg`, `typ`, the `kid` of the key (none for an HMAC) and [header] on
/// top, where a `null` takes a member out.
String sign(
  TokenFactory keys,
  Map<String, Object?> claims, {
  String alg = 'ES256',
  Map<String, Object?> header = const {},
}) {
  final all = <String, Object?>{
    'alg': alg,
    'typ': 'JWT',
    'kid': alg.startsWith('ES')
        ? keys.ec.kid
        : alg.startsWith('HS')
        ? null
        : keys.rsa.kid,
    ...header,
  }..removeWhere((_, value) => value == null);
  final input = '${b64Json(all)}.${b64Json(claims)}';
  return '$input.${b64(keys.signature(alg, ascii.encode(input)))}';
}

/// A token of three parts with [header], [claims] and [signature], signed
/// by nobody.
String unsigned(
  Map<String, Object?> header,
  Map<String, Object?> claims, [
  String signature = '',
]) => '${b64Json(header)}.${b64Json(claims)}.$signature';

/// What the server answered.
final class Answer {
  Answer(this.status, this.headers, this.body);

  final int status;

  /// Lower-case names, the values joined with `, `.
  final Map<String, String> headers;

  final String body;

  /// The body as JSON.
  Object? get json => jsonDecode(body);

  /// Everything a client can read.
  String get text => '$status\n$headers\n$body';

  @override
  String toString() => text;
}

/// A started server and what it sent to the project.
final class TestServer {
  TestServer._(this.port, this.context, this.transport, this._stop);

  /// Starts the application with [properties] on top of the project's
  /// address and keys, [configurations] beside its endpoints, and
  /// [decoder] as its own `JwtDecoder` bean when given.
  static Future<TestServer> start({
    required String projectUrl,
    List<String> properties = const [],
    List<BeanModule> configurations = const [],
    JwtDecoder Function()? decoder,
  }) async {
    final transport = MockHttpTransport();
    final ready = Completer<TestServer>();
    final stop = Completer<void>();
    final done =
        serverRunner(
          transport,
          projectUrl: projectUrl,
          properties: properties,
          configurations: configurations,
          decoder: decoder,
        ).runAsync((started) async {
          final failure = started.startupFailure;
          if (failure != null) {
            ready.completeError(
              StateError('The application failed to start: $failure'),
            );
            return;
          }
          final lifecycle = started.context
              .getBean<WebServerStartStopLifecycle>();
          final server = (await lifecycle.started)!;
          ready.complete(
            TestServer._(server.port, started.context, transport, stop),
          );
          await stop.future;
        });
    final server = await ready.future;
    server._done = done;
    return server;
  }

  final int port;
  final ApplicationContext context;

  /// The project's REST API, as the server calls it.
  final MockHttpTransport transport;

  final Completer<void> _stop;
  late final Future<void> _done;
  final _client = io.HttpClient();

  /// `GET` [path] with [bearer] as the bearer token and [headers].
  Future<Answer> get(
    String path, {
    String? bearer,
    Map<String, String> headers = const {},
  }) async {
    final request = await _client.getUrl(
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    request.headers.set('accept', 'application/json');
    if (bearer != null) {
      request.headers.set('authorization', 'Bearer $bearer');
    }
    headers.forEach(request.headers.set);
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    final all = <String, String>{};
    response.headers.forEach((name, values) => all[name] = values.join(', '));
    return Answer(response.statusCode, all, body);
  }

  /// The name the server gives the caller of [bearer] (`/api/me`).
  Future<Answer> me(String? bearer) => get('/api/me', bearer: bearer);

  Future<void> close() async {
    _client.close(force: true);
    _stop.complete();
    await _done;
  }
}

/// The runner of the test application (the repositories of
/// `app/supabase_app.dart` and the endpoints of `server_app/web/`) with
/// every auto-configuration an application with the web, the security and
/// the Supabase starter gets, in the order their annotations give.
ApplicationContextRunner serverRunner(
  MockHttpTransport transport, {
  required String projectUrl,
  List<String> properties = const [],
  List<BeanModule> configurations = const [],
  JwtDecoder Function()? decoder,
}) {
  var runner = const ApplicationContextRunner()
      .withUserConfiguration($application)
      .withUserConfiguration(supabaseServerBeans)
      .withAutoConfiguration(springBootAutoConfiguration)
      .withAutoConfiguration(springBootStarterLoggingAutoConfiguration)
      .withAutoConfiguration(
        springBootStarterWebAutoConfiguration,
        const AutoConfigurationModule(platform: ModulePlatform.native),
      )
      .withAutoConfiguration(springSecurityCoreAutoConfiguration)
      .withAutoConfiguration(springBootStarterOauth2ClientAutoConfiguration)
      .withAutoConfiguration(
        springBootStarterSecurityAutoConfiguration,
        const AutoConfigurationModule(
          after: ['springBootStarterOauth2ClientAutoConfiguration'],
          platform: ModulePlatform.native,
        ),
      )
      .withAutoConfiguration(
        springBootStarterSecurityOAuth2ClientAutoConfiguration,
        const AutoConfigurationModule(
          before: ['springBootStarterOauth2ClientAutoConfiguration'],
          platform: ModulePlatform.native,
        ),
      )
      .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
      .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration)
      .withAutoConfiguration(springBootStarterDataAutoConfiguration)
      .withAutoConfiguration(springBootStarterCacheAutoConfiguration)
      .withAutoConfiguration(
        springBootStarterSupabaseDataAutoConfiguration,
        const AutoConfigurationModule(
          before: ['springBootStarterDataAutoConfiguration'],
        ),
      )
      .withAutoConfiguration(
        springBootStarterSupabaseAutoConfiguration,
        const AutoConfigurationModule(
          after: [
            'springBootStarterFeignAutoConfiguration',
            'springBootStarterWebsocketAutoConfiguration',
            'springBootStarterDataAutoConfiguration',
            'springSecurityCoreAutoConfiguration',
          ],
        ),
      )
      .withAutoConfiguration(
        springBootStarterSupabaseServerAutoConfiguration,
        const AutoConfigurationModule(
          before: [
            'springBootStarterSecurityAutoConfiguration',
            'springBootStarterSecurityOAuth2ClientAutoConfiguration',
          ],
          platform: ModulePlatform.native,
        ),
      )
      .withPropertyValues([
        'spring.test.web-environment=random-port',
        'server.address=127.0.0.1',
        'spring.supabase.url=$projectUrl',
        'spring.supabase.anon-key=$anonKey',
        'spring.supabase.service-role-key=$serviceRoleKey',
        ...properties,
      ])
      .withBean<HttpTransport>(() => transport);
  for (final configuration in configurations) {
    runner = runner.withUserConfiguration(configuration);
  }
  if (decoder != null) {
    runner = runner.withBean<JwtDecoder>(decoder);
  }
  return runner;
}

/// Everything logged while [body] ran at the default level (info), as
/// text: message, error, stack trace and fields of each record.
Future<String> logged(Future<void> Function() body) async {
  final records = <String>[];
  final handler = SpringLog.handler;
  final level = SpringLog.level;
  SpringLog.handler = (_) {};
  SpringLog.level = SpringLogLevel.info;
  final stop = SpringLog.listen(
    (r) => records.add(
      '[${r.loggerName}] ${r.level.name}: ${r.message} | ${r.error} | '
      '${r.stackTrace} | ${r.fields}',
    ),
  );
  try {
    await body();
  } finally {
    stop();
    SpringLog.handler = handler;
    SpringLog.level = level;
    SpringLog.resetLevels();
  }
  return records.join('\n');
}

/// Why the resource server refuses a token, as its 401 says it.
abstract final class Because {
  static const expired = 'Jwt expired at';
  static const notYetValid = 'Jwt used before';
  static const issuer = 'The iss claim is not valid';
  static const audience = 'The aud claim is not valid';
  static const role = 'The role claim is not valid';
  static const type = 'the given typ value needs to be one of [JWT]';
  static const signature = 'Signed JWT rejected: Invalid signature';
  static const algorithmOrKey =
      'Signed JWT rejected: Another algorithm expected, or no matching '
      'key(s) found';
  static const encrypted = 'Encrypted JWTs (JWE) are not supported';
}

/// A 401 that asks for a bearer token and calls the one sent invalid,
/// [because] of that check when given.
void expectRefused(Answer answer, {String? because, String? reason}) {
  expect(answer.status, 401, reason: reason);
  expect(
    answer.headers['www-authenticate'],
    allOf([
      startsWith('Bearer'),
      contains('error="invalid_token"'),
      if (because != null) contains(because),
    ]),
    reason: reason,
  );
}
