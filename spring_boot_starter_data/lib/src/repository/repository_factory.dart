import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'package:spring_boot_starter_data/src/annotations.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_logging.dart';
import 'package:spring_boot_starter_data/src/mapping/auditing.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_converter.dart';
import 'package:spring_boot_starter_data/src/mapping/mapping_context.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';
import 'package:spring_boot_starter_data/src/repository/repository_invocation_handler.dart';
import 'package:spring_boot_starter_data/src/store/data_store.dart';
import 'package:spring_boot_starter_data/src/store/in_memory_data_sources.dart';
import 'package:spring_boot_starter_data/src/store/in_memory_data_store.dart';
import 'package:spring_boot_starter_data/src/store/in_memory_transaction_manager.dart';
import 'package:spring_boot_starter_data/src/store/jdbc/jdbc_data_store.dart';
import 'package:spring_boot_starter_data/src/transaction/platform_transaction_manager.dart';

/// Builds the working handler behind each repository interface: it finds
/// the entity and the store of the repository and creates its
/// [RepositoryInvocationHandler].
///
/// The starter declares it as the `repositoryFactory` bean; when the
/// container creates a repository bean (any non-generic interface that
/// extends `DataRepository`), the generated class asks this factory for
/// its handler. Applications do not use it directly.
///
/// The entity comes from the interface's type arguments (`Book` in
/// `ListCrudRepository<Book, int>`), through the [mappingContext]. The
/// store is chosen by the interface's annotations:
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
/// The repository runs its writes in transactions of its store: for a memory
/// store the factory gives the handler an `InMemoryTransactionManager` of
/// its own over that store; for a SQL store the `DataSourceTransactionManager`
/// of its data source. It joins the transaction of a `@Transactional`
/// service because both look for the same resource, the store (the data
/// source).
///
/// Every mistake of the repository (the store, the entity, each method) is
/// collected and reported together by the handler, so the application stops
/// at startup with the reasons.
///
/// Spring (Java): `JdbcRepositoryFactoryBean` and its
/// `JdbcRepositoryFactory` (`RepositoryFactorySupport`).
final class RepositoryFactory implements InvocationHandlerFactory {
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

  // The transaction managers of the repositories, one per store.
  final _managers = Map<DataStore, PlatformTransactionManager>.identity();

  @override
  bool supports(InterfaceMetadata<Object> metadata) =>
      metadata.typeArgumentsOf('DataRepository') != null;

  @override
  InvocationHandler create(InterfaceMetadata<Object> metadata) {
    final problems = <String>[];
    final arguments = metadata.typeArgumentsOf('DataRepository')!;
    final entityType = arguments.first;
    final PersistentEntity<Object> entity;
    try {
      entity = _entityOf(entityType);
    } on MappingException catch (e) {
      throw StateError(
        'Invalid repository ${metadata.typeName}:\n  - ${e.message}',
      );
    }
    final store = _storeOf(metadata, problems) ?? stores['memory']!;
    return RepositoryInvocationHandler(
      metadata: metadata,
      entity: entity,
      entityType: entityType,
      converter: converter,
      store: store,
      transactionManager: switch (store) {
        final InMemoryDataStore memory => _managers.putIfAbsent(
          memory,
          () => InMemoryTransactionManager(memory),
        ),
        final JdbcDataStore jdbc => jdbc.transactionManager,
        _ => null,
      },
      auditing: auditing,
      isNewStrategy: isNewStrategy,
      environment: environment,
      beanFactory: beanFactory,
      introspector: mappingContext.introspector,
      problems: problems,
    );
  }

  // The entity by the typed lookup, with the entity's type as the type
  // argument: the by-Type lookup would cache a second, Object-typed
  // PersistentEntity next to the typed one.
  PersistentEntity<Object> _entityOf(TypeInfo<Object?> type) =>
      type.capture<PersistentEntity<Object>>(
        <E>() =>
            // The type argument of a capture has no bound, the lookup's
            // is `extends Object`: the call is checked when it is made.
            (mappingContext as dynamic).getRequiredPersistentEntity<E>()
                as PersistentEntity<Object>,
      );

  DataStore? _storeOf(
    InterfaceMetadata<Object> metadata,
    List<String> problems,
  ) {
    final useStore = metadata.annotation<UseStore>()?.value;
    final dataSource = metadata.annotation<UseDataSource>()?.value;
    final typeName = metadata.typeName;
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
