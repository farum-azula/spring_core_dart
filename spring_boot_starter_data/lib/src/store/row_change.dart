import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';
import 'package:spring_boot_starter_data/src/store/data_store.dart';

/// What happened to a row.
enum RowChangeKind {
  /// A new row.
  insert,

  /// A row replaced by another with the same id.
  update,

  /// A row removed.
  delete,
}

/// One change of a row of an entity's table, as a [ChangeStreamDataStore]
/// reports it once the change is committed.
///
/// ```dart
/// repository.changesByShelf('A').listen((change) {
///   if (change.kind == RowChangeKind.delete) {
///     remove(change.id);
///   } else {
///     put(change.row!);
///   }
/// });
/// ```
///
/// Spring (Java): none in Spring Data JDBC; Spring Data MongoDB's
/// `ChangeStreamEvent` is the nearest (`getOperationType()`, `getBody()`,
/// `getBodyBeforeChange()`).
final class RowChange<T> {
  /// A change of [kind]: [row] is the row after it, [previous] the row
  /// before it when the store knows it, [id] the row's id.
  const RowChange(this.kind, {this.row, this.previous, this.id});

  /// What happened.
  final RowChangeKind kind;

  /// The row after the change: the new row of an insert or an update;
  /// null for a delete.
  final T? row;

  /// The row before the change, when the store knows it (some stores
  /// report only the id of a deleted row, or nothing of an updated row's
  /// past); null for an insert.
  final T? previous;

  /// The id of the row, as the store holds it; null when the store does
  /// not tell.
  final Object? id;

  @override
  String toString() =>
      'RowChange(${kind.name}${id == null ? '' : ' $id'}'
      '${row == null ? '' : ': $row'})';
}

/// A [DataStore] that reports the changes of its rows as they are
/// committed: the store behind the repository methods that return a
/// stream of changes or a result kept up to date.
///
/// A store implements it and says `DataStoreCapabilities.changes`.
///
/// ```dart
/// final changes = store.changes<Book>(entity, criteria: onShelfA);
/// ```
///
/// Spring (Java): none in Spring Data JDBC; Spring Data MongoDB's
/// `ReactiveMongoOperations.changeStream`.
abstract interface class ChangeStreamDataStore implements DataStore {
  /// The changes of the rows of [entity] from the moment the stream is
  /// listened to, each after it is committed (nothing of a transaction
  /// that rolls back), until the subscription is cancelled: then the store
  /// stops reporting (and frees what it held for it).
  ///
  /// With [criteria] the store leaves out the changes that do not concern
  /// it, as far as it can: a change concerns a criteria when the row
  /// after it or the row before it matches (so a row that stops matching
  /// is reported), and a change whose rows the store does not know always
  /// does. A store that cannot apply the whole criteria reports more and
  /// says so in [filtersChanges]: the caller filters the rest (see
  /// `CriteriaMatcher.concerns`).
  ///
  /// Throws `InvalidDataAccessApiUsageException` when the criteria name a
  /// property that is not a column of the entity.
  Stream<RowChange<T>> changes<T extends Object>(
    PersistentEntity<T> entity, {
    Criteria? criteria,
  });

  /// Whether [changes] with [criteria] reports only the changes that
  /// concern it. False when the store cannot apply all of it (an operator
  /// its change feed does not have): the stream then holds more, and the
  /// caller tests each change against the criteria itself.
  bool filtersChanges<T extends Object>(
    PersistentEntity<T> entity,
    Criteria criteria,
  );
}
