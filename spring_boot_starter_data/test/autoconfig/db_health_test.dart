// The actuator's `db` health indicator of the data sources: one per data
// source (by bean name), `UP` with the database and how it was checked,
// `DOWN` when no connection can be taken; off with
// management.health.db.enabled=false.
import 'dart:io';

import 'package:spring_boot_actuator/spring_boot_actuator.dart'
    show CompositeHealthContributor, HealthContributor, Status;
import 'package:spring_boot_starter_data/spring_auto_configuration.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../spring_gen/autoconfig/app/autoconfig_app.spring.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('db_health_test'));
  tearDown(() => temp.deleteSync(recursive: true));

  ApplicationContextRunner runner(
    List<String> properties,
  ) => const ApplicationContextRunner()
      .withUserConfiguration($application)
      .withAutoConfiguration(springBootStarterDataAutoConfiguration)
      .withPropertyValues([
        'spring.datasource.url=sqlite:file:${temp.path}/app.db',
        // The test application keeps its visits in a second database.
        'spring.datasources.stats.url=sqlite:file:${temp.path}/stats.db',
        'spring.datasources.stats.sql.migration.locations=resources:db/stats',
        ...properties,
      ]);

  test('one data source: its indicator, UP with the database', () async {
    await runner(const []).runAsync((context) async {
      expect(context.startupFailure, isNull);
      final db = dataSourceHealthContributor({
        'dataSource': context.getBean<DataSource>(),
      });
      expect(db, isA<DataSourceHealthIndicator>());
      final health = await (db as DataSourceHealthIndicator).health();
      expect(health.toJson(), {
        'status': 'UP',
        'details': {'database': 'SQLite', 'validationQuery': 'isValid()'},
      });
    });
  });

  test('several data sources: a composite by bean name', () async {
    await runner(const []).runAsync((context) async {
      expect(context.startupFailure, isNull);
      final db = context.getBeanByName(
        'dbHealthContributor',
      ) as CompositeHealthContributor;
      final names = db.names.toList();
      expect(names, hasLength(2));
      expect(names, contains('dataSource'));
      for (final name in names) {
        final part = db.getContributor(name)! as DataSourceHealthIndicator;
        expect((await part.health()).status, Status.up);
      }
    });
  });

  test('a validation query', () async {
    await runner(const []).runAsync((context) async {
      final indicator = DataSourceHealthIndicator(
        context.getBean<DataSource>(),
        query: 'SELECT 42',
      );
      expect((await indicator.health()).toJson(), {
        'status': 'UP',
        'details': {
          'database': 'SQLite',
          'validationQuery': 'SELECT 42',
          'result': 42,
        },
      });
      final failing = DataSourceHealthIndicator(
        context.getBean<DataSource>(),
        query: 'SELECT FROM nowhere',
      );
      final health = await failing.health();
      expect(health.status, Status.down);
      expect(health.details['error'], isA<String>());
    });
  });

  test('management.health.db.enabled=false: no indicator', () async {
    await runner(['management.health.db.enabled=false']).runAsync((
      context,
    ) async {
      expect(context.startupFailure, isNull);
      expect(context.containsBean('dbHealthContributor'), isFalse);
    });
    await runner(['management.health.defaults.enabled=false']).runAsync((
      context,
    ) async {
      expect(context, doesNotHaveBean<HealthContributor>());
    });
  });

  test('no data source: an empty composite, left out of the report', () async {
    final contributor = dataSourceHealthContributor(const {});
    expect(contributor, isA<CompositeHealthContributor>());
    expect((contributor as CompositeHealthContributor).names, isEmpty);
  });
}
