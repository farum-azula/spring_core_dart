import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/jdbc/postgres/postgres_jdbc_driver.dart'
    show PostgresSslSetting;
import 'package:spring_boot_starter_data/src/schema/database_initializer.dart'
    show SchemaMode;
import 'package:spring_boot_starter_data/src/schema/migrations/migration_settings.dart';
import 'package:spring_boot_starter_data/src/schema/script_database_initializer.dart';

// The properties of the Data starter. The classes here are the source of
// `spring_metadata.json` (the fields, their `///` text, defaults and enums)
// and the readers bind them: DataSourceProperties, SqlInitSettings,
// MigrationSettings and DatabaseInitSettings read the settings of a data
// source with a prefix that depends on it (`spring.` or
// `spring.datasources.<name>.`), jdbcLogSettingsOf and the others read the
// rest.
//
// The roots ignore invalid values: they are beans of every application
// (`dataConfigBeans`), and the readers report a bad value with their own
// messages.

/// The `spring.data.*` properties.
@ConfigurationProperties('spring.data', ignoreInvalidFields: true)
final class DataProperties {
  /// Settings with these values; the defaults are those of an app without
  /// any property.
  const DataProperties({
    this.store,
    this.jdbc = const DataJdbcProperties(),
    this.memory = const DataMemoryProperties(),
    this.web = const DataWebProperties(),
  });

  /// The store of the repositories without `@UseStore` and
  /// `@UseDataSource`: `memory`, `jdbc`, or the name of another store
  /// (`DataStore.name`). Default: `jdbc` with a primary data source, else
  /// `memory`.
  final String? store;

  /// The JDBC repositories and templates.
  final DataJdbcProperties jdbc;

  /// The in-memory store.
  final DataMemoryProperties memory;

  /// The web support of the repositories.
  final DataWebProperties web;
}

/// The `spring.data.jdbc.*` properties: what the templates log, and how the
/// schema is looked after.
final class DataJdbcProperties {
  /// Settings with these values.
  const DataJdbcProperties({
    this.schema = SchemaMode.validate,
    this.showSql = false,
    this.formatSql = false,
    this.showParameters = false,
    this.slowQueryThreshold,
    this.rateLimit = const DataJdbcRateLimitProperties(),
  });

  /// What the starter does with the schema: `none`, `validate` (tables and
  /// columns of the entities must exist and fit), `create`, `create-drop`
  /// (from the entities; not with migrations or scripts).
  final SchemaMode schema;

  /// Whether the statements are logged at info, so they show with the
  /// default level (Spring Boot's `spring.jpa.show-sql`).
  final bool showSql;

  /// Whether the SQL in the log is on several lines.
  final bool formatSql;

  /// Whether the bound values are logged at info too, instead of trace;
  /// those of secret-looking names stay masked.
  final bool showParameters;

  /// A slower statement is logged at warn. Default: none.
  final Duration? slowQueryThreshold;

  /// The rate limiter's SQL store.
  final DataJdbcRateLimitProperties rateLimit;
}

/// The `spring.data.jdbc.rate-limit.*` properties: the table of the rate
/// limiter's SQL store (`spring.web.rate-limit.store: jdbc`, the default
/// of an application with a primary data source).
final class DataJdbcRateLimitProperties {
  /// Settings with these values.
  const DataJdbcRateLimitProperties({
    this.table = 'rate_limit',
    this.createTable,
  });

  /// The table of the buckets: a name, or `schema.name`.
  final String table;

  /// Whether the store creates the table when it is not there. Default:
  /// only when `spring.data.jdbc.schema` is `create` or `create-drop`;
  /// else the table comes from a migration (the SQL is in the package:
  /// `sql/rate_limit/postgresql.sql`, `sql/rate_limit/sqlite.sql`).
  final bool? createTable;
}

/// The `spring.data.memory.*` properties.
final class DataMemoryProperties {
  /// Settings with these values.
  const DataMemoryProperties({this.lockTimeout = const Duration(seconds: 10)});

  /// The in-memory store's wait for a row lock, such as `500ms` or `10s`;
  /// zero fails at once, as `nowait` does. Default: 10s.
  final Duration lockTimeout;
}

/// The `spring.data.web.*` properties.
final class DataWebProperties {
  /// Settings with these values.
  const DataWebProperties({
    this.pageable = const DataPageableProperties(),
    this.sort = const DataSortProperties(),
  });

  /// The paging parameters.
  final DataPageableProperties pageable;

  /// The sorting parameter.
  final DataSortProperties sort;
}

/// The `spring.data.web.pageable.*` properties.
final class DataPageableProperties {
  /// Settings with these values; the defaults are those of Spring Boot.
  const DataPageableProperties({
    this.defaultPageSize = 20,
    this.maxPageSize = 2000,
    this.oneIndexedParameters = false,
    this.pageParameter = 'page',
    this.sizeParameter = 'size',
    this.prefix = '',
    this.qualifierDelimiter = '_',
  });

  /// The page size when the request has no `size`.
  final int defaultPageSize;

  /// The largest page size; a larger `size` is cut to it.
  final int maxPageSize;

  /// Whether the `page` parameter starts at 1 instead of 0.
  final bool oneIndexedParameters;

  /// The name of the page number parameter.
  final String pageParameter;

  /// The name of the page size parameter.
  final String sizeParameter;

  /// A prefix put before the page and size parameter names.
  final String prefix;

  /// The delimiter between a `@Qualifier` and the parameter name (`x_page`).
  final String qualifierDelimiter;
}

/// The `spring.data.web.sort.*` properties.
final class DataSortProperties {
  /// Settings with these values.
  const DataSortProperties({this.sortParameter = 'sort'});

  /// The name of the sort parameter.
  final String sortParameter;
}

/// The `spring.jdbc.*` properties.
@ConfigurationProperties('spring.jdbc', ignoreInvalidFields: true)
final class JdbcProperties {
  /// Settings with these values.
  const JdbcProperties({this.template = const JdbcTemplateProperties()});

  /// The `JdbcTemplate` beans.
  final JdbcTemplateProperties template;
}

/// The `spring.jdbc.template.*` properties.
final class JdbcTemplateProperties {
  /// Settings with these values.
  const JdbcTemplateProperties({this.queryTimeout});

  /// Bounds each statement of the `JdbcTemplate` beans, such as `500ms` or
  /// `10s`. Default: none.
  final Duration? queryTimeout;
}

/// The `spring.sql.*` properties: the scripts and the migrations.
@ConfigurationProperties('spring.sql', ignoreInvalidFields: true)
final class SqlProperties {
  /// Settings with these values.
  const SqlProperties({
    this.init = const SqlInitSettings(),
    this.migration = const MigrationSettings(),
  });

  /// `schema.sql` and `data.sql` at startup.
  final SqlInitSettings init;

  /// The migrations: `V<version>__<name>.sql` and `R__<name>.sql` files in
  /// `lib/resources/db/migration/`.
  final MigrationSettings migration;
}

/// The `spring.datasource.*` properties: the primary data source.
///
/// The settings are read with `DataSourceProperties`; the named data sources
/// (`spring.datasources.<name>.*`, see [NamedDataSourcesProperties]) take
/// the same keys, and their scripts, migrations and schema mode are under
/// the data source's own name.
@ConfigurationProperties('spring.datasource', ignoreInvalidFields: true)
final class DataSourceConfigProperties {
  /// Settings with these values.
  const DataSourceConfigProperties({
    this.url,
    this.username,
    this.password,
    this.driver,
    this.pool = const DataSourcePoolProperties(),
    this.sqlite = const SqliteConfigProperties(),
    this.postgresql = const PostgresqlConfigProperties(),
  });

  /// The database URL: `sqlite:file:books.db`, `sqlite::memory:` or
  /// `postgresql://user:password@host/db`; the scheme chooses the driver.
  final String? url;

  /// The database user.
  final String? username;

  /// The database password.
  final String? password;

  /// The driver's name (`sqlite3`, `postgres`), when two drivers handle the
  /// scheme.
  final String? driver;

  /// The connection pool.
  final DataSourcePoolProperties pool;

  /// The SQLite driver's settings.
  final SqliteConfigProperties sqlite;

  /// The PostgreSQL driver's settings.
  final PostgresqlConfigProperties postgresql;
}

/// The `spring.datasources.<name>.*` properties: a named data source takes
/// the keys of `spring.datasource.*`, with its scripts, migrations and
/// schema mode under its own name.
@ConfigurationProperties('spring', ignoreInvalidFields: true)
final class NamedDataSourcesProperties {
  /// Settings with these values.
  const NamedDataSourcesProperties({this.datasources});

  /// The named data sources, by name.
  final Map<String, NamedDataSourceProperties>? datasources;
}

/// One named data source, `spring.datasources.<name>.*`.
final class NamedDataSourceProperties {
  /// Settings with these values.
  const NamedDataSourceProperties({
    this.url,
    this.username,
    this.password,
    this.driver,
    this.pool = const DataSourcePoolProperties(),
    this.sqlite = const SqliteConfigProperties(),
    this.postgresql = const PostgresqlConfigProperties(),
    this.sql = const SqlProperties(),
    this.data = const NamedDataProperties(),
  });

  /// The database URL: `sqlite:file:books.db`, `sqlite::memory:` or
  /// `postgresql://user:password@host/db`; the scheme chooses the driver.
  final String? url;

  /// The database user.
  final String? username;

  /// The database password.
  final String? password;

  /// The driver's name (`sqlite3`, `postgres`), when two drivers handle the
  /// scheme.
  final String? driver;

  /// The connection pool.
  final DataSourcePoolProperties pool;

  /// The SQLite driver's settings.
  final SqliteConfigProperties sqlite;

  /// The PostgreSQL driver's settings.
  final PostgresqlConfigProperties postgresql;

  /// The scripts and migrations of this data source.
  final SqlProperties sql;

  /// The `data.*` settings of this data source.
  final NamedDataProperties data;
}

/// The `data.*` settings of a named data source.
final class NamedDataProperties {
  /// Settings with these values.
  const NamedDataProperties({this.jdbc = const NamedDataJdbcProperties()});

  /// The `data.jdbc.*` settings.
  final NamedDataJdbcProperties jdbc;
}

/// The `data.jdbc.*` settings of a named data source.
final class NamedDataJdbcProperties {
  /// Settings with these values.
  const NamedDataJdbcProperties({this.schema = SchemaMode.validate});

  /// What the starter does with the schema of this data source: `none`,
  /// `validate` (tables and columns of the entities must exist and fit),
  /// `create`, `create-drop` (from the entities; not with migrations or
  /// scripts).
  final SchemaMode schema;
}

/// The SQLite driver's settings, `sqlite.*` of a data source. Every driver
/// key is read through the environment, so it is also an environment
/// variable (`SPRING_DATASOURCES_SHOP_SQLITE_BUSYTIMEOUT=2000`).
final class SqliteConfigProperties {
  /// Settings with these values.
  const SqliteConfigProperties({
    this.baseDirectory,
    this.busyTimeout = 5000,
    this.isolate = false,
  });

  /// Where relative `sqlite:file:` names are looked for; in a Flutter app
  /// the starter sets it (SQLite databases). Default: working directory.
  final String? baseDirectory;

  /// Milliseconds a connection waits for SQLite's lock.
  final int busyTimeout;

  /// `true` opens each connection inside an isolate of its own, so a long
  /// query or a busy wait does not hold the caller's isolate (the UI's, the
  /// web server's); in a Flutter app the starter sets it to `true`.
  final bool isolate;
}

/// The PostgreSQL driver's settings, `postgresql.*` of a data source (also
/// `postgres.*`). Every driver key is read through the environment, so it is
/// also an environment variable
/// (`SPRING_DATASOURCE_POSTGRESQL_SSLMODE=verify-full`).
final class PostgresqlConfigProperties {
  /// Settings with these values.
  const PostgresqlConfigProperties({
    this.sslmode = PostgresSslSetting.prefer,
    this.sslRootCert,
    this.connectTimeout = const Duration(seconds: 15),
    this.applicationName,
    this.searchPath,
  });

  /// Whether and how the connection uses TLS (libpq's `sslmode`).
  final PostgresSslSetting sslmode;

  /// PEM file of the certificate authorities a `verify-*` mode checks the
  /// server against. Default: system roots.
  final String? sslRootCert;

  /// The longest wait for the connection and the TLS handshake (`500ms`,
  /// `30s`, `1m`, or milliseconds; this key does not take `PT30S`).
  /// Default: 15s.
  final Duration connectTimeout;

  /// Shown in `pg_stat_activity`.
  final String? applicationName;

  /// The schemas of `search_path`, comma separated (the URL's
  /// `currentSchema`). Default: the server's.
  final String? searchPath;
}

/// The connection pool, `pool.*` of a data source (see `PoolSettings`).
final class DataSourcePoolProperties {
  /// Settings with these values; the defaults are Spring Boot's (Hikari's),
  /// except `minIdle`, which is 0 here.
  const DataSourcePoolProperties({
    this.maxSize = 10,
    this.minIdle = 0,
    this.connectionTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(minutes: 10),
    this.maxLifetime = const Duration(minutes: 30),
    this.validation = true,
  });

  /// Most connections at once, at least 1.
  final int maxSize;

  /// Connections kept open when idle, from 0 to `max-size` (Hikari keeps as
  /// many as `max-size`).
  final int minIdle;

  /// The longest wait for a connection, then
  /// `CannotGetJdbcConnectionException`. Default: 30s.
  final Duration connectionTimeout;

  /// An idle connection above `min-idle` older than this is closed; zero
  /// keeps them forever. Default: 10m.
  final Duration idleTimeout;

  /// A connection older than this is closed when it comes back to the pool;
  /// zero: no limit. Default: 30m.
  final Duration maxLifetime;

  /// Whether a connection that waited in the pool is checked with `isValid`
  /// before it is handed out.
  final bool validation;
}
