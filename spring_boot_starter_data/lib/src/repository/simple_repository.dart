import 'package:spring_boot_starter_data/src/repository/page.dart';
import 'package:spring_boot_starter_data/src/repository/repository.dart';
import 'package:spring_boot_starter_data/src/repository/repository_operations.dart';
import 'package:spring_boot_starter_data/src/repository/sort.dart';

/// The CRUD, sorting and paging methods of every repository: each one hands
/// the call to the [operations] of the repository.
///
/// The class the generator writes for a repository interface extends it, so
/// only the methods the interface declares itself (derived queries, `@Query`
/// methods, a `findById` with `@Lock`) are generated:
///
/// ```dart
/// class _$BookRepositoryImpl extends SimpleRepository<Book, int>
///     implements BookRepository {
///   _$BookRepositoryImpl(super.operations);
///
///   @override
///   Future<List<Book>> findByTitle(String title) =>
///       operations.list(_findByTitle, [title]);
/// }
/// ```
///
/// It implements the `List` flavours of the repository interfaces, so a
/// class that extends it also fits `CrudRepository`,
/// `PagingAndSortingRepository` and the interfaces that extend them.
///
/// Spring (Java):
/// `org.springframework.data.jdbc.repository.support.SimpleJdbcRepository`.
class SimpleRepository<T extends Object, ID extends Object>
    implements
        ListCrudRepository<T, ID>,
        ListPagingAndSortingRepository<T, ID> {
  /// A repository that calls [operations].
  SimpleRepository(this.operations);

  /// What runs the calls: the store, the transactions, the error
  /// translation.
  final RepositoryOperations<T, ID> operations;

  @override
  Future<T> save(T entity) => operations.save(entity);

  @override
  Future<List<T>> saveAll(Iterable<T> entities) => operations.saveAll(entities);

  @override
  Future<T?> findById(ID id) => operations.findById(id);

  @override
  Future<bool> existsById(ID id) => operations.existsById(id);

  @override
  Future<List<T>> findAll() => operations.findAll();

  @override
  Future<List<T>> findAllById(Iterable<ID> ids) => operations.findAllById(ids);

  @override
  Future<int> count() => operations.count();

  @override
  Future<void> deleteById(ID id) => operations.deleteById(id);

  @override
  Future<void> delete(T entity) => operations.delete(entity);

  @override
  Future<void> deleteAllById(Iterable<ID> ids) => operations.deleteAllById(ids);

  @override
  Future<void> deleteAllOf(Iterable<T> entities) =>
      operations.deleteAllOf(entities);

  @override
  Future<void> deleteAll() => operations.deleteAll();

  @override
  Future<List<T>> findAllSorted(Sort sort) => operations.findAllSorted(sort);

  @override
  Future<Page<T>> findAllPaged(Pageable pageable) =>
      operations.findAllPaged(pageable);
}
