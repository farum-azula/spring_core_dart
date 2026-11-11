// What the tests share: the whole server with a project that is not
// there. Its calls to the project's Storage and Edge Functions go to a
// MockHttpTransport, its statements to a FakeDatabase
// (test/stack_test.dart runs the same server against a real project).
import 'dart:convert';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_security/testing.dart';
import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

import '../../bin/spring_gen/main.spring.dart';
import 'fake_database.dart';

export 'fake_database.dart';

/// The project of the tests.
const projectUrl = 'https://abcd.supabase.co';

/// The keys the server sends to the project.
const anonKey = 'anon-KEY-9f3a71c2';
const serviceRoleKey = 'service-KEY-5be04d17';

/// The id of the user of the tokens (a token's `sub`).
const userId = '6f1c2d0e-8a51-4b7e-9c33-0d5a4be7f210';

/// The server with [http] as its network and [database] as the project's
/// database, once for the tests of the calling `main` or `group`. The
/// variables are what a deployment sets (lib/resources/application.yml
/// reads them).
SpringBootTestContext exampleServer(
  MockHttpTransport http,
  FakeDatabase database,
) => springBootTest(
  springApplication,
  systemEnvironment: const {
    'SUPABASE_URL': projectUrl,
    'SUPABASE_ANON_KEY': anonKey,
    'SUPABASE_SERVICE_ROLE_KEY': serviceRoleKey,
    'SUPABASE_DB_URL':
        'postgresql://postgres:secret@db.abcd.supabase.co/postgres',
  },
  overrides: [
    BeanOverride<HttpTransport>(http, name: 'httpTransport'),
    BeanOverride<JdbcDriver>(database, name: 'postgresJdbcDriver'),
  ],
);

String _part(Map<String, Object?> json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

/// An access token of the project's user [userId] as Supabase Auth writes
/// one, with [roles] in `app_metadata.roles` and [issuer] as its `iss`.
/// Signed by nobody: [projectUser] puts it past the resource server, whose
/// checks are the starter's (and tested there).
String userToken({
  List<String> roles = const [],
  String issuer = '$projectUrl/auth/v1',
}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return [
    _part({'alg': 'ES256', 'typ': 'JWT', 'kid': 'test'}),
    _part({
      'iss': issuer,
      'sub': userId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'iat': now,
      'exp': now + 3600,
      'email': 'ada@example.com',
      'app_metadata': {'provider': 'email', 'roles': roles},
    }),
    'c2lnbmF0dXJl',
  ].join('.');
}

/// A request that carries [token] (a [userToken]), as the resource server
/// leaves it after its checks: the token as the request's credentials,
/// `ROLE_<role>` for each of its `app_metadata.roles`.
///
/// Not `jwt()` of `spring_boot_starter_security/testing.dart`: its token
/// is the text `token`, and the Supabase starter reads the claims it
/// passes on to the project from the token itself.
RequestPostProcessor projectUser([String? token]) {
  final value = token ?? userToken();
  final claims = jsonDecode(
    utf8.decode(
      base64Url.decode(base64Url.normalize(value.split('.')[1])),
    ),
  ) as Map<String, Object?>;
  final roles = switch (claims['app_metadata']) {
    {'roles': final List<Object?> roles} => roles,
    _ => const <Object?>[],
  };
  return authentication(
    JwtAuthenticationToken(
      Jwt(value, headers: const {'alg': 'ES256'}, claims: claims),
      [for (final role in roles) SimpleGrantedAuthority('ROLE_$role')],
    ),
  );
}
