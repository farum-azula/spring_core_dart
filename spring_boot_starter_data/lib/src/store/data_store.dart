import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';
import 'package:spring_boot_starter_data/src/query/part_tree.dart';
import 'package:spring_boot_starter_data/src/repository/sort.dart';

/// A condition on the columns of an entity's own table, in a form every
/// store can use: the parts of a derived query's name and the values that
/// are bound to them.
///
/// [predicate] is a disjunction of conjunctions, as a `PartTree` has it:
/// an entity matches when all the parts of at least one [OrPart] hold; no
/// alternative at all matches everything. [arguments] holds the values the
/// parts take, in the order the parts appear (the `OrPart`s in order, and
/// in each the parts in order): a part consumes
/// `PartType.argumentCount` of them (none for `isNull`, two for
/// `between`, one for the rest; `in` and `notIn` take one collection). A
/// store may run the predicate itself (the in-memory store) or turn it
/// into a `WHERE` clause with bind parameters (a SQL store); nothing in
/// it is a closure, so both are possible.
///
/// The values are the ones the repository method was called with: a store
/// converts them as it converts column values (an enum is its `name`, an
/// `AggregateReference` its id).
///
/// ```dart
/// // findByTitleAndYearGreaterThan('Dune', 1960)
/// final criteria = Criteria(tree.predicate, ['Dune', 1960]);
/// ```
///
/// Spring (Java): `org.springframework.data.relational.core.query.Criteria`
/// (and, for the bound values, `RelationalParametersParameterAccessor`).
final class Criteria {
  /// A condition made of [predicate] with [arguments] bound to its parts.
  Criteria(this.predicate, List<Object?> arguments)
    : arguments = List.unmodifiable(arguments) {
    final needed = predicate
        .expand((or) => or.parts)
        .fold<int>(0, (sum, part) => sum + part.type.argumentCount);
    if (needed != arguments.length) {
      throw ArgumentError.value(
        arguments,
        'arguments',
        'the predicate needs $needed argument(s), not ${arguments.length}',
      );
    }
  }

  /// The alternatives: an entity matches when one of them matches.
  final List<OrPart> predicate;

  /// The bound values, in the order of the parts.
  final List<Object?> arguments;

  /// Whether the condition has no part: it matches every entity.
  bool get isEmpty => predicate.every((or) => or.parts.isEmpty);

  @override
  String toString() => predicate.isEmpty ? 'all' : predicate.join(' or ');
}

/// What a repository stores aggregates in.
///
/// A store works on whole aggregates, described by a [PersistentEntity]:
/// the root entity and, with it, the children of its `@MappedCollection`
/// properties, which are written and read with the root and never alone.
/// The instances it takes and gives are the application's objects; what it
/// keeps is its own business (rows), so an instance it returns is always
/// a copy that the application may change without changing the store.
///
/// Every method takes the entity (the table and columns), so one store
/// serves every repository. Failures are `DataAccessException`s:
/// `DuplicateKeyException`, `OptimisticLockingFailureException`,
/// `IncorrectUpdateSemanticsDataAccessException` and so on.
///
/// The in-memory store is the first implementation; a SQL store and a
/// Supabase store implement the same methods. The decisions that belong to
/// a store, and not to the repository, are made here: the generation of
/// ids, the value of a `@Version` after a write and the check of its old
/// value.
///
/// Spring (Java):
/// `org.springframework.data.jdbc.core.JdbcAggregateOperations` (its
/// implementation `JdbcAggregateTemplate`, over `DataAccessStrategy`).
abstract interface class DataStore {
  /// The name of the store (`memory`, later `sql`): what
  /// `@UseStore('...')` selects.
  String get name;

  /// Inserts [instance] as a new aggregate, with its children, and returns
  /// the instance as stored.
  ///
  /// A null `@Id` that the store can generate (an `int`, counted per
  /// table from 1; an identity column in SQL) is generated; an id that is
  /// set is used as it is. A `@Version` becomes 1 for an `int` and the
  /// current time for a `DateTime`. The returned instance carries both (it
  /// is a copy when the properties are `final`): callers must use it and
  /// not [instance].
  ///
  /// Throws `DuplicateKeyException` when the id exists, and
  /// `InvalidDataAccessApiUsageException` when the id is null and cannot
  /// be generated.
  Future<T> insert<T extends Object>(
    PersistentEntity<T> entity,
    T instance,
  );

  /// Replaces the stored aggregate with the id of [instance] by [instance],
  /// children included (the old children are removed), and returns the
  /// instance as stored.
  ///
  /// With a `@Version`, the stored version must equal [expectedVersion],
  /// by default the version [instance] carries (the one it was loaded
  /// with); the stored version is then raised (an `int` by one, a
  /// `DateTime` to the current time) and the returned instance carries it.
  /// A different version, or no such aggregate, is an
  /// `OptimisticLockingFailureException`. Without a `@Version`, no such
  /// aggregate is an `IncorrectUpdateSemanticsDataAccessException`.
  Future<T> update<T extends Object>(
    PersistentEntity<T> entity,
    T instance, {
    Object? expectedVersion,
  });

  /// Removes the aggregate with [id] and its children, and tells whether
  /// there was one.
  ///
  /// With [expectedVersion] the stored version must be equal: another
  /// version, or no such aggregate, is an
  /// `OptimisticLockingFailureException`. Without it nothing is checked and
  /// a missing aggregate is no error.
  Future<bool> deleteById<T extends Object>(
    PersistentEntity<T> entity,
    Object id, {
    Object? expectedVersion,
  });

  /// The aggregate with [id], or null.
  Future<T?> findById<T extends Object>(PersistentEntity<T> entity, Object id);

  /// The aggregates with one of [ids], in the table's order; ids without an
  /// aggregate are skipped.
  Future<List<T>> findAllById<T extends Object>(
    PersistentEntity<T> entity,
    Iterable<Object> ids,
  );

  /// The aggregates that match [criteria] (all without it), in the order
  /// of [sort] (the table's order for equal keys and without a sort),
  /// without the duplicates when [distinct], then skipping the first
  /// [offset] and keeping at most [limit].
  ///
  /// Throws `InvalidDataAccessApiUsageException` when the criteria or the
  /// sort name a property that is not a column of the entity.
  Future<List<T>> find<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
    Sort sort = Sort.unsorted,
    int? offset,
    int? limit,
    bool distinct = false,
  });

  /// How many aggregates match [criteria] (all without it).
  Future<int> count<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  });

  /// Whether an aggregate matches [criteria] (whether there is one at all
  /// without it).
  Future<bool> exists<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  });

  /// Removes the aggregates that match [criteria] (all without it) with
  /// their children, and returns how many there were.
  Future<int> deleteWhere<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  });

  /// Like [deleteWhere], but returns the aggregates that were removed (as
  /// they were stored), in the table's order.
  Future<List<T>> deleteWhereAndReturn<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  });
}
