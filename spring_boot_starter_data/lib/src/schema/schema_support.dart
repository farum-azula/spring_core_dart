import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/properties_binding.dart';
import 'package:spring_boot_starter_data/src/schema/schema_exceptions.dart';

/// Stops the start for a setting of the scripts, the migrations or the
/// schema whose value cannot be converted: a [SchemaException] naming the
/// property and what it should be.
Never refuseSetting(InvalidProperty failure) {
  final wanted = switch (failure.type) {
    'SqlInitMode' => 'embedded, always or never',
    'SchemaMode' => 'none, validate, create or create-drop',
    _ => failure.expected,
  };
  throw SchemaException(
    'The property ${failure.property} must be $wanted, not '
    "'${failure.value}'",
  );
}

/// A resolver of resource patterns over [loader]: [loader] itself when it
/// is one, else the one that lists the classpath and the files with it.
ResourcePatternResolver patternResolverOf(ResourceLoader? loader) =>
    loader is ResourcePatternResolver
    ? loader
    : PathMatchingResourcePatternResolver(resourceLoader: loader);

/// Runs [action] on a connection of [dataSource] and gives it back, also
/// when [action] fails.
Future<T> withConnection<T>(
  DataSource dataSource,
  Future<T> Function(JdbcConnection connection) action,
) async {
  final connection = await dataSource.getConnection();
  try {
    return await action(connection);
  } finally {
    await dataSource.releaseConnection(connection);
  }
}
