/// How a database file is opened.
///
/// The names are those of `package:sqlite3`'s `OpenMode`, so the glue maps
/// one to the other by name.
enum SqliteOpenMode {
  /// The file must exist; nothing can be written (`?mode=ro`).
  readOnly,

  /// The file must exist; it can be written (`?mode=rw`).
  readWrite,

  /// The file is created when it is missing. The default (`?mode=rwc`).
  readWriteCreate,
}

/// What the SQLite driver needs from the `sqlite3` package, and nothing
/// more.
///
/// The starter has no dependency on `sqlite3` (it bundles a native
/// library, and pub has no optional dependencies). The application lists
/// the package; the generator, seeing it, writes a few lines into the
/// generated module that implement this interface with `sqlite3` and make
/// a `SqliteJdbcDriver` bean of it. All the logic stays in the starter,
/// where it is tested; the generated lines only forward calls.
///
/// SQLite's calls are synchronous. Every method throws a `SqlError` (the
/// generated lines convert the package's `SqliteException`: its message,
/// its result code as `vendorCode`, its extended result code as
/// `extendedCode`), never the package's own exception, and never a message
/// holding the values of the statement.
///
/// Spring (Java): the JDBC driver's `org.sqlite.JDBC` (xerial) seen through
/// `java.sql.Driver`.
abstract interface class SqliteBinding {
  /// Opens the database [filename] (a path, `:memory:` for a private
  /// in-memory database, or with [uri], a `file:` URI of SQLite).
  SqliteDatabase open(
    String filename, {
    SqliteOpenMode mode = SqliteOpenMode.readWriteCreate,
    bool uri = false,
  });
}

/// One open SQLite database.
///
/// Spring (Java): the driver's `java.sql.Connection`, at its lowest level.
abstract interface class SqliteDatabase {
  /// Runs [sql] and ignores its rows. Without [parameters], it may hold
  /// several statements separated by `;`.
  void execute(String sql, [List<Object?> parameters = const []]);

  /// Runs [sql] and returns all its rows: the column names and, for each
  /// row, its values in that order.
  ({List<String> columns, List<List<Object?>> rows}) select(
    String sql, [
    List<Object?> parameters = const [],
  ]);

  /// Starts [sql] and returns a cursor over its rows, to read them one by
  /// one.
  SqliteCursor cursor(String sql, [List<Object?> parameters = const []]);

  /// Registers a SQL function [name] of [argumentCount] arguments, called
  /// with their values (the driver gives SQLite a `lower` that folds
  /// non-ASCII letters this way). [function] gives the same result for the
  /// same arguments (the function is deterministic).
  void createFunction(
    String name,
    int argumentCount,
    Object? Function(List<Object?> arguments) function,
  );

  /// The rows changed by the last insert, update or delete.
  int get updatedRows;

  /// The `rowid` of the last inserted row.
  int get lastInsertRowId;

  /// Whether no transaction is open (SQLite's autocommit mode).
  bool get autocommit;

  /// Closes the database.
  void close();
}

/// The rows of a query, read one by one.
///
/// Spring (Java): a forward-only `java.sql.ResultSet`.
abstract interface class SqliteCursor {
  /// The column names; reliable after the first call of [next].
  List<String> get columns;

  /// The values of the next row, or null when there is none.
  List<Object?>? next();

  /// Releases the statement; always called, also after an error.
  void close();
}
