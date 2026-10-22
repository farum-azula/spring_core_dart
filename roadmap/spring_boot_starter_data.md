# spring_boot_starter_data_* (planned)

## Entities and repositories

Entities and repositories generated at build time, no reflection. `@Entity`
classes get generated row mapping; repository interfaces get a generated
implementation; method names (`findBy...And...OrderBy...`) are parsed by the
generator, so a typo in a property name is a build error. `@Transactional`
runs on the existing AOP proxies (`PlatformTransactionManager`);
`DataSource` and transactions come from `spring.datasource.*`. SQLite first
(Flutter and server), then PostgreSQL.

```dart
@Entity()
@Table('books')
class Book {
  @Id() @GeneratedValue()
  int? id;
  @Column(nullable: false)
  String title;
  int year;
  @ManyToOne()
  Author? author;
}

@Repository()
abstract interface class BookRepository extends CrudRepository<Book, int> {
  List<Book> findByTitleContainingAndYearGreaterThan(String title, int year);
  Page<Book> findByAuthorName(String name, Pageable page);

  @Query('select * from books where year = :year')
  List<Book> byYear(int year);

  // SpEL in queries, evaluated by the existing engine: the entity name,
  // properties of parameters, beans and ${...} properties.
  @Query('select * from #{#entityName} where title = :#{#book.title}')
  List<Book> sameTitle(Book book);

  @Query('select * from books where year >= :#{@clock.now().year - 1}')
  List<Book> recent();

  @Query(r'select * from books limit ${books.page-size:20}')
  List<Book> firstPage();
}

@Service()
class Library {
  Library(this.books);
  final BookRepository books;

  @Transactional()
  void publish(Book book) => books.save(book);
}
```
