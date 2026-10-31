import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'package:spring_boot_starter_data/src/annotations.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_converter.dart';
import 'package:spring_boot_starter_data/src/store/in_memory_data_store.dart';
import 'package:spring_boot_starter_data/src/store/in_memory_transaction_manager.dart';
import 'package:spring_boot_starter_data/src/transaction/platform_transaction_manager.dart';

/// The in-memory stores of the `@UseDataSource` names: one store per name,
/// named `memory:<name>`, shared by every repository that names it and by
/// the transaction manager of that name.
///
/// A repository with `@UseStore('memory')` and `@UseDataSource('x')`
/// keeps its aggregates in `storeFor('x')`; the starter registers a
/// `PlatformTransactionManager` bean over the same store (see
/// [DataSourceTransactionManagerRegistrar]), so
/// `@Transactional(transactionManager: 'x')` runs transactions of exactly
/// that store. The stores are made on first use.
///
/// Spring (Java): none; Spring has one `DataSource` bean per database,
/// and the repositories and the `DataSourceTransactionManager` both refer
/// to it. This registry stands for those beans while the data sources are
/// only names.
final class InMemoryDataSources {
  /// A registry whose stores convert with [converter] and wait at most
  /// [lockTimeout] for a row lock.
  InMemoryDataSources({
    required this.converter,
    this.lockTimeout = const Duration(seconds: 10),
  });

  /// Turns instances into rows and back.
  final EntityConverter converter;

  /// The lock timeout of the stores it makes.
  final Duration lockTimeout;

  final _stores = <String, InMemoryDataStore>{};

  /// The store of the data source [name], made on first use.
  InMemoryDataStore storeFor(String name) => _stores.putIfAbsent(
    name,
    () => InMemoryDataStore(
      converter: converter,
      name: 'memory:$name',
      lockTimeout: lockTimeout,
    ),
  );

  /// The data source names whose store exists, sorted.
  List<String> get names => _stores.keys.toList()..sort();
}

/// Registers a `PlatformTransactionManager` bean for every in-memory data
/// source the application's repositories name, so
/// `@Transactional(transactionManager: 'x')` finds it (and the startup
/// check of `@Transactional` knows it).
///
/// It reads the annotations of the bean definitions: each one with
/// `@UseStore('memory')` and `@UseDataSource('x')` makes one
/// [InMemoryTransactionManager] bean named `xTransactionManager`, with the
/// qualifier `x`, over `InMemoryDataSources.storeFor('x')`. The managers
/// are fallbacks: an empty `transactionManager` still means the default
/// store's manager (or the application's own primary one). A bean already
/// named so, or already qualified `x`, is the application's choice and
/// stays.
///
/// The starter registers it; applications do not use it.
///
/// Spring (Java): a `BeanDefinitionRegistryPostProcessor`, as Spring Boot
/// uses to register one bean per configured entry.
final class DataSourceTransactionManagerRegistrar
    implements BeanDefinitionRegistryPostProcessor {
  /// A registrar; it has no settings.
  DataSourceTransactionManagerRegistrar();

  /// The bean name of the manager of the data source [dataSource].
  static String beanNameOf(String dataSource) =>
      '${dataSource}TransactionManager';

  @override
  void postProcessBeanDefinitionRegistry(BeanDefinitionRegistry registry) {
    final names = <String>{};
    for (final name in registry.beanDefinitionNames) {
      final annotations = registry.getBeanDefinition(name).annotations;
      final store = annotations.whereType<UseStore>().firstOrNull?.value;
      final dataSource = annotations
          .whereType<UseDataSource>()
          .firstOrNull
          ?.value;
      if (store == 'memory' && dataSource != null) {
        names.add(dataSource);
      }
    }
    for (final dataSource in names) {
      final beanName = beanNameOf(dataSource);
      final taken = registry.beanDefinitionNames.any((other) {
        final definition = registry.getBeanDefinition(other);
        return other == beanName ||
            (definition.qualifiers.contains(dataSource) &&
                definition.types.contains(PlatformTransactionManager));
      });
      if (taken) {
        continue;
      }
      registry.registerBeanDefinition(
        BeanDefinition<InMemoryTransactionManager>(
          name: beanName,
          types: const [InMemoryTransactionManager, PlatformTransactionManager],
          qualifiers: {dataSource},
          fallback: true,
          source: 'package:spring_boot_starter_data#DataAutoConfiguration',
          create: (r) => InMemoryTransactionManager(
            r.dependency<InMemoryDataSources>().storeFor(dataSource),
          ),
        ),
      );
    }
  }

  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {}
}
