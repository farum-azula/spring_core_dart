/// How the connection to PostgreSQL is secured: the values of libpq's
/// `sslmode` the `postgres` package offers (the driver turns the others,
/// `prefer` and `allow`, into a try with TLS and then without).
enum PostgresSslMode {
  /// No TLS: the password may travel as plain text. Only for a database
  /// that nobody else can listen to.
  disable,

  /// TLS, without checking the server's certificate (an eavesdropper is
  /// kept out, a machine in the middle is not).
  require,

  /// TLS, with the certificate and the host name checked against the
  /// system's trusted roots, or `sslrootcert`.
  verifyFull,
}

/// Where and how to open one connection: what the driver parsed out of the
/// URL and the properties, for a [PostgresBinding].
///
/// Spring (Java): the `java.util.Properties` of `org.postgresql.Driver`.
final class PostgresEndpoint {
  /// An endpoint on [host], [port], for [database].
  const PostgresEndpoint({
    required this.host,
    required this.port,
    required this.database,
    this.username,
    this.password,
    this.sslMode = PostgresSslMode.require,
    this.rootCertificate,
    this.connectTimeout = const Duration(seconds: 15),
    this.applicationName,
  });

  /// The host name or address.
  final String host;

  /// The port (5432 by default).
  final int port;

  /// The database.
  final String database;

  /// The user.
  final String? username;

  /// The password. Never logged.
  final String? password;

  /// The TLS mode.
  final PostgresSslMode sslMode;

  /// The path of a PEM file of the certificate authorities the server's
  /// certificate is checked against (`sslrootcert`); null: the system's.
  final String? rootCertificate;

  /// The longest wait for the connection, the TLS handshake included.
  final Duration connectTimeout;

  /// What the server shows for this connection in `pg_stat_activity`.
  final String? applicationName;

  @override
  String toString() => 'PostgresEndpoint($host:$port/$database)';
}

/// One row of a result, with the labels of its columns.
final class PostgresRow {
  /// A row of [values] under [columns] (the list may be shared by the rows
  /// of one result).
  const PostgresRow(this.columns, this.values);

  /// The column labels.
  final List<String> columns;

  /// The values, as the `postgres` package decodes them.
  final List<Object?> values;
}

/// What a statement returned.
final class PostgresResult {
  /// A result of [rows] under [columns], for a statement that changed
  /// [affectedRows] rows.
  const PostgresResult(this.columns, this.rows, this.affectedRows);

  /// The column labels (empty for a statement that returns no rows).
  final List<String> columns;

  /// The values of each row.
  final List<List<Object?>> rows;

  /// The rows an insert, update or delete changed.
  final int affectedRows;
}

/// What the PostgreSQL driver needs from the `postgres` package, and
/// nothing more.
///
/// The starter has no dependency on `postgres`. The application lists the
/// package; the generator, seeing it, writes a few lines into the generated
/// module that implement this interface and make a `PostgresJdbcDriver` of
/// them. The logic (the URL, TLS fallback, transactions, savepoints, the
/// `?` markers turned into `$1`, error text without values) stays in the
/// starter, where it is tested without a database.
///
/// Every method throws a `SqlError` (the generated lines convert the
/// package's `ServerException`: its message, never its `detail`, which
/// holds values, its SQL state as `sqlState` and the constraint's name),
/// not an exception of the package.
///
/// Spring (Java): the JDBC driver's `org.postgresql.Driver` seen through
/// `java.sql.Driver`.
abstract interface class PostgresBinding {
  /// Opens a connection to [endpoint].
  Future<PostgresSession> open(PostgresEndpoint endpoint);
}

/// One open connection of a [PostgresBinding]; statements use `$1`, `$2`
/// for their parameters.
///
/// Spring (Java): the driver's `java.sql.Connection`, at its lowest level.
abstract interface class PostgresSession {
  /// Whether the connection is open (the server closes it on a fatal error
  /// and when it shuts down).
  bool get isOpen;

  /// Runs [sql] with [parameters] and returns its rows; with [simple] it
  /// goes through the simple query protocol, for statements without
  /// parameters or rows (`BEGIN`, `SET`, DDL). A statement past [timeout]
  /// is cancelled by the server (SQL state `57014`).
  Future<PostgresResult> execute(
    String sql, {
    List<Object?> parameters = const [],
    bool simple = false,
    Duration? timeout,
  });

  /// Runs [sql] and gives its rows as the server sends them; cancelling the
  /// subscription drops the rest of the rows and leaves the connection
  /// usable.
  Stream<PostgresRow> stream(
    String sql, {
    List<Object?> parameters = const [],
    Duration? timeout,
  });

  /// Closes the connection.
  Future<void> close();
}
