import 'package:spring_boot_actuator/spring_boot_actuator.dart'
    show
        AbstractHealthIndicator,
        CompositeHealthContributor,
        HealthBuilder,
        HealthContributor,
        Status;
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';

/// The health of a [DataSource] for the actuator: `UP` when a connection
/// can be taken and is valid (`isValid()`), or answers a [query]; `DOWN`
/// with the error otherwise. The details name the database and how it was
/// checked:
///
/// ```json
/// {"status": "UP", "details": {"database": "PostgreSQL",
///   "validationQuery": "isValid()"}}
/// ```
///
/// The data starter declares the `db` contributor with one per data
/// source (see [dataSourceHealthContributor]);
/// `management.health.db.enabled=false` switches it off.
///
/// Spring Boot (Java): `DataSourceHealthIndicator`.
class DataSourceHealthIndicator extends AbstractHealthIndicator {
  /// The indicator of [dataSource], checked with [query] (a statement
  /// such as `SELECT 1`) or, without one, with the connection's
  /// `isValid()`.
  DataSourceHealthIndicator(this.dataSource, {this.query})
    : super('DataSource health check failed');

  /// The data source checked.
  final DataSource dataSource;

  /// The validation query, or `null` for `isValid()`.
  final String? query;

  @override
  Future<void> doHealthCheck(HealthBuilder builder) async {
    builder.up().withDetail(
      'database',
      databaseProductName(dataSource.dialect.name),
    );
    final connection = await dataSource.getConnection();
    try {
      final validation = query;
      if (validation == null || validation.trim().isEmpty) {
        final valid = await connection.isValid();
        builder
            .status(valid ? Status.up : Status.down)
            .withDetail('validationQuery', 'isValid()');
      } else {
        final result = await connection.query(validation);
        builder.withDetail('validationQuery', validation);
        if (result.rows.isNotEmpty && result.rows.first.values.isNotEmpty) {
          builder.withDetail('result', result.rows.first.values.first);
        }
      }
    } finally {
      await dataSource.releaseConnection(connection);
    }
  }
}

/// The database's product name, as JDBC's `getDatabaseProductName()`
/// gives it (`SQLite`, `PostgreSQL`), from the dialect's name.
String databaseProductName(String dialect) => switch (dialect.toLowerCase()) {
  'sqlite' => 'SQLite',
  'postgres' || 'postgresql' => 'PostgreSQL',
  _ => dialect,
};

/// The `db` health contributor of [dataSources] (by bean name): the
/// indicator of the only data source, a composite of one indicator per
/// data source when there are several, and an empty composite (left out
/// of the report) when there is none.
///
/// Spring Boot (Java): `DataSourceHealthContributorAutoConfiguration`.
HealthContributor dataSourceHealthContributor(
  Map<String, DataSource> dataSources,
) => dataSources.length == 1
    ? DataSourceHealthIndicator(dataSources.values.single)
    : CompositeHealthContributor.fromMap({
        for (final MapEntry(:key, :value) in dataSources.entries)
          key: DataSourceHealthIndicator(value),
      });
