// The integration application, started the way an application's tests start
// it: its generated module and the starters' auto-configurations.
import 'dart:async';

import 'package:spring_boot_starter_cache/spring_auto_configuration.dart';
import 'package:spring_boot_starter_data/spring_auto_configuration.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

import '../spring_gen/integration/app/integration_app.spring.dart';
import 'app/integration_app.dart';

export 'app/integration_app.dart';

/// What the tests reach in the started application.
final class App {
  App(this.context);

  final AssertableApplicationContext context;

  Warehouse get warehouse => context.getBean<Warehouse>();
  Auditor get auditor => context.getBean<Auditor>();
  Catalog get catalog => context.getBean<Catalog>();
  Gate get gate => context.getBean<Gate>();
  ItemRepository get items => context.getBean<ItemRepository>();
  StockRepository get stock => context.getBean<StockRepository>();
  JobRepository get jobs => context.getBean<JobRepository>();
  AuditRepository get audit => context.getBean<AuditRepository>();
  LabelRepository get labels => context.getBean<LabelRepository>();
  ShipmentRepository get shipments => context.getBean<ShipmentRepository>();
  ArchiveRepository get archive => context.getBean<ArchiveRepository>();
  InMemoryDataStore get store => context.getBean<InMemoryDataStore>();
  InMemoryDataSources get dataSources => context.getBean<InMemoryDataSources>();

  /// The names of the items, in the order of the table.
  Future<List<String>> itemNames() async => [
    for (final item in await items.findAll()) item.name,
  ];

  /// The texts of the audit lines.
  Future<List<String>> auditTexts() async => [
    for (final line in await audit.findAll()) line.text,
  ];

  /// Yields to the event loop until [condition] holds: for the moments a
  /// test must wait for another task to reach a point (never a sleep).
  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 10000 && !condition(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
    if (!condition()) {
      throw StateError('The condition was never met');
    }
  }
}

/// The runner of the application: its beans and the auto-configurations of
/// the Data and Cache starters.
ApplicationContextRunner integrationRunner([
  List<String> properties = const [],
]) => const ApplicationContextRunner()
    .withUserConfiguration($application)
    .withAutoConfiguration(springBootStarterDataAutoConfiguration)
    .withAutoConfiguration(springBootStarterCacheAutoConfiguration)
    .withPropertyValues(properties);

/// Starts the application and calls [body]; the start must not fail.
Future<void> withApp(
  FutureOr<void> Function(App app) body, {
  List<String> properties = const [],
}) => integrationRunner(properties).runAsync((context) async {
  if (context.startupFailure case final failure?) {
    throw StateError('The application did not start: $failure');
  }
  await body(App(context));
});

/// What a future ends with: its value, or the error it failed with.
Future<Object?> outcome(Future<Object?> future) =>
    future.then<Object?>((value) => value, onError: (Object error) => error);
