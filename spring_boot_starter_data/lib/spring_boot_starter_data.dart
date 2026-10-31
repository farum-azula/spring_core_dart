/// Spring Data for `spring_boot_dart` applications: entities, repositories
/// whose implementations the generator writes, derived queries
/// (`findByTitleContaining`), paging and sorting, optimistic locking with
/// `@Version`, auditing.
///
/// An aggregate is a class marked `@Table`; a repository is an interface
/// extending `CrudRepository<Book, int>` (or `DataRepository` with only the
/// methods you declare). The generator implements it and makes it a bean:
///
/// ```dart
/// @Table('books')
/// class Book {
///   Book({this.id, required this.title, this.year});
///
///   @Id()
///   int? id;
///   String title;
///   int? year;
///
///   @Version()
///   int version = 0;
/// }
///
/// abstract interface class BookRepository
///     implements ListCrudRepository<Book, int> {
///   Future<List<Book>> findByTitleContainingIgnoreCase(String text);
///   Future<Page<Book>> findByYearGreaterThan(int year, Pageable page);
/// }
/// ```
///
/// The model is Spring Data JDBC's, not JPA's: an aggregate is loaded and
/// saved whole, `save` writes at once, other aggregates are referenced by
/// id. No driver is inside: the application adds the one it wants.
///
/// This import re-exports `spring_boot_starter_logging` and, through it,
/// `spring_boot_dart` and `spring_core_dart`. It is the Dart version of
/// Spring Boot's `spring-boot-starter-data-jdbc`.
library;

export 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';

export 'src/annotations.dart';
export 'src/data_auto_configuration.dart' show auditingHandlerFromAnnotation;
export 'src/exceptions.dart';
export 'src/mapping/auditing.dart';
export 'src/mapping/entity_converter.dart';
export 'src/mapping/mapping_context.dart';
export 'src/mapping/naming_strategy.dart';
export 'src/mapping/persistent_entity.dart';
export 'src/query/part_tree.dart';
export 'src/query/part_tree_parser.dart';
export 'src/repository/page.dart';
export 'src/repository/repository.dart';
export 'src/repository/repository_factory.dart';
export 'src/repository/repository_invocation_handler.dart';
export 'src/repository/sort.dart';
export 'src/store/data_store.dart';
export 'src/store/in_memory_data_store.dart';
