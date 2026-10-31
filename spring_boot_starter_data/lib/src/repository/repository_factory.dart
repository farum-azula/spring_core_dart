import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'package:spring_boot_starter_data/src/annotations.dart';
import 'package:spring_boot_starter_data/src/mapping/auditing.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_converter.dart';
import 'package:spring_boot_starter_data/src/mapping/mapping_context.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';
import 'package:spring_boot_starter_data/src/repository/repository_invocation_handler.dart';
import 'package:spring_boot_starter_data/src/store/data_store.dart';
import 'package:spring_boot_starter_data/src/store/in_memory_data_sources.dart';
import 'package:spring_boot_starter_data/src/store/in_memory_data_store.dart';
import 'package:spring_boot_starter_data/src/store/in_memory_transaction_manager.dart';
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
/// - `@UseDataSource` without `@UseStore('memory')`: an error, as it asks
///   for a SQL database, which this version cannot offer;
/// - any other `@UseStore` name: an error naming the stores there are.
///
/// The repository runs its writes in transactions of its store: for a memory
/// store the factory gives the handler an `InMemoryTransactionManager` of
/// its own over that store. It joins the transaction of a `@Transactional`
/// service because both look for the same resource, the store.
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
  }) : stores = {for (final store in stores) store.name: store},
       dataSources = dataSources ?? InMemoryDataSources(converter: converter) {
    this.stores.putIfAbsent(
      'memory',
      () => InMemoryDataStore(converter: converter),
    );
  }

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
        _ => null,
      },
      auditing: auditing,
      isNewStrategy: isNewStrategy,
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
    if (useStore != null && useStore != 'memory') {
      final store = stores[useStore];
      if (store == null) {
        final unavailable = const {'jdbc', 'supabase'}.contains(useStore)
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
      return stores['memory'];
    }
    if (useStore == null) {
      problems.add(
        "$typeName: @UseDataSource('$dataSource') needs a SQL database "
        '(spring.datasources.$dataSource.url and a driver), which is '
        "coming in a later version; add @UseStore('memory') to keep the "
        'repository in memory meanwhile',
      );
      return null;
    }
    return dataSources.storeFor(dataSource);
  }
}
