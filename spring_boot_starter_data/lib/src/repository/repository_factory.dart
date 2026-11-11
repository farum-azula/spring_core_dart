import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'package:spring_boot_starter_data/src/annotations.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_logging.dart';
import 'package:spring_boot_starter_data/src/mapping/auditing.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_converter.dart';
import 'package:spring_boot_starter_data/src/mapping/mapping_context.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';
import 'package:spring_boot_starter_data/src/repository/query/procedure_method.dart';
import 'package:spring_boot_starter_data/src/repository/query/query_method.dart';
import 'package:spring_boot_starter_data/src/repository/repository_operations.dart';
import 'package:spring_boot_starter_data/src/store/data_store.dart';
import 'package:spring_boot_starter_data/src/store/data_store_capabilities.dart';
import 'package:spring_boot_starter_data/src/store/in_memory_data_sources.dart';
import 'package:spring_boot_starter_data/src/store/in_memory_data_store.dart';
import 'package:spring_boot_starter_data/src/store/jdbc/jdbc_data_store.dart';
import 'package:spring_boot_starter_data/src/transaction/platform_transaction_manager.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_definition.dart';

/// Builds the working [RepositoryOperations] behind each repository
/// interface: it finds the entity and the store of the repository and
/// creates the operations the generated class calls.
///
/// The starter declares it as the `repositoryFactory` bean; when the
/// container creates a repository bean (any non-generic interface that
/// extends `DataRepository`), the generated class (which extends
/// `SimpleRepository`) asks this factory for its [operations]. Applications
/// do not use it directly.
///
/// The entity comes from the interface's type arguments (`Book` in
/// `ListCrudRepository<Book, int>`), through the [mappingContext]. The
/// store is chosen by the interface's annotations (`UseStore`,
/// `UseDataSource`):
///
/// - no annotation, or `@UseStore('memory')`: the store named `memory`
///   (the in-memory store of the application);
/// - `@UseStore('memory')` with `@UseDataSource('name')`: an in-memory
///   store of its own for that data source name, shared by the
///   repositories that name it (and by the transaction manager bean of
///   that name, through `InMemoryDataSources`);
/// - `@UseStore('jdbc')`: the SQL store ([JdbcDataStore]) of the data
///   source `@UseDataSource('name')` names, or of the primary one (the
///   data source under [primaryDataSource]) without it; an unknown data
///   source is an error naming the ones there are;
/// - `@UseDataSource('name')` alone: the SQL store of that data source
///   when [dataSources] has it, else an error (it asks for a database that
///   is not configured);
/// - no annotation at all: the [defaultStore], by default `memory`;
/// - any other `@UseStore` name: an error naming the stores there are.
///
/// The SQL stores are made on first use, one for each data source,
/// named `jdbc` (the primary) and `jdbc:<name>`; a [DataStore] given to
/// the factory under the name `jdbc` takes the place of the primary one.
///
/// The repository runs its writes in transactions of its store, when the
/// store has them (a `TransactionalDataStore`): the operations get the
/// store's own manager, an `InMemoryTransactionManager` for a memory store
/// and the `DataSourceTransactionManager` of its data source for a SQL
/// store. It joins the transaction of a `@Transactional` service because
/// both look for the same resource, the store (the data source). A store
/// without transactions gives none, and its writes are not wrapped.
///
/// What the build cannot know is checked here, when the repository is
/// created: the store and the data source, the entity, the `@Query` and
/// `@Procedure` methods, and what the methods need of the store
/// (`StoreRequirement`s against the store's `DataStoreCapabilities`: a
/// `@Lock` on a store without locks, a `@Transactional` on one without
/// transactions, a stream of changes from a store that reports none).
/// Every mistake is collected and reported together, so the application
/// stops at startup with the reasons. The method names are checked by the
/// build.
///
/// Spring (Java): `JdbcRepositoryFactoryBean` and its
/// `JdbcRepositoryFactory` (`RepositoryFactorySupport`).
final class RepositoryFactory {
  /// A factory whose repositories use [mappingContext] and [converter] and
  /// the [stores] there are (each under its `name`); [auditing] fills the
  /// audit properties when given.
  ///
  /// The store named `memory` is made when [stores] holds none.
  RepositoryFactory({
    required this.mappingContext,
    required this.converter,
    Iterable<DataStore> stores = const [],
    this.auditing,
    this.isNewStrategy = const IsNewStrategy(),
    InMemoryDataSources? dataSources,
    Map<String, DataSource> jdbcDataSources = const {},
    this.defaultStore = 'memory',
    this.jdbcLogSettings = const JdbcLogSettings(),
    this.environment,
    this.beanFactory,
  }) : stores = {for (final store in stores) store.name: store},
       dataSources = dataSources ?? InMemoryDataSources(converter: converter),
       jdbcDataSources = Map.of(jdbcDataSources) {
    this.stores.putIfAbsent(
      'memory',
      () => InMemoryDataStore(converter: converter),
    );
  }

  /// The key of the primary data source in [jdbcDataSources]: the one a
  /// repository with `@UseStore('jdbc')` and no `@UseDataSource` uses.
  static const primaryDataSource = 'default';

  /// The entities of the application, as the repositories' type arguments
  /// name them.
  final RelationalMappingContext mappingContext;

  /// Turns instances into rows and back.
  final EntityConverter converter;

  /// The stores, by the name `@UseStore` gives them.
  final Map<String, DataStore> stores;

  /// Sets the audit properties of the entities saved; `null` for no
  /// auditing.
  final AuditingHandler? auditing;

  /// Tells a new entity from one to update.
  final IsNewStrategy isNewStrategy;

  /// The in-memory stores of the `@UseDataSource` names.
  final InMemoryDataSources dataSources;

  /// The SQL data sources by name, the primary one under
  /// [primaryDataSource]. A data source may be added after the factory is
  /// made, but before the repository that uses it is created.
  final Map<String, DataSource> jdbcDataSources;

  /// The store of a repository without `@UseStore` and `@UseDataSource`:
  /// `memory`, or `jdbc` for the primary data source.
  final String defaultStore;

  /// What the SQL stores log, and how (see `JdbcLogSettings`).
  final JdbcLogSettings jdbcLogSettings;

  /// Resolves the `${property}` placeholders of `@Query` texts and answers
  /// `@environment` in their SpEL; null for neither.
  final Environment? environment;

  /// Gives the SpEL of `@Query` methods their `@bean` references; null for
  /// none.
  final BeanFactory? beanFactory;

  // The SQL stores, one for each data source name.
  final _jdbcStores = <String, JdbcDataStore>{};

  // The managers handed to the repositories made so far.
  final _used = Set<PlatformTransactionManager>.identity();

  /// The transaction managers of the repositories made so far: one for each
  /// store they use, the in-memory ones and those of the SQL data sources
  /// (the primary one and the named ones). A `@DataTest` begins a
  /// transaction in each, so that everything a test writes is undone.
  List<PlatformTransactionManager> get transactionManagers =>
      List.unmodifiable(_used);

  /// The operations of the repository [typeName] for aggregates of type [T]
  /// with ids of type [ID]: the interface's [annotations] choose the store,
  /// its `@Query` methods ([queries]) and `@Procedure` methods ([functions])
  /// are compiled and checked, and what its other methods need of the store
  /// ([requirements]: a `@Lock`, a `@Transactional`, a stream of changes)
  /// is compared with what the store has. A `@Transactional` among
  /// [annotations] is a requirement of the interface itself.
  ///
  /// ```dart
  /// factory.operations<Stock, int>(
  ///   r'StockRepository',
  ///   annotations: const [UseStore(r'jdbc')],
  ///   queries: [_low],
  ///   functions: [_restock],
  ///   requirements: const [
  ///     StoreRequirement(r'findBySku', DataStoreCapability.locks),
  ///     StoreRequirement(r'watchBySku', DataStoreCapability.changes),
  ///   ],
  /// );
  /// ```
  ///
  /// Throws a [StateError] listing every mistake of the repository: the
  /// entity, the store, the data source, the queries, the functions, the
  /// requirements the store does not meet.
  RepositoryOperations<T, ID> operations<T extends Object, ID extends Object>(
    String typeName, {
    List<Object> annotations = const [],
    List<QueryMethod> queries = const [],
    List<ProcedureMethod> functions = const [],
    List<StoreRequirement> requirements = const [],
  }) {
    final problems = <String>[];
    final PersistentEntity<T> entity;
    try {
      entity = mappingContext.getRequiredPersistentEntity<T>();
    } on MappingException catch (e) {
      throw StateError('Invalid repository $typeName:\n  - ${e.message}');
    }
    final store =
        _storeOf(typeName, annotations, problems) ?? stores['memory']!;
    final manager = switch (store) {
      final TransactionalDataStore transactional =>
        transactional.transactionManager,
      _ => null,
    };
    if (manager != null) {
      _used.add(manager);
    }
    return RepositoryOperations<T, ID>(
      typeName: typeName,
      entity: entity,
      converter: converter,
      store: store,
      transactionManager: manager,
      auditing: auditing,
      isNewStrategy: isNewStrategy,
      environment: environment,
      beanFactory: beanFactory,
      introspector: converter.introspector,
      mappingContext: mappingContext,
      queries: queries,
      functions: functions,
      requirements: [
        if (annotations.whereType<Transactional>().isNotEmpty)
          const StoreRequirement.ofInterface(DataStoreCapability.transactions),
        ...requirements,
      ],
      problems: problems,
    );
  }

  DataStore? _storeOf(
    String typeName,
    List<Object> annotations,
    List<String> problems,
  ) {
    final useStore = annotations.whereType<UseStore>().firstOrNull?.value;
    final dataSource = annotations
        .whereType<UseDataSource>()
        .firstOrNull
        ?.value;
    if (useStore == 'jdbc') {
      if (dataSource == null && stores.containsKey('jdbc')) {
        return stores['jdbc'];
      }
      return _jdbcStoreOf(dataSource, typeName, problems);
    }
    if (useStore != null && useStore != 'memory') {
      final store = stores[useStore];
      if (store == null) {
        final unavailable = const {'supabase'}.contains(useStore)
            ? ' (its store is not available in this version)'
            : '';
        problems.add(
          "$typeName: @UseStore('$useStore') names no store$unavailable; "
          'the stores here: ${(stores.keys.toList()..sort()).join(', ')}',
        );
      } else if (dataSource != null) {
        problems.add(
          "$typeName: @UseDataSource('$dataSource') needs a SQL store; "
          'the $useStore store has no data sources',
        );
      }
      return store;
    }
    if (dataSource == null) {
      return defaultStore == 'jdbc' && useStore == null
          ? _jdbcStoreOf(null, typeName, problems)
          : stores[useStore ?? defaultStore] ??
                _unknownDefault(typeName, problems);
    }
    if (useStore == null) {
      if (jdbcDataSources.containsKey(dataSource)) {
        return _jdbcStoreOf(dataSource, typeName, problems);
      }
      problems.add(
        "$typeName: @UseDataSource('$dataSource') needs a SQL database "
        '(spring.datasources.$dataSource.url and a driver), and none is '
        'configured under this name'
        '${jdbcDataSources.isEmpty ? '' : ' (the data sources: '
                  '${(jdbcDataSources.keys.toList()..sort()).join(', ')})'}'
        "; add @UseStore('memory') to keep the repository in memory "
        'meanwhile',
      );
      return null;
    }
    return dataSources.storeFor(dataSource);
  }

  DataStore? _unknownDefault(String typeName, List<String> problems) {
    problems.add(
      "$typeName: the default store '$defaultStore' names no store; the "
      'stores here: ${(stores.keys.toList()..sort()).join(', ')}',
    );
    return null;
  }

  /// The SQL store of the data source [name] (the primary one without a
  /// name), made on first use; null when the factory has no such data
  /// source.
  JdbcDataStore? jdbcStoreFor([String? name]) {
    final key = name ?? primaryDataSource;
    final dataSource = jdbcDataSources[key];
    if (dataSource == null) {
      return null;
    }
    return _jdbcStores.putIfAbsent(
      key,
      () => JdbcDataStore(
        dataSource: dataSource,
        converter: converter,
        namingStrategy: mappingContext.namingStrategy,
        name: name == null ? 'jdbc' : 'jdbc:$name',
        logSettings: jdbcLogSettings,
      ),
    );
  }

  DataStore? _jdbcStoreOf(
    String? name,
    String typeName,
    List<String> problems,
  ) {
    final store = jdbcStoreFor(name);
    if (store == null) {
      final known = (jdbcDataSources.keys.toList()..sort()).join(', ');
      problems.add(
        name == null
            ? "$typeName: @UseStore('jdbc') needs the primary data source "
                  '(spring.datasource.url and a driver), which is not '
                  'configured'
            : "$typeName: @UseDataSource('$name') names no data source"
                  '${known.isEmpty ? '' : '; the data sources: $known'}',
      );
    }
    return store;
  }
}
