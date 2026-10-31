# spring_boot_starter_data

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

> **In development.** This first version keeps the data in memory; SQLite
> and PostgreSQL, transactions and pessimistic locks come next (see
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

## Differences from Spring

- The repository marker is `DataRepository` (`@Repository` is the
  stereotype annotation), a sort step is `SortOrder` (`@Order` orders
  beans).
- Dart has no overloading: `findAll()`, `findAllSorted(Sort)` and
  `findAllPaged(Pageable)`.
- The database and store of a repository: `@UseDataSource('analytics')`,
  `@UseStore('memory')`.
- Every method is asynchronous (`Future` or `Stream`).
