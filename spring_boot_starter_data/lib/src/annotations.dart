import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Marks a class as the root of an aggregate stored in table [value] (by
/// default the class name in snake case: `OrderLine` → `order_line`).
///
/// The generator describes the class (as `@Introspected` does: it is one),
/// so the repositories can read and set its properties and call its
/// constructor without reflection. Each property is a column, named after
/// the property in snake case (`createdAt` → `created_at`) unless
/// [Column] says otherwise; [Transient] properties are not stored. Children
/// of the aggregate are [MappedCollection]s; other aggregates are
/// referenced by id with [AggregateReference].
///
/// A class used only as a child of an aggregate takes `@Table` too, for its
/// table's name.
///
/// ```dart
/// @Table('books')
/// class Book {
///   Book({this.id, required this.title});
///
///   @Id()
///   int? id;
///   String title;
/// }
/// ```
///
/// Spring (Java): `org.springframework.data.relational.core.mapping.Table`.
class Table extends Introspected {
  /// Stores the class in table [value], or in the snake-case class name.
  const Table([this.value, this.schema]);

  /// The table's name; null for the class name in snake case.
  final String? value;

  /// The schema of the table; null for the connection's default.
  final String? schema;
}

/// Marks the property holding the aggregate's id.
///
/// An entity whose id is null is new: `CrudRepository.save` inserts it and
/// the store gives the id (an identity column, `AUTOINCREMENT`, a
/// sequence), which `save` then sets on the returned entity.
///
/// An entity with an id is not new: `save` updates its row, and when there
/// is no such row it throws an `IncorrectUpdateSemanticsDataAccessException`
/// (as Spring Data JDBC). An id the application gives itself (a UUID, a
/// natural key) therefore needs a [Version] property: version 0 means new,
/// and the entity is inserted with its id.
///
/// Spring (Java): `org.springframework.data.annotation.Id`.
class Id {
  /// Marks the id property.
  const Id();
}

/// Names the column of a property, when it is not the property's name in
/// snake case.
///
/// Spring (Java): `org.springframework.data.relational.core.mapping.Column`.
class Column {
  /// Stores the property in column [value].
  const Column(this.value);

  /// The column's name.
  final String value;
}

/// Marks a property that is not stored: it is neither written nor read, and
/// keeps the value the constructor gives it.
///
/// Spring (Java): `org.springframework.data.annotation.Transient`.
class Transient {
  /// Marks a property that is not stored.
  const Transient();
}

/// Marks the version of an aggregate root, for optimistic locking: an `int`
/// (or `DateTime`) the repository raises at each save.
///
/// A new entity (null id, or version 0) is inserted with version 1. A
/// loaded one is updated with `... where id = ? and version = ?`; when no
/// row matches (another save got in between, or the row was deleted),
/// `save` throws an `OptimisticLockingFailureException`. `delete(entity)`
/// checks the version the same way; `deleteById` cannot (it has no
/// version). The children of the aggregate are covered by the root's
/// version.
///
/// Spring (Java): `org.springframework.data.annotation.Version`.
class Version {
  /// Marks the version property.
  const Version();
}

/// Marks a `DateTime` property set to the time of the insert (and kept
/// after).
///
/// Spring (Java): `org.springframework.data.annotation.CreatedDate`.
class CreatedDate {
  /// Marks the creation time property.
  const CreatedDate();
}

/// Marks a `DateTime` property set to the time of each save.
///
/// Spring (Java): `org.springframework.data.annotation.LastModifiedDate`.
class LastModifiedDate {
  /// Marks the modification time property.
  const LastModifiedDate();
}

/// Marks a property set at insert to the current auditor (the
/// `AuditorAware` bean's answer; with the security starter, the logged-in
/// user's name).
///
/// Spring (Java): `org.springframework.data.annotation.CreatedBy`.
class CreatedBy {
  /// Marks the creator property.
  const CreatedBy();
}

/// Marks a property set at each save to the current auditor.
///
/// Spring (Java): `org.springframework.data.annotation.LastModifiedBy`.
class LastModifiedBy {
  /// Marks the modifier property.
  const LastModifiedBy();
}

/// Marks a `List`, `Set` or `Map` of child entities saved, loaded and
/// deleted with their aggregate root, never alone.
///
/// The children's table holds a column [idColumn] referencing the root's id
/// (by default the root's table name followed by `_id`) and, for a `List`
/// or a `Map`, a column [keyColumn] with the position or the key (by
/// default the root's table name followed by `_key`).
///
/// A save writes the children again: the old rows are deleted and the
/// current ones inserted, as in Spring Data JDBC.
///
/// Spring (Java):
/// `org.springframework.data.relational.core.mapping.MappedCollection`.
class MappedCollection {
  /// Children referencing the root by [idColumn], ordered or keyed by
  /// [keyColumn].
  const MappedCollection({this.idColumn, this.keyColumn});

  /// The column of the children's table holding the root's id.
  final String? idColumn;

  /// The column holding a child's position (a `List`) or key (a `Map`).
  final String? keyColumn;
}

/// The reference from one aggregate to another, by id: the referenced
/// aggregate is never loaded with this one (Spring Data JDBC's model).
///
/// ```dart
/// AggregateReference<Author, int> authorId; // stored as author_id
/// ```
///
/// [ID] has no `extends Object` bound so the mapping can build a reference
/// from a `TypeInfo` (whose captured types are unbounded), without
/// reflection; ids are never null in practice.
///
/// Spring (Java):
/// `org.springframework.data.jdbc.core.mapping.AggregateReference`.
final class AggregateReference<T, ID> {
  /// A reference to the aggregate of type [T] whose id is [id].
  const AggregateReference(this.id);

  /// The id of the referenced aggregate.
  final ID id;

  @override
  bool operator ==(Object other) =>
      other is AggregateReference<T, ID> && other.id == id;

  @override
  int get hashCode => Object.hash(T, id);

  @override
  String toString() => 'AggregateReference<$T>($id)';
}

/// The statement of a repository method, instead of a query derived from
/// its name.
///
/// [value] is SQL with named parameters (`:year`), bound to the method's
/// parameters by name; `:#{...}` takes a SpEL expression (`#book.title`, a
/// bean `@clock`), `#{#entityName}` the entity's table, `${...}` a
/// property. Values are always bound as parameters, never written into the
/// SQL text.
///
/// A method returning a `Page` gives the count's statement in
/// [countQuery]. A change (`update`, `delete`, `insert`) needs [Modifying].
///
/// Spring (Java): `org.springframework.data.jdbc.repository.query.Query`.
class Query {
  /// The method runs [value].
  const Query(this.value, {this.countQuery, this.name});

  /// The SQL of the method.
  final String value;

  /// For a method returning a `Page`: the SQL counting all results.
  final String? countQuery;

  /// The name of a named query in the properties instead of [value];
  /// reserved, not used in this version.
  final String? name;
}

/// Marks a [Query] that changes data (`update`, `delete`, `insert`): the
/// method returns the number of rows changed (`Future<int>`), a `bool`
/// (any row changed) or nothing.
///
/// Spring (Java): `org.springframework.data.jdbc.repository.query.Modifying`.
class Modifying {
  /// Marks a changing query.
  const Modifying();
}

/// The kind of pessimistic lock a query method takes on the rows it reads.
///
/// Spring (Java): `org.springframework.data.relational.repository.Lock`
/// with `org.springframework.data.relational.core.sql.LockMode`.
enum LockMode {
  /// A shared lock (`for share`): others may read, not change.
  pessimisticRead,

  /// An exclusive lock (`for update`): others wait to read for update or to
  /// change.
  pessimisticWrite,
}

/// Locks the rows a query method reads until the transaction ends.
///
/// Only inside a transaction: a `@Lock` method called outside one fails at
/// once (`IllegalTransactionStateException`), it never runs unlocked.
/// [timeout] bounds the wait (zero: fail at once, `nowait`); [skipLocked]
/// leaves out rows another transaction has locked (a work queue). A lock
/// that cannot be had throws `CannotAcquireLockException`.
///
/// SQLite has no row locks: the transaction takes the whole database
/// (`BEGIN IMMEDIATE`). The store in memory has no transactions: a `@Lock`
/// method fails there (use a SQL store).
///
/// Spring (Java): `org.springframework.data.relational.repository.Lock`
/// (`timeout` and `skipLocked` are extensions; Spring sets them with query
/// hints).
class Lock {
  /// Takes a lock of [value] on the rows read.
  const Lock(this.value, {this.timeout, this.skipLocked = false});

  /// The kind of lock.
  final LockMode value;

  /// The longest wait for the lock; null for the store's default, zero for
  /// none.
  final Duration? timeout;

  /// Whether rows locked by another transaction are skipped.
  final bool skipLocked;
}

/// Puts a repository on the database named [value]: the
/// `spring.datasources.<value>.*` properties. Without it a repository uses
/// the primary database (`spring.datasource.*`).
///
/// ```dart
/// @UseDataSource('analytics')
/// abstract interface class SaleStats extends CrudRepository<SaleStat, int> {}
/// ```
///
/// An extension of Spring Data, which sets the database per package
/// (`@EnableJdbcRepositories(jdbcOperationsRef: ...)`).
class UseDataSource {
  /// The repository uses the database [value].
  const UseDataSource(this.value);

  /// The name of the database.
  final String value;
}

/// Puts a repository on the store named [value]: `memory` (in memory, for
/// tests and prototypes), `jdbc` (SQLite, PostgreSQL), `supabase` (with the
/// Supabase starter). Without it the starter chooses: `jdbc` when a
/// database is configured, else `memory`.
///
/// An extension of Spring Data, where each store has its own module and
/// annotations.
class UseStore {
  /// The repository uses the store [value].
  const UseStore(this.value);

  /// The name of the store.
  final String value;
}
