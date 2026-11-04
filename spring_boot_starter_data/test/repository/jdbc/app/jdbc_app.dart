// The application of the SQL store tests: aggregates and repositories as an
// application writes them; the generator writes the implementations
// (jdbc_app.spring.dart, from `dart run build_runner build`).
//
// Every aggregate has a memory repository and a SQL one over one base
// interface, so the semantic suite runs the same calls on both stores.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

import '../../../spring_gen/repository/jdbc/app/jdbc_app.spring.dart';

// --- Aggregates ------------------------------------------------------------

/// What a book is about.
enum Genre { scifi, fantasy, crime }

/// An author; the books refer to it by id.
@Table('authors')
class Author {
  Author({required this.name, this.id});

  @Id()
  int? id;

  String name;
}

/// A book: ids generated, a version, references, an enum, a date, nulls.
@Table('books')
class Book {
  Book({
    required this.title,
    required this.year,
    this.id,
    this.subtitle,
    this.inStock = true,
    this.author,
    this.rating,
    this.released,
    this.genre,
    this.version,
  });

  @Id()
  int? id;

  String title;
  int year;
  String? subtitle;
  bool inStock;
  AggregateReference<Author, int>? author;
  double? rating;
  DateTime? released;
  Genre? genre;

  @Version()
  int? version;

  @override
  String toString() => 'Book($id, $title, $year)';
}

/// An order with children in a list, a map and a set.
@Table('orders')
class PurchaseOrder {
  PurchaseOrder({
    required this.customer,
    this.id,
    this.lines = const [],
    this.notes = const {},
    this.tags = const {},
  });

  @Id()
  int? id;

  String customer;

  @MappedCollection()
  List<OrderLine> lines;

  @MappedCollection()
  Map<String, OrderNote> notes;

  @MappedCollection()
  Set<OrderTag> tags;
}

/// A child in a list.
@Table('order_lines')
class OrderLine {
  OrderLine({required this.sku, required this.quantity});

  String sku;
  int quantity;
}

/// A child in a map.
@Table('order_notes')
class OrderNote {
  OrderNote({required this.text});

  String text;
}

/// A child in a set.
@Table('order_tags')
class OrderTag {
  OrderTag({required this.label});

  String label;
}

/// A root whose children have ids of their own.
@Table('shelves')
class Shelf {
  Shelf({required this.name, this.id, this.slots = const []});

  @Id()
  int? id;

  String name;

  @MappedCollection(idColumn: 'shelf_id', keyColumn: 'position')
  List<Slot> slots;
}

/// A child with an id the database generates.
@Table('slots')
class Slot {
  Slot({required this.label, this.id});

  @Id()
  int? id;

  String label;
}

/// A root with children that have children of their own: more than the JDBC
/// store supports (one level), so it refuses them.
@Table('crates')
class Crate {
  Crate({required this.name, this.id, this.jars = const []});

  @Id()
  int? id;

  String name;

  @MappedCollection()
  List<Jar> jars;
}

/// A child with a collection of its own.
@Table('jars')
class Jar {
  Jar({required this.label, this.lids = const []});

  String label;

  @MappedCollection()
  List<Lid> lids;
}

/// A grandchild.
@Table('lids')
class Lid {
  Lid({required this.color});

  String color;
}

/// Immutable, with an id the application gives and an `int` version.
@Table('accounts')
class Account {
  const Account({required this.iban, required this.owner, this.version = 0});

  @Id()
  final String iban;

  final String owner;

  @Version()
  final int version;
}

/// A version that is a time stamp.
@Table('tickets')
class Ticket {
  Ticket({required this.subject, this.id, this.stamp});

  @Id()
  int? id;

  String subject;

  @Version()
  DateTime? stamp;
}

/// What is on the shelf; sold under a pessimistic lock.
@Table('stock')
class Stock {
  Stock({required this.sku, required this.quantity, this.id});

  @Id()
  int? id;

  String sku;
  int quantity;
}

/// Without a version: an update of a missing row is not detected by a
/// version but by the row count.
@Table('notes')
class Note {
  Note({required this.text, this.id});

  @Id()
  int? id;

  String text;
}

/// Columns that hold secrets: the logs write their values masked.
@Table('members')
class Member {
  Member({
    required this.username,
    required this.passwordHash,
    this.apiToken,
    this.id,
  });

  @Id()
  int? id;

  String username;

  String passwordHash;

  String? apiToken;
}

/// A version that is a nullable `int`: new only when null, so a row stored
/// at version 0 can be updated.
@Table('gauges')
class Gauge {
  Gauge({required this.name, this.id, this.version});

  @Id()
  int? id;

  String name;

  @Version()
  int? version;
}

// --- References, foreign keys and unique keys ------------------------------

/// What the other aggregates reference; its name is unique.
@Table('clubs')
class Club {
  Club({required this.name, this.id});

  @Id()
  int? id;

  @Unique()
  String name;
}

/// References a club by a plain id; deleting the club is refused while a
/// fan references it (`noAction`, the default).
@Table('fans')
class Fan {
  Fan({required this.name, required this.clubId, this.id});

  @Id()
  int? id;

  String name;

  @Reference(Club)
  int clubId;
}

/// Like a fan, but `restrict`.
@Table('sponsors')
class Sponsor {
  Sponsor({required this.name, required this.clubId, this.id});

  @Id()
  int? id;

  String name;

  @Reference(Club)
  @OnDelete(OnDeleteAction.restrict)
  int clubId;
}

/// References a club by an `AggregateReference`; deleted with the club,
/// with its medals and its goals.
@Table('players')
class Player {
  Player({
    required this.name,
    required this.club,
    this.id,
    this.medals = const [],
  });

  @Id()
  int? id;

  String name;

  @OnDelete(OnDeleteAction.cascade)
  AggregateReference<Club, int> club;

  @MappedCollection()
  List<Medal> medals;
}

/// A child of a player.
@Table('medals')
class Medal {
  Medal({required this.title});

  String title;
}

/// Deleted with its player, so with the club: a cascade of two steps.
@Table('goals')
class Goal {
  Goal({required this.playerId, required this.minute, this.id});

  @Id()
  int? id;

  @Reference(Player)
  @OnDelete(OnDeleteAction.cascade)
  int playerId;

  int minute;
}

/// Its club is set to null when the club is deleted.
@Table('coaches')
class Coach {
  Coach({required this.name, this.clubId, this.id});

  @Id()
  int? id;

  String name;

  @Reference(Club)
  @OnDelete(OnDeleteAction.setNull)
  int? clubId;
}

/// A root whose children reference a club: the places of a squad.
@Table('squads')
class Squad {
  Squad({required this.name, this.id, this.places = const []});

  @Id()
  int? id;

  String name;

  @MappedCollection()
  List<Place> places;
}

/// A child that references a club, deleted with it (the squad stays).
@Table('places')
class Place {
  Place({required this.label, required this.clubId});

  String label;

  @Reference(Club)
  @OnDelete(OnDeleteAction.cascade)
  int clubId;
}

/// A self-reference, `noAction`.
@Table('employees')
class Employee {
  Employee({required this.name, this.bossId, this.id});

  @Id()
  int? id;

  String name;

  @Reference(Employee)
  int? bossId;
}

/// A self-reference, `restrict`.
@Table('categories')
class Category {
  Category({required this.name, this.parentId, this.id});

  @Id()
  int? id;

  String name;

  @Reference(Category)
  @OnDelete(OnDeleteAction.restrict)
  int? parentId;
}

/// A self-reference, `cascade`.
@Table('folders')
class Folder {
  Folder({required this.name, this.parentId, this.id});

  @Id()
  int? id;

  String name;

  @Reference(Folder)
  @OnDelete(OnDeleteAction.cascade)
  int? parentId;
}

/// Unique values: the name of a citizen is unique, and so is the passport
/// (which may be null: several citizens may have none).
@Table('citizens')
@UniqueConstraint(['firstName', 'lastName'], name: 'uq_citizens_name')
class Citizen {
  Citizen({
    required this.firstName,
    this.lastName,
    this.passport,
    this.id,
  });

  @Id()
  int? id;

  String firstName;

  String? lastName;

  @Unique()
  String? passport;
}

// --- Results of @Query methods ----------------------------------------------

/// A join, mapped by column name (`author_name` into `authorName`): a
/// class a `@Query` returns, which the generator describes.
class BookWithAuthor {
  const BookWithAuthor({
    required this.id,
    required this.title,
    required this.authorName,
  });

  final int id;
  final String title;
  final String authorName;

  @override
  String toString() => 'BookWithAuthor($id, $title, $authorName)';
}

/// One to many in one answer.
@Introspected()
class AuthorWithBooks {
  const AuthorWithBooks(this.name, this.titles);

  final String name;
  final List<String> titles;

  /// A `ResultSetExtractor`: the rows of a join, grouped by author.
  static List<AuthorWithBooks> extract(JdbcResult result) {
    final byAuthor = <String, List<String>>{};
    for (final row in result.rows) {
      final titles = byAuthor.putIfAbsent(row.string('name'), () => []);
      if (row.stringOrNull('title') case final title?) {
        titles.add(title);
      }
    }
    return [
      for (final MapEntry(:key, :value) in byAuthor.entries)
        AuthorWithBooks(key, value),
    ];
  }
}

/// A `RowMapper`: the title in capitals.
String shoutTitle(JdbcRow row) => row.string('title').toUpperCase();

/// A bean SpEL reaches with `@years`.
@Component()
@Introspected()
class Years {
  /// The year the queries start from.
  int get cutoff => 1990;

  /// The year before [year].
  int before(int year) => year - 1;
}

// --- Repositories ----------------------------------------------------------

/// The derived queries both stores run.
abstract interface class BookQueries
    implements
        ListCrudRepository<Book, int>,
        ListPagingAndSortingRepository<Book, int> {
  Future<List<Book>> findByTitle(String title);
  Future<List<Book>> findByTitleIgnoreCase(String title);
  Future<Book?> findOneByTitle(String title);
  Future<Book> getByTitle(String title);
  Future<List<Book>> findByTitleAndYear(String title, int year);
  Future<List<Book>> findByTitleOrYear(String title, int year);
  Future<List<Book>> findByYearNot(int year);
  Future<List<Book>> findByTitleNot(String title);
  Future<List<Book>> findByTitleNotIgnoreCase(String title);
  Future<List<Book>> findByYearBetween(int from, int to);
  Future<List<Book>> findByYearGreaterThan(int year);
  Future<List<Book>> findByYearGreaterThanEqual(int year);
  Future<List<Book>> findByYearLessThan(int year);
  Future<List<Book>> findByYearLessThanEqual(int year);
  Future<List<Book>> findByYearIn(List<int> years);
  Future<List<Book>> findByYearNotIn(Set<int> years);
  Future<List<Book>> findByTitleIn(List<String> titles);
  Future<List<Book>> findByTitleInIgnoreCase(List<String> titles);
  Future<List<Book>> findBySubtitleIn(List<String?> subtitles);
  Future<List<Book>> findBySubtitleNotIn(List<String?> subtitles);
  Future<List<Book>> findByTitleStartingWith(String prefix);
  Future<List<Book>> findByTitleEndingWith(String suffix);
  Future<List<Book>> findByTitleContaining(String part);
  Future<List<Book>> findByTitleNotContaining(String part);
  Future<List<Book>> findByTitleLike(String pattern);
  Future<List<Book>> findByTitleNotLike(String pattern);
  Future<List<Book>> findByTitleLikeIgnoreCase(String pattern);
  Future<List<Book>> findByTitleContainingIgnoreCase(String part);
  Future<List<Book>> findByTitleStartingWithIgnoreCase(String prefix);
  Future<List<Book>> findByTitleEndingWithIgnoreCase(String suffix);
  Future<List<Book>> findBySubtitleIsNull();
  Future<List<Book>> findBySubtitleIsNotNull();
  Future<List<Book>> findBySubtitle(String? subtitle);
  Future<List<Book>> findBySubtitleNot(String? subtitle);
  Future<List<Book>> findBySubtitleLessThan(String? subtitle);
  Future<List<Book>> findBySubtitleBetween(String? from, String? to);
  Future<List<Book>> findBySubtitleLike(String? pattern);
  Future<List<Book>> findByInStockTrue();
  Future<List<Book>> findByInStockFalse();
  Future<List<Book>> findByInStock(bool inStock, Sort sort);
  Future<List<Book>> findByAuthor(AggregateReference<Author, int> author);
  Future<List<Book>> findByAuthorIn(
    List<AggregateReference<Author, int>> authors,
  );
  Future<List<Book>> findByAuthorIsNull();
  Future<List<Book>> findByGenre(Genre genre);
  Future<List<Book>> findByGenreIn(List<Genre> genres);
  Future<List<Book>> findByRatingBetween(double low, double high);
  Future<List<Book>> findByRatingGreaterThan(double rating);
  Future<List<Book>> findByReleasedAfter(DateTime moment);
  Future<List<Book>> findByReleased(DateTime? moment);
  Future<List<Book>> findByInStockOrderByYearDescTitleAsc(bool inStock);
  Future<List<Book>> findByInStockOrderBySubtitleAscIdAsc(bool inStock);
  Future<List<Book>> findByInStockOrderBySubtitleDescIdAsc(bool inStock);
  Future<Set<Book>> findByYear(int year);
  Future<Iterable<Book>> findByYearLessThanOrderByYear(int year);
  Future<List<Book>> findDistinctByInStock(bool inStock);
  Stream<Book> streamByInStock(bool inStock);

  Future<Page<Book>> findByYearAfter(int year, Pageable pageable);
  Future<Slice<Book>> findByInStockIsTrue(Pageable pageable);
  Future<List<Book>> findByInStockEquals(bool inStock, Pageable pageable);

  Future<Book?> findFirstByOrderByYearAsc();
  Future<List<Book>> findTop2ByOrderByYearDesc();
  Future<Page<Book>> findTop3ByInStock(bool inStock, Pageable pageable);

  Future<int> countByInStock(bool inStock);
  Future<int> countByTitleContaining(String part);
  Future<bool> existsByTitle(String title);
  Future<int> deleteByYearLessThan(int year);
  Future<void> removeByTitle(String title);
  Future<List<Book>> deleteByInStock(bool inStock);
  Future<int> deleteByTitleIn(List<String> titles);
}

@UseStore('memory')
abstract interface class MemoryBooks implements BookQueries {}

/// The SQL repository: the derived queries, and `@Query` methods.
@UseStore('jdbc')
abstract interface class SqlBooks implements BookQueries {
  // Named parameters, repeated, a list.
  @Query('select * from books where year = :year order by id')
  Future<List<Book>> byYear(int year);

  @Query('select * from books where year = :year or year = :year + 1')
  Future<List<Book>> aroundYear(int year);

  @Query('select * from books where id in (:ids) order by id')
  Future<List<Book>> byIds(List<int> ids);

  @Query('select * from books where title = :title order by id')
  Future<List<Book>> byTitle(String title);

  @Query('select * from books where title like :pattern order by id')
  Future<List<Book>> byTitleLike(String pattern);

  @Query('select * from books where genre = :genre order by id')
  Future<List<Book>> byGenre(Genre genre);

  @Query('select * from books where author = :author order by id')
  Future<List<Book>> byAuthor(AggregateReference<Author, int> author);

  @Query('select * from books where in_stock = :inStock order by id')
  Future<List<Book>> byStock(bool inStock);

  // SpEL: a property of a parameter, the arguments, a bean, the
  // environment, a calculation.
  @Query('select * from books where title = :#{#book.title} order by id')
  Future<List<Book>> sameTitle(Book book);

  @Query('select * from books where year = :#{[0]} order by id')
  Future<List<Book>> byFirstArgument(int year);

  @Query('select * from books where year >= :#{@years.cutoff} order by id')
  Future<List<Book>> sinceCutoff();

  @Query(
    'select * from books where year = :#{@years.before(#year)} order by id',
  )
  Future<List<Book>> yearBefore(int year);

  @Query(
    'select * from books where '
    'year > :#{@environment.getProperty("books.cutoff", "0")} order by id',
  )
  Future<List<Book>> afterConfiguredCutoff();

  @Query('select * from books where year > :#{#p0 + #a1} order by id')
  Future<List<Book>> afterSum(int year, int more);

  @Query('select * from books where title = :#{#year} order by id')
  Future<List<Book>> broken(int year);

  // The table, a property placeholder.
  @Query('select * from #{#entityName} where title = :title')
  Future<List<Book>> viaEntityName(String title);

  @Query(r'select * from books order by id limit ${books.page-size:3}')
  Future<List<Book>> firstPage();

  // Entity placeholders: the tables and columns as the mapping names them
  // (`inStock` is stored in `in_stock`).
  @Query(
    'select b.* from {Book} b '
    'join {Author} a on a.{Author.id} = b.{Book.author} '
    'where a.{Author.name} like :name and b.{Book.inStock} = :inStock '
    'order by b.{Book.id}',
  )
  Future<List<Book>> byAuthorName(String name, bool inStock);

  // Results: DTO, scalar, single, nullable.
  @Query(
    'select b.id, b.title, a.name as author_name from books b '
    'join authors a on a.id = b.author where a.name like :name order by b.id',
  )
  Future<List<BookWithAuthor>> withAuthor(String name);

  @Query('select b.id, b.title from books b order by b.id')
  Future<List<BookWithAuthor>> missingColumn();

  @Query('select count(*) from books where year > :year')
  Future<int> countAfter(int year);

  @Query('select title from books where id = :id')
  Future<String?> titleOf(int id);

  @Query('select title from books where id = :id')
  Future<String> requiredTitleOf(int id);

  @Query('select title from books where year > :year order by title')
  Future<List<String>> titlesAfter(int year);

  @Query('select year from books where year > :year order by year')
  Future<Set<int>> yearsAfter(int year);

  @Query('select in_stock from books where id = :id')
  Future<bool?> inStockOf(int id);

  @Query('select rating from books where id = :id')
  Future<double?> ratingOf(int id);

  @Query('select released from books where id = :id')
  Future<DateTime?> releasedOf(int id);

  @Query('select genre from books where id = :id')
  Future<Genre?> genreOf(int id);

  @Query('select * from books where id = :id')
  Future<Book?> one(int id);

  @Query('select * from books where id = :id')
  Future<Book> requiredOne(int id);

  @Query('select * from books order by id')
  Future<Book?> theOnlyOne();

  @Query('select id, title, year from books where id = :id')
  Future<Map<String, Object?>?> asMap(int id);

  // Sorting and paging by parameter.
  @Query('select * from books where year > :year')
  Future<List<Book>> afterSorted(int year, Sort sort);

  @Query('select * from books where year > :year order by in_stock desc')
  Future<List<Book>> afterSortedAndOrdered(int year, Sort sort);

  @Query('select * from books where year > :year')
  Future<List<Book>> afterWindow(int year, Pageable pageable);

  @Query('select * from books where year > :year')
  Future<Page<Book>> pageAfter(int year, Pageable pageable);

  @Query(
    'select b.id, b.title, a.name as author_name from books b '
    'join authors a on a.id = b.author',
    countQuery:
        'select count(*) from books b join authors a on a.id = b.author',
  )
  Future<Page<BookWithAuthor>> pageWithAuthor(Pageable pageable);

  @Query('select * from books where year > :year')
  Future<Slice<Book>> sliceAfter(int year, Pageable pageable);

  @Query('select * from books where year > :year order by id')
  Stream<Book> streamAfter(int year);

  @Query('select title from books order by id')
  Stream<String> streamTitles();

  @Query(
    'select b.id, b.title, a.name as author_name from books b '
    'join authors a on a.id = b.author order by b.id',
  )
  Stream<BookWithAuthor> streamWithAuthor();

  // Changes.
  @Modifying()
  @Query('update books set year = year + :delta where year < :year')
  Future<int> shift(int year, int delta);

  @Modifying()
  @Query('delete from books where year < :year')
  Future<bool> deleteOlder(int year);

  @Modifying()
  @Query('update books set subtitle = :subtitle where id = :id')
  Future<void> retitle(int id, String? subtitle);

  // A row mapper and a result set extractor.
  @Query(
    'select a.id, a.name, b.title from authors a '
    'left join books b on b.author = a.id order by a.id, b.id',
    resultSetExtractor: AuthorWithBooks.extract,
  )
  Future<List<AuthorWithBooks>> authorsWithBooks();

  @Query('select title from books order by id', rowMapper: shoutTitle)
  Future<List<String>> shouted();

  // Hostile text, bound.
  @Query('select * from books where subtitle = :text order by id')
  Future<List<Book>> bySubtitleText(String text);
}

abstract interface class OrderQueries
    implements ListCrudRepository<PurchaseOrder, int> {
  Future<List<PurchaseOrder>> findByCustomer(String customer);
  Future<List<PurchaseOrder>> deleteByCustomer(String customer);
  Future<int> deleteByCustomerStartingWith(String prefix);
}

@UseStore('memory')
abstract interface class MemoryOrders implements OrderQueries {}

@UseStore('jdbc')
abstract interface class SqlOrders implements OrderQueries {
  @Query('select id, customer from orders where customer = :customer')
  Future<List<PurchaseOrder>> viaQuery(String customer);

  @Query('select customer from orders where customer = :customer')
  Future<List<PurchaseOrder>> withoutId(String customer);
}

@UseStore('memory')
abstract interface class MemoryShelves
    implements ListCrudRepository<Shelf, int> {}

@UseStore('jdbc')
abstract interface class SqlShelves implements ListCrudRepository<Shelf, int> {}

@UseStore('memory')
abstract interface class MemoryAccounts
    implements CrudRepository<Account, String> {
  Future<List<Account>> findByOwner(String owner);
}

@UseStore('jdbc')
abstract interface class SqlAccounts
    implements CrudRepository<Account, String> {
  Future<List<Account>> findByOwner(String owner);
}

@UseStore('memory')
abstract interface class MemoryTickets
    implements ListCrudRepository<Ticket, int> {}

@UseStore('jdbc')
abstract interface class SqlTickets
    implements ListCrudRepository<Ticket, int> {}

@UseStore('memory')
abstract interface class MemoryNotes implements ListCrudRepository<Note, int> {}

@UseStore('jdbc')
abstract interface class SqlNotes implements ListCrudRepository<Note, int> {}

@UseStore('jdbc')
abstract interface class SqlCrates implements ListCrudRepository<Crate, int> {}

/// Authors on the SQL store (for the joins).
@UseStore('jdbc')
abstract interface class SqlAuthors implements ListCrudRepository<Author, int> {
  Future<List<Author>> findByNameStartingWith(String prefix);
}

@UseStore('memory')
abstract interface class MemoryAuthors
    implements ListCrudRepository<Author, int> {}

/// Pessimistic locks.
@UseStore('jdbc')
abstract interface class SqlStocks implements ListCrudRepository<Stock, int> {
  @Lock(LockMode.pessimisticWrite)
  Future<Stock?> findBySku(String sku);

  @Lock(LockMode.pessimisticRead)
  Future<List<Stock>> findByQuantityLessThan(int quantity);

  @override
  @Lock(LockMode.pessimisticWrite)
  Future<Stock?> findById(int id);

  Future<Stock?> findOneBySku(String sku);
}

/// The fans, with a query on the plain reference.
abstract interface class FanQueries implements ListCrudRepository<Fan, int> {
  Future<List<Fan>> findByClubId(int clubId);
}

@UseStore('memory')
abstract interface class MemoryFans implements FanQueries {}

@UseStore('jdbc')
abstract interface class SqlFans implements FanQueries {
  @Query('select * from fans where club_id = :clubId order by id')
  Future<List<Fan>> byClub(int clubId);
}

/// The aggregates of the reference tests, on both stores.
abstract interface class CitizenQueries
    implements ListCrudRepository<Citizen, int> {
  Future<List<Citizen>> findByPassport(String? passport);
}

@UseStore('memory')
abstract interface class MemoryCitizens implements CitizenQueries {}

@UseStore('jdbc')
abstract interface class SqlCitizens implements CitizenQueries {}

abstract interface class CategoryQueries
    implements ListCrudRepository<Category, int> {
  Future<int> deleteByNameStartingWith(String prefix);
}

@UseStore('memory')
abstract interface class MemoryCategories implements CategoryQueries {}

@UseStore('jdbc')
abstract interface class SqlCategories implements CategoryQueries {}

abstract interface class EmployeeQueries
    implements ListCrudRepository<Employee, int> {
  Future<int> deleteByNameStartingWith(String prefix);
}

@UseStore('memory')
abstract interface class MemoryEmployees implements EmployeeQueries {}

@UseStore('jdbc')
abstract interface class SqlEmployees implements EmployeeQueries {}

@UseStore('memory')
abstract interface class MemoryClubs implements ListCrudRepository<Club, int> {}

@UseStore('jdbc')
abstract interface class SqlClubs implements ListCrudRepository<Club, int> {}

@UseStore('memory')
abstract interface class MemorySponsors
    implements ListCrudRepository<Sponsor, int> {}

@UseStore('jdbc')
abstract interface class SqlSponsors
    implements ListCrudRepository<Sponsor, int> {}

@UseStore('memory')
abstract interface class MemoryPlayers
    implements ListCrudRepository<Player, int> {}

@UseStore('jdbc')
abstract interface class SqlPlayers
    implements ListCrudRepository<Player, int> {}

@UseStore('memory')
abstract interface class MemoryGoals implements ListCrudRepository<Goal, int> {}

@UseStore('jdbc')
abstract interface class SqlGoals implements ListCrudRepository<Goal, int> {}

@UseStore('memory')
abstract interface class MemoryCoaches
    implements ListCrudRepository<Coach, int> {}

@UseStore('jdbc')
abstract interface class SqlCoaches implements ListCrudRepository<Coach, int> {}

@UseStore('memory')
abstract interface class MemorySquads
    implements ListCrudRepository<Squad, int> {}

@UseStore('jdbc')
abstract interface class SqlSquads implements ListCrudRepository<Squad, int> {}

@UseStore('memory')
abstract interface class MemoryFolders
    implements ListCrudRepository<Folder, int> {}

@UseStore('jdbc')
abstract interface class SqlFolders
    implements ListCrudRepository<Folder, int> {}

@UseStore('jdbc')
abstract interface class SqlMembers implements ListCrudRepository<Member, int> {
  Future<Member?> findOneByUsernameAndApiToken(
    String username,
    String apiToken,
  );

  Future<List<Member>> findByPasswordHash(String passwordHash);

  Future<List<Member>> findByUsernameIn(List<String> usernames);
}

@UseStore('memory')
abstract interface class MemoryGauges
    implements ListCrudRepository<Gauge, int> {}

@UseStore('jdbc')
abstract interface class SqlGauges implements ListCrudRepository<Gauge, int> {}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final context = await springApplication.runAsync(args);
  context.close();
}
