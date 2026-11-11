import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';
import 'package:spring_boot_starter_data/src/store/data_store.dart';
import 'package:spring_boot_starter_data/src/transaction/platform_transaction_manager.dart';

/// One thing a [DataStore] may or may not be able to do, with the words a
/// startup error needs: what asks for it and what to do without it.
///
/// A repository says what its methods need as [StoreRequirement]s; the
/// store says what it has as [DataStoreCapabilities]; `RepositoryFactory`
/// compares the two when the repository is created.
///
/// Spring (Java): none; Spring Data has a module for each store, and a
/// feature a module lacks (a `@Lock` in Spring Data Redis) does not exist
/// there at all.
enum DataStoreCapability {
  /// Transactions: several statements that commit or roll back together.
  transactions(
    '@Transactional',
    'a store with transactions',
    "use a SQL store (@UseStore('jdbc') with spring.datasource.url), or "
        'remove @Transactional and do the atomic work in one database '
        'function (@Procedure)',
  ),

  /// Rows locked by a read until the transaction ends.
  locks(
    '@Lock',
    'a store with row locks',
    "use a SQL store (@UseStore('jdbc') with spring.datasource.url), or "
        'remove @Lock (a @Version checks concurrent writes without a lock)',
  ),

  /// The SQL text of `@Query`.
  queries(
    '@Query',
    'a SQL store',
    'set spring.datasource.url and add a driver '
        "(@UseStore('jdbc')), or write a derived query",
  ),

  /// Database functions called by name.
  functions(
    '@Procedure',
    'a store with database functions',
    'use a store whose database has them (PostgreSQL), or write the '
        'work as repository calls',
  ),

  /// A stream of the changes of the rows.
  changes(
    'a stream of changes',
    'a store that reports the changes of its rows',
    'use a store that does (the memory store), or return a Future and '
        'query again when the data may have changed',
  );

  DataStoreCapability(this.usedBy, this.need, this.fix);

  /// What uses the capability, as an error names it: `@Lock`.
  final String usedBy;

  /// What the user of the capability needs: `a store with row locks`.
  final String need;

  /// What to do with a store that lacks it.
  final String fix;
}

/// What a [DataStore] can do beyond storing and finding aggregates.
///
/// Everything is false unless said: a store declares what it has, and a
/// repository that uses more fails when it is created, with the method,
/// the store and the fix.
///
/// ```dart
/// @override
/// DataStoreCapabilities get capabilities =>
///     const DataStoreCapabilities(transactions: true, locks: true);
/// ```
///
/// Spring (Java): none (see [DataStoreCapability]).
final class DataStoreCapabilities {
  /// The capabilities named true.
  const DataStoreCapabilities({
    this.transactions = false,
    this.locks = false,
    this.queries = false,
    this.functions = false,
    this.changes = false,
  });

  /// Whether the store has transactions (`@Transactional`, the atomic
  /// writes of a repository). Such a store is a [TransactionalDataStore].
  final bool transactions;

  /// Whether a read can lock its rows (`@Lock`).
  final bool locks;

  /// Whether the store runs the SQL text of `@Query`.
  final bool queries;

  /// Whether the store calls database functions (`@Procedure`). Such a store is
  /// a `FunctionDataStore`.
  final bool functions;

  /// Whether the store reports the changes of its rows (repository methods
  /// that return them as a `Stream`). Such a store is a
  /// `ChangeStreamDataStore`.
  final bool changes;

  /// Whether the store has [capability].
  bool supports(DataStoreCapability capability) => switch (capability) {
    DataStoreCapability.transactions => transactions,
    DataStoreCapability.locks => locks,
    DataStoreCapability.queries => queries,
    DataStoreCapability.functions => functions,
    DataStoreCapability.changes => changes,
  };

  @override
  bool operator ==(Object other) =>
      other is DataStoreCapabilities &&
      DataStoreCapability.values.every(
        (capability) => other.supports(capability) == supports(capability),
      );

  @override
  int get hashCode => Object.hashAll(DataStoreCapability.values.map(supports));

  @override
  String toString() {
    final has = DataStoreCapability.values.where(supports);
    return 'DataStoreCapabilities('
        '${has.isEmpty ? 'none' : has.map((c) => c.name).join(', ')})';
  }
}

/// What one method of a repository interface needs of its store, as the
/// build writes it: `findBySku` with `@Lock` needs
/// [DataStoreCapability.locks].
///
/// The generated repository class hands its requirements to
/// `RepositoryFactory.operations`; one the store lacks is a problem of the
/// repository, reported when it is created with the method, the store and
/// the fix. The build writes one for the `@Query` and `@Procedure` methods too
/// (it checks them against the stores it knows); they are also given as
/// `queries` and `functions` and checked with them, and reported once.
///
/// ```dart
/// // @Lock(LockMode.pessimisticWrite)
/// // Future<Stock?> findBySku(String sku);
/// const StoreRequirement(r'findBySku', DataStoreCapability.locks)
/// ```
///
/// Spring (Java): none (see [DataStoreCapability]).
final class StoreRequirement {
  /// The method [method] needs [capability]; [usedBy] says what of the
  /// method does, when it is not the usual annotation of the capability.
  const StoreRequirement(this.method, this.capability, {this.usedBy});

  /// The requirement of the interface itself (an annotation on it, such
  /// as `@Transactional`).
  const StoreRequirement.ofInterface(this.capability, {this.usedBy})
    : method = null;

  /// The name of the method; null for the interface itself.
  final String? method;

  /// What the method needs.
  final DataStoreCapability capability;

  /// What of the method needs it, in the words of the error; null for
  /// [DataStoreCapability.usedBy].
  final String? usedBy;

  /// The problem of a repository [typeName] whose store [store] lacks the
  /// capability, or null when the store has it.
  String? problemWith(String typeName, DataStore store) {
    if (store.capabilities.supports(capability)) {
      return null;
    }
    return '${method == null ? typeName : '$typeName.$method'}: '
        '${usedBy ?? capability.usedBy} needs ${capability.need}, and the '
        '${store.name} store is none: ${capability.fix}';
  }

  @override
  bool operator ==(Object other) =>
      other is StoreRequirement &&
      other.method == method &&
      other.capability == capability &&
      other.usedBy == usedBy;

  @override
  int get hashCode => Object.hash(method, capability, usedBy);

  @override
  String toString() =>
      'StoreRequirement(${method ?? 'the interface'}: ${capability.name})';
}

/// A [DataStore] with transactions: it gives the manager that runs them.
///
/// The repositories of the store run their writes in transactions of
/// [transactionManager], and a `@DataTest` begins one in it to undo what a
/// test writes. A store that implements it says
/// `DataStoreCapabilities.transactions`.
///
/// Spring (Java): none; a Spring Data module brings its own
/// `PlatformTransactionManager` bean (`JdbcTransactionManager`,
/// `MongoTransactionManager`).
abstract interface class TransactionalDataStore implements DataStore {
  /// The manager of the store's transactions: every caller gets a manager
  /// of the same resource, so a transaction of a service is the one the
  /// repositories join.
  PlatformTransactionManager get transactionManager;
}

/// A [DataStore] that can tell, before any statement runs, what of an
/// entity's mapping it cannot keep.
///
/// `RepositoryOperations` asks it when a repository is created and adds
/// what it says to the problems of the repository (`Invalid repository
/// X:`). The SQL store is one: a `Map`, `List` or `Set` property without
/// `@Json` that its database has no column for is refused there, with the
/// fix, instead of failing in the driver at the first insert.
///
/// Spring (Java): none; Spring Data JDBC finds an unsupported property at
/// the first statement.
abstract interface class EntityCheckingDataStore implements DataStore {
  /// What of [entity] (and of the children of its mapped collections) the
  /// store cannot keep: a sentence each, naming the entity, the property
  /// and the fix; empty when all is well.
  List<String> mappingProblems(PersistentEntity<Object> entity);
}
