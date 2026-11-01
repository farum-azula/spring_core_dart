import 'package:spring_boot_starter_data/src/repository/page.dart';
import 'package:spring_boot_starter_data/src/repository/sort.dart';

/// The marker of a repository of aggregates of type [T] whose id is of type
/// [ID]: an `abstract interface class` of the application extending it
/// (usually through [CrudRepository]) gets its implementation from the
/// generator, and is a bean, with no annotation needed. `@Repository('name')`
/// names the bean; `@UseDataSource` and `@UseStore` choose its database and
/// store.
///
/// Extend it directly to offer only the methods you declare (derived
/// queries, `@Query`), not the whole of [CrudRepository]. A generic
/// interface (`BaseRepository<T>`) is a base for others, never a bean
/// (Spring's `@NoRepositoryBean`).
///
/// Every method is asynchronous (a `Future`): Dart has one thread per
/// isolate, so there is no blocking API.
///
/// Spring (Java): `org.springframework.data.repository.Repository`; named
/// `DataRepository` here, since `Repository` is the stereotype annotation.
abstract interface class DataRepository<T, ID> {}

/// Saving, loading, counting and deleting aggregates by id.
///
/// An aggregate is loaded and saved whole, Spring Data JDBC's model: [save]
/// writes at once (there is no persistence context to flush), its children
/// (`@MappedCollection`) are written with it, and other aggregates are
/// referenced by id (`AggregateReference`), never loaded with it.
///
/// Spring (Java): `org.springframework.data.repository.CrudRepository`. The
/// `Iterable` results of Spring are `Iterable`s here too; [ListCrudRepository]
/// returns `List`s.
abstract interface class CrudRepository<T, ID>
    implements DataRepository<T, ID> {
  /// Inserts [entity] when it is new (its id is null, or its `@Version` is
  /// 0), else updates it; returns the saved entity, with the id the store
  /// gave and the version raised.
  ///
  /// With a `@Version` property, an update matches on the version it was
  /// loaded with; when another save got in between no row matches and an
  /// `OptimisticLockingFailureException` is thrown.
  Future<T> save(T entity);

  /// Saves each of [entities] as [save] does, in turn; returns them saved.
  Future<Iterable<T>> saveAll(Iterable<T> entities);

  /// The aggregate with id [id], or null when there is none.
  Future<T?> findById(ID id);

  /// Whether an aggregate with id [id] exists.
  Future<bool> existsById(ID id);

  /// Every aggregate.
  Future<Iterable<T>> findAll();

  /// The aggregates whose ids are among [ids]; missing ids are skipped.
  Future<Iterable<T>> findAllById(Iterable<ID> ids);

  /// The number of aggregates.
  Future<int> count();

  /// Deletes the aggregate with id [id], with its children; nothing when
  /// there is none. The version is not checked (there is none to check).
  Future<void> deleteById(ID id);

  /// Deletes [entity] with its children. With a `@Version` property the
  /// version is checked as in [save]: an
  /// `OptimisticLockingFailureException` when it no longer matches.
  Future<void> delete(T entity);

  /// Deletes the aggregates whose ids are among [ids].
  Future<void> deleteAllById(Iterable<ID> ids);

  /// Deletes each of [entities] as [delete] does.
  Future<void> deleteAllOf(Iterable<T> entities);

  /// Deletes every aggregate.
  Future<void> deleteAll();
}

/// [CrudRepository] returning `List`s instead of `Iterable`s.
///
/// Spring (Java): `org.springframework.data.repository.ListCrudRepository`.
abstract interface class ListCrudRepository<T, ID>
    implements CrudRepository<T, ID> {
  @override
  Future<List<T>> saveAll(Iterable<T> entities);

  @override
  Future<List<T>> findAll();

  @override
  Future<List<T>> findAllById(Iterable<ID> ids);
}

/// Loading aggregates sorted, or one page at a time.
///
/// Spring (Java):
/// `org.springframework.data.repository.PagingAndSortingRepository`.
abstract interface class PagingAndSortingRepository<T, ID>
    implements DataRepository<T, ID> {
  /// Every aggregate, ordered by [sort].
  Future<Iterable<T>> findAllSorted(Sort sort);

  /// One page of aggregates, as [pageable] asks; the page knows the total.
  Future<Page<T>> findAllPaged(Pageable pageable);
}

/// [PagingAndSortingRepository] returning a `List` for the sorted query.
///
/// Spring (Java):
/// `org.springframework.data.repository.ListPagingAndSortingRepository`.
abstract interface class ListPagingAndSortingRepository<T, ID>
    implements PagingAndSortingRepository<T, ID> {
  @override
  Future<List<T>> findAllSorted(Sort sort);
}
