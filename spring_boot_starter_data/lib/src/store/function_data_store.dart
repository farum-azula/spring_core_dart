import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_dialect.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';
import 'package:spring_boot_starter_data/src/store/data_store.dart';

/// A [DataStore] whose database has functions that are called by name: the
/// store behind the `@Procedure` methods of a repository.
///
/// A store implements it when its database can have functions, and says
/// `DataStoreCapabilities.functions` when it does have them (the SQL store
/// implements it for every dialect and has the capability with
/// PostgreSQL only).
///
/// ```dart
/// final rows = await store.callFunction('restock', {
///   'sku': 'A-1',
///   'quantity': 5,
/// });
/// ```
///
/// Spring (Java): `org.springframework.jdbc.core.simple.SimpleJdbcCall`
/// (`withFunctionName(name).execute(arguments)`).
abstract interface class FunctionDataStore implements DataStore {
  /// Calls the database function [name] with [arguments] by name and
  /// returns what it returns, as rows of column names to values: a
  /// function that returns a table or a set gives its rows, a scalar
  /// function one row with one column, a function that returns nothing
  /// what its database gives for it (the caller ignores it).
  ///
  /// The values of [arguments] are the ones the caller has: the store
  /// converts them as it converts column values (an enum is its `name`),
  /// and a list is one array argument. The call runs in the current
  /// transaction of the store when there is one. The values of the rows
  /// are as the database gives them (see [RowReadingDataStore]).
  ///
  /// Failures are `DataAccessException`s, as for every method of a store.
  Future<List<Map<String, Object?>>> callFunction(
    String name,
    Map<String, Object?> arguments,
  );
}

/// A [DataStore] whose rows need the store to become objects: the values
/// are in the form of its database, and an aggregate has children the
/// store loads.
///
/// The results of a `@Procedure` method are read with it when the store is one:
/// each value through [valueReader] before the entity converter, and rows
/// of the repository's entity through [readAggregates]. A store that is
/// none has its rows read by the entity converter alone, which is right
/// when they hold plain values (numbers, texts, booleans, ISO-8601 dates)
/// under the names of the columns.
///
/// Spring (Java): none; Spring Data JDBC reads every row through its
/// `JdbcConverter` and the JDBC driver.
abstract interface class RowReadingDataStore implements DataStore {
  /// Converts a value of a row of this store into what a property of a
  /// type wants (the SQL dialect of a SQL store).
  ColumnValueReader get valueReader;

  /// The aggregates of [entity] that [rows] hold (rows with the columns of
  /// its table), whole: with the children the rows do not carry.
  Future<List<T>> readAggregates<T extends Object>(
    PersistentEntity<T> entity,
    List<JdbcRow> rows,
  );
}
