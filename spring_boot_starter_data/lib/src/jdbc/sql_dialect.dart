import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/annotations.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/json_storage.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_definition.dart';

/// Turns a value as a store's rows hold it into what a property of a type
/// wants, before the entity converter's own conversions (enums,
/// references, widening).
///
/// A [SqlDialect] is one (SQLite's 0/1 into a `bool`, PostgreSQL's numeric
/// text into a `double`); a store that is not SQL gives its own for the
/// rows it returns (see `RowReadingDataStore`). The row mappers take one
/// as their `dialect`.
///
/// ```dart
/// final mapper = SingleColumnRowMapper<bool>(dialect: SqliteDialect());
/// ```
///
/// Spring (Java): none; `JdbcUtils.getResultSetValue` asks the JDBC driver
/// for the Java type.
abstract interface class ColumnValueReader {
  /// [value] read from the store as a property of [type] wants it.
  Object? fromDatabase(Object? value, TypeInfo<Object?> type);
}

/// What differs between the SQL of two databases, for the statements the
/// starter writes itself (repositories, schema creation, migrations'
/// history) and for reading and writing values.
///
/// The SQL the application writes (`@Query`, `JdbcTemplate`) is sent as it
/// is, only its `:name` parameters turned into `?`.
///
/// Spring (Java): `org.springframework.data.relational.core.dialect.
/// Dialect` with `SQLErrorCodeSQLExceptionTranslator`'s per-database
/// codes.
abstract class SqlDialect implements ColumnValueReader {
  /// A dialect.
  const SqlDialect();

  /// The database's name in messages and in `{vendor}` of migration
  /// locations (`sqlite`, `postgresql`).
  String get name;

  // ---------------------------------------------------------------- names

  /// [identifier] (a table or column name) quoted, so a name that is a
  /// keyword (`order`, `user`) works: `"order"`.
  String quote(String identifier) => '"${identifier.replaceAll('"', '""')}"';

  /// The table [table] of [schema], quoted.
  String table(String table, [String? schema]) =>
      schema == null ? quote(table) : '${quote(schema)}.${quote(table)}';

  // ------------------------------------------------------------- clauses

  /// The clause limiting a query to [limit] rows after skipping [offset]
  /// (either may be null): `LIMIT 10 OFFSET 20`.
  String limitOffset(int? limit, int? offset) {
    if (limit == null && offset == null) {
      return '';
    }
    return [
      if (limit != null) 'LIMIT $limit' else if (offset != null) 'LIMIT -1',
      if (offset != null) 'OFFSET $offset',
    ].join(' ');
  }

  /// [expression] folded to lower case, for `ignoreCase` comparisons and
  /// sorts: `lower(<expression>)`. A dialect whose `lower` does not fold
  /// every letter (SQLite's knows ASCII only) names a function that does.
  String lower(String expression) => 'lower($expression)';

  /// Whether `LIKE` ignores the case of letters (SQLite's does for ASCII
  /// ones, and has no switch that is not connection wide): the generated
  /// SQL of a case sensitive `like` then uses the database's case
  /// sensitive pattern operator ([globOperator]) instead.
  bool get likeIgnoresCase => false;

  /// The case sensitive pattern operator of a dialect whose [likeIgnoresCase]
  /// is true: SQLite's `GLOB` (`*` any text, `?` one character, `[...]`
  /// escapes a special character, no escape character).
  String get globOperator => 'GLOB';

  /// The most values one statement binds (the protocol's or the library's
  /// limit), or null when none is known. A derived `In` with more values
  /// than this on a dialect that cannot bind a list as one value
  /// ([arrayMembership] is null) is refused with a clear message instead of
  /// the database's.
  int? get maxBoundParameters => null;

  /// The SQL of `column in (values)` (`negate`: `not in`) that binds all
  /// the values as ONE array parameter (the single `?`), or null when the
  /// dialect has no array parameters (the generator then writes one
  /// marker per value). With [ignoreCase] each element is folded to lower
  /// case on the server, as the column is.
  String? arrayMembership(
    String column, {
    required bool ignoreCase,
    required bool negate,
  }) => null;

  /// Whether the driver sends [values] (column values, as
  /// `EntityConverter.toColumnValue` gives them; nulls among them) as the
  /// one array parameter of [arrayMembership]. False (the default, and of
  /// a dialect with arrays for values its driver has no array of, such as
  /// bytes) makes the generator write one marker per value.
  bool bindsAsArray(Iterable<Object?> values) => false;

  /// How the database takes the row locks of a `@Lock` query.
  LockStrategy get lockStrategy;

  /// The clause after a query locking its rows (`FOR UPDATE`, `FOR SHARE`,
  /// with `NOWAIT` for a zero [timeout] and `SKIP LOCKED`); empty when
  /// [lockStrategy] is not [LockStrategy.rowLocks].
  String lockClause(
    LockMode mode, {
    Duration? timeout,
    bool skipLocked = false,
  });

  /// A harmless statement that takes the write lock of the database (or
  /// null when there is none): run by a `@Lock` query in a transaction that
  /// already ran statements, when [LockStrategy.databaseLock] cannot be had
  /// by beginning the transaction again (see `ConnectionHolder.
  /// requireWriteLock`). A dialect of such a database may override it.
  String? get writeLockStatement => null;

  /// The statement setting the lock wait of the current transaction to
  /// [timeout] (PostgreSQL's `SET LOCAL lock_timeout`), or null when the
  /// database has none or the clause handles it.
  String? lockTimeoutStatement(Duration timeout) => null;

  /// The column definition of an id the database generates, for schema
  /// creation (`INTEGER PRIMARY KEY` in SQLite, `BIGINT GENERATED BY
  /// DEFAULT AS IDENTITY PRIMARY KEY` in PostgreSQL).
  String identityColumn(TypeInfo<Object?> type);

  /// The column type for a property of [type], for schema creation and
  /// validation (`TEXT`, `INTEGER`, `REAL`, `BLOB`, `TIMESTAMP`...); null
  /// when the type cannot be stored as a column.
  String? columnType(TypeInfo<Object?> type);

  /// Whether a column of the database holds a property of the collection
  /// [type] (a `List`, a `Set` or a `Map`) as it is, with no `@Json`: an
  /// array column. False by default: the store then refuses such a
  /// property when its repository is created (`CollectionColumns`), with
  /// the fix. Bytes (`List<int>`) are no collection here: [columnType]
  /// names their column. A dialect that answers true converts the
  /// elements in [toDatabase] and [fromDatabase] as it does single values.
  bool storesCollection(TypeInfo<Object?> type) => false;

  /// Whether a column declared with [declared] (as the database reports
  /// it) can hold a property of [type]: the schema validation's test.
  bool columnFits(String declared, TypeInfo<Object?> type);

  /// How the database keeps a `@Json` property ([json]: its settings):
  /// the column type, the test of an existing column, the marker and the
  /// value an insert or update binds, and the reading of what the column
  /// gives. By default the JSON text in a `TEXT` column, which every
  /// database can hold; a dialect of a database with a JSON type
  /// overrides it.
  ///
  /// ```dart
  /// const PostgresDialect().jsonStorage(const Json()).columnType; // JSONB
  /// SqliteDialect().jsonStorage(const Json()).columnType; // TEXT
  /// ```
  JsonStorage jsonStorage(Json json) => const JsonStorage();

  /// The isolation levels the database offers; [Isolation.defaultLevel]
  /// is always among them.
  Set<Isolation> get isolationLevels;

  /// Whether the database has savepoints (`nested`).
  bool get supportsSavepoints => true;

  // --------------------------------------------------------------- schema

  /// Whether a table may be created with a foreign key to a table that does
  /// not exist yet (SQLite accepts it, so references that form a cycle
  /// work). When false, the creator writes such a foreign key afterwards,
  /// with [addForeignKeyStatement].
  bool get supportsForwardForeignKeys => true;

  /// The `ALTER TABLE` statement adding the foreign key [name] on [column]
  /// of [table] to [parentColumn] of [parentTable], with [onDelete]: for a
  /// database that cannot have the key in `CREATE TABLE` when the parent
  /// comes later (PostgreSQL).
  String addForeignKeyStatement({
    required String name,
    required String table,
    required String? schema,
    required String column,
    required String parentTable,
    required String? parentSchema,
    required String parentColumn,
    required OnDeleteAction onDelete,
  }) =>
      'ALTER TABLE ${this.table(table, schema)} ADD CONSTRAINT '
      '${quote(name)} FOREIGN KEY (${quote(column)}) REFERENCES '
      '${this.table(parentTable, parentSchema)} (${quote(parentColumn)})'
      '${onDeleteClause(onDelete)}';

  /// The `ON DELETE` clause of [action], with a leading space; empty for
  /// [OnDeleteAction.noAction], the default.
  String onDeleteClause(OnDeleteAction action) => switch (action) {
    OnDeleteAction.noAction => '',
    OnDeleteAction.restrict => ' ON DELETE RESTRICT',
    OnDeleteAction.cascade => ' ON DELETE CASCADE',
    OnDeleteAction.setNull => ' ON DELETE SET NULL',
    OnDeleteAction.setDefault => ' ON DELETE SET DEFAULT',
  };

  /// The statements to run, in the transaction that drops the tables,
  /// before the first `DROP TABLE`, so that tables referencing each other
  /// (or holding rows that do) can be dropped in any order: SQLite's
  /// `PRAGMA defer_foreign_keys = ON`. Empty when none are needed.
  List<String> get beforeDropStatements => const [];

  /// The statement dropping [table] (in [schema]) if it exists.
  /// [referenced] tells that other tables hold foreign keys to it (a
  /// PostgreSQL dialect adds `CASCADE`, so a cycle can be dropped).
  String dropTableStatement(
    String table, {
    String? schema,
    bool referenced = false,
  }) => 'DROP TABLE IF EXISTS ${this.table(table, schema)}';

  /// Describes the columns of [table] (in [schema] when given) as the
  /// database has them, in their order; an empty list when the table does
  /// not exist; `null` when this dialect cannot describe tables (schema
  /// validation then fails with a clear message).
  Future<List<ColumnInfo>?> describeTable(
    JdbcConnection connection,
    String table, [
    String? schema,
  ]) async => null;

  /// Describes the foreign keys of [table] (in [schema] when given), one
  /// for each referencing column; an empty list when it has none or does
  /// not exist; `null` when this dialect cannot describe them (the schema
  /// validation then skips the check and says so in its debug log).
  Future<List<ForeignKeyInfo>?> describeForeignKeys(
    JdbcConnection connection,
    String table, [
    String? schema,
  ]) async => null;

  /// Describes the unique constraints and unique indexes of [table] (in
  /// [schema] when given): the columns each covers, in order; an empty
  /// list when it has none; `null` when this dialect cannot describe them.
  /// The primary key counts; a partial index does not (it makes the columns
  /// unique for some rows only).
  Future<List<UniqueInfo>?> describeUniqueKeys(
    JdbcConnection connection,
    String table, [
    String? schema,
  ]) async => null;

  /// The names of the tables the database holds (in the current schema),
  /// without the system tables; `null` when this dialect cannot list them.
  /// The migration runner uses it to tell an existing database from an
  /// empty one.
  Future<List<String>?> listTables(JdbcConnection connection) async => null;

  /// The statement that takes the migration lock of the database for the
  /// whole run of the migrations, such as PostgreSQL's
  /// `SELECT pg_advisory_lock(...)`; null when there is none (SQLite takes
  /// its write lock with `BEGIN IMMEDIATE` instead).
  String? get migrationLock => null;

  /// The statement that gives the [migrationLock] back; null when there is
  /// none.
  String? get migrationUnlock => null;

  /// [value] (a property's constant default) as the literal of a column's
  /// `DEFAULT` in a generated schema, through [toDatabase]: `NULL`, a
  /// number, a quoted text (an enum by its name, a `bool` as the database
  /// stores it); null when it has no literal here (a list, an object): the
  /// column then gets no default.
  String? defaultLiteral(Object? value) {
    final stored = toDatabase(value is Enum ? value.name : value);
    return switch (stored) {
      null => 'NULL',
      final bool b => b ? 'TRUE' : 'FALSE',
      final int i => '$i',
      final double d when d.isFinite => '$d',
      final String text => "'${text.replaceAll("'", "''")}'",
      _ => null,
    };
  }

  // --------------------------------------------------------------- values

  /// [value] as the driver takes it: SQLite stores a `DateTime` as an
  /// ISO-8601 text in UTC and a `bool` as 0 or 1, PostgreSQL takes them as
  /// they are.
  Object? toDatabase(Object? value) => value;

  /// [value] read from the database as a property of [type] wants it: the
  /// reverse of [toDatabase] (a text to a `DateTime`, 0/1 to a `bool`, an
  /// `int` to a `double`). The entity converter applies its own
  /// conversions after it (enums, references).
  @override
  Object? fromDatabase(Object? value, TypeInfo<Object?> type) => value;

  // ------------------------------------------------------------ functions

  /// Whether the database has functions that [functionCall] can call
  /// with named arguments (PostgreSQL); a `@Procedure` method needs it.
  bool get supportsFunctions => false;

  /// The statement that calls the database function [name] with one `?`
  /// for each of [arguments], passed by name, and returns what it returns
  /// as rows (a scalar function: one row with one column):
  /// `select * from "restock"("sku" => ?, "quantity" => ?)`. Every name
  /// is quoted; a `schema.name` is quoted part by part.
  ///
  /// Throws an [UnsupportedError] without [supportsFunctions].
  String functionCall(String name, List<String> arguments) =>
      throw UnsupportedError(
        '${this.name} has no functions to call by name',
      );

  // --------------------------------------------------------------- errors

  /// [error] (with the failed statement [sql]) as a `DataAccessException`
  /// of the starter's hierarchy: a duplicate key, a broken constraint, a
  /// lock not had, a deadlock, a timeout, wrong SQL, a lost connection.
  /// The message keeps the SQL with its markers, never the values.
  DataAccessException translate(SqlError error, {String? sql});

  /// The fallback of [translate] for an error the dialect does not know:
  /// a lost connection or a generic data access failure. For dialects.
  DataAccessException unknown(SqlError error, {String? sql}) =>
      error.connectionLost
      ? DataAccessResourceFailureException(
          error.message,
          cause: error,
          sql: sql ?? error.sql,
        )
      : UncategorizedSqlException(
          error.message,
          cause: error,
          sql: sql ?? error.sql,
        );
}

/// How a database takes the locks of a `@Lock` query.
enum LockStrategy {
  /// Row locks in the query (`FOR UPDATE`, `FOR SHARE`): PostgreSQL.
  rowLocks,

  /// No row locks: a transaction with a `@Lock` query takes the write lock
  /// of the whole database when it begins (SQLite's `BEGIN IMMEDIATE`).
  databaseLock,
}

/// A database error the dialect could not put in a finer class.
///
/// Spring (Java): `org.springframework.jdbc.UncategorizedSQLException`.
class UncategorizedSqlException extends NonTransientDataAccessException {
  /// An error described by [message].
  UncategorizedSqlException(super.message, {super.cause, super.sql});
}

/// A column of a table as the database describes it.
///
/// Spring (Java): `java.sql.DatabaseMetaData.getColumns`, reduced to what
/// the schema validation needs.
final class ColumnInfo {
  /// A column named [name] declared as [type].
  const ColumnInfo({
    required this.name,
    required this.type,
    this.notNull = false,
    this.defaultValue,
    this.primaryKey = false,
  });

  /// The column name.
  final String name;

  /// The declared type, as the database writes it (`INTEGER`, `TEXT`,
  /// `varchar(40)`); empty when it has none (SQLite allows that).
  final String type;

  /// Whether the column refuses null.
  final bool notNull;

  /// The default expression, null when there is none.
  final String? defaultValue;

  /// Whether the column is (part of) the primary key.
  final bool primaryKey;

  @override
  String toString() => 'ColumnInfo($name $type)';
}

/// A foreign key of a table as the database describes it.
///
/// Spring (Java): `java.sql.DatabaseMetaData.getImportedKeys`, reduced to
/// what the schema validation needs.
final class ForeignKeyInfo {
  /// A key from [column] to [parentColumn] of [parentTable], which does
  /// [onDelete] (null when the database reports an action unknown here).
  const ForeignKeyInfo({
    required this.column,
    required this.parentTable,
    required this.parentColumn,
    this.onDelete,
  });

  /// The referencing column.
  final String column;

  /// The referenced table.
  final String parentTable;

  /// The referenced column; null when the key names none (the parent's
  /// primary key).
  final String? parentColumn;

  /// What happens to the row when the parent row is deleted.
  final OnDeleteAction? onDelete;

  @override
  String toString() => 'ForeignKeyInfo($column -> $parentTable)';
}

/// A set of columns the database keeps unique (a `UNIQUE` constraint, a
/// unique index, the primary key).
final class UniqueInfo {
  /// A unique key over [columns].
  const UniqueInfo(this.columns, {this.name});

  /// The covered columns, in order.
  final List<String> columns;

  /// The constraint's or index's name, when there is one.
  final String? name;

  @override
  String toString() => 'UniqueInfo(${columns.join(', ')})';
}
