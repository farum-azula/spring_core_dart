import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_supabase/src/config/supabase_properties.dart';

/// What the starter checks and says once, when the application starts
/// (the bean `supabaseStartup`).
///
/// - `spring.supabase.url` with a trailing slash, a query or a user is
///   refused: the addresses of the services and the issuer of the tokens
///   are made from it.
/// - How the repositories reach the database is said once (the REST API,
///   or SQL and over which kind of connection), without any password.
///   The transaction pooler is warned about, and refused together with
///   `spring.supabase.db.rls: user`.
/// - In a client application (Flutter), a key or a password that ships in
///   the app is warned about, once each: `service-role-key`, `db.url`,
///   `auth.jwt-secret`. Nothing is forbidden (an internal tool, an admin
///   app); the warning says what whoever has the app can do with it.
final class SupabaseStartup {
  /// Checks [properties]; [isClientApplication] is whether the code runs
  /// in a client application (Flutter) rather than on a server.
  SupabaseStartup(
    this.properties, {
    bool isClientApplication = const bool.fromEnvironment('dart.library.ui'),
    SpringLog log = const SpringLog('spring.supabase'),
  }) {
    final url = properties.url?.trim() ?? '';
    if (url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !uri.hasAuthority ||
          (uri.scheme != 'https' && uri.scheme != 'http') ||
          uri.hasQuery ||
          uri.hasFragment ||
          uri.userInfo.isNotEmpty ||
          url.endsWith('/')) {
        throw StateError(
          'spring.supabase.url must be an http(s) address without a '
          'trailing slash, user, query or fragment, like '
          'https://<ref>.supabase.co',
        );
      }
    }
    _describeData(url, log);
    if (!isClientApplication) {
      return;
    }
    for (final (key, value, consequence) in [
      (
        'spring.supabase.service-role-key',
        properties.serviceRoleKey,
        'whoever has the app reads and writes every table past row-level '
            'security',
      ),
      (
        'spring.supabase.db.url',
        properties.db.url,
        'whoever has the app has the database password',
      ),
      (
        'spring.supabase.auth.jwt-secret',
        properties.auth.jwtSecret,
        'whoever has the app can sign a token for any user (and a client '
            'application does not use it: only a server checks tokens)',
      ),
    ]) {
      if (value != null && value.trim().isNotEmpty) {
        warnings.add('$key ships in this application: $consequence');
        log.warning('$key ships in this application: $consequence');
      }
    }
  }

  // Says once how the repositories reach the database, and refuses what
  // would let one user's statements run as another.
  void _describeData(String url, SpringLog log) {
    final text = properties.db.url?.trim() ?? '';
    final asUser = properties.db.rls == SupabaseRls.user;
    if (text.isEmpty) {
      if (url.isNotEmpty) {
        dataPath = 'the REST API of ${Uri.parse(url).host}';
        log.info(
          'Supabase: the repositories use $dataPath, as the current user '
          '(row-level security applies); no transactions, locks or SQL '
          '(spring.supabase.db.url for those)',
        );
      }
      return;
    }
    final database = Uri.tryParse(
      text.startsWith('jdbc:') ? text.substring(5) : text,
    );
    if (database == null || database.host.isEmpty) {
      throw StateError(
        'spring.supabase.db.url is not the address of a database '
        '(postgresql://user:password@host:5432/postgres)',
      );
    }
    final port = database.hasPort ? database.port : 5432;
    final pooler = database.host.endsWith('.pooler.supabase.com');
    final transactionPooler = pooler && port == 6543;
    final kind = transactionPooler
        ? 'transaction pooler'
        : pooler
        ? 'session pooler'
        : 'direct connection';
    dataPath = 'SQL over ${database.host}:$port ($kind)';
    if (transactionPooler) {
      if (asUser) {
        throw StateError(
          'spring.supabase.db.rls: user cannot be used through the '
          'transaction pooler (${database.host}:6543): it keeps no session '
          'between statements, so a role set for one user could be used '
          "by another's statement. Use the session pooler (port 5432) or "
          'the direct connection',
        );
      }
      const warning =
          'spring.supabase.db.url is the transaction pooler (port 6543): '
          'it keeps no session between transactions, so prepared '
          'statements, advisory locks and LISTEN do not work through it. '
          'Use the session pooler (port 5432) or the direct connection';
      warnings.add(warning);
      log.warning(warning);
    }
    final who = asUser
        ? 'as the current user (row-level security applies)'
        : 'as the user of the address (row-level security is passed; '
              'spring.supabase.db.rls: user to apply it)';
    log.info('Supabase: the repositories use $dataPath, $who');
  }

  /// The `spring.supabase.*` properties.
  final SupabaseProperties properties;

  /// How the repositories reach the database (`the REST API of <host>`,
  /// `SQL over <host>:<port> (<kind of connection>)`); `null` without a
  /// project. Never a password or a key.
  String? dataPath;

  /// What was warned about, for tests and the actuator.
  final List<String> warnings = [];
}
