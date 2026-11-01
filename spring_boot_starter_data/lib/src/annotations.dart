/// Marks a class as the root of an aggregate stored in table [value] (by
/// default the class name in snake case: `OrderLine` → `order_line`).
///
/// The generator describes the class (an `EntityIntrospection`),
/// so the repositories can read and set its properties and call its
/// constructor without reflection. Each property is a column, named after
/// the property in snake case (`createdAt` → `created_at`) unless
/// [Column] says otherwise; [Transient] properties are not stored. Children
/// of the aggregate are [MappedCollection]s; other aggregates are
/// referenced by id with [AggregateReference] or [Reference]; [Unique] and
/// [UniqueConstraint] ask for unique values.
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
class Table {
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

/// References another aggregate by its id, from a plain property: the
/// column holds the id of an aggregate of type [target].
///
/// ```dart
/// @Reference(Author)
/// int authorId; // a foreign key to authors(id)
/// ```
///
/// It is the other way, next to `AggregateReference<Author, int>`, to
/// reference an aggregate: the property keeps its own type (the id's), so
/// derived queries (`findByAuthorId(int id)`) and `@Query` work on it like
/// on any column. The type of the property must be the type of [target]'s
/// `@Id` (nullability aside), or the mapping fails at startup naming both
/// types.
///
/// Every reference gets a foreign key in a schema the starter creates
/// (`REFERENCES "authors"("id")`) and an index on its column; [OnDelete]
/// chooses what happens to the referencing rows when the aggregate they
/// reference is deleted.
///
/// A property whose type is an entity (`Author author;`) without
/// [MappedCollection] is a mapping error: in Spring Data JDBC it would be a
/// child of the aggregate, so the starter never guesses which of the two is
/// meant.
///
/// Spring (Java): none; Spring Data JDBC only has `AggregateReference`.
/// JPA's `@ManyToOne` is the closest, without the object graph.
class Reference {
  /// The property holds the id of an aggregate of type [target].
  const Reference(this.target);

  /// The class of the referenced aggregate (marked [Table], with an
  /// `@Id`).
  final Type target;
}

/// What the database does to the rows that reference an aggregate when it
/// is deleted: the choices of [OnDelete].
///
/// Spring (Java): `org.hibernate.annotations.OnDeleteAction`, and the
/// `ON DELETE` actions of SQL.
enum OnDeleteAction {
  /// The delete fails when referencing rows exist (checked at the end of
  /// the statement). The default, also for a reference without [OnDelete].
  noAction,

  /// Like [noAction], but checked at once, row by row: a delete of rows
  /// that reference each other (a self-reference) may fail where
  /// [noAction] passes.
  restrict,

  /// The referencing aggregates are deleted too (and what references
  /// them, recursively).
  cascade,

  /// The referencing property is set to null; it must be nullable.
  setNull,

  /// The referencing property is set to its default value: the constant
  /// initializer of its field (`int? publisherId = 1`) or the constant
  /// default of its constructor parameter, which a generated schema writes
  /// as the column's `DEFAULT`. A property without a default stops the
  /// start; the aggregate the default references must exist when the
  /// delete happens (else the delete fails as for [noAction]).
  setDefault,
}

/// Chooses what happens to the aggregates referencing the one that is
/// deleted: on a property that is an `AggregateReference` or marked
/// [Reference].
///
/// Without it a reference is [OnDeleteAction.noAction]: deleting a
/// referenced aggregate fails while others reference it.
///
/// ```dart
/// @Reference(Author)
/// @OnDelete(OnDeleteAction.cascade)
/// int authorId; // deleting an author deletes its books
/// ```
///
/// The database does it, not the repository: a cascade or a `setNull` goes
/// through no `delete` or `save` of the repository, so a `@Version` is not
/// checked and auditing does not touch the affected rows (Hibernate's
/// `@OnDelete` has the same limit). The in-memory store does the same, to
/// behave as the database does.
///
/// [OnDeleteAction.setNull] needs a nullable property, or the mapping fails
/// at startup. With `spring.data.jdbc.schema=validate` an explicit
/// `@OnDelete` that the database's foreign key does not match is an error.
///
/// Spring (Java): `org.hibernate.annotations.OnDelete`.
class OnDelete {
  /// The referencing rows follow [action] when the referenced one is
  /// deleted.
  const OnDelete(this.action);

  /// The action.
  final OnDeleteAction action;
}

/// Marks a property whose values must be unique in its table (`NULL`s
/// excepted: as in SQL, several rows may hold null).
///
/// The schema the starter creates gets a `UNIQUE` constraint
/// (`uq_<table>_<column>`); a repository save that breaks it throws a
/// `DuplicateKeyException`, from the database and from the in-memory store
/// alike. For a constraint on several properties use [UniqueConstraint]
/// on the class.
///
/// Dart cannot add a named `unique:` to `@Column('x')` (a positional
/// parameter cannot be mixed with named ones), so uniqueness is an
/// annotation of its own.
///
/// Spring (Java): `jakarta.persistence.Column(unique = true)`.
class Unique {
  /// Marks a unique property.
  const Unique();
}

/// A unique constraint over several properties of a class marked [Table]:
/// no two rows may hold the same values in all of them (a row with a null
/// among them never conflicts). Repeatable.
///
/// ```dart
/// @Table('books')
/// @UniqueConstraint(['author', 'title'], name: 'uq_books_author_title')
/// class Book { ... }
/// ```
///
/// [properties] are Dart property names, checked at startup. Without
/// [name] the constraint is `uq_<table>_<columns>`.
///
/// Spring (Java): `jakarta.persistence.UniqueConstraint` (in
/// `@Table(uniqueConstraints: ...)`, with column names).
class UniqueConstraint {
  /// A constraint over [properties], named [name] (or by default).
  const UniqueConstraint(this.properties, {this.name});

  /// The names of the properties, as written in the class.
  final List<String> properties;

  /// The name of the constraint in the database; null for
  /// `uq_<table>_<columns>`.
  final String? name;
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
/// `{Book}` is the quoted table of the entity `Book` and `{Book.authorId}`
/// the quoted column of its property `authorId` (`author_id` by default; the
/// naming strategy, `@Table` and `@Column` decide), outside quotes and
/// comments. The column is not qualified: write `b.{Book.authorId}` in a
/// join.
///
/// ```dart
/// @Query('select {Book.title} from {Book} where {Book.authorId} = :id')
/// Future<List<String>> titlesOf(int id);
/// ```
///
/// A method returning a `Page` gives the count's statement in
/// [countQuery]. A change (`update`, `delete`, `insert`) needs [Modifying].
///
/// The rows become what the method returns by its type: the entity (the
/// columns of its table; its children are loaded too), a class of the
/// application (a DTO, which the generator describes: the columns by name,
/// `author_name` into `authorName`), one column (`int`, `String`...), a
/// `Map<String, Object?>`, or the whole result with [rowMapper] or
/// [resultSetExtractor], static methods (or top-level functions) given as
/// constants:
///
/// ```dart
/// @Query('select a.id, a.name, b.title from authors a '
///     'join books b on b.author_id = a.id',
///     resultSetExtractor: AuthorWithBooks.extract)
/// Future<List<AuthorWithBooks>> authorsWithBooks();
/// ```
///
/// **The build checks the query**, so a mistake is an error of the build,
/// listed with the others of the repository, and not of the first call:
///
/// - the annotation and the method: `name:` (not supported yet), a
///   [rowMapper] and a [resultSetExtractor] together, one that is not a
///   function of the `JdbcRow` or the `JdbcResult`, a method that is not
///   `Future` or `Stream`, `@Lock`, more than one `Pageable` or `Sort`, a
///   `Page` or `Slice` without a `Pageable`, `@Modifying` with a result
///   other than `int`, `bool` or `void` (or with a mapper or a `Pageable`),
///   `void` without `@Modifying`, a [countQuery] for anything but a `Page`,
///   a result that rows cannot become (the entity, a class of yours, a
///   column type, a `Map<String, Object?>`);
/// - the text: each `:name` must be a parameter of the method, a plain `?`
///   and a `#{...}` other than `#{#entityName}` are refused, and the entity
///   and the property of a `{Entity.property}` must exist (a `@Table` class
///   of the application, a stored property: not `@Transient`, not a
///   `@MappedCollection`);
/// - **misspelled names**: a table after `from`, `join`, `update`, `into`
///   or `delete from`, a qualified `alias.column`, and an unqualified column
///   are errors when the build knows no such name (from the entities and
///   from `db/migration` and `schema.sql` of `lib/resources/`) and does
///   know a close one: `books.titel: no column titel in books, did you
///   mean 'title'?`. A name nothing is close to is left alone (a table of
///   another schema, a function, a word of your database).
///
/// What depends on the run time stays at startup: `${...}` placeholders are
/// resolved from the environment, the `{Entity}` names come from the
/// entity's mapping, and a result class must be described.
///
/// Spring (Java): `org.springframework.data.jdbc.repository.query.Query`
/// (whose text Spring checks only when the repository is created).
class Query {
  /// The method runs [value].
  const Query(
    this.value, {
    this.countQuery,
    this.name,
    this.rowMapper,
    this.resultSetExtractor,
  });

  /// The SQL of the method.
  final String value;

  /// For a method returning a `Page`: the SQL counting all results.
  final String? countQuery;

  /// The name of a named query in the properties instead of [value];
  /// reserved, not used in this version.
  final String? name;

  /// Maps each row of the result: a `T Function(JdbcRow row)` (a static
  /// method or a top-level function). The method returns a `List`, `Set`,
  /// `Stream`, `Page` or `Slice` of `T`, or one `T`. Not together with
  /// [resultSetExtractor].
  ///
  /// Spring (Java): `@Query(rowMapperClass = ...)`.
  final Function? rowMapper;

  /// Turns the whole result into what the method returns: a
  /// `R Function(JdbcResult result)` (a static method or a top-level
  /// function), for results that span rows (one to many). Not together with
  /// [rowMapper]; the method has no `Pageable`.
  ///
  /// Spring (Java): `@Query(resultSetExtractorClass = ...)`.
  final Function? resultSetExtractor;
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
/// (`BEGIN IMMEDIATE`). The store in memory has row locks of its own (read
/// committed, with deadlock detection): the transaction is the one of the
/// repository's store. It applies to the derived `find` methods and to
/// `findById`.
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
