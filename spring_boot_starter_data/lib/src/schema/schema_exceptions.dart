import 'package:spring_boot_starter_data/src/exceptions.dart';

/// A failure of the database setup at startup: a script, a migration, the
/// validation of the schema or its creation. It stops the start; its
/// message names the file, the line or the entity, never a value.
///
/// Spring (Java): `org.springframework.jdbc.datasource.init.
/// ScriptException` and Flyway's `FlywayException`, in one family.
class SchemaException extends NonTransientDataAccessException {
  /// A failure described by [message], caused by [cause] when there is one.
  SchemaException(super.message, {super.cause});
}

/// A script that could not be read, split or run: the message names the
/// script, and for a failed statement its number and its line.
///
/// Spring (Java):
/// `org.springframework.jdbc.datasource.init.ScriptStatementFailedException`.
class ScriptException extends SchemaException {
  /// A failure of the script described as [script].
  ScriptException(
    super.message, {
    this.script,
    this.statementNumber,
    this.line,
    super.cause,
  });

  /// The description of the script (`class path resource [schema.sql]`).
  final String? script;

  /// The 1-based number of the failed statement in the script.
  final int? statementNumber;

  /// The 1-based line of the script where the failed statement starts.
  final int? line;
}

/// A migration that cannot be applied, or a history that does not match
/// the files: the start stops, naming the file.
///
/// Spring (Java): Flyway's `FlywayException` and `FlywayValidateException`.
class MigrationException extends SchemaException {
  /// A failure described by [message].
  MigrationException(super.message, {this.script, super.cause});

  /// The file of the migration involved, when one is.
  final String? script;
}

/// The schema of the database does not fit the entities: one error lists
/// every problem.
///
/// Spring (Java): Hibernate's `SchemaManagementException` of
/// `hbm2ddl=validate`.
class SchemaValidationException extends SchemaException {
  /// A failure with the [problems] found.
  SchemaValidationException(this.problems)
    : super(
        'Schema validation failed with ${problems.length} problem'
        '${problems.length == 1 ? '' : 's'}:\n'
        '${problems.map((p) => '  - $p').join('\n')}',
      );

  /// One line per problem.
  final List<String> problems;
}
