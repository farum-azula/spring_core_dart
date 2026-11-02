/// Spring Data for `spring_boot_dart` applications: entities, repositories
/// whose implementations the generator writes, derived queries
/// (`findByTitleContaining`), paging and sorting, optimistic locking with
/// `@Version`, auditing.
///
/// An aggregate is a class marked `@Table`; a repository is an interface
/// extending `CrudRepository<Book, int>` (or `DataRepository` with only the
/// methods you declare). The generator implements it and makes it a bean:
///
/// ```dart
/// @Table('books')
/// class Book {
///   Book({this.id, required this.title, this.year});
///
///   @Id()
///   int? id;
///   String title;
///   int? year;
///
///   @Version()
///   int version = 0;
/// }
///
/// abstract interface class BookRepository
///     implements ListCrudRepository<Book, int> {
///   Future<List<Book>> findByTitleContainingIgnoreCase(String text);
///   Future<Page<Book>> findByYearGreaterThan(int year, Pageable page);
/// }
/// ```
///
/// The model is Spring Data JDBC's, not JPA's: an aggregate is loaded and
/// saved whole, `save` writes at once, other aggregates are referenced by
/// id. No driver is inside: the application adds the one it wants.
///
/// This import re-exports `spring_boot_starter_logging` and, through it,
/// `spring_boot_dart` and `spring_core_dart`. It is the Dart version of
/// Spring Boot's `spring-boot-starter-data-jdbc`.
library;

export 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';

export 'src/annotations.dart';
export 'src/data_auto_configuration.dart' show auditingHandlerFromAnnotation;
export 'src/data_failure_analyzer.dart';
export 'src/data_source_auto_configuration.dart'
    show
        DataSourceInitialization,
        DataSourceRegistrar,
        createInitializingDataSource,
        dataSourcesByName,
        jdbcLogSettingsOf,
        jdbcQueryTimeout;
export 'src/exceptions.dart';
export 'src/jdbc/data_source.dart';
export 'src/jdbc/data_source_properties.dart';
export 'src/jdbc/data_source_transaction_manager.dart';
export 'src/jdbc/data_source_utils.dart';
export 'src/jdbc/entity_row_mapper.dart';
export 'src/jdbc/jdbc_client.dart';
export 'src/jdbc/jdbc_driver.dart';
export 'src/jdbc/jdbc_template.dart';
export 'src/jdbc/named_parameter_jdbc_template.dart';
export 'src/jdbc/named_parameter_utils.dart';
export 'src/jdbc/postgres/postgres_binding.dart';
export 'src/jdbc/postgres/postgres_dialect.dart';
export 'src/jdbc/postgres/postgres_jdbc_driver.dart';
export 'src/jdbc/postgres/postgres_markers.dart';
export 'src/jdbc/row_mapper.dart';
export 'src/jdbc/sql_dialect.dart';
export 'src/jdbc/sql_logging.dart';
export 'src/jdbc/sqlite/sqlite_binding.dart';
export 'src/jdbc/sqlite/sqlite_dialect.dart';
export 'src/jdbc/sqlite/sqlite_jdbc_driver.dart';
export 'src/mapping/auditing.dart';
export 'src/mapping/entity_converter.dart';
export 'src/mapping/entity_introspection.dart';
export 'src/mapping/mapping_context.dart';
export 'src/mapping/naming_strategy.dart';
export 'src/mapping/persistent_entity.dart';
export 'src/query/part_tree.dart';
export 'src/repository/page.dart';
export 'src/repository/query/query_method.dart';
export 'src/repository/query/query_text.dart';
export 'src/repository/query/result_shaper.dart';
export 'src/repository/query/string_based_jdbc_query.dart';
export 'src/repository/repository.dart';
export 'src/repository/repository_factory.dart';
export 'src/repository/repository_operations.dart';
export 'src/repository/simple_repository.dart';
export 'src/repository/sort.dart';
export 'src/schema/database_initializer.dart';
export 'src/schema/initializing_data_source.dart';
export 'src/schema/migrations/migration_runner.dart';
export 'src/schema/migrations/migration_script.dart';
export 'src/schema/migrations/migration_settings.dart';
export 'src/schema/migrations/migration_source.dart';
export 'src/schema/migrations/migration_version.dart';
export 'src/schema/migrations/schema_history.dart';
export 'src/schema/repository_entities.dart';
export 'src/schema/schema_creator.dart';
export 'src/schema/schema_exceptions.dart';
export 'src/schema/schema_model.dart';
export 'src/schema/schema_support.dart' show SettingsReader;
export 'src/schema/schema_validator.dart';
export 'src/schema/script_database_initializer.dart';
export 'src/schema/script_utils.dart';
export 'src/store/data_store.dart';
export 'src/store/in_memory_data_sources.dart';
export 'src/store/in_memory_data_store.dart';
export 'src/store/in_memory_transaction.dart';
export 'src/store/in_memory_transaction_manager.dart';
export 'src/store/jdbc/jdbc_data_store.dart';
export 'src/store/jdbc/sql_generator.dart';
export 'src/store/row_locks.dart';
export 'src/store/stored_aggregate.dart';
export 'src/testing/data_test.dart';
export 'src/transaction/abstract_platform_transaction_manager.dart';
export 'src/transaction/platform_transaction_manager.dart';
export 'src/transaction/transaction_definition.dart';
export 'src/transaction/transaction_exceptions.dart';
export 'src/transaction/transaction_interceptor.dart';
export 'src/transaction/transaction_synchronization_manager.dart';
export 'src/transaction/transaction_template.dart' show TransactionTemplate;
export 'src/web/web_paging.dart';
