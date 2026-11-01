import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source_properties.dart';
import 'package:spring_boot_starter_data/src/schema/schema_exceptions.dart';

/// Explains the startup failures of the database as an
/// `APPLICATION FAILED TO START` report instead of a stack trace: a URL
/// no driver handles, a migration that failed, a schema that does not fit
/// the entities, a database that cannot be reached.
///
/// The starter declares it as the `dataFailureAnalyzer` bean; applications
/// do not use it. It looks through the causes of the error (a failure while
/// a bean is created arrives wrapped in a `BeanCreationException`) and
/// explains the outermost problem it knows.
///
/// ```text
/// Description:
///
/// Failed to configure the data source: spring.datasource.url is
/// sqlite:file:books.db — add the sqlite3 package to your dependencies (no
/// driver handles the scheme "sqlite"; the application has no driver at all)
///
/// Action:
///
/// Add the sqlite3 package to the dependencies of the application
/// (pubspec.yaml) and run the code generator again.
/// ```
///
/// Spring (Java): `DataSourceBeanCreationFailureAnalyzer`,
/// `FlywayMigrationScriptMissingFailureAnalyzer` and the analyzers of
/// Spring Boot's JDBC support.
final class DataFailureAnalyzer implements FailureAnalyzer {
  /// The analyzer; it has no state.
  const DataFailureAnalyzer();

  @override
  FailureAnalysis? analyze(Object failure) {
    BeanCreationException? bean;
    for (final error in _chain(failure)) {
      if (error is BeanCreationException) {
        bean = error;
      }
      final analysis = _explain(error, failure, bean);
      if (analysis != null) {
        return analysis;
      }
    }
    return null;
  }

  static Iterable<Object> _chain(Object failure) sync* {
    Object? current = failure;
    while (current != null) {
      yield current;
      current = switch (current) {
        BeansException(:final cause) => cause,
        DataAccessException(:final cause) => cause,
        _ => null,
      };
    }
  }

  // [bean] is the failed bean closest to [error] in the chain.
  static FailureAnalysis? _explain(
    Object error,
    Object failure,
    BeanCreationException? bean,
  ) => switch (error) {
    DataSourceConfigurationException(:final message, :final action) =>
      FailureAnalysis(
        'Failed to configure the data source: $message',
        action,
        failure,
      ),
    SchemaValidationException(:final message) => FailureAnalysis(
      'The database schema does not fit the entities. $message',
      'Add a migration that creates or changes what is missing (a file '
          'such as db/migration/V2__add_column.sql), or change the '
          'entity. spring.data.jdbc.schema=none switches the check '
          'off, and create or create-drop builds the tables from the '
          'entities (for tests and prototypes, without migrations).',
      failure,
    ),
    MigrationException(:final message) => FailureAnalysis(
      'A database migration failed. $message',
      'Fix the migration file named above. A migration that failed was '
          'rolled back, so the database is at the previous version; '
          'a migration that was applied must never be edited, add a '
          'new one instead.',
      failure,
    ),
    ScriptException(:final message) => FailureAnalysis(
      'A database script failed. $message',
      'Fix the script named above, or set spring.sql.init.mode=never '
          'to skip the scripts.',
      failure,
    ),
    SchemaException(:final message) => FailureAnalysis(
      'The database could not be set up. $message',
      'Check the spring.sql.* and spring.data.jdbc.schema properties '
          'named above.',
      failure,
    ),
    // The core's refusal of a synchronous refresh: the data source (or
    // what waits for it) sets up the schema asynchronously.
    StateError(:final message)
        when message.startsWith('An init callback returned a Future') &&
            bean != null =>
      FailureAnalysis(
        'The application was started synchronously, and the bean '
            "'${bean.beanName}' needs asynchronous startup. With a SQL "
            'data source the schema is checked and migrated on a connection, '
            'which Dart cannot wait for without await, so the context must '
            'be refreshed with refreshAsync().',
        'Start the application with `await runApplicationAsync(args)` '
            '(SpringApplication.runAsync) instead of runApplication(args); '
            'in a test, ApplicationContextRunner.runAsync.',
        failure,
      ),
    CannotGetJdbcConnectionException(:final message) => FailureAnalysis(
      'The application could not connect to the database. $message',
      'Check that the database is running and that '
          'spring.datasource.url, username and password (or the '
          'spring.datasources.<name> ones) are right. The pool waits '
          'at most spring.datasource.pool.connection-timeout.',
      failure,
    ),
    _ => null,
  };
}
