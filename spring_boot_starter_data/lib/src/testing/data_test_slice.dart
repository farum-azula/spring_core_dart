import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_client.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_template.dart';
import 'package:spring_boot_starter_data/src/jdbc/named_parameter_jdbc_template.dart';
import 'package:spring_boot_starter_data/src/jdbc/sql_logging.dart';
import 'package:spring_boot_starter_data/src/mapping/auditing.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_converter.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_introspection.dart';
import 'package:spring_boot_starter_data/src/mapping/mapping_context.dart';
import 'package:spring_boot_starter_data/src/mapping/naming_strategy.dart';
import 'package:spring_boot_starter_data/src/repository/repository.dart';
import 'package:spring_boot_starter_data/src/repository/repository_factory.dart';
import 'package:spring_boot_starter_data/src/store/data_store.dart';
import 'package:spring_boot_starter_data/src/store/in_memory_data_sources.dart';
import 'package:spring_boot_starter_data/src/transaction/platform_transaction_manager.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_template.dart';

const _log = SpringLog('spring.data.test.DataTestSlice');

/// Removes the beans of an application that a `@DataTest` leaves out, before
/// any bean is created: its repositories and the other data beans stay, its
/// services, controllers and other components go.
///
/// A bean of the application stays when one of the types it is registered
/// under is a [dataTypes] (a repository is a `DataRepository`, an
/// `AuditorAware` bean is one), when its class carries
/// `@EnableDataAuditing`, or when it is one of the `include` types. Two more
/// stay with them: the configuration object that makes a kept `@Bean`
/// method's bean (a factory needs its instance, without the other `@Bean`
/// methods of it), and, for an `include` type that is a configuration class,
/// all its `@Bean` methods. Only the beans the application's modules declare
/// are judged: the auto-configurations of the starters and what a test adds
/// (`@TestBean`) are left alone.
///
/// The removal happens in the context, after its modules were read, so the
/// conditions of the beans (`@ConditionalOnProperty`...) were decided with
/// the whole application: a repository a property switches off stays off. A
/// kept bean that needs a left out one fails the start as it always does:
/// the report names the missing bean, and `include` it.
///
/// Spring (Java): the `TypeExcludeFilter` of `@DataJdbcTest`
/// (`DataJdbcTypeExcludeFilter`) in the component scan of a slice; here the
/// beans are listed by the generator at build time, so the filter works on
/// their types.
final class DataTestSlice implements BeanDefinitionRegistryPostProcessor {
  /// A slice of the application whose beans [modules] declare, with the
  /// beans of the [include] types added.
  DataTestSlice(
    Iterable<BeanModule> modules, {
    Iterable<Type> include = const [],
  }) : include = List.unmodifiable(include) {
    for (final definition in applicationDefinitions(modules)) {
      _application[definition.name] = definition.source;
    }
  }

  /// The types of the beans a slice keeps whatever the test says: the
  /// repositories, the entities' introspections, the database drivers, and
  /// the types the starter's auto-configuration looks up or replaces.
  static const Set<Type> dataTypes = {
    DataRepository<dynamic, dynamic>,
    EntityIntrospections,
    JdbcDriver,
    DataSource,
    DataStore,
    InMemoryDataSources,
    PlatformTransactionManager,
    TransactionTemplate,
    JdbcTemplate,
    NamedParameterJdbcTemplate,
    JdbcClient,
    JdbcLogSettings,
    RelationalMappingContext,
    EntityConverter,
    RepositoryFactory,
    NamingStrategy,
    AuditorAware<dynamic>,
    DateTimeProvider,
    AuditingHandler,
  };

  /// The beans added to the slice by the types of their classes.
  final List<Type> include;

  // The name and the source of every definition of the application's
  // modules: which definitions of the registry are the application's.
  final Map<String, String?> _application = {};

  /// Every definition of [modules] and of the modules they import, once.
  static List<BeanDefinition<Object>> applicationDefinitions(
    Iterable<BeanModule> modules,
  ) {
    final seen = Set<BeanModule>.identity();
    final found = <BeanDefinition<Object>>[];
    void visit(BeanModule module) {
      if (!seen.add(module)) {
        return;
      }
      module.imports.forEach(visit);
      found.addAll(module.definitions);
    }

    modules.forEach(visit);
    return found;
  }

  /// Whether a bean registered as [definition] is a data bean: one of its
  /// types is a [dataTypes] or its class carries `@EnableDataAuditing`.
  static bool isDataBean(BeanDefinition<Object> definition) =>
      definition.types.any(dataTypes.contains) ||
      definition.annotations.any((a) => a is EnableDataAuditing);

  bool _isApplication(BeanDefinition<Object> definition) =>
      _application.containsKey(definition.name) &&
      _application[definition.name] == definition.source;

  /// The names, among [definitions] (the application's, by bean name),
  /// of the beans the slice keeps.
  ///
  /// Throws a [StateError] when a type of [include] is the type of none of
  /// them.
  Set<String> keptNames(Map<String, BeanDefinition<Object>> definitions) {
    final kept = <String>{};
    final included = <String>{};
    for (final type in include) {
      final names = [
        for (final MapEntry(:key, :value) in definitions.entries)
          if (value.types.contains(type)) key,
      ];
      if (names.isEmpty) {
        throw StateError(
          '@DataTest(include: [$type]): no bean of the application has this '
          'type (a class is a bean when it is annotated @Component, @Service, '
          '@Configuration...)',
        );
      }
      included.addAll(names);
    }
    kept.addAll(included);
    for (final MapEntry(:key, :value) in definitions.entries) {
      if (isDataBean(value) || included.contains(value.factoryBeanName)) {
        kept.add(key);
      }
    }
    // A @Bean method needs the object of its configuration class.
    for (final name in kept.toList()) {
      final factory = definitions[name]!.factoryBeanName;
      if (factory != null && definitions.containsKey(factory)) {
        kept.add(factory);
      }
    }
    return kept;
  }

  @override
  void postProcessBeanDefinitionRegistry(BeanDefinitionRegistry registry) {
    final definitions = <String, BeanDefinition<Object>>{
      for (final name in registry.beanDefinitionNames)
        if (_isApplication(registry.getBeanDefinition(name)))
          name: registry.getBeanDefinition(name),
    };
    final kept = keptNames(definitions);
    final removed =
        definitions.keys.where((name) => !kept.contains(name)).toList()
          ..forEach(registry.removeBeanDefinition);
    _log.debug(
      () =>
          'Data slice: ${kept.length} beans of the application kept, '
          '${removed.length} left out: ${removed.join(', ')}',
    );
  }

  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {}
}
