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
  PostgreSQL, key-value over Redis, Supabase over PostgREST (HTTP: Flutter apps never hold
  database credentials; the user's token and row-level security decide),
  and in memory for tests. A repository chooses its store and database:
  `@Repository(dataSource: 'analytics')`, `@Repository(store: 'supabase')`.

## Order of work

1. `spring_data_commons` part of the starter: `Repository`,
   `CrudRepository`, `ListCrudRepository`, `PagingAndSortingRepository`,
   `Page`, `Slice`, `Pageable`, `Sort`; the generator's entity mapping and
   repository implementations, derived queries parsed at build time (a
   wrong property name is a build error); `@Query` with named parameters
   and SpEL; auditing; `@Version`; the in-memory store; `@DataTest`.
2. Transactions: `PlatformTransactionManager`, `@Transactional` on the AOP
   proxies (propagation, isolation, read-only, rollback rules),
   `TransactionTemplate`; the current transaction in a `Zone`, so it
   follows `await`.
3. SQLite (the `sqlite3` package): server and Flutter; `spring.sql.init`
   (`schema.sql`, `data.sql`); migrations `db/migration/V1__*.sql`
   (Flyway's naming, `spring.flyway.*`).
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
6. Supabase over PostgREST: derived queries as filters
   (`findByTitleContaining` → `title=ilike.*dune*`), `@Version` as a
   conditional `PATCH`, the user's token from the Flutter security
   starter. No transactions and no pessimistic locks there: a
   `@Transactional` or `@Lock` method of a Supabase repository is a build
   error, not a silent no-op.

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
spring.flyway.enabled=true

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
@Repository(dataSource: 'analytics')
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
      books.findAll(PageRequest.of(page, 20, Sort.by(['title'])));

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
@Repository(store: 'supabase')
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
