import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'package:spring_boot_starter_data/src/mapping/auditing.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_converter.dart';
import 'package:spring_boot_starter_data/src/mapping/mapping_context.dart';
import 'package:spring_boot_starter_data/src/mapping/naming_strategy.dart';
import 'package:spring_boot_starter_data/src/repository/repository_factory.dart';
import 'package:spring_boot_starter_data/src/store/data_store.dart';
import 'package:spring_boot_starter_data/src/store/in_memory_data_sources.dart';
import 'package:spring_boot_starter_data/src/store/in_memory_data_store.dart';
import 'package:spring_boot_starter_data/src/store/in_memory_transaction_manager.dart';
import 'package:spring_boot_starter_data/src/transaction/platform_transaction_manager.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_interceptor.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_template.dart';

const _source = 'package:spring_boot_starter_data#DataAutoConfiguration';

/// Builds the [AuditingHandler] that the `@EnableDataAuditing` annotation
/// found on a bean of [beans] describes: the starter's `auditingHandler`
/// bean is made by it.
///
/// - `auditorAwareRef`: the name of the [AuditorAware] bean to use; empty
///   (the default) takes the only `AuditorAware` bean there is, and none
///   at all means the `@CreatedBy` and `@LastModifiedBy` properties stay
///   untouched. Several beans without a reference is an error.
/// - `dateTimeProviderRef`: the name of the [DateTimeProvider] bean; empty
///   takes the only `DateTimeProvider` bean, else the system clock.
/// - `setDates` and `modifyOnCreate` as the annotation sets them.
///
/// A reference naming no bean, or a bean of another type, throws a
/// `StateError` that stops the application at startup. Where several
/// beans carry the annotation, the first one's settings count.
///
/// Spring (Java): `AuditingBeanDefinitionParser` / `AuditingHandler`
/// registered by `@EnableJdbcAuditing` (`JdbcAuditingRegistrar`).
AuditingHandler auditingHandlerFromAnnotation(
  ConfigurableListableBeanFactory beans,
  EntityConverter converter,
) {
  final owner = beans.getBeanNamesForAnnotation<EnableDataAuditing>().first;
  final settings = beans.findAnnotationOnBean<EnableDataAuditing>(owner)!;
  final auditor = _bean<AuditorAware<Object?>>(
    beans,
    settings.auditorAwareRef,
    'AuditorAware',
    'auditorAwareRef',
  );
  final clock = _bean<DateTimeProvider>(
    beans,
    settings.dateTimeProviderRef,
    'DateTimeProvider',
    'dateTimeProviderRef',
  );
  return AuditingHandler(
    converter: converter,
    auditorAware: auditor as AuditorAware<Object>?,
    dateTimeProvider: clock ?? const DateTimeProvider(),
    setDates: settings.setDates,
    modifyOnCreate: settings.modifyOnCreate,
  );
}

// The bean [reference] names, else the only bean whose type is called
// [typeName] (a generic type such as AuditorAware<String> is found by its
// name, whatever its type argument is); null when there is none.
T? _bean<T extends Object>(
  ConfigurableListableBeanFactory beans,
  String reference,
  String typeName,
  String attribute,
) {
  if (reference.isNotEmpty) {
    if (!beans.containsBean(reference)) {
      throw StateError(
        '@EnableDataAuditing($attribute: "$reference"): no bean has this '
        'name',
      );
    }
    final bean = beans.getBeanByName(reference);
    if (bean is! T) {
      throw StateError(
        '@EnableDataAuditing($attribute: "$reference"): the bean is a '
        '${bean.runtimeType}, not a $typeName',
      );
    }
    return bean;
  }
  final names = [
    for (final name in beans.beanDefinitionNames)
      if (beans
          .getBeanDefinition(name)
          .types
          .any((type) => '$type'.split('<').first == typeName))
        name,
  ];
  if (names.isEmpty) {
    return null;
  }
  if (names.length > 1) {
    throw StateError(
      'Several $typeName beans (${names.join(', ')}): name the one to use '
      'with @EnableDataAuditing($attribute: ...)',
    );
  }
  return beans.getBeanByName(names.single) as T;
}

/// The longest a memory store waits for a row lock:
/// `spring.data.memory.lock-timeout` (a duration such as `500ms` or
/// `10s`), 10 seconds by default. A negative value is an error that stops
/// the start; zero fails at once, as `nowait` does.
Duration memoryLockTimeout(Environment environment) {
  const key = 'spring.data.memory.lock-timeout';
  final value = environment.getPropertyAs<Duration>(key);
  if (value != null && value.isNegative) {
    throw ArgumentError.value('$value', key, 'must not be negative');
  }
  return value ?? const Duration(seconds: 10);
}

/// The bean definitions the Data starter adds to every application that
/// lists it. The repository beans themselves are registered by the
/// generator (every non-generic interface extending `DataRepository`); these
/// are what they need:
///
/// - `relationalMappingContext` — the entities (`@Table` classes) known to
///   the application's `BeanIntrospector`, named by the application's
///   [NamingStrategy] bean when it has one;
/// - `entityConverter` — turns entities into rows and back;
/// - `inMemoryDataStore` — the store behind repositories that name none
///   (`@UseStore('memory')`), waiting at most
///   `spring.data.memory.lock-timeout` for a row lock (10 seconds by
///   default);
/// - `inMemoryDataSources` — the stores of `@UseDataSource` names (one per
///   name, `memory:<name>`), shared by the repositories and the managers
///   below;
/// - `transactionManager` — an `InMemoryTransactionManager` of the default
///   memory store, unless the application declares a
///   `PlatformTransactionManager`. For each `@UseDataSource('x')` memory
///   repository the `dataSourceTransactionManagerRegistrar` adds a
///   fallback manager bean `xTransactionManager`, qualified `x`, over the
///   store of `x`: `@Transactional(transactionManager: 'x')`;
/// - `auditingHandler` — only when a bean's class carries
///   `@EnableDataAuditing`: fills `@CreatedDate`, `@LastModifiedDate`,
///   `@CreatedBy` and `@LastModifiedBy` on save, with the application's
///   [AuditorAware] and [DateTimeProvider] beans (see
///   [auditingHandlerFromAnnotation]);
/// - `repositoryFactory` — builds the handler of each repository with the
///   mapping context, the converter, every [DataStore] bean and the
///   auditing handler, and fails the startup with the reasons when a
///   repository is wrong;
/// - `transactionInterceptor`, `transactionValidator` and
///   `transactionAdvisor` — `@Transactional` on bean methods: the
///   interceptor runs them in transactions, the validator fails the
///   startup for a method that is not async or a transaction manager that
///   does not exist, and the advisor applies the interceptor to the
///   annotated methods. The advisor has the lowest precedence, so it is the
///   innermost: advice with a higher precedence (a future `@Retryable`)
///   wraps the transaction, and each retry gets a fresh one;
/// - `transactionTemplate` — a `TransactionTemplate` of the application's
///   only (or primary, or non-fallback) `PlatformTransactionManager`, when
///   there is one.
///
/// Each bean is made only when the application declares none of its type,
/// so an application replaces any of them by declaring its own.
///
/// Spring Boot's counterpart is `JdbcRepositoriesAutoConfiguration` and
/// `JdbcTemplateAutoConfiguration`, with `@EnableJdbcAuditing` for the
/// auditing.
final dataAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<RelationalMappingContext>(
    name: 'relationalMappingContext',
    // A @Bean method: its bean conditions are decided when it is read.
    factoryMethodName: 'relationalMappingContext',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.relationalMappingContext', [
        ConditionalOnMissingBean(RelationalMappingContext),
      ]),
    ],
    create: (r) => RelationalMappingContext(
      introspector: r.dependency<BeanIntrospector>(),
      namingStrategy:
          r.optionalDependency<NamingStrategy>() ?? const NamingStrategy(),
    ),
  ),
  BeanDefinition<EntityConverter>(
    name: 'entityConverter',
    factoryMethodName: 'entityConverter',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.entityConverter', [
        ConditionalOnMissingBean(EntityConverter),
      ]),
    ],
    create: (r) =>
        EntityConverter(introspector: r.dependency<BeanIntrospector>()),
  ),
  BeanDefinition<InMemoryDataStore>(
    name: 'inMemoryDataStore',
    factoryMethodName: 'inMemoryDataStore',
    types: const [InMemoryDataStore, DataStore],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.inMemoryDataStore', [
        ConditionalOnMissingBean(InMemoryDataStore),
      ]),
    ],
    create: (r) => InMemoryDataStore(
      converter: r.dependency<EntityConverter>(),
      lockTimeout: memoryLockTimeout(r.dependency<Environment>()),
    ),
  ),
  BeanDefinition<InMemoryDataSources>(
    name: 'inMemoryDataSources',
    factoryMethodName: 'inMemoryDataSources',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.inMemoryDataSources', [
        ConditionalOnMissingBean(InMemoryDataSources),
      ]),
    ],
    create: (r) => InMemoryDataSources(
      converter: r.dependency<EntityConverter>(),
      lockTimeout: memoryLockTimeout(r.dependency<Environment>()),
    ),
  ),
  BeanDefinition<InMemoryTransactionManager>(
    name: 'transactionManager',
    factoryMethodName: 'transactionManager',
    types: const [InMemoryTransactionManager, PlatformTransactionManager],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.transactionManager', [
        ConditionalOnMissingBean(PlatformTransactionManager),
      ]),
    ],
    create: (r) =>
        InMemoryTransactionManager(r.dependency<InMemoryDataStore>()),
  ),
  BeanDefinition<DataSourceTransactionManagerRegistrar>(
    name: 'dataSourceTransactionManagerRegistrar',
    types: const [
      DataSourceTransactionManagerRegistrar,
      BeanDefinitionRegistryPostProcessor,
      BeanFactoryPostProcessor,
    ],
    source: _source,
    create: (_) => DataSourceTransactionManagerRegistrar(),
  ),
  BeanDefinition<AuditingHandler>(
    name: 'auditingHandler',
    factoryMethodName: 'auditingHandler',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.auditingHandler', [
        ConditionalOnBean.where(annotations: [EnableDataAuditing]),
        ConditionalOnMissingBean(AuditingHandler),
      ]),
    ],
    create: (r) => auditingHandlerFromAnnotation(
      r.dependency<BeanFactory>() as ConfigurableListableBeanFactory,
      r.dependency<EntityConverter>(),
    ),
  ),
  BeanDefinition<RepositoryFactory>(
    name: 'repositoryFactory',
    factoryMethodName: 'repositoryFactory',
    types: const [RepositoryFactory, InvocationHandlerFactory],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.repositoryFactory', [
        ConditionalOnMissingBean(RepositoryFactory),
      ]),
    ],
    create: (r) => RepositoryFactory(
      mappingContext: r.dependency<RelationalMappingContext>(),
      converter: r.dependency<EntityConverter>(),
      stores: r.optionalDependencyList<DataStore>() ?? const [],
      dataSources: r.dependency<InMemoryDataSources>(),
      auditing: r.optionalDependency<AuditingHandler>(),
    ),
  ),
  BeanDefinition<TransactionInterceptor>(
    name: 'transactionInterceptor',
    types: const [TransactionInterceptor, MethodInterceptor],
    source: _source,
    create: (r) => TransactionInterceptor(
      beanFactory: r.dependency<BeanFactory>(),
      introspector: r.dependency<BeanIntrospector>(),
    ),
  ),
  BeanDefinition<TransactionValidator>(
    name: 'transactionValidator',
    types: const [TransactionValidator, BeanPostProcessor, BeanFactoryAware],
    source: _source,
    create: (_) => TransactionValidator(),
  ),
  BeanDefinition<DefaultPointcutAdvisor>(
    name: 'transactionAdvisor',
    types: const [DefaultPointcutAdvisor, PointcutAdvisor, Advisor, Ordered],
    source: _source,
    create: (r) => DefaultPointcutAdvisor(
      const TransactionAnnotationPointcut(),
      r.dependency<TransactionInterceptor>(),
    ),
  ),
  BeanDefinition<TransactionTemplate>(
    name: 'transactionTemplate',
    factoryMethodName: 'transactionTemplate',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.transactionTemplate', [
        ConditionalOnSingleCandidate(PlatformTransactionManager),
        ConditionalOnMissingBean(TransactionTemplate),
      ]),
    ],
    create: (r) =>
        TransactionTemplate(r.dependency<PlatformTransactionManager>()),
  ),
];
