// The application the auto-configuration tests start: aggregates,
// repositories on the primary data source, on a named one (`stats`) and in
// memory (`scratch`), a transactional service, and beans that use a
// repository while the context is being built. The migrations are in
// lib/resources/db/. The generator writes autoconfig_app.spring.dart.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

import 'autoconfig_app.spring.dart';

@Table('authors')
class Author {
  Author({required this.name, this.id});

  @Id()
  int? id;

  String name;
}

@Table('books')
class Book {
  Book({
    required this.title,
    required this.year,
    this.id,
    this.author,
    this.version,
  });

  @Id()
  int? id;

  String title;
  int year;
  AggregateReference<Author, int>? author;

  @Version()
  int? version;
}

@Table('orders')
class PurchaseOrder {
  PurchaseOrder({required this.customer, this.id, this.lines = const []});

  @Id()
  int? id;

  String customer;

  @MappedCollection()
  List<OrderLine> lines;
}

@Table('order_lines')
class OrderLine {
  OrderLine({required this.sku, required this.quantity});

  String sku;
  int quantity;
}

/// Lives in the `stats` database.
@Table('visits')
class Visit {
  Visit({required this.page, this.id});

  @Id()
  int? id;

  String page;
}

/// Only in memory: its data source name is not a SQL database.
@Table('notes')
class Note {
  Note({required this.text, this.id});

  @Id()
  int? id;

  String text;
}

abstract interface class AuthorRepository
    implements ListCrudRepository<Author, int> {}

abstract interface class BookRepository
    implements ListCrudRepository<Book, int> {
  Future<List<Book>> findByYearGreaterThan(int year);
}

abstract interface class OrderRepository
    implements ListCrudRepository<PurchaseOrder, int> {}

@UseDataSource('stats')
abstract interface class VisitRepository
    implements ListCrudRepository<Visit, int> {}

@UseStore('memory')
@UseDataSource('scratch')
abstract interface class NoteRepository
    implements ListCrudRepository<Note, int> {}

/// Transactions on the primary and the named data source.
@Service()
class Library {
  Library(this.books, this.authors, this.visits);

  final BookRepository books;
  final AuthorRepository authors;
  final VisitRepository visits;

  /// An author and a book in one transaction; a title of `boom` fails.
  @Transactional()
  Future<void> addBook(String title) async {
    final author = await authors.save(Author(name: 'Ursula'));
    await books.save(
      Book(
        title: title,
        year: 1969,
        author: AggregateReference<Author, int>(author.id!),
      ),
    );
    if (title == 'boom') {
      throw StateError('boom');
    }
  }

  /// A visit in the `stats` database; [fail] rolls it back.
  @Transactional(transactionManager: 'stats')
  Future<void> visit(String page, {bool fail = false}) async {
    await visits.save(Visit(page: page));
    if (fail) {
      throw StateError('fail');
    }
  }
}

/// Beans that use the database while the context starts exist unless
/// `app.early-queries` is false: a `DataSource` of the application's own is
/// set up when the context has made all the beans, not before.
const _earlyQueries = ConditionalOnProperty(
  'app.early-queries',
  matchIfMissing: true,
);

/// Starts a query in a synchronous `@PostConstruct`, without waiting for it:
/// the data source must hold the query back until the schema is ready.
@Component()
@_earlyQueries
class EagerQuery {
  EagerQuery(this.books);

  final BookRepository books;
  late final Future<int> count;

  @PostConstruct()
  void start() {
    count = books.count();
    // A failed start is reported by the context, not here.
    count.ignore();
  }
}

/// Writes through a repository in an asynchronous `@PostConstruct`.
@Component()
@_earlyQueries
class AsyncQuery {
  AsyncQuery(this.books, this.orders);

  final BookRepository books;
  final OrderRepository orders;
  int? count;

  @PostConstruct()
  Future<void> start() async {
    await orders.save(PurchaseOrder(customer: 'From PostConstruct'));
    count = await orders.count();
  }
}

/// A command line runner that uses the database; the tests call it as
/// `SpringApplication` would.
@Component()
class SeedRunner implements CommandLineRunner {
  SeedRunner(this.authors);

  final AuthorRepository authors;
  final seen = <String>[];

  @override
  Future<void> run(List<String> args) async {
    seen.add('command line: ${await authors.count()}');
  }
}

/// The same for an application runner.
@Component()
class SeedApplicationRunner implements ApplicationRunner {
  SeedApplicationRunner(this.books);

  final BookRepository books;
  final seen = <String>[];

  @override
  Future<void> run(ApplicationArguments args) async {
    seen.add('application: ${await books.count()}');
  }
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final context = await springApplication.runAsync(args);
  context.close();
}
