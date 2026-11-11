import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_supabase/src/config/supabase_properties.dart';
import 'package:spring_security_core/spring_security_core.dart';
import 'package:spring_web_dart/spring_web_dart.dart' show RequestContextHolder;

/// As whom a call to Supabase is made.
enum SupabaseRole {
  /// Nobody is signed in: the anon key.
  anon,

  /// A signed-in user: their access token.
  user,

  /// The service role, which passes row-level security.
  service,
}

/// Who a call to Supabase is made as: nobody ([SupabaseRole.anon]), a user
/// with their id, or the service role.
///
/// Two calls with equal callers see the same rows, so [key] is what a
/// cache key carries (see `SupabaseKeyGenerator`).
final class SupabaseCaller {
  /// Nobody is signed in.
  const SupabaseCaller.anon() : role = SupabaseRole.anon, id = null;

  /// The user with [id] (the token's `sub`).
  const SupabaseCaller.user(String this.id) : role = SupabaseRole.user;

  /// The service role.
  const SupabaseCaller.service() : role = SupabaseRole.service, id = null;

  /// The kind of caller.
  final SupabaseRole role;

  /// The user's id; `null` unless [role] is [SupabaseRole.user].
  final String? id;

  /// `anon`, `user:<id>` or `service`.
  String get key => switch (role) {
    SupabaseRole.anon => 'anon',
    SupabaseRole.user => 'user:$id',
    SupabaseRole.service => 'service',
  };

  @override
  bool operator ==(Object other) =>
      other is SupabaseCaller && other.role == role && other.id == id;

  @override
  int get hashCode => Object.hash(role, id);

  @override
  String toString() => key;
}

/// The one place every call to Supabase takes its key and token from: the
/// repositories, Storage, Edge Functions and Realtime all ask this bean,
/// so they always act as the same user.
///
/// - Inside [asServiceRole]: the service role key.
/// - Else, in a client application with a signed-in user (the
///   `LoginSession` bean, `SupabaseAuth`): the user's access token,
///   refreshed before it expires.
/// - Else, on a server handling a request with a bearer token of this
///   project's Auth: that token, so the database applies the caller's
///   row-level security.
/// - Else: the anon key.
///
/// ```dart
/// // On a server, a job that must see every row:
/// await credentials.asServiceRole(() => todos.deleteByDoneTrue());
/// ```
///
/// A key or a token is only ever sent to `spring.supabase.url`.
abstract interface class SupabaseCredentials {
  /// The key sent as `apikey`: the anon key, or the service role key
  /// inside [asServiceRole].
  String get apiKey;

  /// The bearer token of the next call (see the class for whose).
  Future<String> accessToken();

  /// Who the next call is made as.
  SupabaseCaller get caller;

  /// Runs [body] with every call to Supabase made in it (and in what it
  /// starts) as the service role. Throws a [StateError] when
  /// `spring.supabase.service-role-key` is not set.
  Future<T> asServiceRole<T>(FutureOr<T> Function() body);
}

/// The default [SupabaseCredentials] (the bean `supabaseCredentials`).
final class DefaultSupabaseCredentials implements SupabaseCredentials {
  /// Credentials from [properties]; `session` gives the application's
  /// login when it has one (looked up at each call, since the login bean
  /// itself needs the credentials), `authentication` the current user of
  /// a server (Spring Security's context unless given).
  DefaultSupabaseCredentials({
    required this.properties,
    this._session,
    Authentication? Function()? authentication,
  }) : _authentication =
           authentication ??
           (() => SecurityContextHolder.getContext().authentication);

  /// The `spring.supabase.*` properties.
  final SupabaseProperties properties;

  final LoginSession? Function()? _session;
  final Authentication? Function() _authentication;

  static final Object _serviceRole = Object();

  bool get _isServiceRole => Zone.current[_serviceRole] == true;

  // The application's own login (SupabaseAuth), which is one for the
  // whole process: the user of a client application. Never while a server
  // handles a request: there the caller is whoever sent the request, and
  // a login made in the process (an endpoint that signs a user in, a
  // session restored at start) must not become the caller of everybody
  // else's requests.
  LoginSession? get _login {
    if (RequestContextHolder.currentRequest != null) {
      return null;
    }
    final session = _session?.call();
    return session != null && session.isLoggedIn ? session : null;
  }

  String get _anonKey => switch (properties.anonKey?.trim()) {
    final key? when key.isNotEmpty => key,
    _ => throw StateError(
      'spring.supabase.anon-key is not set: every call to Supabase needs '
      "the project's anon (publishable) key",
    ),
  };

  String get _serviceKey => switch (properties.serviceRoleKey?.trim()) {
    final key? when key.isNotEmpty => key,
    _ => throw StateError(
      'spring.supabase.service-role-key is not set: asServiceRole needs '
      "the project's service role key (keep it on a server)",
    ),
  };

  /// The issuer of this project's tokens: `spring.supabase.auth.issuer`,
  /// else `<url>/auth/v1`.
  String? get issuer {
    final issuer = properties.auth.issuer?.trim();
    if (issuer != null && issuer.isNotEmpty) {
      return issuer;
    }
    final url = properties.url?.trim();
    if (url == null || url.isEmpty) {
      return null;
    }
    return '${url.endsWith('/') ? url.substring(0, url.length - 1) : url}'
        '/auth/v1';
  }

  @override
  String get apiKey => _isServiceRole ? _serviceKey : _anonKey;

  @override
  Future<String> accessToken() async {
    if (_isServiceRole) {
      return _serviceKey;
    }
    final session = _login;
    if (session != null) {
      final token = await session.accessToken();
      if (token != null) {
        return token;
      }
      // Signed in when the call began, and the session ended while its
      // token was asked for (the refresh was refused): the call was a
      // user's, and must not go on as nobody's with the anon key.
      throw CredentialsExpiredException(
        'The session ended while the call was made: sign in again',
      );
    }
    return _requestToken()?.token ?? _anonKey;
  }

  @override
  SupabaseCaller get caller {
    if (_isServiceRole) {
      return const SupabaseCaller.service();
    }
    final session = _login;
    if (session != null) {
      final name = session.authentication?.name;
      if (name != null && name.isNotEmpty) {
        return SupabaseCaller.user(name);
      }
    }
    return switch (_requestToken()) {
      final token? => SupabaseCaller.user(token.subject),
      null => const SupabaseCaller.anon(),
    };
  }

  @override
  Future<T> asServiceRole<T>(FutureOr<T> Function() body) {
    _serviceKey;
    return runZoned(
      () async => await body(),
      zoneValues: {_serviceRole: true},
    );
  }

  // The bearer token of the current request, when it is a user's token of
  // this project. The server has verified it already (the resource server
  // refuses anything else before a controller runs); here it is only
  // decided whether to pass it on: a token of another issuer (Keycloak, a
  // test user) is never sent to Supabase.
  ({String token, String subject})? _requestToken() {
    final authentication = _authentication();
    if (authentication == null || !authentication.isAuthenticated) {
      return null;
    }
    final credentials = authentication.credentials;
    if (credentials is! OAuth2Token) {
      return null;
    }
    final claims = supabaseTokenClaims(credentials.tokenValue);
    if (claims == null) {
      return null;
    }
    final subject = claims['sub'];
    if (claims['iss'] != issuer ||
        claims['role'] != 'authenticated' ||
        subject is! String ||
        subject.isEmpty) {
      return null;
    }
    return (token: credentials.tokenValue, subject: subject);
  }
}

/// The claims of [token], a JWT, read without checking its signature;
/// `null` when the text is no JWT.
///
/// For code that only decides what to do with a token already checked
/// elsewhere (a server's resource server, the project's Auth), never to
/// decide whether to trust one.
Map<String, Object?>? supabaseTokenClaims(String token) {
  final parts = token.split('.');
  if (parts.length != 3) {
    return null;
  }
  try {
    final json = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    return json is Map<String, Object?> ? json : null;
  } on FormatException {
    return null;
  }
}
