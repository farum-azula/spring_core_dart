import 'dart:convert';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_web_dart/testing.dart';

/// The project the tests talk to.
const projectUrl = 'https://abcd.supabase.co';

/// Properties of [projectUrl] with an anon key (and a service role key
/// when [serviceRole]).
SupabaseProperties properties({bool serviceRole = false}) =>
    SupabaseProperties()
      ..url = projectUrl
      ..anonKey = 'anon-key'
      ..serviceRoleKey = serviceRole ? 'service-key' : null;

/// A client of [projectUrl] over [transport], as nobody (the anon key)
/// unless [credentials] is given.
SupabaseHttp http(
  MockHttpTransport transport, {
  SupabaseProperties? properties_,
  SupabaseCredentials? credentials,
}) {
  final all = properties_ ?? properties();
  return SupabaseHttp(
    properties: all,
    transport: transport,
    credentials:
        credentials ??
        DefaultSupabaseCredentials(properties: all, authentication: () => null),
  );
}

/// A token shaped like a JWT with [claims] (not signed: for code that
/// only reads claims).
String unsignedToken(Map<String, Object?> claims) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'ES256', 'typ': 'JWT'})}.${part(claims)}.c2ln';
}

/// A bearer token as a resource server leaves it in the security context.
final class TestToken implements OAuth2Token {
  /// The token [tokenValue].
  TestToken(this.tokenValue);

  @override
  final String tokenValue;

  @override
  DateTime? get issuedAt => null;

  @override
  DateTime? get expiresAt => null;
}
