// The application of the @DataTest tests: a book entity and its repository,
// beans a data slice keeps (the auditor behind @EnableDataAuditing) and beans
// it leaves out (a service, a runner that writes at startup). The generator
// writes the repository and the module (data_test_app.spring.dart, from
// `dart run build_runner build`); the database is configured as a file that
// no test may create: a slice replaces it with an in-memory SQLite one.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

import 'data_test_app.spring.dart';

/// A book; the audit properties are filled on save.
@Table('books')
class Book {
  Book({
    required this.title,
    required this.year,
    this.id,
    this.createdBy,
    this.createdAt,
  });

  @Id()
  int? id;

  String title;
  int year;

  @CreatedBy()
  String? createdBy;

  @CreatedDate()
  DateTime? createdAt;
}

abstract interface class BookRepository
    implements ListCrudRepository<Book, int> {
  Future<List<Book>> findByTitle(String title);

  Future<List<Book>> findByYearGreaterThan(int year);
}

/// Switches the audit properties on, with the auditor below.
@Configuration()
@EnableDataAuditing()
class AuditingSetup {}

/// The auditor: a data bean, so the slice keeps it.
@Component()
class Reader implements AuditorAware<String> {
  @override
  String? getCurrentAuditor() => 'reader';
}

/// A service on the repository: not a data bean, left out of the slice.
@Service()
class BookService {
  BookService(this.books);

  final BookRepository books;

  Future<int> count() => books.count();
}

/// Writes at startup: it would give every test a book if the slice ran it.
@Component()
class Seeder implements CommandLineRunner {
  Seeder(this.books);

  final BookRepository books;

  @override
  Future<void> run(List<String> args) async {
    await books.save(Book(title: 'Seeded', year: 1999));
  }
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final context = await springApplication.runAsync(args);
  context.close();
}
