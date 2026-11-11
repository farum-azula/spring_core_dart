import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source_utils.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';

/// Prepares the database session of a JDBC connection for the work about
/// to run on it, and cleans it before the connection goes back to the
/// pool: the way to run every statement as the current user (a role and
/// the user's claims for row-level security), to set a tenant, a search
/// path or a time zone.
///
/// Declare a bean of this type (or several, run in `@Order`); the starter
/// gives them to every `DataSource` bean, and the JDBC infrastructure
/// calls them at its two doors:
///
/// - **a transaction** (`DataSourceTransactionManager`): [afterBegin]
///   runs right after the transaction began on its connection, before
///   any statement of the application. Set what must last for the
///   transaction with transaction scope (`set local role ...`,
///   `select set_config('request.jwt.claims', ?, true)`): the database
///   drops it at commit or rollback, so nothing is left on the connection
///   and nothing needs cleaning. When a transaction is begun again on its
///   connection (SQLite's upgrade to a writer for a `@Lock` query),
///   [afterBegin] runs again.
/// - **work outside a transaction** (`JdbcTemplate`, `JdbcClient`, the
///   repositories, through `DataSourceUtils.getConnection` and
///   `releaseConnection`): [beforeWork] runs on the pooled connection
///   before the first statement, and [afterWork] before the connection
///   goes back to the pool, in the reverse order of the hooks. One unit
///   of work is one call of the template (a statement, a batch, a stream
///   until it ends or is cancelled, a `executeWithConnection` callback).
///   Session state set in [beforeWork] must be undone in [afterWork]
///   (`reset role`), as the next user of the connection is someone else.
///
/// A hook runs its statements on the connection it is given
/// (`connection.execute`, `connection.query`), never through a template
/// (which would ask for the hooks again).
///
/// **Failures.** An error of [afterBegin] fails the transaction's begin
/// (a `CannotCreateTransactionException` for an error of the database),
/// and an error of [beforeWork] fails the work (translated to a
/// `DataAccessException` for an error of the database); the connection is
/// closed, so it never serves with half a preparation. An error of
/// [afterWork] closes the connection too, so it does not go back to the
/// pool with state left on it; the work is done by then, so its result
/// stands and the error is logged as a warning.
///
/// What does not go through the hooks: the schema initializer and the
/// migrations (they run as the owner of the schema), the health
/// indicator's validation, and code that takes connections from the
/// `DataSource` itself.
///
/// A hook must not depend on a `DataSource` (or on a bean made from one):
/// it is created with the first data source.
///
/// ```dart
/// @Component()
/// class CurrentUserSession extends JdbcSessionHook {
///   CurrentUserSession(this.users);
///
///   final CurrentUser users;
///
///   @override
///   Future<void> afterBegin(ConnectionHolder transaction) async {
///     await transaction.connection.query(
///       "select set_config('app.user', ?, true)",
///       [users.id],
///     );
///   }
///
///   @override
///   Future<void> beforeWork(
///     DataSource dataSource,
///     JdbcConnection connection,
///   ) async {
///     await connection.query(
///       "select set_config('app.user', ?, false)",
///       [users.id],
///     );
///   }
///
///   @override
///   Future<void> afterWork(
///     DataSource dataSource,
///     JdbcConnection connection,
///   ) => connection.execute('reset app.user');
/// }
/// ```
///
/// Spring (Java): `DataSourceTransactionManager.
/// prepareTransactionalConnection` (a protected method to override, for
/// the transaction's door) and a `DataSource` adapter overriding
/// `getConnection` (`UserCredentialsDataSourceAdapter`,
/// `IsolationLevelDataSourceAdapter`) for the other; here one bean covers
/// both.
abstract class JdbcSessionHook {
  /// A hook that does nothing until its methods are overridden.
  const JdbcSessionHook();

  /// Runs right after a transaction began on the connection of
  /// [transaction] (its `connection`, `dataSource`, `readOnly`,
  /// `isolation`, `name`), before any statement of the application.
  Future<void> afterBegin(ConnectionHolder transaction) async {}

  /// Runs on a pooled [connection] of [dataSource] taken for work outside
  /// a transaction, before its first statement.
  Future<void> beforeWork(
    DataSource dataSource,
    JdbcConnection connection,
  ) async {}

  /// Runs after the work outside a transaction, before [connection] goes
  /// back to the pool of [dataSource]: undo here what [beforeWork] set.
  /// Not called for a connection that is closed (broken) by then.
  Future<void> afterWork(
    DataSource dataSource,
    JdbcConnection connection,
  ) async {}
}

/// Gives the [JdbcSessionHook] beans, in their order, to every
/// `DataSource` bean when it is created (the starter's own data sources
/// and the application's), so the JDBC infrastructure finds them on the
/// data source it works with.
///
/// The starter declares it as the `jdbcSessionHookRegistrar` bean. A data
/// source that is not a bean gets its hooks by hand:
/// `dataSource.sessionHooks.add(hook)`.
///
/// Spring (Java): none; Spring's hooks are overridden methods, not beans.
final class JdbcSessionHookRegistrar extends BeanPostProcessor {
  /// A registrar that asks [resolver] for the hooks.
  JdbcSessionHookRegistrar(this.resolver);

  /// Finds the hook beans, in order.
  final DependencyResolver resolver;

  @override
  Object postProcessBeforeInitialization(Object bean, String beanName) {
    if (bean is DataSource) {
      final hooks =
          resolver.optionalDependencyList<JdbcSessionHook>() ?? const [];
      for (final hook in hooks) {
        if (!bean.sessionHooks.contains(hook)) {
          bean.sessionHooks.add(hook);
        }
      }
    }
    return bean;
  }
}
