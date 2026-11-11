import 'dart:convert';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_supabase/src/config/supabase_properties.dart';
import 'package:spring_boot_starter_supabase/src/supabase_credentials.dart';

/// Row-level security as the current user on the SQL path
/// (`spring.supabase.db.rls: user`; the bean `supabaseRlsSessionHook`).
///
/// SQL over `spring.supabase.db.url` runs as the user of that address,
/// usually `postgres`, which passes row-level security. With `rls: user`
/// every transaction, and every statement outside one, first becomes the
/// caller, the way the project's REST API does:
///
/// - a signed-in user: the role `authenticated` and the claims of their
///   token (`auth.uid()`, `auth.jwt()` and the policies see them);
/// - nobody: the role `anon`;
/// - inside `SupabaseCredentials.asServiceRole`: nothing is changed, the
///   statements run as the address's user.
///
/// In a transaction the role and the claims are set for that transaction
/// only (`set local`). Outside one they are set on the connection and
/// taken off again before it goes back to the pool; a connection whose
/// reset fails is closed, never reused.
///
/// The role is one of two fixed names and the claims are passed as a
/// value, never written into the SQL text.
///
/// Only the data source of `spring.supabase.db.url` is touched, and only
/// when its driver is PostgreSQL.
final class SupabaseRlsSessionHook extends JdbcSessionHook {
  /// A hook for the database of [properties], asking [credentials] who
  /// calls.
  SupabaseRlsSessionHook({required this.properties, required this.credentials});

  /// The `spring.supabase.*` properties.
  final SupabaseProperties properties;

  /// Who the current call is made as.
  final SupabaseCredentials credentials;

  late final Uri? _database = switch (properties.db.url?.trim()) {
    final url? when url.isNotEmpty => Uri.tryParse(
      url.startsWith('jdbc:') ? url.substring(5) : url,
    ),
    _ => null,
  };

  bool _applies(DataSource dataSource) {
    final database = _database;
    final url = dataSource.settings.url;
    return properties.db.rls == SupabaseRls.user &&
        database != null &&
        dataSource.driver.name == 'postgres' &&
        url.host == database.host &&
        (url.hasPort ? url.port : 5432) ==
            (database.hasPort ? database.port : 5432) &&
        url.path == database.path;
  }

  @override
  Future<void> afterBegin(ConnectionHolder transaction) async {
    if (_applies(transaction.dataSource)) {
      await _become(transaction.connection, local: true);
    }
  }

  @override
  Future<void> beforeWork(
    DataSource dataSource,
    JdbcConnection connection,
  ) async {
    if (_applies(dataSource)) {
      await _become(connection, local: false);
    }
  }

  @override
  Future<void> afterWork(
    DataSource dataSource,
    JdbcConnection connection,
  ) async {
    if (_applies(dataSource)) {
      await connection.execute('reset role');
      await _claims(connection, const ['', '', ''], local: false);
    }
  }

  Future<void> _become(JdbcConnection connection, {required bool local}) async {
    final caller = credentials.caller;
    if (caller.role == SupabaseRole.service) {
      return;
    }
    final scope = local ? 'set local role' : 'set role';
    if (caller.role == SupabaseRole.anon) {
      await connection.execute('$scope anon');
      await _claims(connection, const [
        '{"role":"anon"}',
        '',
        'anon',
      ], local: local);
      return;
    }
    final claims = supabaseTokenClaims(await credentials.accessToken());
    final subject = claims?['sub'];
    if (claims == null || subject is! String || subject.isEmpty) {
      throw PermissionDeniedDataAccessException(
        'The token of the current user has no claims to give the database '
        '(spring.supabase.db.rls: user)',
      );
    }
    await connection.execute('$scope authenticated');
    await _claims(connection, [
      jsonEncode(claims),
      subject,
      'authenticated',
    ], local: local);
  }

  // The claims as the database's functions read them (`auth.uid()`,
  // `auth.jwt()`, `auth.role()`): the whole of them, and the two older
  // settings some policies still read.
  static Future<void> _claims(
    JdbcConnection connection,
    List<String> values, {
    required bool local,
  }) => connection.query(
    "select set_config('request.jwt.claims', ?, $local), "
    "set_config('request.jwt.claim.sub', ?, $local), "
    "set_config('request.jwt.claim.role', ?, $local)",
    values,
  );
}
