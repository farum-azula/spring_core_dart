# spring_boot_starter_data

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

> **In development.** Repositories run in memory (with transactions and
> locks) or on SQLite and PostgreSQL from properties (see
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

The build parses the method names and checks them against the entity: a
name the entity does not support (`findByTitel`) is a build error, not a
startup one (`No property 'titel' found for type 'Book'; did you mean
'title'?`). The generated class extends `SimpleRepository` (the CRUD,
sorting and paging methods) and writes only what the interface declares:
a constant `PartTree` and one call for each derived query, a constant
`QueryMethod` for each `@Query` method. At startup the repository checks what
the build cannot know: its store and data source, its entity, the
`${property}` placeholders and the expressions of its `@Query` texts.

## `@Query`, checked by the build

```dart
abstract interface class BookRepository
    implements ListCrudRepository<Book, int> {
  @Query('select {Book.title} from {Book} where {Book.authorId} = :authorId')
  Future<List<String>> titlesOf(int authorId);

  @Query('select b.title, a.name as author_name from books b '
      'join authors a on a.id = b.author_id where b.year > :year')
  Future<Page<BookCard>> cards(int year, Pageable page);

  @Modifying()
  @Query('update books set year = year + 1 where year > :year')
  Future<int> shift(int year);
}
```

What can be checked without running is checked by the build, and every
problem of the interface is one build error:

- the method against its annotation: it returns a `Future` or a `Stream`; a
  `Page` or `Slice` has a `Pageable`; `@Modifying` returns `int`, `bool` or
  nothing and has no `rowMapper` or `Pageable`; `void` needs `@Modifying`;
  `countQuery` is for a `Page`; a `rowMapper` or `resultSetExtractor` is a
  function of a `JdbcRow` or a `JdbcResult`; no `@Lock`; the rows can become
  the result: the entity, a class of yours (the generator describes it), a
  column type or a `Map<String, Object?>`;
- the text: each `:name` is a parameter of the method, a plain `?` and a
  `#{...}` other than `#{#entityName}` are refused;
- the `:#{expression}` values (SpEL). The build compiles each one it can to
  Dart, a function of the arguments, so a mistake is a build error with a
  suggestion and nothing is interpreted at run time:

  ```dart
  @Query('select * from books where title = :#{#book.title}')
  Future<List<Book>> sameTitle(Book book);
  // generated: expressions: [(arguments, context) => (arguments[0] as Book).title]

  @Query('select * from books where title = :#{#book.titel}')
  // BookRepository.sameTitle: the expression :#{#book.titel} is invalid:
  //   No property 'titel' on type 'Book'; did you mean 'title'?
  ```

  The variables are `#name` of each parameter, `#p0` and `#a0`, `#root` (the
  list of the arguments), `#entityName` and `#methodName`; `@bean` is a bean
  of the application and `@environment.getProperty(key, default)` the
  environment. An unknown `#variable`, a wrong call, a member of a value
  that can be null without `?.` and a syntax error are build errors too.
  What the compiler leaves alone (`T(...)`, `new`, selection, `matches`,
  `instanceof`, Java-style `size()`, a member of `Object`) is interpreted at
  run time, and only the arguments of such a method are described for it
  (`@Introspected()` on their classes always does);
- the entity placeholders: `{Book}` is the quoted table of the entity `Book`
  and `{Book.authorId}` the quoted column of its property (`author_id`;
  the naming strategy, `@Table` and `@Column` decide, at run time, through
  the mapping). `Book` must be a `@Table` class of the application and
  `authorId` a stored property (not `@Transient`, not a `@MappedCollection`).
  The column is not qualified: write `b.{Book.authorId}` in a join;
- misspelled names. The build knows the tables and columns of the entities
  and of the migrations and init scripts in `lib/resources/`
  (`db/migration/V*__*.sql`, `R__*.sql`, `schema.sql`: `create table`,
  `alter table` to add, rename or drop a column or rename the table, `drop
  table`, `create view` with its select list, in the order they run). A
  table after `from`, `join`, `update`, `into` or `delete from`, a qualified
  `alias.column` and an unqualified column that it does not know, when it
  knows a close name, is an error:

  ```text
  Invalid repository BookRepository:
    - BookRepository.cards: b.titel: no column titel in books, did you mean 'title'?
  ```

  The rule is made to say nothing when unsure: a name nothing is close to is
  left alone (another schema's table, a function, a word of your database),
  as are the columns of a table or view the build only partly understands, of
  a `select *` and of a `${placeholder}` table; keywords, functions, aliases
  (of tables, columns and CTEs), casts and quoted text are never names. When
  the application declares its own `NamingStrategy` bean, the names derived
  from entities are not known to the build. It reads
  `spring.sql.migration.locations` and `spring.sql.init.schema-locations`
  from `application.properties`, `application.yml` and `application.yaml`
  (`classpath:` only; any other location turns the check off, and so does a
  profile file or a profile-specific YAML document that sets them, a
  `spring.config.import` or the settings of a named data source). With
  `{vendor}` in a location, the migrations of each database are an
  alternative: a column of any of them is known. A name of one or two
  characters is never taken for a typo. A `{Entity}` that is no `@Table`
  class of the application, and close to none, is left to the start up (an
  entity of another package the repository's library can see is written
  through it).

At startup the repository still resolves `${property:default}` from the
environment, writes the names of `{Entity}` placeholders through the mapping,
and runs the `:#{expression}` values the build did not compile (SpEL).

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

### Compared with Spring

The transactions are checked against Spring itself, on PostgreSQL:
`tool/data_reference` is a Spring Boot 4.1 application (Spring Data JDBC,
real `@Transactional` services) and `test/transaction_matrix` runs the same
304 scenarios in both, each giving a normalized outcome (the rows that
committed, the values read, the kind of each exception with its SQL state).
The CI job "Data compared with Spring Data" compares them outcome by outcome;
the suite alone (`dart test -t postgres`) checks the starter's side against a
model of Spring's rules. Two transactions run side by side, step by step, with
no sleeps: the test waits until PostgreSQL reports a backend waiting for a
lock.

| Scenarios | Count | What is shown |
|---|---|---|
| Propagation | 224 + 7 | every outer (none or the seven) against every inner (the seven), four ways each: nothing fails, the inner throws and the outer catches it, the inner throws through the outer, the outer throws after the inner returned; and the inner waiting for a row the outer holds (`requiresNew` and `notSupported` use another connection and wait for the outer to end: a statement timeout shows the wait) |
| Rollback rules, templates, read only | 22 | `rollbackFor`, `noRollbackFor` (with subtypes), errors, `TransactionTemplate`, `setRollbackOnly`, read-only refusing writes (and a joined method keeping the outer's mode) |
| Isolation | 31 | dirty read, non-repeatable read, phantom, lost update (read-modify-write and atomic) and write skew at five levels, and a deadlock |
| Locks, versions, timeouts | 20 | `FOR UPDATE`, `FOR SHARE`, `NOWAIT`, `SKIP LOCKED` (with a limit), a lock timeout, `@Version` lost updates, `@Transactional(timeout:)` |

What the propagation matrix shows, as Spring has it: a method that joins
runs in the outer transaction and, when it fails, marks it rollback-only
(the outer commit then throws `UnexpectedRollbackException`, even when the
outer caught the error); `nested` rolls back to its savepoint and the outer
goes on; `requiresNew` commits or rolls back alone and does not see the
outer's uncommitted rows; `notSupported` runs in autocommit; `mandatory`
without a transaction and `never` within one are
`IllegalTransactionStateException`.

PostgreSQL's isolation (the level is really set: the scenarios read
`transaction_isolation`):

| | read uncommitted, read committed (default) | repeatable read | serializable |
|---|---|---|---|
| dirty read | no (read uncommitted runs as read committed) | no | no |
| non-repeatable read | yes | no | no |
| phantom | yes | no (a snapshot) | no |
| lost update, read-modify-write | the second overwrites | the second fails: `CannotSerializeTransactionException` (`40001`) | the same |
| lost update, `balance = balance + n` | none (the second waits, then adds) | the second fails (`40001`) | the same |
| write skew | yes | yes | the second commit fails (`40001`) |
| deadlock | `DeadlockLoserDataAccessException` (`40P01`) for one of the two | | |

What the comparison found in the starter, now fixed (each with a regression
test): a transaction that timed out was not rollback-only (Spring marks it:
its commit is an `UnexpectedRollbackException`); a commit that PostgreSQL
refused (a serialization failure under `serializable`) came wrapped in a
`TransactionSystemException` (Spring throws the translated
`DataAccessException` as it is); the exceptions had no
`ConcurrencyFailureException` root (the type retry code catches: the
version conflict, lock, deadlock and serialization failures extend it).

Where the starter deliberately differs (the differential test pins both
sides of each):

| Difference | Why |
|---|---|
| Every exception rolls back (Spring commits after a checked one: `rules/checked-exception`) | Dart has no checked exceptions; list the ones to commit in `noRollbackFor` |
| An exception that matches both `rollbackFor` and `noRollbackFor` rolls back (Spring: the entry closest to the exception's class wins; `rollbackFor: Exception, noRollbackFor: Soft` commits there, not here) | Dart cannot rank two types without reflection; leave out `rollbackFor`, which is the default |
| A `@Lock` query outside a transaction fails with `IllegalTransactionStateException` (Spring runs it in autocommit: the lock is gone at once) | an unlocked "locking" read is a bug |
| `40001` is a `CannotSerializeTransactionException`, `40P01` a `DeadlockLoserDataAccessException`, `55P03` a `CannotAcquireLockException`, `25006` an `InvalidDataAccessResourceUsageException` | Spring 7's `JdbcTemplate` translates by SQL state and gives `CannotAcquireLockException`, `PessimisticLockingFailureException`, `UncategorizedSQLException` and `UncategorizedSQLException`; the starter keeps the finer classes of Spring's PostgreSQL error-code table, with the same supertypes for code that retries (the comparison treats them as equal: `equivalentKinds`) |
| One transaction is not tied to a thread: it follows `await` through a `Zone`, and work started without `await` that outlives it fails | Dart has no thread-bound transactions |

## SQL databases

The starter has no driver inside: list the one you want in `pubspec.yaml`
(`sqlite3`, `postgres`), run the code generator, and set properties. The generator
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
| `spring.datasource.url` | | `sqlite:file:books.db`, `sqlite::memory:` (one connection: `pool.max-size=1`), `postgresql://user:password@host:5432/shop?sslmode=require`; a leading `jdbc:` is dropped |
| `spring.datasource.username`, `.password` | | when the URL does not carry them; never logged |
| `spring.datasource.driver` | | the driver's name (`sqlite3`, `postgres`) when two handle the scheme |
| `spring.datasource.pool.max-size` | `10` | most connections at once |
| `spring.datasource.pool.min-idle` | `0` | connections kept open when idle |
| `spring.datasource.pool.connection-timeout` | `30s` | the longest wait for a connection |
| `spring.datasource.pool.idle-timeout` | `10m` | an idle connection above `min-idle` older than this is closed |
| `spring.datasource.pool.max-lifetime` | `30m` | a connection older than this is closed when released |
| `spring.datasource.pool.validation` | `true` | check a connection that waited, before handing it out |
| `spring.datasource.sqlite.busy-timeout` | `5000` | milliseconds a connection waits for a lock |
| `spring.datasource.sqlite.base-directory` | working directory | where relative `sqlite:file:` names are looked for; beats `SqliteJdbcDriver.baseDirectory` |
| `spring.datasource.sqlite.isolate` | `false` | `true` opens each connection inside an isolate of its own; beats `SqliteJdbcDriver(isolate:)` |
| `spring.datasource.postgresql.sslmode` | `prefer` | `disable`, `allow`, `prefer`, `require`, `verify-ca`, `verify-full`; `ssl-root-cert`, `connect-timeout`, `application-name` and `search-path` sit beside it |
| `spring.datasources.<name>.*` | | the same keys for a named database, also `sql.init.*`, `sql.migration.*`, `data.jdbc.schema` |
| `spring.sql.init.*`, `spring.sql.migration.*`, `spring.data.jdbc.schema` | see the roadmap | scripts, migrations, `none` / `validate` (default) / `create` / `create-drop` |
| `spring.jdbc.template.query-timeout` | none | bounds each statement of the `JdbcTemplate` beans |
| `spring.data.jdbc.show-sql`, `format-sql`, `show-parameters` | `false` | statements (and values) at info |
| `spring.data.jdbc.slow-query-threshold` | none | a slower statement is logged at warn |

**PostgreSQL.** List `postgres` (the `postgres` package is the application's
dependency, never the starter's) and give a `postgresql://` URL, in the
properties or as pasted from Spring Boot (`jdbc:postgresql://host/db`). The
generator writes a `PostgresBinding` over the package and the
`postgresJdbcDriver` bean; the starter's `PostgresJdbcDriver` and
`PostgresDialect` do the rest:

- `?` markers become `$1`, `$2` (`??` is a literal `?`), values are always
  parameters; `int` is `BIGINT`, `DateTime` `TIMESTAMPTZ` (UTC), `bool`
  `BOOLEAN`, `Uint8List` `BYTEA`, `BigInt` `NUMERIC`; generated ids are
  `GENERATED BY DEFAULT AS IDENTITY`, read back with `RETURNING`;
- every isolation level (read uncommitted runs as read committed, as
  PostgreSQL does), read only transactions, savepoints, statement timeouts
  cancelled on the server, transactional DDL, advisory lock for the
  migrations of several instances;
- `@Lock` is `FOR UPDATE` / `FOR SHARE`, `NOWAIT` for a zero timeout,
  `SKIP LOCKED`, `SET LOCAL lock_timeout` for a longer wait;
- errors by SQL state (`23505` a `DuplicateKeyException`, `40001` a
  `CannotSerializeTransactionException`, `40P01` a
  `DeadlockLoserDataAccessException`, `55P03` a `CannotAcquireLockException`,
  `57014` a `QueryTimeoutException`, `42xxx` wrong SQL, `08xxx` a lost
  connection...), with the server's message but never a bound value or a
  password;
- TLS follows `sslmode` (default `prefer`: TLS if the server has it; use
  `require` or `verify-full` outside development);
- text is ordered by the database's collation, not code units as in the
  in-memory store and SQLite.

The [configuration reference](../docs/configuration.md#postgresql) has the
URL parameters and every detail. The tests of the driver, the schema, the
locks and the suites memory, SQLite and PostgreSQL share run against a real
server when `SPRING_TEST_POSTGRES_URL` is set; without it each test file
starts a PostgreSQL container of its own when Docker is there (the
containers of `spring_boot_starter_test`, `dart test -t postgres`), and
they are skipped when it is not (tag `postgres`):

```text
docker run --rm -d --name spring-pg-test -e POSTGRES_PASSWORD=test -p 55432:5432 postgres:17
SPRING_TEST_POSTGRES_URL=postgresql://postgres:test@localhost:55432/postgres dart test -t postgres
docker stop spring-pg-test
```

**SQLite on an isolate of its own.** SQLite's calls are synchronous: on
Flutter's UI isolate or a server's event loop, a long query or a wait for a
lock holds everything else. With `spring.datasource.sqlite.isolate=true`
each connection opens its database inside a worker isolate, and every
statement is a message to it. Nothing else changes: transactions,
savepoints, read-only mode, streams (rows come in batches, the cursor is
closed when the stream is cancelled) and errors, with their types, work as
before. Values are copied between the isolates, so a very large result costs
a copy; a connection must be closed (the pool does it when the application
closes), which ends its isolate; if the isolate dies, the pending and the
later statements fail with a `SqlError` whose `connectionLost` is true.
The generated `SqliteBinding` is sent to the isolate, so a binding of your
own must hold no native resource. A loader override of the `sqlite3` package
(`open.overrideFor(...)`) belongs to the isolate that runs it: the one made
in `main` does not reach the worker, which opens the database with the
package's default loader, and the starter has no hook to run code in the
worker. When a platform needs an override, keep the databases on the
caller's isolate with `spring.datasource.sqlite.isolate=false`. In a Flutter
app,
[`spring_boot_starter_flutter`](https://pub.dev/packages/spring_boot_starter_flutter)
turns it on and points `spring.datasource.sqlite.base-directory` at the
app's own directory (`spring.datasource.sqlite.location`: `support`,
`cache` or `documents`): it only sets these properties, the starters do not
depend on each other.

**In a web application.** With
[`spring_boot_starter_web`](https://pub.dev/packages/spring_boot_starter_web)
among the application's dependencies, the generator adds a
`HandlerExceptionResolver` (the bean `dataAccessExceptionResolver`) that
answers an `OptimisticLockingFailureException` or a `DuplicateKeyException`
with a 409 and an `EmptyResultDataAccessException` with a 404, with a fixed
detail that never shows the exception's message; the starters do not
depend on each other.

Durations are written `500ms`, `30s`, `10m`, `PT30S`, or as milliseconds.
The names of `spring.datasources` are found in property sources that list
their keys (files, the command line), not in an environment variable
alone. The context must be refreshed with `refreshAsync()` (what
`SpringApplication.runAsync` and `ApplicationContextRunner.runAsync` do):
the schema is set up asynchronously.

## Testing: `@DataTest`

A test class marked `@DataTest()` runs on the repositories of the
application only: its data beans, an in-memory SQLite database (the
migrations applied, or the tables made from the entities) and a transaction
around every test that is rolled back afterwards. The services, controllers
and runners of the application are not in the context, and
[`spring_boot_starter_test`](https://pub.dev/packages/spring_boot_starter_test)
runs it (a dev dependency; the starters do not depend on each other, the
generator joins them in `test/spring/<name>.test.spring.dart`).

```dart
@DataTest()
class BookRepositoryTest {
  @Autowired()
  late BookRepository books;

  @Test()
  Future<void> findsABookByItsTitle() async {
    await books.save(Book(title: 'Dune', year: 1965));
    expect(await books.findByTitle('Dune'), hasLength(1));
  } // rolled back: the next test starts with no books
}

void main() => runSpringTests();
```

`@Commit()` (or `@Rollback(false)`) on a test, a class or a `@Nested` group
commits instead; `@BeforeEach` and `@AfterEach` run inside the transaction;
`@DataTest(include: [Library])` adds beans of the application, and
`replaceDatabase: false` keeps the configured database;
`@DataTest(transactionManager: 'stats')` runs the tests in the transaction of
that one manager (and no other) instead of every manager the repositories
use. The in-memory
database is one connection, so a test cannot start a `requiresNew`
transaction on it. [Testing, section 19](../docs/testing.md#19-data-tests-datatest)
has the details; `DataTestSetup` and `runInTestTransaction`
(`package:spring_boot_starter_data/testing.dart`) do the same for tests
written as functions.

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
- `@DataTest` replaces `@DataJdbcTest` with `@AutoConfigureTestDatabase`: it
  is transactional by itself, and the database is always an in-memory SQLite
  one (`replaceDatabase: false` keeps yours).
