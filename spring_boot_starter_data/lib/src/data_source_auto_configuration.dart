import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/data_failure_analyzer.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source_properties.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source_transaction_manager.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_client.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_template.dart';
import 'package:spring_boot_starter_data/src/jdbc/named_parameter_jdbc_template.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_logging.dart';
import 'package:spring_boot_starter_data/src/mapping/mapping_context.dart';
import 'package:spring_boot_starter_data/src/properties/data_properties.dart';
import 'package:spring_boot_starter_data/src/properties_binding.dart';
import 'package:spring_boot_starter_data/src/schema/database_initializer.dart';
import 'package:spring_boot_starter_data/src/schema/initializing_data_source.dart';
import 'package:spring_boot_starter_data/src/schema/repository_entities.dart';
import 'package:spring_boot_starter_data/src/store/in_memory_data_sources.dart';
import 'package:spring_boot_starter_data/src/transaction/platform_transaction_manager.dart';

const _source = 'package:spring_boot_starter_data#DataSourceAutoConfiguration';

/// `spring.jdbc.template.query-timeout`: how long a statement of a
/// `JdbcTemplate` bean may run, null (no limit) when it is not set.
///
/// A value that is not a duration (`500ms`, `10s`, `PT5S`, milliseconds) or
/// is negative is an error that stops the start.
Duration? jdbcQueryTimeout(Environment environment) {
  final value = bindSettings<JdbcTemplateProperties>(
    environment,
    'spring.jdbc.template',
    fallback: const JdbcTemplateProperties(),
    onInvalid: (failure) => throw ArgumentError.value(
      failure.value,
      failure.property,
      'must be a duration such as 500ms or 10s',
    ),
  ).queryTimeout;
  if (value != null && value.isNegative) {
    throw ArgumentError.value(
      '$value',
      'spring.jdbc.template.query-timeout',
      'must not be negative',
    );
  }
  return value;
}

/// The switches `spring.data.jdbc.show-sql`, `format-sql`,
/// `show-parameters` and `slow-query-threshold` (a duration) as
/// [JdbcLogSettings]; everything off by default. A value that is not a
/// boolean or a duration stops the start.
JdbcLogSettings jdbcLogSettingsOf(Environment environment) {
  final jdbc = bindSettings<DataJdbcProperties>(
    environment,
    'spring.data.jdbc',
    fallback: const DataJdbcProperties(),
    onInvalid: (failure) {
      // The schema mode is checked where the schema is set up.
      if (failure.type == 'SchemaMode') {
        return;
      }
      throw ArgumentError.value(
        failure.value,
        failure.property,
        failure.type == 'Duration'
            ? 'must be a duration such as 500ms or 2s'
            : 'must be ${failure.expected}',
      );
    },
  );
  final threshold = jdbc.slowQueryThreshold;
  if (threshold != null && threshold.isNegative) {
    throw ArgumentError.value(
      '$threshold',
      'spring.data.jdbc.slow-query-threshold',
      'must not be negative',
    );
  }
  return JdbcLogSettings(
    showSql: jdbc.showSql,
    showParameters: jdbc.showParameters,
    formatSql: jdbc.formatSql,
    slowQueryThreshold: threshold,
  );
}

/// Makes the data source the properties under [prefix] describe, with its
/// schema set up by a [DatabaseInitializer] that reads the keys under
/// [initializerPrefix]: the pool opens when first used, the schema is
/// applied at startup and before any other use (see
/// [InitializingDataSource]).
///
/// [name] is the data source's name in logs; [dataSource] is the
/// `spring.datasources` name (null for the primary one), which says what
/// repositories it serves.
///
/// Throws a `DataSourceConfigurationException` when the properties or the
/// driver are wrong.
InitializingDataSource createInitializingDataSource(
  DependencyResolver r, {
  required String prefix,
  required String initializerPrefix,
  required String name,
  String? dataSource,
}) {
  final environment = r.dependency<Environment>();
  final properties = DataSourceProperties.fromEnvironment(
    environment,
    prefix: prefix,
    name: name,
  );
  final pool = properties.createPool(
    r.optionalDependencyList<JdbcDriver>() ?? const [],
  );
  final mapping = r.dependency<RelationalMappingContext>();
  final beans = r.dependency<BeanFactory>() as ConfigurableListableBeanFactory;
  final initializer = DatabaseInitializer.fromEnvironment(
    pool,
    environment,
    prefix: initializerPrefix,
    entities: RepositoryEntities(
      beans: beans,
      mappingContext: mapping,
      dataSource: dataSource,
    ),
    resourceLoader: r.dependency<ResourceLoader>(),
    naming: mapping.namingStrategy,
  );
  return InitializingDataSource(pool, initializer);
}

/// The data sources among the beans of [beans], by the name a repository
/// gives them: the primary one under [primaryName], and each qualifier of
/// a `DataSource` bean (`spring.datasources.shop.*` gives the qualifier
/// `shop`) under that name.
///
/// The primary data source is the bean named `dataSource` or, when there
/// is none, the only `DataSource` bean without a qualifier.
Map<String, DataSource> dataSourcesByName(
  ConfigurableListableBeanFactory beans,
  String primaryName,
) {
  final result = <String, DataSource>{};
  final unqualified = <String>[];
  for (final name in beans.getBeanNamesForType(DataSource)) {
    final qualifiers = beans.containsBeanDefinition(name)
        ? beans.getBeanDefinition(name).qualifiers
        : const <String>{};
    if (qualifiers.isEmpty) {
      unqualified.add(name);
      continue;
    }
    final bean = beans.getBeanByName(name) as DataSource;
    for (final qualifier in qualifiers) {
      result.putIfAbsent(qualifier, () => bean);
    }
  }
  final primary = unqualified.contains('dataSource')
      ? 'dataSource'
      : unqualified.length == 1
      ? unqualified.single
      : null;
  if (primary != null) {
    result[primaryName] = beans.getBeanByName(primary) as DataSource;
  }
  return result;
}

/// Sets up the schema of a `DataSource` bean that the application declared
/// itself: the starter's own data sources do it by themselves (see
/// [InitializingDataSource]).
///
/// It runs the [DatabaseInitializer] when the bean is made (the context
/// awaits it before the application starts) and drops what `create-drop`
/// made when the context closes. Unlike the starter's own data source, the
/// application's one does not wait for the schema on its first use, so
/// code that starts a query while the context is still being built (a
/// synchronous `@PostConstruct`) may be early.
///
/// Spring (Java): `DataSourceScriptDatabaseInitializer` /
/// `FlywayMigrationInitializer` over the application's `DataSource`.
final class DataSourceInitialization
    implements InitializingBean, DisposableBean {
  /// An initialization of the schema by [initializer].
  DataSourceInitialization(this.initializer);

  /// Does the work.
  final DatabaseInitializer initializer;

  @override
  Future<void> afterPropertiesSet() => initializer.initialize();

  @override
  Future<void> destroy() => initializer.close();
}

/// Registers the beans of the databases named under `spring.datasources`:
/// for each name `shop`, `shopDataSource` (an [InitializingDataSource]),
/// `shopTransactionManager` (a [DataSourceTransactionManager]),
/// `shopJdbcTemplate`, `shopNamedParameterJdbcTemplate` and
/// `shopJdbcClient`, all qualified `shop` and all fallbacks, so injection
/// by type still finds the primary beans.
///
/// A `DataSource` of the application, named so or qualified with the name,
/// replaces the whole group of that name (the application then declares
/// the manager and the templates it wants); a bean of the same name as one
/// of the others is left alone. The names come from properties that list
/// their keys (not from an environment variable alone).
///
/// The starter registers it; applications do not use it.
///
/// Spring (Java): a `BeanDefinitionRegistryPostProcessor`, as Spring Boot
/// uses to register one bean per configured entry; Boot itself configures
/// only one `DataSource` from properties.
final class DataSourceRegistrar implements BeanDefinitionRegistryPostProcessor {
  /// A registrar reading the names from [environment].
  DataSourceRegistrar(this.environment);

  /// Where the names and settings come from.
  final Environment environment;

  @override
  void postProcessBeanDefinitionRegistry(BeanDefinitionRegistry registry) {
    for (final name in DataSourceProperties.namedDataSources(environment)) {
      final prefix = DataSourceProperties.prefixOf(name);
      final dataSourceName = '${name}DataSource';
      final templateName = '${name}JdbcTemplate';
      final namedName = '${name}NamedParameterJdbcTemplate';
      bool taken(String beanName, Type type) =>
          registry.beanDefinitionNames.any((other) {
            final definition = registry.getBeanDefinition(other);
            return other == beanName ||
                (definition.qualifiers.contains(name) &&
                    definition.types.contains(type));
          });
      final ours = !taken(dataSourceName, DataSource);
      if (ours) {
        registry.registerBeanDefinition(
          BeanDefinition<InitializingDataSource>(
            name: dataSourceName,
            types: const [InitializingDataSource, DataSource],
            qualifiers: {name},
            fallback: true,
            source: _source,
            create: (r) => createInitializingDataSource(
              r,
              prefix: prefix,
              initializerPrefix: prefix,
              name: name,
              dataSource: name,
            ),
          ),
        );
      }
      // The others work on this registrar's data source.
      if (!ours) {
        continue;
      }
      final managerName = DataSourceTransactionManagerRegistrar.beanNameOf(
        name,
      );
      if (!taken(managerName, PlatformTransactionManager)) {
        registry.registerBeanDefinition(
          BeanDefinition<DataSourceTransactionManager>(
            name: managerName,
            types: const [
              DataSourceTransactionManager,
              PlatformTransactionManager,
            ],
            qualifiers: {name},
            fallback: true,
            source: _source,
            create: (r) => DataSourceTransactionManager(
              r.dependency<BeanFactory>().getBeanByName(dataSourceName)
                  as DataSource,
            ),
          ),
        );
      }
      if (!taken(templateName, JdbcTemplate)) {
        registry.registerBeanDefinition(
          BeanDefinition<JdbcTemplate>(
            name: templateName,
            qualifiers: {name},
            fallback: true,
            source: _source,
            create: (r) => _jdbcTemplate(
              r,
              r.dependency<BeanFactory>().getBeanByName(dataSourceName)
                  as DataSource,
            ),
          ),
        );
      }
      if (!taken(namedName, NamedParameterJdbcTemplate)) {
        registry.registerBeanDefinition(
          BeanDefinition<NamedParameterJdbcTemplate>(
            name: namedName,
            qualifiers: {name},
            fallback: true,
            source: _source,
            create: (r) => NamedParameterJdbcTemplate(
              r.dependency<BeanFactory>().getBeanByName(templateName)
                  as JdbcTemplate,
            ),
          ),
        );
      }
      if (!taken('${name}JdbcClient', JdbcClient)) {
        registry.registerBeanDefinition(
          BeanDefinition<JdbcClient>(
            name: '${name}JdbcClient',
            qualifiers: {name},
            fallback: true,
            source: _source,
            create: (r) => JdbcClient.fromTemplate(
              r.dependency<BeanFactory>().getBeanByName(templateName)
                  as JdbcTemplate,
            ),
          ),
        );
      }
    }
  }

  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {}
}

JdbcTemplate _jdbcTemplate(DependencyResolver r, DataSource dataSource) =>
    JdbcTemplate(
      dataSource,
      queryTimeout: jdbcQueryTimeout(r.dependency<Environment>()),
      logSettings:
          r.optionalDependency<JdbcLogSettings>() ?? const JdbcLogSettings(),
      introspector: r.dependency<BeanIntrospector>(),
    );

/// The bean definitions that connect the application to SQL databases from
/// its properties, so that it only sets properties and lists a driver:
///
/// - `dataFailureAnalyzer` — explains startup failures of the database
///   (see `DataFailureAnalyzer`);
/// - `jdbcLogSettings` — `spring.data.jdbc.show-sql`, `format-sql`,
///   `show-parameters`, `slow-query-threshold`; the templates and the
///   repositories log as it says;
/// - `dataSource` — the primary data source, when
///   `spring.datasource.url` is set and the application declares no
///   `DataSource` of its own: a pool of `spring.datasource.pool.*` over the
///   driver (a `JdbcDriver` bean the generator wrote for each driver
///   package the application lists) whose scheme the URL has, with the
///   schema set up before first use; the pool closes when the context
///   does. It is `@Primary`;
/// - `dataSourceRegistrar` — for each `spring.datasources.<name>.url`, the
///   beans of the database `<name>` (see [DataSourceRegistrar]);
/// - `transactionManager` — a `DataSourceTransactionManager` of the single
///   `DataSource` (this one replaces the in-memory manager, which only
///   serves an application with no data source);
/// - `jdbcTemplate`, `namedParameterJdbcTemplate`, `jdbcClient` — over the
///   single `DataSource`, with `spring.jdbc.template.query-timeout`;
/// - `dataSourceInitialization` — the schema setup of a `DataSource` the
///   application declared itself.
///
/// Every bean is skipped when the application declares one of its type
/// (`@ConditionalOnMissingBean`), so an application replaces any of them.
///
/// Spring Boot's counterparts: `DataSourceAutoConfiguration`,
/// `DataSourceTransactionManagerAutoConfiguration`,
/// `JdbcTemplateAutoConfiguration`,
/// `NamedParameterJdbcTemplateAutoConfiguration`,
/// `JdbcClientAutoConfiguration`, `SqlInitializationAutoConfiguration` and
/// `FlywayAutoConfiguration` (here the migrations are the starter's own,
/// `spring.sql.migration.*`).
final dataSourceAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<DataFailureAnalyzer>(
    name: 'dataFailureAnalyzer',
    types: const [DataFailureAnalyzer, FailureAnalyzer],
    source: _source,
    create: (_) => const DataFailureAnalyzer(),
  ),
  BeanDefinition<JdbcLogSettings>(
    name: 'jdbcLogSettings',
    factoryMethodName: 'jdbcLogSettings',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.jdbcLogSettings', [
        ConditionalOnMissingBean(JdbcLogSettings),
      ]),
    ],
    create: (r) => jdbcLogSettingsOf(r.dependency<Environment>()),
  ),
  BeanDefinition<InitializingDataSource>(
    name: 'dataSource',
    factoryMethodName: 'dataSource',
    types: const [InitializingDataSource, DataSource],
    primary: true,
    source: _source,
    conditions: const [
      ConditionGroup('$_source.dataSource', [
        ConditionalOnProperty('spring.datasource.url'),
        ConditionalOnMissingBean(DataSource),
      ]),
    ],
    create: (r) => createInitializingDataSource(
      r,
      prefix: DataSourceProperties.primaryPrefix,
      initializerPrefix: 'spring.',
      name: DataSourceProperties.primaryName,
    ),
  ),
  BeanDefinition<DataSourceInitialization>(
    name: 'dataSourceInitialization',
    factoryMethodName: 'dataSourceInitialization',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.dataSourceInitialization', [
        ConditionalOnSingleCandidate(DataSource),
        ConditionalOnMissingBean(InitializingDataSource),
        ConditionalOnMissingBean(DataSourceInitialization),
      ]),
    ],
    create: (r) {
      final mapping = r.dependency<RelationalMappingContext>();
      return DataSourceInitialization(
        DatabaseInitializer.fromEnvironment(
          r.dependency<DataSource>(),
          r.dependency<Environment>(),
          entities: RepositoryEntities(
            beans:
                r.dependency<BeanFactory>() as ConfigurableListableBeanFactory,
            mappingContext: mapping,
          ),
          resourceLoader: r.dependency<ResourceLoader>(),
          naming: mapping.namingStrategy,
        ),
      );
    },
  ),
  BeanDefinition<DataSourceRegistrar>(
    name: 'dataSourceRegistrar',
    types: const [
      DataSourceRegistrar,
      BeanDefinitionRegistryPostProcessor,
      BeanFactoryPostProcessor,
    ],
    source: _source,
    create: (r) => DataSourceRegistrar(r.dependency<Environment>()),
  ),
  BeanDefinition<DataSourceTransactionManager>(
    name: 'transactionManager',
    factoryMethodName: 'transactionManager',
    types: const [DataSourceTransactionManager, PlatformTransactionManager],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.transactionManager', [
        ConditionalOnSingleCandidate(DataSource),
        ConditionalOnMissingBean(PlatformTransactionManager),
      ]),
    ],
    create: (r) => DataSourceTransactionManager(r.dependency<DataSource>()),
  ),
  BeanDefinition<JdbcTemplate>(
    name: 'jdbcTemplate',
    factoryMethodName: 'jdbcTemplate',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.jdbcTemplate', [
        ConditionalOnSingleCandidate(DataSource),
        ConditionalOnMissingBean(JdbcTemplate),
      ]),
    ],
    create: (r) => _jdbcTemplate(r, r.dependency<DataSource>()),
  ),
  BeanDefinition<NamedParameterJdbcTemplate>(
    name: 'namedParameterJdbcTemplate',
    factoryMethodName: 'namedParameterJdbcTemplate',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.namedParameterJdbcTemplate', [
        ConditionalOnSingleCandidate(JdbcTemplate),
        ConditionalOnMissingBean(NamedParameterJdbcTemplate),
      ]),
    ],
    create: (r) => NamedParameterJdbcTemplate(r.dependency<JdbcTemplate>()),
  ),
  BeanDefinition<JdbcClient>(
    name: 'jdbcClient',
    factoryMethodName: 'jdbcClient',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.jdbcClient', [
        ConditionalOnSingleCandidate(JdbcTemplate),
        ConditionalOnMissingBean(JdbcClient),
      ]),
    ],
    create: (r) => JdbcClient.fromTemplate(r.dependency<JdbcTemplate>()),
  ),
];
