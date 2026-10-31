# spring_boot_starter_data (planned, 0.6.0)

Spring Data for Dart: entities, repositories, transactions, locks, SpEL in
queries; on a server and in Flutter apps. One starter, no driver inside:
the application adds the driver it wants, the generator sees it.

## Decisions (the owner, October 2026)

- **The model of Spring Data JDBC, not JPA.** An aggregate is loaded and
  saved whole, `save` writes at once, other aggregates are referenced by
  id. No persistence context, no dirty checking, no lazy proxies (they
  need run-time proxies of entities, which Dart without reflection has
  not, and they are JPA's usual traps: `LazyInitializationException`,
  N+1). The annotations keep the familiar names (`@Table`, `@Id`,
  `@Column`, `@Version`, `@Transactional`, `@Lock`, `@Query`).
- **One starter, `spring_boot_starter_data`, without drivers.** Pub has no
  optional dependencies, and `sqlite3` builds and bundles a native
  library: a starter depending on every driver would put SQLite into
  every Postgres server and every Flutter app. So the application lists
  its driver (`postgres`, `sqlite3`), as in Spring Boot (the starter plus
  the JDBC driver), and the generator, seeing it in the application's
  dependencies, generates the small adapter (connections, parameters,
  types, transactions) into the `.spring.dart` file — Spring Boot's
  `@ConditionalOnClass`. The third-party driver is the application's
  dependency, not ours (`roadmap/README.md`, dependencies).
- **A driver present only makes it available; the properties make a
  database.** No driver: the in-memory store and Supabase (HTTP, no
  driver) still work; a `spring.datasource.url` without its driver stops
  the start with what to add. Several drivers, several databases:
  `spring.datasource.*` (the primary one, as in Spring Boot) and
  `spring.datasources.<name>.*` (an extension: Spring Boot configures one
  `DataSource`, more are beans written by hand). The driver is chosen by
  the URL's scheme.
- **Stores behind one repository interface:** JDBC-like over SQLite and
  PostgreSQL, key-value over Redis, Supabase (its own starter) over
  PostgREST (HTTP: Flutter apps never hold
  database credentials; the user's token and row-level security decide),
  and in memory for tests. A repository chooses its store and database:
  `@UseDataSource('analytics')`, `@UseStore('supabase')`.

## Decisions made while building it (step 1)

- **No annotation needed on a repository**, as in Spring Data: an
  interface extending `DataRepository<T, ID>` (directly or through
  `CrudRepository` and the others) gets a generated implementation and is
  a bean. `@Repository('name')` only names the bean. A generic interface
  is a base for others, never a bean (Spring's `@NoRepositoryBean`).
- **Names that differ from Spring**, because Dart has one namespace per
  import and the core already has these names: the marker is
  `DataRepository` (`@Repository` is the stereotype annotation), a sort
  step is `SortOrder` (`@Order` orders beans), the database and store of a
  repository are `@UseDataSource('analytics')` and `@UseStore('supabase')`
  (Dart cannot mix an optional positional `name` with named parameters on
  `@Repository`).
- **No overloading in Dart:** `findAll()`, `findAllSorted(Sort)` and
  `findAllPaged(Pageable)` instead of Spring's three `findAll`.
- **How it works:** the generator reuses the `@InterfaceProxy` machinery
  (Feign's): `_$BookRepositoryImpl` forwards each call to the starter's
  handler; `InterfaceMetadata.supertypeArguments` gives it `Book` and
  `int` as `TypeInfo`s. `@Table` extends `@Introspected`, so the entity's
  properties and constructor are described at build time. Derived queries
  are parsed and checked when the repository is created: a wrong property
  stops the application at startup with the reason and a suggestion
  (`did you mean 'title'?`). Checking them in the build itself is a later
  step.

## Order of work

1. `spring_data_commons` part of the starter: `Repository`,
   `CrudRepository`, `ListCrudRepository`, `PagingAndSortingRepository`,
   `Page`, `Slice`, `Pageable`, `Sort`; the generator's entity mapping and
   repository implementations, derived queries parsed at build time (a
   wrong property name is a build error); `@Query` with named parameters
   and SpEL; auditing; `@Version`; the in-memory store; `@DataTest`.
   Containers in tests (`@Container`, `@ServiceConnection`, our own
   Docker client: [spring_boot_starter_test.md](spring_boot_starter_test.md))
   come with it, before SQLite and PostgreSQL need them.
2. Transactions: `PlatformTransactionManager`, `@Transactional` on the AOP
   proxies (propagation, isolation, read-only, rollback rules),
   `TransactionTemplate`; the current transaction in a `Zone`, so it
   follows `await`. Decided while building it:
   - each transactional block runs in its own zone scope; `requiresNew`
     and `notSupported` isolate the scope instead of Spring's suspend and
     resume (the outer transaction goes on when the block's code ends);
     work started in a transaction without `await` and still running
     after it fails (`IllegalTransactionStateException`), it never runs
     outside the transaction unnoticed;
   - `@Transactional(transactionManager: 'analytics')`: Dart cannot mix
     Spring's positional `value` with named parameters;
   - every exception rolls back unless listed in `noRollbackFor`; types
     match with subtypes: the generator writes a `value is T` test for
     every type written in an annotation (`BeanModule.typeTests`,
     `BeanIntrospector.isInstanceOf`), usable later by `@ExceptionHandler`
     and `@Retryable` too;
   - the in-memory store has transactions (read committed, row locks,
     deadlock detection, savepoints) and `@Lock`, so the propagation
     matrix and the locks are tested before SQLite.
3. SQLite (the `sqlite3` package): server and Flutter; `spring.sql.init`
   (`schema.sql`, `data.sql`); migrations `db/migration/V1__*.sql`
   (Flyway's naming, `spring.sql.migration.*`).
   Built (server); decided while building it:
   - the driver: the generator writes a thin glue over `package:sqlite3`
     into each module of an application that lists `sqlite3` (a template
     in the starter, `lib/src/jdbc/drivers/sqlite3.dart.tmpl`, its symbols
     imported through the module's prefixes); everything else
     (`SqliteJdbcDriver`, `SqliteDialect`, transactions, savepoints, one
     statement at a time per connection) is the starter's, without
     importing `sqlite3`. `postgres` is one more row of the same table;
   - the JDBC layer: `PooledDataSource`, `DataSourceTransactionManager`,
     `JdbcTemplate`, `NamedParameterJdbcTemplate`, `JdbcClient`,
     `DataClassRowMapper`; `JdbcDataStore` turns derived queries into SQL,
     `@Query` with named parameters, SpEL and DTOs; one test suite runs on
     the in-memory store and on SQLite and must give the same answers,
     with hostile strings in every operator;
   - startup: the `dataSource` bean runs scripts, migrations and the
     schema check before handing out its first connection, so no
     application code reaches the database first;
   - SQLite's limits, in the docs: a `@Lock` query takes the database's
     write lock and must be the transaction's first statement; no
     statement timeout (the package cannot interrupt); a busy wait blocks
     the isolate (keep `busy-timeout` short in a UI); two transactions
     that read then write: the second fails with
     `CannotAcquireLockException`; ids reused after a delete (no
     `AUTOINCREMENT`); `lower()` folds ASCII only (to fix: a Dart
     `lower` registered through the glue);
   - references and keys (the owner): another aggregate is referenced
     as `AggregateReference<Author, int>` or as a plain id
     `@Reference(Author) int authorId` (the id type checked against the
     target's `@Id`); a field typed as an entity is a startup error with
     both forms as the hint (never guessed: Spring Data JDBC would read it
     as a child). Every reference gets a foreign key and an index in
     generated schemas; `@OnDelete(OnDeleteAction.cascade / setNull /
     setDefault / restrict / noAction)` (Hibernate's name) is its action.
     `@Unique` and `@UniqueConstraint([...])` (JPA's names: Dart cannot
     add a named `unique:` to `@Column('x')`). Defaults: a field's
     constant initializer (or the constructor parameter's constant
     default), described by the generator, is the column's `DEFAULT` and
     what `setDefault` sets. The in-memory store enforces all of it as
     SQLite does with `foreign_keys = ON` (checked case by case against
     sqlite3), and the shared suite runs it on both. `validate` checks
     them: an explicit annotation missing in the database is an error, a
     plain reference without a foreign key a warning;
   - left for Flutter: the app's directory for relative file names
     (`SqliteJdbcDriver.baseDirectory`, set by the Flutter starter), the
     web build (WASM), a background isolate for the synchronous calls;
     `@DataTest`.
4. PostgreSQL (the `postgres` package): a connection pool
   (`spring.datasource.pool.*`), `FOR UPDATE` / `FOR SHARE`, `NOWAIT`,
   `SKIP LOCKED`.
5. Redis, with this project's own client (RESP over `dart:io`: a few
   hundred lines, a pool, TLS, `AUTH`, the database index, Pub/Sub; no
   third-party package), switched on by `spring.data.redis.*` (Spring
   Boot's names: `url`, `host`, `port`, `password`, `database`, `ssl`):
   - sessions in Redis (`spring.session.store-type=redis`, Spring
     Session's): several instances without sticky routing, a restart
     logs nobody out — the main gap of in-memory sessions;
   - the cache starter's `RedisCacheManager` (`spring.cache.type=redis`);
   - `RedisTemplate` / `StringRedisTemplate`: strings, hashes, lists,
     sets, TTLs, `incr`;
   - repositories of `@RedisHash` entities (`findBy` only on `@Indexed`
     properties, equality only, as in Spring Data Redis), `@TimeToLive`;
   - Pub/Sub (`RedisMessageListenerContainer`): events between instances;
   - the security starter's shared state: the DPoP replay cache and the
     login counters for every instance (in memory they hold for one);
   - a distributed lock (`RedisLockRegistry`, Spring Integration's) and
     optimistic updates with `WATCH` / `MULTI`.
   Not in Flutter apps.
6. Supabase, after the 0.6.0 release (the owner): in its own starter, on
   its official packages
   ([spring_boot_starter_supabase.md](spring_boot_starter_supabase.md)):
   a store for these repositories, its Auth as a login of the security
   starters.

Later (the owner, October 2026): `BigDecimal` in `spring_core_dart` (an
unscaled `BigInt` and a scale, `RoundingMode`; no third-party package,
the repository's rule) for money: `NUMERIC` in PostgreSQL, `TEXT` in
SQLite, a string in JSON, `@DecimalMin` / `@Digits`; and custom
converters (Spring Data's `@ReadingConverter` / `@WritingConverter`) so
an application can map its own types. Until then: money as an `int` in
minor units, never a `double`.

Later, not in 0.6.0 (the owner): MongoDB (`@Document`, `MongoTemplate`,
`MongoRepository`, `@Version` and `findAndModify` instead of pessimistic
locks, `MongoTransactionManager` on a replica set; the driver to decide:
`mongo_dart` behind our template first, checked on a replica set, our
own if it falls short).

## The full example

### pubspec.yaml (a server on PostgreSQL)

```yaml
dependencies:
  spring_boot_starter_web: ^0.6.0
  spring_boot_starter_data: ^0.6.0
  postgres: ^3.0.0        # the driver: the generator wires it
dev_dependencies:
  spring_core_dart_generator: ^0.6.0
```

### application.properties

```properties
spring.datasource.url=postgresql://db:5432/shop
spring.datasource.username=shop
spring.datasource.password=${DB_PASSWORD}
spring.datasource.pool.max-size=10

# A second database (an extension of Spring Boot), its own driver.
spring.datasources.analytics.url=postgresql://warehouse:5432/stats

# Migrations: lib/resources/db/migration/V1__books.sql, V2__orders.sql
spring.sql.migration.enabled=true

books.page-size=20
```

### Entities

```dart
@Table('authors')
class Author {
  Author({this.id, required this.name});

  @Id()
  int? id; // null: inserted, the database gives it
  String name;
}

@Table('books')
class Book {
  Book({this.id, required this.title, required this.authorId,
      required this.price, this.year});

  @Id()
  int? id;

  @Column('title')
  String title;

  // Another aggregate: by id, never loaded with the book.
  AggregateReference<Author, int> authorId;

  int price; // in cents
  int? year;

  // Optimistic locking: `save` updates `where id = ? and version = ?`;
  // no row (someone saved in between): OptimisticLockingFailureException.
  @Version()
  int version = 0;

  @CreatedDate()
  DateTime? createdAt;

  @LastModifiedBy() // the logged-in user (AuditorAware from security)
  String? modifiedBy;

  @Transient()
  bool selected = false;
}

// An aggregate with its children: lines are saved and deleted with
// the order, never alone.
@Table('orders')
class Order {
  Order({this.id, required this.customer, this.lines = const []});

  @Id()
  int? id;
  String customer;

  @MappedCollection(idColumn: 'order_id', keyColumn: 'position')
  List<OrderLine> lines;

  @Version()
  int version = 0;
}

@Table('order_lines')
class OrderLine {
  OrderLine({required this.bookId, required this.quantity});
  AggregateReference<Book, int> bookId;
  int quantity;
}

@Table('stock')
class Stock {
  Stock({required this.bookId, required this.available});
  @Id()
  int bookId;
  int available;
}
```

### Repositories

```dart
@Repository()
abstract interface class BookRepository
    extends ListCrudRepository<Book, int>,
        PagingAndSortingRepository<Book, int> {
  // Derived queries: parsed at build time; `titel` would not compile.
  Future<List<Book>> findByTitleContainingIgnoreCaseAndYearGreaterThan(
      String title, int year);
  Future<Page<Book>> findByAuthorId(int authorId, Pageable page);
  Future<List<Book>> findTop5ByOrderByCreatedAtDesc();
  Future<int> countByYearBetween(int from, int to);
  Future<bool> existsByTitle(String title);

  // SQL with named parameters.
  @Query('select * from books where year = :year')
  Future<List<Book>> byYear(int year);

  // SpEL: the entity's table, a property of a parameter, a bean, a
  // property of the environment (the engine the project already has).
  @Query('select * from #{#entityName} where title = :#{#book.title}')
  Future<List<Book>> sameTitle(Book book);

  @Query('select * from books where year >= :#{@clock.now().year - 1}')
  Future<List<Book>> recent();

  @Query(r'select * from books order by title limit ${books.page-size:20}')
  Future<List<Book>> firstPage();

  // A change: @Modifying, inside a transaction.
  @Modifying()
  @Query('update books set price = price * :factor / 100 where year < :year')
  Future<int> discountOlderThan(int year, int factor);
}

@Repository()
abstract interface class StockRepository
    extends CrudRepository<Stock, int> {
  // Pessimistic locking: `select ... for update` (PostgreSQL); the row
  // stays locked until the transaction ends. SQLite has no row locks:
  // there the transaction is BEGIN IMMEDIATE (the whole database).
  @Lock(LockMode.pessimisticWrite)
  Future<Stock?> findByBookId(int bookId);

  // Wait no longer than 2 s for the lock (PostgreSQL: lock_timeout),
  // or skip locked rows (a work queue).
  @Lock(LockMode.pessimisticWrite, timeout: Duration(seconds: 2))
  Future<List<Stock>> findByAvailableLessThan(int threshold);

  @Lock(LockMode.pessimisticWrite, skipLocked: true)
  Future<List<Stock>> findTop10ByAvailableLessThan(int threshold);
}

@Repository()
abstract interface class OrderRepository extends CrudRepository<Order, int> {
  Future<List<Order>> findByCustomer(String customer, Sort sort);
}

// The second database.
@UseDataSource('analytics')
abstract interface class SaleStatsRepository
    extends CrudRepository<SaleStat, int> {}
```

### Services: transactions, both kinds of locks

```dart
@Service()
class Checkout {
  Checkout(this.orders, this.stock, this.books);

  final OrderRepository orders;
  final StockRepository stock;
  final BookRepository books;

  /// One transaction: the stock rows are locked (pessimistic) until the
  /// order is saved; any exception rolls everything back.
  @Transactional()
  Future<Order> place(String customer, Map<int, int> quantities) async {
    for (final MapEntry(key: bookId, value: count) in quantities.entries) {
      final row = await stock.findByBookId(bookId) // select ... for update
          ?? (throw ResponseStatusException(HttpStatus.notFound));
      if (row.available < count) {
        throw OutOfStockException(bookId);
      }
      row.available -= count;
      await stock.save(row);
    }
    return orders.save(Order(customer: customer, lines: [
      for (final MapEntry(key: bookId, value: count) in quantities.entries)
        OrderLine(bookId: AggregateReference(bookId), quantity: count),
    ]));
  }
}

@Service()
class Pricing {
  Pricing(this.books);
  final BookRepository books;

  /// Optimistic: two admins edit the same book; the second save fails
  /// with OptimisticLockingFailureException (a 409 by default), unless
  /// it is retried on fresh data (spring_boot_starter_retry).
  @Transactional()
  @Retryable(retryFor: [OptimisticLockingFailureException], maxAttempts: 3)
  Future<Book> changePrice(int id, int price) async {
    final book = (await books.findById(id))!;
    book.price = price;
    return books.save(book); // where id = ? and version = ?
  }

  @Transactional(readOnly: true)
  Future<Page<Book>> catalog(int page) =>
      books.findAllPaged(PageRequest.of(page, 20, Sort.by(['title'])));

  /// A step that must commit on its own (an audit line), whatever
  /// happens to the caller's transaction.
  @Transactional(propagation: Propagation.requiresNew)
  Future<void> audit(String line) async { /* ... */ }

  /// Without annotations: TransactionTemplate.
  Future<void> bulk(TransactionTemplate tx) => tx.execute((status) async {
        await books.discountOlderThan(1990, 80);
      });
}
```

### Flutter: a local database and Supabase, the same entity

```yaml
dependencies:
  spring_boot_starter_flutter: ^0.6.0
  spring_boot_starter_data: ^0.6.0
  sqlite3: ^2.4.0            # the offline cache; no postgres here
```

```properties
spring.datasource.url=sqlite:file:books.db
spring.supabase.url=https://xyz.supabase.co
spring.supabase.anon-key=${SUPABASE_ANON_KEY}
```

```dart
@Repository() // SQLite on the device
abstract interface class LocalBooks extends ListCrudRepository<Book, int> {
  Future<List<Book>> findByTitleContainingIgnoreCase(String text);
}

// Supabase over PostgREST, with the user's token; row-level security
// decides. @Version works (a conditional PATCH); @Lock and
// @Transactional here are build errors.
@UseStore('supabase')
abstract interface class RemoteBooks extends ListCrudRepository<Book, int> {
  Future<Page<Book>> findByAuthorId(int authorId, Pageable page);
}
```

### Tests

```dart
@DataTest() // the repositories on SQLite in memory, the migrations run,
            // each test in a transaction rolled back at its end
void main() {
  test('a concurrent price change fails, the first one stays', () async {
    final books = context.getBean<BookRepository>();
    final a = (await books.findById(1))!;
    final b = (await books.findById(1))!;
    await books.save(a..price = 1000);
    await expectLater(books.save(b..price = 2000),
        throwsA(isA<OptimisticLockingFailureException>()));
  });
}
```

### Joins

Derived queries stay inside an aggregate (as in Spring Data JDBC:
`findByAuthorName` on `Book` does not exist, the author is another
aggregate); children of an aggregate load with it. Across aggregates:

```dart
record BookWithAuthor(int id, String title, String authorName);

// A join into a DTO: columns by name (author_name -> authorName), the
// mapping generated, a column the record lacks is a build error.
@Query('select b.id, b.title, a.name as author_name '
    'from books b join authors a on a.id = b.author_id where a.name like :name')
Future<List<BookWithAuthor>> withAuthor(String name);

// Paged, with its count query.
@Query('select b.id, b.title, a.name as author_name '
    'from books b join authors a on a.id = b.author_id',
    countQuery: 'select count(*) from books')
Future<Page<BookWithAuthor>> page(Pageable page);

// One to many in one answer (Spring's ResultSetExtractor).
@Query('select a.id, a.name, b.title from authors a '
    'join books b on b.author_id = a.id',
    resultSetExtractor: AuthorWithBooks.extract)
Future<List<AuthorWithBooks>> authorsWithBooks();
```

Built at run time: `JdbcClient` (Spring 6.1's), `.sql(...).param(...)
.query(mapper).list()`. Many-to-many: the link table as children of the
owning aggregate (`Book` → `Set<BookAuthor>`, table `book_authors`). No
`@ManyToOne` / `@OneToMany` across aggregates and no lazy loading (the
owner's decision).

### Redis

```properties
spring.data.redis.url=redis://:${REDIS_PASSWORD}@redis:6379/0
spring.session.store-type=redis   # sessions shared by every instance
spring.cache.type=redis           # @Cacheable shared too
```

```dart
@RedisHash('carts', timeToLive: Duration(hours: 2))
class Cart {
  @Id() String? id;
  @Indexed() String customer;
  List<int> bookIds;
}

@Repository()
abstract interface class CartRepository extends CrudRepository<Cart, String> {
  Future<List<Cart>> findByCustomer(String customer); // @Indexed: equality
}

@Service()
class Counters {
  Counters(this.redis);
  final StringRedisTemplate redis;
  Future<int> visit(String page) => redis.opsForValue().increment('visits:$page');
}
```

### Locks

**Optimistic: `@Version`** (Spring Data's), on an `int` or `DateTime`
property of an aggregate root:
- `save` of a new entity (id `null`, or version `0`) inserts with
  version 1; of a loaded one updates `... set version = version + 1
  where id = ? and version = ?`; no row updated:
  `OptimisticLockingFailureException` (409 from the web starter).
- `delete(entity)` checks the version the same way; `deleteById` does
  not (it has no version), as in Spring Data JDBC.
- The children of an aggregate are covered by the root's version.
- Retried on fresh data with `@Retryable` (the retry starter), or
  answered as a conflict.
- Supabase: a `PATCH` filtered on `version=eq.N` returning the row; none
  returned: the same exception.
- Redis: `WATCH` / `MULTI` / `EXEC` in `RedisTemplate`; a `@RedisHash`
  with `@Version` checks it in a Lua script, atomically.

**Pessimistic: `@Lock`** on a repository query method (Spring Data's):
- `LockMode.pessimisticWrite` → `select ... for update`;
  `LockMode.pessimisticRead` → `for share`; `timeout:` (PostgreSQL's
  `lock_timeout`; 0 = `nowait`), `skipLocked: true` (a work queue).
- Only inside a transaction: a `@Lock` method called outside one fails
  at once (`IllegalTransactionStateException`), never runs unlocked.
- A lock that cannot be had: `CannotAcquireLockException`; a deadlock:
  `DeadlockLoserDataAccessException` (both transient: worth a retry).
- SQLite has no row locks: the transaction becomes `BEGIN IMMEDIATE`
  (one writer for the whole database), stated in the docs.
- In memory (done in step 2): row locks, shared and exclusive, with the
  timeout (`spring.data.memory.lock-timeout`), `skipLocked` and deadlock
  detection, so the same code runs before a database is there.
- Supabase: none (a build error on its repositories).
- In SQL by hand: `jdbc.sql('select ... for update')` inside
  `@Transactional`.

**Between instances: a distributed lock** over Redis
(`RedisLockRegistry`, Spring Integration's): `lock.tryLock(timeout)`,
with an expiry so a dead instance does not keep it.

### Transactions: the test matrix (the owner's request)

Every combination of `propagation` × `isolation` gets tests, on every
store that has transactions (SQLite, PostgreSQL in Docker in CI), with
races between real connections:

- **Propagation** (Spring's seven): `required`, `requiresNew`,
  `supports`, `notSupported`, `mandatory`, `never`, `nested`
  (savepoints). For each: called with and without a transaction around
  it, the inner one throwing or not, the outer one rolling back or not:
  what is committed, what is rolled back, which connection is used,
  `UnexpectedRollbackException` when an inner `required` marked the
  transaction rollback-only and the outer one tries to commit,
  `IllegalTransactionStateException` for `mandatory` without one and
  `never` within one, a `nested` rollback to its savepoint only.
- **Isolation** (`defaultLevel`, `readUncommitted`, `readCommitted`,
  `repeatableRead`, `serializable`) × the anomalies, each provoked by two
  transactions on two connections, ordered by completers (barriers), not
  by sleeps, so the race happens every run:
  dirty read, non-repeatable read, phantom read, lost update, write
  skew. The expected result per database is a table in the docs
  (PostgreSQL: `readUncommitted` behaves as `readCommitted`,
  `repeatableRead` has no phantoms, `serializable` fails one of two
  conflicting transactions with `CannotSerializeTransactionException`,
  transient); a level a database does not offer (SQLite: only
  serializable writes) fails at the transaction's start, never silently
  downgraded.
- **The rest of `@Transactional`:** `readOnly` (PostgreSQL: a write
  fails), `timeout` (a statement past it is cancelled,
  `QueryTimeoutException`), `rollbackFor` / `noRollbackFor`, checked and
  unchecked exceptions as in Spring (here: every exception rolls back
  unless listed), the qualifier of a second datasource
  (`@Transactional(transactionManager: 'analytics')`), `TransactionTemplate` with the same
  settings.
- **Dart's own cases:** the transaction follows `await` (the `Zone`);
  `Future.wait` of two statements in one transaction (one connection:
  run in turn, never interleaved on the wire); `unawaited` work started
  inside a transaction and running after its end (fails, does not use a
  returned connection); a transaction across `Isolate.run` (refused);
  the pool exhausted by nested `requiresNew` (bounded wait, then
  `CannotGetJdbcConnectionException`, never a deadlock of the pool).
- **Locks in the same matrix:** `@Lock` under each isolation;
  `@Version` lost-update test under `readCommitted` (the version catches
  what the level lets through).
- **Compared with Spring:** the same scenarios against a Spring Boot +
  Spring Data JDBC reference on the same PostgreSQL (the way
  `tool/security_reference` compares security): what commits, what
  fails and with which exception must match, or the difference is
  documented on purpose.

### The imperative layer: JdbcTemplate, JdbcClient, RedisTemplate

The repositories are generated over it; applications use it where a
repository is not enough. Everything returns a `Future` (one thread: no
blocking API). Inside `@Transactional` / `TransactionTemplate` the
templates use the transaction's connection, the same as the
repositories (the transaction lives in a `Zone`).

```dart
// JdbcTemplate: positional parameters.
final books = await jdbc.query('select id, title from books where year > ?',
    [2000], (row) => Book(id: row.int_('id'), title: row.string('title')));
final count = await jdbc.queryForObject<int>('select count(*) from books');
await jdbc.update('update stock set available = ? where book_id = ?', [5, 42]);
await jdbc.batchUpdate('insert into tags(book_id, tag) values (?, ?)',
    [[1, 'sf'], [1, 'classic']]);

// NamedParameterJdbcTemplate: names, lists expanded in IN.
await named.query('select * from books where id in (:ids)',
    {'ids': [1, 2, 3]}, bookMapper);

// JdbcClient (Spring 6.1).
final book = await jdbc.sql('select * from books where id = :id')
    .param('id', 42).query(bookMapper).optional();

// Large results as a stream, not all in memory.
await for (final row in jdbc.queryForStream('select * from events', [])) {}
```

- Row mapping: a function (`RowMapper`), `DataClassRowMapper<T>`
  generated at build time (columns by name, `author_name` →
  `authorName`), `ResultSetExtractor` (one to many).
- Values only as parameters: the API never puts a value into the SQL
  text.

```dart
// RedisTemplate / StringRedisTemplate, serializers (strings, JSON through
// the ObjectMapper, bytes).
await redis.opsForValue().set('session:42', 'data', ttl: Duration(minutes: 30));
await redis.opsForValue().increment('visits:/books');
await redis.opsForHash().putAll('book:1', {'title': 'Dune', 'year': '1965'});
await redis.opsForList().rightPush('queue:emails', jsonEncode(mail));
await redis.opsForZSet().add('top-books', '1', score: 42);

// WATCH / MULTI / EXEC (optimistic), pipelines, Lua scripts, Pub/Sub.
await redis.execute((ops) async { await ops.watch(['stock:42']); /* ... */ });
await redis.executePipelined((ops) { for (final id in ids) ops.opsForValue().get('book:$id'); });
await redis.execute(RedisScript<int>(decrementIfPositive), ['stock:42']);
await redis.convertAndSend('events', 'book-added:42');
// SCAN, never KEYS: keys as a Stream.
```

Redis transactions (`MULTI` / `EXEC`) are not joined with SQL ones by
`@Transactional`, as in Spring; the docs say so. Order of work: the JDBC
templates with SQLite (step 3), `RedisTemplate` first in step 5.

### Errors: exception translation

As in Spring, a `@Repository` bean (and every template) translates the
driver's errors (`PersistenceExceptionTranslationPostProcessor`,
`SQLErrorCodeSQLExceptionTranslator`) into one hierarchy, the same for
SQLite, PostgreSQL, Redis and Supabase:

`DataAccessException` → `DuplicateKeyException`,
`DataIntegrityViolationException`, `EmptyResultDataAccessException`,
`IncorrectResultSizeDataAccessException`,
`OptimisticLockingFailureException`, `PessimisticLockingFailureException`
/ `CannotAcquireLockException`, `DeadlockLoserDataAccessException`,
`QueryTimeoutException`, `DataAccessResourceFailureException`
(connection lost), `BadSqlGrammarException`,
`TransientDataAccessException` (worth a retry) /
`NonTransientDataAccessException`.

Each carries what is needed to understand it: the SQL (with `?` /
`:name`, never the values), the SQL state and the vendor code, the
constraint or column when the driver gives it, the cause. The web
starter answers them: `OptimisticLockingFailureException` → 409,
`DuplicateKeyException` → 409, `EmptyResultDataAccessException` → 404,
the others → 500 without details (the log has them).

### Logs: what goes to the database

Spring's way, our logger (`SpringLog`), logger names after Spring's
classes so the same switches work:

```properties
# The SQL of each statement (Spring: org.springframework.jdbc.core.JdbcTemplate).
logging.level.spring.jdbc.core.JdbcTemplate=debug
# The bound values too (Spring: ...StatementCreatorUtils=trace).
logging.level.spring.jdbc.core.StatementCreatorUtils=trace
# Transactions: begin, commit, rollback, the connection (Spring's).
logging.level.spring.jdbc.datasource.DataSourceTransactionManager=debug
# Redis commands (Spring Data Redis).
logging.level.spring.data.redis=debug
# A repository's derived query, as generated.
logging.level.spring.data.repository=debug

# Short switches (Spring Boot has spring.jpa.show-sql; these are its
# counterparts here, not in Spring Boot for JDBC):
spring.data.jdbc.show-sql=true            # = JdbcTemplate at debug
spring.data.jdbc.format-sql=true          # SQL on several lines
spring.data.jdbc.show-parameters=true     # = the values, at trace
spring.data.jdbc.slow-query-threshold=500ms   # warn on slower statements
```

A logged statement: the SQL, the time it took, the rows, the
datasource's name, the transaction's id and the request's id (the MDC
the web starter already fills), so a slow page leads to its queries:

```
DEBUG spring.jdbc.core.JdbcTemplate : [shop tx#12] select * from stock where book_id = ? for update  (1 row, 3 ms) {request=7f3a}
TRACE ...StatementCreatorUtils      : [shop tx#12]   ?1 = 42 (int)
WARN  spring.jdbc.core.JdbcTemplate : [shop] slow statement, 812 ms: select ... from books b join authors a ...  {request=7f3a}
```

Values are logged only at trace; parameters whose name looks secret
(`password`, `token`, `secret`, `key`) are masked even there, Redis
`AUTH` never shows its password, and the connection URL is logged without
its password.

## The schema: migrations, validation, creation (step 3)

Spring Data JDBC creates no schema (unlike Hibernate's `ddl-auto`): the
schema is the application's SQL. Here the same, plus what the mapping
model makes cheap.

**Migrations, Flyway's way** (`spring.sql.migration.*`, next to
`spring.sql.init.*`; Flyway's file naming, our own runner, no Flyway):

- Files in `lib/resources/db/migration/`: `V1__create_books.sql`,
  `V2__add_year.sql` (versioned, run once, in order), `R__views.sql`
  (repeatable, run again when its checksum changes). Per database when
  needed: `spring.sql.migration.locations=classpath:db/migration/{vendor}`
  (`sqlite`, `postgresql`). Several data sources: `spring.datasources.
  <name>.sql.migration.*`.
- The generator already embeds `lib/resources/` in the generated module,
  so the migrations are in the binary on every platform (server, Flutter,
  web) with no assets to declare.
- At startup, before any repository is used: the history table
  (`schema_history`: version, description, script, CRC32
  checksum, installed on, execution time, success) is read, the pending
  migrations run in order, each in its own transaction (PostgreSQL and
  SQLite both roll DDL back), the failed one stops the start with its
  file and line.
- A changed checksum of an applied migration stops the start
  (`validate-on-migrate`, on by default); a migration newer than the
  application (a database from a later version) is ignored, as Flyway
  does by default; `out-of-order` off; `baseline-on-migrate` and
  `baseline-version` for an existing database; `clean` is never run
  (no switch to allow it).
- Several server instances starting together: the first takes a
  PostgreSQL advisory lock (`pg_advisory_lock`), the others wait, then
  find nothing to do. SQLite: one process, a `BEGIN IMMEDIATE`.
- `spring.sql.init` (`schema.sql`, `data.sql`, `mode=embedded|always|
  never`) for simple cases and tests, as in Boot; not both with
  migrations on one database: the start fails (stricter than Boot, which
  only advises against it — the schema has one owner).

**Validation against the entities** (an extension;
`spring.data.jdbc.schema=validate`, the default): after the migrations,
every entity's table and columns must exist with a type that fits the
property (`int` → integer types, `String` → text types, `DateTime` →
timestamp / text in SQLite, `bool`, `double`, `Uint8List`), and a
non-null property must not sit on a nullable column without a default
being noted. A missing table or column stops the start naming the entity,
property and column; extra columns and tables are fine. Hibernate's
`validate`, which Spring Data JDBC lacks.

**Creation from the entities** (`spring.data.jdbc.schema=create` or
`create-drop`): `CREATE TABLE` for each entity and child table from the
mapping (id as identity / `INTEGER PRIMARY KEY`, `@Version`, the reverse
and key columns of `@MappedCollection`, foreign keys to the root), for
tests, prototypes and on-device caches. `update` is not offered (the
classic Hibernate accident: it never drops or renames, the schema
drifts).

**A migration written from the entities** (a tool, like Spring Data
JDBC's `LiquibaseChangeSetWriter`): `dart run
spring_boot_starter_data:schema diff` applies the existing migrations to
a scratch database (SQLite in memory, or PostgreSQL in a container),
compares with the entities, and writes the next `V<n>__<name>.sql` to
review and commit; never applied by itself.

**Flutter**:

- The migrations run on the device at the app's start, on its SQLite
  file (`spring.datasource.url=sqlite:file:books.db`, relative to the
  app's support directory); on the web on `sqlite3`'s WASM build (the
  file in OPFS / IndexedDB).
- A failed migration on a phone cannot be fixed by hand: each runs in a
  transaction (the database stays at the previous version, the error
  goes to the app as a startup failure it can show), and a test helper
  applies every migration in turn to SQLite in memory (and, from saved
  schemas of released versions, each upgrade path), so CI catches it.
- No downgrades (stores refuse older versions); a database from a newer
  version (a restored backup) is left as is, its unknown migrations
  ignored.
- An on-device database that is only a cache may use
  `schema=create-drop` (rebuilt when the entities change) instead of
  migrations.
- Supabase repositories run no DDL: the schema is the server's (Supabase
  CLI migrations); a Flutter app never holds the credentials for it.

## Renaming properties named after Java libraries (the owner, at the end of 0.6.0)

Properties named after a library or a Java technology this project does
not use are renamed; names of Spring's own concepts stay. The old Spring
Boot name stops the start with the new one (a forgotten
`server.servlet.session.*` silently ignored would leave sessions on their
defaults):

| Now | New |
|---|---|
| `spring.cloud.openfeign.*` | `spring.feign.*` |
| `spring.jackson.*` | `spring.json.*` |
| `spring.servlet.multipart.*` | `spring.web.multipart.*` |
| `server.servlet.context-path`, `server.servlet.session.*` | `server.context-path`, `server.session.*` |
| `logging.logback.rollingpolicy.*` | `logging.file.rolling-policy.*` |
| (`spring.flyway.*`, planned) | `spring.sql.migration.*` |

Code, tests, READMEs, docs, guides, and a Breaking entry in each
package's CHANGELOG.

## Differences from Spring to state in the docs

- Spring Data JDBC's model; JPA (`EntityManager`, lazy associations,
  `@OneToMany` with a persistence context) is not offered.
- Several databases from properties (`spring.datasources.*`), the store
  and database of a repository on `@Repository`.
- Repository methods return `Future`s; there is no blocking API.
- SQLite has no row locks: `@Lock` takes the whole database
  (`BEGIN IMMEDIATE`), stated in the docs.
- A Supabase repository: no transactions, no pessimistic locks (build
  errors), `@Version` as a conditional `PATCH`.
