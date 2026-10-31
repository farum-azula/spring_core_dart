# spring_boot_starter_data

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

> **In development.** Repositories run in memory (with transactions and
> locks) or on SQLite from properties; PostgreSQL comes next (see
> [the roadmap](https://github.com/farum-azula/spring_core_dart/blob/main/roadmap/spring_boot_starter_data.md)).

Spring Data for [`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
applications: describe an aggregate with `@Table`, declare a repository
interface, and the generator writes its implementation, derived queries
included.

The model is Spring Data JDBC's, not JPA's: an aggregate is loaded and
saved whole, `save` writes at once, and other aggregates are referenced by
id. There is no persistence context, no lazy loading and no proxy of
entities.

```dart
@Table('books')
class Book {
  Book({this.id, required this.title, this.year});

  @Id()
  int? id;
  String title;
  int? year;

  @Version()
  int version = 0;
}

// No annotation needed: extending a repository interface is enough.
abstract interface class BookRepository
    implements
        ListCrudRepository<Book, int>,
        ListPagingAndSortingRepository<Book, int> {
  Future<List<Book>> findByTitleContainingIgnoreCase(String text);
  Future<Page<Book>> findByYearGreaterThan(int year, Pageable page);
  Future<int> countByYearBetween(int from, int to);
}
```

A method name the entity does not support (`findByTitel`) stops the
application at startup: `No property 'titel' found for type 'Book'; did
you mean 'title'?`.

## References, foreign keys and unique keys

Aggregates reference each other by id, in one of two ways:

```dart
@Table('books')
@UniqueConstraint(['authorId', 'title'], name: 'uq_books_author_title')
class Book {
  Book({this.id, required this.title, required this.authorId, this.editor});

  @Id()
  int? id;
  String title;

  // A plain id: the id type comes from Author's @Id and is checked.
  // Derived queries (findByAuthorId) and @Query work on it as on any column.
  @Reference(Author)
  @OnDelete(OnDeleteAction.cascade) // deleting an author deletes its books
  int authorId;

  // Or an AggregateReference; no @OnDelete means noAction.
  AggregateReference<Editor, int>? editor;
}

@Table('authors')
class Author {
  Author({this.id, required this.name});

  @Id()
  int? id;

  @Unique() // a DuplicateKeyException on a second author of this name
  String name;
}
```

- A field whose type is an entity (`Author author;`) is a mapping error with
  a hint: it would be a child of the aggregate in Spring Data JDBC, so it
  is never guessed.
- Every reference is a foreign key in a schema the starter creates
  (`spring.data.jdbc.schema=create`), with an index on its column.
  `@OnDelete(OnDeleteAction.x)` chooses the action: `noAction` (default),
  `restrict`, `cascade`, `setNull` (the property must be nullable) or
  `setDefault` (the column gets no default yet, so it becomes null; a later
  version checks the default exists). `@Unique()` and
  `@UniqueConstraint([...], name:)` become `UNIQUE` constraints
  (`uq_<table>_<columns>` by default).
- `spring.data.jdbc.schema=validate` checks them against the database: an
  explicit `@OnDelete`, `@Unique` or `@UniqueConstraint` that the database
  does not have is an error; a reference without a foreign key is a warning
  (its integrity is not enforced).
- The in-memory store behaves exactly like SQLite with `foreign_keys = ON`,
  so a test that passes in memory does not fail in production: a reference
  to a missing aggregate is a `DataIntegrityViolationException`, a delete
  follows the `@OnDelete` (cascades are recursive and run in the
  transaction, so a rollback undoes them), a duplicate is a
  `DuplicateKeyException`, null references and null unique values are never
  checked.
- A cascade or `setNull` is done by the database, not by the repository: no
  `@Version` check and no auditing on the rows it changes (Hibernate's
  `@OnDelete` has the same limit). A reference must point to an aggregate
  root.

## Transactions

```dart
@Service()
class Checkout {
  Checkout(this.stock, this.orders);
  final StockRepository stock;
  final OrderRepository orders;

  // One transaction: the stock row stays locked until the order is saved;
  // any exception rolls everything back.
  @Transactional()
  Future<void> place(int bookId) async {
    final row = (await stock.findByBookId(bookId))!; // @Lock(pessimisticWrite)
    row.available--;
    await stock.save(row);
    await orders.save(PurchaseOrder(bookId: bookId));
  }
}
```

The transaction lives in a `Zone`: it follows `await`, and work started
in it without `await` that outlives it fails instead of running outside
it.

## SQL databases

The starter has no driver inside: list the one you want in `pubspec.yaml`
(`sqlite3`), run the code generator, and set properties. The generator
writes a `JdbcDriver` bean for each driver package it finds; the URL's
scheme chooses among them.

```properties
# lib/resources/application.properties
spring.datasource.url=sqlite:file:library.db
spring.datasource.pool.max-size=4

# A second database: its own beans, qualifier and properties.
spring.datasources.stats.url=sqlite:file:stats.db
spring.datasources.stats.sql.migration.locations=classpath:db/stats

# Migrations: lib/resources/db/migration/V1__books.sql, V2__orders.sql,
# R__views.sql (applied at startup, before any repository is used).
```

```dart
@UseDataSource('stats')                 // a repository on the second one
abstract interface class VisitRepository
    implements ListCrudRepository<Visit, int> {}

@Transactional(transactionManager: 'stats')
Future<void> visit(String page) => ...
```

With `spring.datasource.url` the starter makes (each skipped when the
application declares a bean of its type):

| Bean | What |
|---|---|
| `dataSource` | the primary `DataSource` (a pool; `@Primary`), its schema set up before its first connection |
| `transactionManager` | a `DataSourceTransactionManager` of it (the in-memory one serves only an application with no data source) |
| `jdbcTemplate`, `namedParameterJdbcTemplate`, `jdbcClient` | over the primary data source |
| `<name>DataSource`, `<name>TransactionManager`, `<name>JdbcTemplate`, `<name>NamedParameterJdbcTemplate`, `<name>JdbcClient` | for each `spring.datasources.<name>.url`, qualified `<name>` (fallbacks, so injection by type still finds the primary) |
| `jdbcLogSettings` | the `spring.data.jdbc.*` log switches |
| `dataFailureAnalyzer` | explains a URL no driver handles, a failed migration, a schema that does not fit |

Repositories without `@UseStore` use `jdbc` when a primary data source
exists, `memory` otherwise.

**The schema is ready before any use.** At startup the context applies the
migrations and checks the entities against the schema (a failure stops
the start with its message), and the data source itself holds back every
connection until that is done, so a repository, a `JdbcTemplate`, a
runner or a synchronous `@PostConstruct` that starts a query never sees an
unmigrated database. The entities checked or created are those of the
repositories on that data source (their children come with them);
entities no repository uses are the application's own tables. A
`DataSource` the application declares itself gets the same setup at
startup, but does not hold back early queries.

| Key | Default | Meaning |
|---|---|---|
| `spring.datasource.url` | | `sqlite:file:books.db`, `sqlite::memory:` (one connection: `pool.max-size=1`); a leading `jdbc:` is dropped |
| `spring.datasource.username`, `.password` | | when the URL does not carry them; never logged |
| `spring.datasource.driver` | | the driver's name (`sqlite3`) when two handle the scheme |
| `spring.datasource.pool.max-size` | `10` | most connections at once |
| `spring.datasource.pool.min-idle` | `0` | connections kept open when idle |
| `spring.datasource.pool.connection-timeout` | `30s` | the longest wait for a connection |
| `spring.datasource.pool.idle-timeout` | `10m` | an idle connection above `min-idle` older than this is closed |
| `spring.datasource.pool.max-lifetime` | `30m` | a connection older than this is closed when released |
| `spring.datasource.pool.validation` | `true` | check a connection that waited, before handing it out |
| `spring.datasource.sqlite.busy-timeout` | `5000` | milliseconds a connection waits for a lock |
| `spring.datasource.sqlite.base-directory` | working directory | where relative `sqlite:file:` names are looked for; beats `SqliteJdbcDriver.baseDirectory` |
| `spring.datasources.<name>.*` | | the same keys for a named database, also `sql.init.*`, `sql.migration.*`, `data.jdbc.schema` |
| `spring.sql.init.*`, `spring.sql.migration.*`, `spring.data.jdbc.schema` | see the roadmap | scripts, migrations, `none` / `validate` (default) / `create` / `create-drop` |
| `spring.jdbc.template.query-timeout` | none | bounds each statement of the `JdbcTemplate` beans |
| `spring.data.jdbc.show-sql`, `format-sql`, `show-parameters` | `false` | statements (and values) at info |
| `spring.data.jdbc.slow-query-threshold` | none | a slower statement is logged at warn |

Durations are written `500ms`, `30s`, `10m`, `PT30S`, or as milliseconds.
The names of `spring.datasources` are found in property sources that list
their keys (files, the command line), not in an environment variable
alone. The context must be refreshed with `refreshAsync()` (what
`SpringApplication.runAsync` and `ApplicationContextRunner.runAsync` do):
the schema is set up asynchronously.

## Differences from Spring

- The repository marker is `DataRepository` (`@Repository` is the
  stereotype annotation), a sort step is `SortOrder` (`@Order` orders
  beans).
- Dart has no overloading: `findAll()`, `findAllSorted(Sort)` and
  `findAllPaged(Pageable)`.
- The database and store of a repository: `@UseDataSource('analytics')`,
  `@UseStore('memory')`.
- Every method is asynchronous (`Future` or `Stream`).
- References: `AggregateReference` or `@Reference(Author) int authorId`
  (Spring Data JDBC has only the first), with foreign keys, `@OnDelete`
  (Hibernate's name) and `@Unique` / `@UniqueConstraint` (JPA's names);
  Spring Data JDBC leaves the schema to you.
- `@Transactional(transactionManager: 'x')` instead of a positional value;
  every exception rolls back unless listed in `noRollbackFor` (Dart has
  no checked exceptions).
