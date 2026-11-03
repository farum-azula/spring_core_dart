// The application of the @DataTest tests that run on a PostgreSQL container:
// a book entity and its repository, a database URL in the properties that no
// server answers (the container's own replaces it), and PostgreSQL migrations.
// The generator writes the repository and the module
// (postgres_data_app.spring.dart, from `dart run build_runner build`) and,
// seeing `postgres` among the dev dependencies, the driver's glue.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

import '../../spring_gen/data_test/postgres_app/postgres_data_app.spring.dart';

/// A book.
@Table('books')
class Book {
  Book({required this.title, required this.year, this.id});

  @Id()
  int? id;

  String title;
  int year;
}

abstract interface class BookRepository
    implements ListCrudRepository<Book, int> {
  Future<List<Book>> findByYearGreaterThan(int year);
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final context = await springApplication.runAsync(args);
  context.close();
}
