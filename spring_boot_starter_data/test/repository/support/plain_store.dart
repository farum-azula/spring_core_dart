// Stores that are not SQL, for the tests of what a repository needs of its
// store: they keep their rows in an in-memory store and say they can do
// what the test tells them.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

/// A store with the methods of [DataStore] and nothing else, unless
/// [capabilities] says more.
class PlainStore implements DataStore {
  PlainStore(
    this.inner, {
    this.name = 'rest',
    this.capabilities = const DataStoreCapabilities(),
  });

  /// Where the rows are.
  final InMemoryDataStore inner;

  @override
  final String name;

  @override
  final DataStoreCapabilities capabilities;

  @override
  Future<T> insert<T extends Object>(PersistentEntity<T> entity, T instance) =>
      inner.insert(entity, instance);

  @override
  Future<T> update<T extends Object>(
    PersistentEntity<T> entity,
    T instance, {
    Object? expectedVersion,
  }) => inner.update(entity, instance, expectedVersion: expectedVersion);

  @override
  Future<bool> deleteById<T extends Object>(
    PersistentEntity<T> entity,
    Object id, {
    Object? expectedVersion,
  }) => inner.deleteById(entity, id, expectedVersion: expectedVersion);

  @override
  Future<T?> findById<T extends Object>(
    PersistentEntity<T> entity,
    Object id, {
    LockMode? lock,
    Duration? lockTimeout,
    bool skipLocked = false,
  }) => inner.findById(entity, id);

  @override
  Future<List<T>> findAllById<T extends Object>(
    PersistentEntity<T> entity,
    Iterable<Object> ids,
  ) => inner.findAllById(entity, ids);

  @override
  Future<List<T>> find<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
    Sort sort = Sort.unsorted,
    int? offset,
    int? limit,
    bool distinct = false,
    LockMode? lock,
    Duration? lockTimeout,
    bool skipLocked = false,
  }) => inner.find(
    entity,
    criteria: criteria,
    sort: sort,
    offset: offset,
    limit: limit,
    distinct: distinct,
  );

  @override
  Future<int> count<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) => inner.count(entity, criteria: criteria);

  @override
  Future<bool> exists<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) => inner.exists(entity, criteria: criteria);

  @override
  Future<int> deleteWhere<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) => inner.deleteWhere(entity, criteria: criteria);

  @override
  Future<List<T>> deleteWhereAndReturn<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) => inner.deleteWhereAndReturn(entity, criteria: criteria);
}

/// A store with database functions: [onCall] answers each call, and
/// [calls] keeps them.
class FunctionStore extends PlainStore implements FunctionDataStore {
  FunctionStore(
    super.inner, {
    super.name = 'functions',
    super.capabilities = const DataStoreCapabilities(functions: true),
    this.onCall,
  });

  /// The answer to a call; default: no row.
  List<Map<String, Object?>> Function(
    String name,
    Map<String, Object?> arguments,
  )?
  onCall;

  /// The calls made: the function and its arguments by name.
  final calls = <(String, Map<String, Object?>)>[];

  @override
  Future<List<Map<String, Object?>>> callFunction(
    String name,
    Map<String, Object?> arguments,
  ) async {
    calls.add((name, arguments));
    return onCall?.call(name, arguments) ?? const [];
  }
}

/// A store that reports every change of a table whatever the criteria,
/// and says so: the caller must filter.
class UnfilteredChangeStore extends PlainStore
    implements ChangeStreamDataStore {
  UnfilteredChangeStore(
    super.inner, {
    super.name = 'feed',
    super.capabilities = const DataStoreCapabilities(changes: true),
  });

  /// The criteria the store was asked to apply (and did not).
  final asked = <Criteria?>[];

  @override
  Stream<RowChange<T>> changes<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  }) {
    asked.add(criteria);
    return inner.changes<T>(entity);
  }

  @override
  bool filtersChanges<T extends Object>(
    PersistentEntity<T> entity,
    Criteria criteria,
  ) => false;
}
