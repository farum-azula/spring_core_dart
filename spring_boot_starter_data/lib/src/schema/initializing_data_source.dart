import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/schema/database_initializer.dart';

/// The data source the application sees: a pool whose schema is set up
/// before its first connection, whoever asks for it.
///
/// The Data starter makes one for each database it configures from
/// properties. It owns the raw [pool] and the [DatabaseInitializer] that
/// works on that pool:
///
/// - at startup the context calls [afterPropertiesSet] (the bean's async
///   init), which runs the initializer and so applies the migrations and
///   checks the schema; a failure stops the start with its own message;
/// - [getConnection] waits for the same run to finish before it takes a
///   connection of the pool, so no code can read or write the database
///   before its schema is ready: not a repository, not a `JdbcTemplate`,
///   not a `CommandLineRunner`, and not an application bean whose
///   `@PostConstruct` starts a query while the context is still being
///   built (the context awaits async init callbacks only after it has
///   created all the beans, so no ordering of beans alone could promise
///   this);
/// - [destroy] drops the tables of `create-drop`, then closes the pool.
///
/// The initializer uses the pool itself, never this wrapper, so it does not
/// wait for itself. A failed initialization is not cached: the next
/// connection tries again (the same error reaches that caller too).
///
/// Everything else (transaction managers, templates, stores) is built over
/// this object, so they all share one transaction resource: the bean.
///
/// Spring (Java): none. Spring Boot orders the initializers before the
/// beans that use a `DataSource` (`DependsOnDatabaseInitialization`), which
/// works there because bean creation is synchronous; here the schema work
/// is asynchronous, so the data source itself waits for it.
final class InitializingDataSource extends DataSource
    implements InitializingBean, DisposableBean {
  /// A data source over [pool] whose schema [initializer] sets up; the
  /// [initializer] must work on [pool] (not on this object).
  InitializingDataSource(this.pool, this.initializer)
    : super(name: pool.name, driver: pool.driver, settings: pool.settings);

  /// The pool that holds the connections.
  final PooledDataSource pool;

  /// Sets up the schema; it uses [pool].
  final DatabaseInitializer initializer;

  var _closed = false;

  /// Completes when the schema is ready (the initializer ran); fails with
  /// the reason when it could not. Safe to call any number of times.
  Future<void> get ready => initializer.initialize();

  /// Called by the context once the bean is made: sets the schema up now,
  /// so that a failure stops the start.
  @override
  Future<void> afterPropertiesSet() async {
    try {
      await ready;
    } on Object {
      // The context may not be waiting any more: when another bean failed
      // to be made, it closes this data source under the running setup. The
      // failure is the other bean's to report.
      if (_closed) {
        return;
      }
      rethrow;
    }
  }

  @override
  Future<JdbcConnection> getConnection() async {
    await ready;
    return await pool.getConnection();
  }

  @override
  Future<void> releaseConnection(JdbcConnection connection) =>
      pool.releaseConnection(connection);

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    try {
      await initializer.close();
    } finally {
      await pool.close();
    }
  }

  /// Called by the context when it closes: [close].
  @override
  Future<void> destroy() => close();
}
