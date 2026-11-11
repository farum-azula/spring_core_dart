# spring_boot_starter_data

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

**Documentation:** [farum-azula.org/components/spring-boot-starter-data](https://farum-azula.org/components/spring-boot-starter-data)

> **First release.** Repositories run in memory (with transactions and
> locks) or on SQLite and PostgreSQL from properties. What is planned next
> is in
> [the roadmap](https://github.com/farum-azula/spring_core_dart/blob/main/roadmap/spring_boot_starter_data.md).

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

`save` inserts a new entity and updates an existing one, and the rule is
Spring Data's. With a `@Version`, the entity is new when the version is
`null`, or `0` for a version that cannot be null (`int version = 0`, Java's
primitive `long`); a nullable `int? version` (Java's `Long`) is new only when
`null`, so a row stored at version `0` (by a SQL script, or by a Spring Data
JDBC application) is updated, not inserted again. A `DateTime` version is new
when `null`. Without a version, an entity is new when its id is `null`.

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
  (`resources:` only; any other location turns the check off, and so does a
  profile file or a profile-specific YAML document that sets them, a
  `spring.config.import` or the settings of a named data source). With
  `{vendor}` in a location, the migrations of each database are an
  alternative: a column of any of them is known. A name of one or two
  characters is never taken for a typo. A `{Entity}` that is no `@Table`
  class of the application, and close to none, is left to the start up (an
  entity of another package the repository's library can see is written
  through it).

### In the editor

The Dart language server of the `dart_spring` extension (Zed) knows the data
layer, from the entities in your sources and the `entities` of
`lib/spring_gen/spring_metadata.json`: inside `@Query('...')` it colours the
SQL, completes `{` (entities), `{Book.` (properties) and `:` (parameters),
goes from `{Book}` to the class, from `{Book.authorId}` to the field and from
`:year` to the parameter, shows the table and column on hover, and reports
what the build would, while you type: an unknown `{Entity}` or property with
"did you mean", a `:name` that is no parameter, a parameter the query never
uses (a warning; `Pageable` and `Sort` are exempt), a mistake in a `:#{...}`
expression (the parameters are `#name`, beans `@name`), unbalanced quotes
and parentheses. A derived query name (`findByTitelAndYear`) is read with the
build's grammar: the unknown property is underlined with a suggestion, the
parameter count is checked, a hover shows the SQL the name stands for and the
property part goes to the entity's field.

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

## JSON columns

`@Json()` on a property stores it as JSON in one column: a class of the
application, a list or a map of them, or plain `Map<String, Object?>` / `List`
data.

```dart
@Table('profiles')
class UserProfile {
  @Id()
  int? id;

  @Json() // PostgreSQL: jsonb
  Settings settings; // a class of the application

  @Json(binary: false) // PostgreSQL: json
  Map<String, Object?> raw;

  @Json()
  List<Address>? addresses;
}
```

The value is written and read by the application's `ObjectMapper` (the bean
controllers and Feign clients use, so its settings and the `@Json...`
annotations of the classes apply; without the bean, a mapper with the default
settings). The build describes the classes of the property's type for it,
nested ones too, the way it describes a controller's body: no `@Introspected`
to add for the classes of the application's package (a class of another
package is described there, with `@Introspected`). A `null` property is a SQL
`NULL`, not the JSON `null`.

| Store | What it keeps |
|---|---|
| PostgreSQL | a `jsonb` column, or `json` with `binary: false` (the text as written: key order, spaces); bound as text with `CAST(? AS JSONB)` |
| SQLite | the JSON text in a `TEXT` column; a table the starter creates has `CHECK (json_valid("column"))` |
| any other SQL database | the JSON text in a `TEXT` column: what a dialect that overrides nothing does |
| in-memory | the decoded JSON (maps, lists, numbers, strings), copied on the way in and out, so a saved value does not change with the object it came from |
| a store over a REST API (Supabase) | the decoded JSON, sent and received as nested JSON |

`spring.data.jdbc.schema: create` writes those column types and `validate`
checks them: PostgreSQL wants exactly `jsonb` or `json`, SQLite a text column
(or one declared `JSON`, or without a type); another type is reported like any
other mismatch (`Column "settings" in table "profiles" for
UserProfile.settings has the wrong type: expected JSONB (Settings), found
json`). A JSON column gets no `DEFAULT`: the property's default value is used
when a row has none.

A dialect says how its database keeps JSON in one place,
`SqlDialect.jsonStorage(Json)`, which returns a `JsonStorage` (the column
type, the test of an existing column, an optional `CHECK`, the marker and the
value an insert or update binds, the reading of what the driver gives). The
default suits a database without a JSON type; a dialect of your own overrides
it for one that has it.

A `@Query` reads such a column like the repository's own methods do, into the
entity or into a class with a `@Json` property of its own, and it is the way
to filter by what is inside:

```dart
@Query("select * from profiles where settings ->> 'theme' = :theme")
Future<List<UserProfile>> themed(String theme);
```

What is refused, with the fix in the message:

- A condition or an order on a `@Json` property in a derived query
  (`findBySettings`, `OrderBySettings`, a `Sort` by it): a build error, and an
  `InvalidDataAccessApiUsageException` at run time on every store. Use
  `@Query` with the database's JSON operators on a SQL store, or `@Procedure`.
- `@Json` on the `@Id`, the `@Version`, an audited property, a
  `@MappedCollection` or a reference to another aggregate: a
  `MappingException` when the entity is read.
- A stored value that cannot be read as the property's type: a
  `MappingException` naming the class and the property (and the place in the
  JSON), never the value.

Without `@Json`, a `Map`, `List` or `Set` property (other than `List<int>` and
`Uint8List`, which are bytes, and a `@MappedCollection`) is no column of a SQL
database, and the SQL store refuses it before any statement runs:

```
Invalid repository Parcels:
  - Parcel.meta: a Map<String, Object?> property without @Json has no column on a SQL store: add @Json() to keep it as JSON, or @MappedCollection for rows of a child table
```

- **At build time**, when the build knows that the repository's store is the
  SQL store (`@UseStore('jdbc')`, `@UseDataSource`, or `spring.datasource.url`
  in the configuration): a `Map`, a `Set`, or a `List` of anything but simple
  values is a build error. A store says it needs this check with
  `DataStoreDescriptor(collectionsNeedJson: true)`.
- **When the application starts**, on every SQL store: the repository is not
  created (`Invalid repository X:`), and `spring.data.jdbc.schema: validate`
  and `create` report the same line (`SchemaValidator`, `SchemaCreator`). The
  store asks its dialect: `SqlDialect.storesCollection(type)`.
- **PostgreSQL arrays** stay: a `List` of simple values (`List<String>`,
  `List<double>`, `List<bool>`, `List<DateTime>`) is stored in and read from
  an array column you create (`tags text[]`), so the build leaves such a list
  to the store, and SQLite, which has no arrays, refuses it at start. A `Set`
  and a `Map` are never arrays.

The in-memory store keeps the Dart object as it is (its inner lists and maps
are shared with the instance that was saved), and a store over a REST API
sends a plain map or list as JSON and reads it back, but cannot build classes
from it: neither is checked.

## Auditing

`@EnableDataAuditing()` on a `@Configuration` class (Spring Data JDBC's
`@EnableJdbcAuditing`) sets the properties marked `@CreatedDate`,
`@LastModifiedDate`, `@CreatedBy` and `@LastModifiedBy` on each save. The
time comes from a `DateTimeProvider` bean (the system clock when there is
none). The auditor comes from an `AuditorAware` bean that the application
declares: no starter provides one, the security starter included, so
without it the `@CreatedBy` and `@LastModifiedBy` properties stay as they
are. With several, `auditorAwareRef` / `dateTimeProviderRef` name the
bean.

```dart
@Configuration()
@EnableDataAuditing()
class AuditConfig {
  // The logged-in user's name, from the security context.
  @Bean()
  AuditorAware<String> auditor() => CurrentUserAuditor();
}

final class CurrentUserAuditor implements AuditorAware<String> {
  @override
  String? getCurrentAuditor() =>
      SecurityContextHolder.getContext().authentication?.name;
}
```

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
spring.datasources.stats.sql.migration.locations=resources:db/stats

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
| `spring.datasource.postgresql.sslmode` | `prefer` | `disable`, `allow`, `prefer`, `require`, `verify-ca`, `verify-full`; `ssl-root-cert`, `connect-timeout`, `application-name` and `search-path` sit beside it. Like every `postgresql.*` and `sqlite.*` key, also set by a variable (`SPRING_DATASOURCE_POSTGRESQL_SSLMODE=verify-full`, `SPRING_DATASOURCES_SHOP_POSTGRESQL_SSLMODE` for a named database) |
| `spring.datasource.sqlite.location` | `support` | read by the Flutter starter only: `support`, `cache` or `documents`, the directory it sets `base-directory` to |
| `spring.datasources.<name>.*` | | the same keys for a named database, also `sql.init.*`, `sql.migration.*`, `data.jdbc.schema` |
| `spring.sql.init.*`, `spring.sql.migration.*`, `spring.data.jdbc.schema` | see [the configuration reference](https://github.com/farum-azula/spring_core_dart/blob/main/docs/configuration.md#20-reference-sql-databases) | scripts, migrations, `none` / `validate` (default) / `create` / `create-drop` |
| `spring.jdbc.template.query-timeout` | none | bounds each statement of the `JdbcTemplate` beans |
| `spring.data.jdbc.show-sql`, `format-sql`, `show-parameters` | `false` | statements (and values) at info; the values of a name that looks secret, and the values bound without a name, are masked (see "What the logs hold") |
| `spring.data.jdbc.slow-query-threshold` | none | a slower statement is logged at warn |
| `spring.data.memory.lock-timeout` | `10s` | the in-memory store's wait for a row lock |
| `spring.data.store` | `jdbc` with a primary data source, else `memory` | the store of the repositories without `@UseStore` and `@UseDataSource`: `memory`, `jdbc` or the name of another store; the build reads it too (see "Stores") |

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
- TLS follows `sslmode` (default `prefer`: TLS if the server has it, plain
  text when it has none, which an attacker on the path can force: the driver
  logs a warning, once for each database, when it falls back; use `require`
  or `verify-full` outside development, also through
  `SPRING_DATASOURCE_POSTGRESQL_SSLMODE`);
- text is ordered by the database's collation, not code units as in the
  in-memory store and SQLite;
- a derived `In` / `NotIn` is one array parameter (`= any($1)`), so a list can
  have more than the protocol's 65 535 parameters; SQLite refuses a list past
  its 32 766 with a clear message, and a NUL character in a text is refused
  before it is sent (`InvalidDataAccessApiUsageException`, on every store for
  a derived query).

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

**What the logs hold.** Statements are logged at debug without values. The
values are logged at trace (`spring.jdbc.core.StatementCreatorUtils`), or at
info with `spring.data.jdbc.show-parameters=true`, each with the name it is
bound to: the column of a repository's `save`, derived query or `delete`, the
`:name` of a `@Query`. The value of a name that looks secret (case and
separators ignored, it contains `password`, `passwd`, `passphrase`, `secret`,
`credential`, `token`, `apikey`, `privatekey`, `accesskey`, `signingkey` or
`encryptionkey`, or one of its words is `pwd` or `key`: `password_hash`,
`apiToken`, `clientSecret`, `sslpassword`, `privatekey`; not `monkey`,
`keyword`, `tokenizer` or `secretary`) is written
`******`, in the repository's method line too. A value bound without a name
(a plain list given to a `JdbcTemplate`) cannot be told from a secret: it is
shown at trace, as Spring does, and masked when `show-parameters` puts it at
info. A password of the URL's user info is never logged, and neither is the
value of a query parameter whose name looks secret
(`?password=…`, `sslpassword`, `token`): the pool's "Starting..." line and
every message about a URL show `password=******`. Names that do not look
secret but hold one (`pw`, `pin`) are not masked: name columns so the rule
sees them, or keep trace off in production.

**Input from requests.** A `Sort` or a `Pageable` built from request
parameters never reaches the SQL as text: sort properties are entity
properties (or, for a `@Query`, identifiers, quoted: `a.b`), directions
are `asc` and `desc`. A `@Query` that returns an entity checks the name
against the entity's properties and columns, and one that returns a class
against the class's properties (`authorName` sorts by `author_name`, as the
row mapper matches it) and the entity's; a single column, a `Map` or a
`rowMapper` result knows nothing to check against, and the database answers an
unknown column. A property that does not exist is a
`PropertyReferenceException` (an `InvalidDataAccessApiUsageException`) whose
message writes the name escaped, so a name with a line break cannot forge a
log line. `PageRequest.of` refuses a negative page, a size below one, and a
page and size whose offset would pass 2^53 - 1 (an
`InvalidPagingRequestException`, an `ArgumentError`), so an offset never
wraps around to another page; a `Pageable` of your own with a negative
offset is refused by the stores. There is no `Pageable`/`Sort` argument
resolver for controllers yet: parse `page`, `size` and `sort` yourself and
cap `size` (a client that sends `size=1000000000` gets the whole table), and
allow-list the properties a request may sort by (a sort is an `ORDER BY`
oracle: a client can learn the order of values it cannot read, such as a
password hash). Bind request bodies to DTOs, not to entities: an entity
binding lets the client choose the id and the version.

**In a web application.** With
[`spring_boot_starter_web`](https://pub.dev/packages/spring_boot_starter_web)
among the application's dependencies, the generator adds a
`HandlerExceptionResolver` (the bean `dataAccessExceptionResolver`) that
answers an `OptimisticLockingFailureException` or a `DuplicateKeyException`
with a 409, a `PermissionDeniedDataAccessException` with a 403 ("Access
denied"), an `EmptyResultDataAccessException` with a 404, and a
`PropertyReferenceException` ("Invalid sort property") or an
`InvalidPagingRequestException` ("Invalid page or sort request") or an
`InvalidDataArgumentException` ("Invalid request value": a text with a NUL
character, a list longer than a statement binds, a `LIKE` pattern the
database rejects; the caller's value, not a developer's mistake, so the
other `InvalidDataAccessApiUsageException`s stay a 500) with a 400,
with a fixed detail that never shows the exception's message (the web
starter logs these answers at debug); the starters do not depend on each
other.

A `Pageable` or `Sort` parameter of a controller method is filled from
`?page=&size=&sort=title,desc&sort=year` by the same glue (the bean
`pagingArgumentResolvers`, a `WebMvcConfigurer`), with Spring Data Web's
rules and Spring Boot's properties `spring.data.web.pageable.default-page-size`
(20), `max-page-size` (2000), `one-indexed-parameters` (false),
`page-parameter`, `size-parameter`, `prefix`, `qualifier-delimiter` and
`spring.data.web.sort.sort-parameter`; `@PageableDefault(size:, page:, sort:,
direction:)` and `@SortDefault(sort:, direction:)` go on the parameter, and a
`@Qualifier('x')` reads `x_page`, `x_size`, `x_sort`. A size above the maximum
is cut, a negative or non-numeric page is 0, a size below one is the default.
A sort property the entity does not have is a 400. A returned `Page<T>` is
written as Spring Data 3.3's stable JSON: `{"content": [...], "page": {"size",
"number", "totalElements", "totalPages"}}`.

Durations are written `500ms`, `30s`, `10m`, `PT30S`, or as milliseconds
(`spring.datasource.postgresql.connect-timeout` does not take `PT30S`).
The names of `spring.datasources` are found in property sources that list
their keys (files, the command line), not in an environment variable
alone. The context must be refreshed with `refreshAsync()` (what
`SpringApplication.runAsync` and `ApplicationContextRunner.runAsync` do):
the schema is set up on a connection, which Dart cannot wait for without
`await`. With a SQL data source start the application with
`await runApplicationAsync(args)`; the synchronous `runApplication(args)`
fails at start with a report that says so.

### The rate limiter's buckets: `JdbcRateLimitStore`

The web starter's rate limiter (`spring.web.rate-limit.*`, its
[Rate limiting](../spring_boot_starter_web/README.md#rate-limiting)
section) keeps its buckets in a table of the primary data source when the
application has one: every server on the database then shares the limits,
and they outlive a restart. Nothing to declare; `spring.web.rate-limit.store`
is `jdbc` by default with a primary `DataSource` (set it to `memory` to
keep the counting out of the database).

An acquisition is one statement, atomic in the database and on its clock,
on a connection of its own (a rolled-back transaction of the request has
still been counted):

```sql
-- PostgreSQL; SQLite runs the same with min / max and its own clock.
insert into rate_limit as b (key, tokens, allowed, updated_at, expires_at)
values (:key, :capacity - :permits, true, now, now + :capacity / :refill)
on conflict (key) do update set
  tokens  = <the bucket filled for the time that passed, less :permits when it holds them>,
  allowed = <whether it held them>,
  updated_at = greatest(b.updated_at, excluded.updated_at),
  expires_at = excluded.expires_at
returning allowed, tokens
```

The table:

```sql
create unlogged table if not exists rate_limit (   -- SQLite: a plain table, real and integer
  key text primary key,
  tokens double precision not null,
  allowed boolean not null,
  updated_at double precision not null,              -- seconds since 1970
  expires_at double precision not null               -- when the bucket is full again
);
create index if not exists rate_limit_expires_at on rate_limit (expires_at);
```

The store creates it before its first statement when
`spring.data.jdbc.schema` is `create` or `create-drop` (or
`spring.data.jdbc.rate-limit.create-table: true`). Otherwise it comes
from your migrations: copy `lib/sql/rate_limit/postgresql.sql` or
`lib/sql/rate_limit/sqlite.sql` of this package
(`package:spring_boot_starter_data/sql/rate_limit/...`).
`spring.data.jdbc.rate-limit.table` renames the table (`name` or
`schema.name`). Rows of buckets that are full again are deleted about
once a minute. For a database the starter has no statements for, declare
a `RateLimitStatements` bean. Spring has no counterpart; Bucket4j's JDBC
`ProxyManager` is the nearest.

### Sessions per user: `JdbcSessionHook`

A `JdbcSessionHook` bean prepares the database session of a connection
for the work about to run on it: the way to run every statement as the
current user (a role and the user's claims, for row-level security), to
set a tenant or a search path. All the beans of the type run, in `@Order`,
on every `DataSource` bean:

```dart
@Component()
class CurrentUserSession extends JdbcSessionHook {
  CurrentUserSession(this.users);
  final CurrentUser users;

  // Right after a transaction began: transaction scope, gone at its end.
  @override
  Future<void> afterBegin(ConnectionHolder transaction) async {
    await transaction.connection.query(
      "select set_config('app.user_id', ?, true)",
      [users.id],
    );
  }

  // Around one unit of work outside a transaction, on a pooled connection.
  @override
  Future<void> beforeWork(DataSource dataSource, JdbcConnection c) async {
    await c.query("select set_config('app.user_id', ?, false)", [users.id]);
  }

  @override
  Future<void> afterWork(DataSource dataSource, JdbcConnection c) =>
      c.execute('reset app.user_id');
}
```

`afterBegin` runs once for each transaction, before its first statement
(every `DataSourceTransactionManager` of the data source calls it);
`beforeWork` and `afterWork` run around each call of `JdbcTemplate`,
`JdbcClient` or a repository outside a transaction (a stream until it
ends), `afterWork` in reverse order. A hook that fails before the work
fails it and the connection is closed; a hook that fails after it is
logged and the connection is closed instead of going back to the pool, so
no statement runs unprepared and no connection is reused with another
user's state. Migrations, the schema initializer and the health check do
not go through the hooks. A statement the database refuses for a missing
privilege or a row-level security policy (PostgreSQL's `42501`) is a
`PermissionDeniedDataAccessException`.

## Stores: what a store can do

A repository talks to a `DataStore`: the in-memory one, the SQL one
(`JdbcDataStore`), or one of another package registered under its
`@UseStore` name. A store says what it has beyond the CRUD and derived
queries in `capabilities`, and a repository that uses more fails at
startup, with the method, the store and the fix:

| Capability | Used by | Memory | SQL | Interface of the store |
|---|---|---|---|---|
| `transactions` | `@Transactional`, atomic writes | yes | yes | `TransactionalDataStore` |
| `locks` | `@Lock` | yes | yes | |
| `queries` | the SQL of `@Query` | no | yes | |
| `functions` | `@Procedure` (database functions) | no | PostgreSQL | `FunctionDataStore` |
| `changes` | streams of changes | yes | no | `ChangeStreamDataStore` |

```text
Invalid repository StockRepository:
  - StockRepository.findBySku: @Lock needs a store with row locks, and the
    rest store is none: use a SQL store (@UseStore('jdbc') with
    spring.datasource.url), or remove @Lock (a @Version checks concurrent
    writes without a lock)
```

**The store of a repository** is its `@UseStore('name')`; else the SQL
store with a `@UseDataSource`; else `spring.data.store` (`memory`, `jdbc`
or the name of any other store) when it is set; else `jdbc` with a primary
data source and `memory` without. A name of no store fails the start with
the stores there are.

**Checked by the build.** A package describes its store to the build with
a constant in (or exported by) its `lib/spring_auto_configuration.dart`,
and the starter describes `memory` and `jdbc` the same way:

```dart
@DataStoreDeclaration()
const documentStore = DataStoreDescriptor(
  'documents',
  capabilities: DataStoreCapabilities(changes: true),
  // The default store when the application's application.yml (without a
  // profile) sets every `whenProperty` and none of `unlessProperty`.
  defaultWhen: DataStoreDefault(
    whenProperty: ['documents.url'],
    unlessProperty: ['spring.datasource.url', 'spring.data.store'],
  ),
  // The store's own fix for what it lacks, said before the general one.
  fixes: {
    DataStoreCapability.transactions:
        'set documents.sql-url to keep the documents in SQL',
  },
);
```

When the build knows the store of a repository (`@UseStore`,
`@UseDataSource`, `spring.data.store` in `application.yml` or
`application.properties`, or the first described store whose `defaultWhen`
holds) and the store is described, the error above is a build error, in
the list of the repository's problems. So is a `@Transactional` (without a
`transactionManager:`) on any bean when the application's default store is
described without transactions. A capability that depends on the database
(`functions` of the SQL store) is declared `true` and decided at startup;
a store nothing describes is checked at startup only.

**Database functions.** A method with `@Procedure('name')` calls the function
with its parameters as named arguments, each named in snake case
(`accountId` → `account_id`), and reads its rows as the rows of a `@Query`
are: the entity, a described class, a single column; as a `List`, a
`Set`, a `Stream`, one value or nothing. On PostgreSQL the call is
`select * from "name"("argument" => ?)`, in the caller's transaction.

```dart
abstract interface class Accounts implements CrudRepository<Account, int> {
  @Procedure('transfer')
  Future<void> transfer(int fromId, int toId, int amount);

  @Procedure('accounts_over')
  Future<List<Account>> over(int balance);
}
```

**Changes of rows.** Two more kinds of derived methods, on a store that
reports its changes (the in-memory store does, at commit, never from a
transaction that rolls back):

```dart
abstract interface class Tasks implements CrudRepository<Task, int> {
  // The result of the query, emitted when the stream is listened to and
  // again after every change that concerns it.
  Stream<List<Task>> watchByListIdOrderByPositionAsc(int listId);

  // Every task: nothing after `By`, as `findAllBy()`.
  Stream<List<Task>> watchAllBy(Sort sort);

  // The inserts, updates and deletes of the rows the conditions match,
  // each with the row after and before.
  Stream<RowChange<Task>> changesByListId(int listId);
}
```

A `watch…By` method takes what a find takes (`First`/`Top`, `Distinct`,
`OrderBy`, a `Sort` or a `Pageable`) and returns `Stream<List<T>>`; it
never runs two queries at once, and cancelling the subscription stops the
store's reporting. A `changes…By` method returns `Stream<RowChange<T>>`
and has conditions only. Any other return type is a build error.
`stream…By` keeps its meaning (the result once, as a stream).
`CriteriaMatcher` tests an instance or a row against a `Criteria` without
a database.

## Testing: `@DataTest`

A test class marked `@DataTest()` runs on the repositories of the
application only: its data beans, an in-memory SQLite database (the
migrations applied, or the tables made from the entities) and a transaction
around every test that is rolled back afterwards. The services, controllers
and runners of the application are not in the context, and
[`spring_boot_starter_test`](https://pub.dev/packages/spring_boot_starter_test)
runs it (a dev dependency; the starters do not depend on each other, the
generator joins them in `test/spring_gen/<name>.test.spring.dart`).

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
use, and `@Transactional(transactionManager: 'stats')` on a test method (or a
`@Nested` group) does it for that test alone. The in-memory
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
  no checked exceptions); when `rollbackFor` and `noRollbackFor` both match,
  the entry closest to the exception's class wins, as in Spring.
- A store declares its `DataStoreCapabilities`, and a repository that
  needs more fails at startup (Spring Data has a module for each store
  instead). `@Procedure('name')` calls a database function (Spring Data JPA's
  `@Procedure`; Spring Data JDBC has none); `RowChange` streams have no
  counterpart in Spring Data JDBC.
- `JdbcSessionHook` beans prepare the connections' sessions; Spring has
  `DataSourceTransactionManager.prepareTransactionalConnection` to
  override and `DataSource` adapters.
- `@DataTest` replaces `@DataJdbcTest` with `@AutoConfigureTestDatabase`: it
  is transactional by itself, and the database is always an in-memory SQLite
  one (`replaceDatabase: false` keeps yours).
