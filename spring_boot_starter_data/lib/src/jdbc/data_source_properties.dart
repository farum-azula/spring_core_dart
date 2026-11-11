import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/properties/data_properties.dart'
    show DataSourceConfigProperties;
import 'package:spring_boot_starter_data/src/properties_binding.dart';

/// What is wrong with the configuration of a data source: no driver for
/// the URL, two drivers for it, a missing URL, a value that is not valid.
///
/// It stops the start. The message names the property and what to do; the
/// Data starter's failure analyzer turns it into the
/// `APPLICATION FAILED TO START` report. It never holds a password.
///
/// Spring (Java): the `DataSourceProperties` errors, such as
/// `DataSourceBeanCreationException` ("Failed to determine a suitable
/// driver class").
class DataSourceConfigurationException extends NonTransientDataAccessException {
  /// A configuration error with [property] (the key that is wrong) and
  /// the [action] that fixes it, both for the report.
  DataSourceConfigurationException(
    super.message, {
    required this.property,
    required this.action,
    super.cause,
  });

  /// The property that is missing or wrong (`spring.datasource.url`).
  final String property;

  /// What the developer should do.
  final String action;
}

/// The settings of one data source, read from the properties of an
/// [Environment]: `spring.datasource.*` for the primary one, and
/// `spring.datasources.<name>.*` for each named one (an extension of
/// Spring Boot, which configures one `DataSource` from properties).
///
/// The keys, below the prefix:
///
/// - `url`: `sqlite:file:books.db`, `postgresql://db:5432/shop` (a leading
///   `jdbc:` is accepted and dropped, as people paste Spring Boot URLs);
///   the scheme chooses the driver;
/// - `username`, `password` (never logged);
/// - `driver`: the name of the driver (`sqlite3`) when two drivers handle
///   the scheme;
/// - `pool.max-size` (10), `pool.min-idle` (0), `pool.connection-timeout`
///   (30 s), `pool.idle-timeout` (10 min), `pool.max-lifetime` (30 min),
///   `pool.validation` (true): see [PoolSettings];
/// - `<scheme>.*` and `<driver name>.*`: the driver's own settings, passed
///   as [ConnectionSettings.properties] (`sqlite.busy-timeout`,
///   `sqlite.base-directory`, `sqlite.isolate`; `postgresql.sslmode`...).
///   The driver lists its keys ([JdbcDriver.propertyNames]) and each is read
///   through the environment, so an environment variable
///   (`SPRING_DATASOURCE_POSTGRESQL_SSLMODE`) sets it as a file or an
///   argument does.
///
/// Durations are written `500ms`, `30s`, `10m`, `PT30S`, or as a number of
/// milliseconds.
///
/// Spring (Java): `org.springframework.boot.autoconfigure.jdbc.
/// DataSourceProperties` with the `spring.datasource.hikari.*` pool keys.
final class DataSourceProperties {
  /// The settings of the data source called [name], as [environment] has
  /// them under [prefix].
  ///
  /// Throws a [DataSourceConfigurationException] when `url` is missing or a
  /// value is not valid.
  factory DataSourceProperties.fromEnvironment(
    Environment environment, {
    String prefix = primaryPrefix,
    String name = primaryName,
  }) {
    final config = bindSettings<DataSourceConfigProperties>(
      environment,
      // The prefix ends with a dot, the name bound does not.
      prefix.substring(0, prefix.length - 1),
      fallback: const DataSourceConfigProperties(),
      onInvalid: (failure) {
        // The driver's settings are checked by the driver, with its own
        // words.
        final rest = failure.property.substring(prefix.length);
        if (rest.startsWith('sqlite.') || rest.startsWith('postgresql.')) {
          return;
        }
        throw _invalid(
          prefix,
          rest,
          failure.value,
          failure.type == 'Duration'
              ? 'a duration such as 500ms, 30s or 10m'
              : failure.expected,
        );
      },
    );
    final text = _text(config.url);
    if (text == null) {
      throw DataSourceConfigurationException(
        'The data source $name has no URL: ${prefix}url is not set',
        property: '${prefix}url',
        action:
            'Set ${prefix}url (for example sqlite:file:app.db), or remove '
            'the other ${prefix.substring(0, prefix.length - 1)} properties '
            'to run without a SQL database.',
      );
    }
    final url = _parseUrl(text, '${prefix}url');
    final pool = config.pool;
    if (pool.maxSize < 1) {
      throw _invalid(prefix, 'pool.max-size', '${pool.maxSize}', 'at least 1');
    }
    if (pool.minIdle < 0 || pool.minIdle > pool.maxSize) {
      throw _invalid(
        prefix,
        'pool.min-idle',
        '${pool.minIdle}',
        'between 0 and pool.max-size (${pool.maxSize})',
      );
    }
    for (final (key, value) in [
      ('pool.connection-timeout', pool.connectionTimeout),
      ('pool.idle-timeout', pool.idleTimeout),
      ('pool.max-lifetime', pool.maxLifetime),
    ]) {
      if (value.isNegative) {
        throw _invalid(
          prefix,
          key,
          environment.getProperty('$prefix$key') ?? '$value',
          'a duration such as 500ms, 30s or 10m',
        );
      }
    }
    final password = config.password;
    return DataSourceProperties._(
      name: name,
      prefix: prefix,
      url: url,
      username: _text(config.username),
      // As written, spaces kept: a password may have them.
      password: password == null || password.isEmpty ? null : password,
      driver: _text(config.driver),
      pool: PoolSettings(
        maxSize: pool.maxSize,
        minIdle: pool.minIdle,
        connectionTimeout: pool.connectionTimeout,
        idleTimeout: pool.idleTimeout,
        maxLifetime: pool.maxLifetime,
        validation: pool.validation,
      ),
      environment: environment,
    );
  }

  const DataSourceProperties._({
    required this.name,
    required this.prefix,
    required this.url,
    required this.username,
    required this.password,
    required this.driver,
    required this.pool,
    required Environment environment,
    // A private field cannot be an initializing formal of a named
    // parameter.
    // ignore: prefer_initializing_formals
  }) : _environment = environment;

  /// The prefix of the primary data source's properties.
  static const primaryPrefix = 'spring.datasource.';

  /// The prefix below which the named data sources are.
  static const namedPrefix = 'spring.datasources.';

  /// The name of the primary data source in logs.
  static const primaryName = 'default';

  /// The prefix of the properties of the data source called [name].
  static String prefixOf(String name) => '$namedPrefix$name.';

  /// The names of the data sources the properties of [environment] define
  /// under `spring.datasources.`, sorted: `shop` for
  /// `spring.datasources.shop.url`.
  ///
  /// It needs an environment that lists its properties (a name written
  /// only in an environment variable is not found).
  static List<String> namedDataSources(Environment environment) {
    final names = <String>{};
    if (environment is! ConfigurableEnvironment) {
      return const [];
    }
    for (final source in environment.propertySources) {
      if (source is! EnumerablePropertySource<Object>) {
        continue;
      }
      for (final property in source.propertyNames) {
        if (!property.startsWith(namedPrefix)) {
          continue;
        }
        final rest = property.substring(namedPrefix.length);
        final dot = rest.indexOf('.');
        if (dot > 0) {
          names.add(rest.substring(0, dot));
        }
      }
    }
    return names.toList()..sort();
  }

  /// Whether the primary data source is configured: `spring.datasource.url`
  /// is set.
  static bool hasPrimary(Environment environment) =>
      hasUrl(environment, primaryPrefix);

  /// Whether `<prefix>url` is set.
  static bool hasUrl(Environment environment, String prefix) =>
      _text(
        bindSettingsOrNull<DataSourceConfigProperties>(
          environment,
          prefix.substring(0, prefix.length - 1),
        )?.url,
      ) !=
      null;

  /// The name in logs: `default`, or the name of `spring.datasources.<name>`.
  final String name;

  /// The key prefix these settings were read with (`spring.datasource.`).
  final String prefix;

  /// The database URL; its scheme chooses the driver.
  final Uri url;

  /// The user, when the URL does not carry it.
  final String? username;

  /// The password, when the URL does not carry it. Never logged.
  final String? password;

  /// The name of the driver to use, when the scheme alone does not tell.
  final String? driver;

  /// The pool settings.
  final PoolSettings pool;

  final Environment _environment;

  /// The URL as it may be logged: without its password.
  String get safeUrl => ConnectionSettings(url: url).safeUrl;

  /// The driver among [drivers] that opens [url]: the one named by
  /// `driver` when it is set, else the only one that handles the scheme.
  ///
  /// Throws a [DataSourceConfigurationException] when none does, telling
  /// what to add, or when several do, telling how to choose.
  JdbcDriver selectDriver(Iterable<JdbcDriver> drivers) {
    final all = drivers.toList();
    final scheme = url.scheme.toLowerCase();
    final named = driver;
    if (named != null) {
      final found = all.where((d) => d.name == named).toList();
      if (found.isEmpty) {
        throw DataSourceConfigurationException(
          '${prefix}driver is $named, but the application has no such '
          'driver${_known(all)}',
          property: '${prefix}driver',
          action:
              'Use one of the drivers there are, or add the $named package '
              'to the dependencies of the application and run the code '
              'generator again.',
        );
      }
      return found.first;
    }
    final matching = [
      for (final d in all)
        if (d.schemes.contains(scheme)) d,
    ];
    if (matching.length == 1) {
      return matching.single;
    }
    if (matching.length > 1) {
      final names = (matching.map((d) => d.name).toList()..sort()).join(', ');
      throw DataSourceConfigurationException(
        '${prefix}url is $safeUrl, and $names all handle the scheme '
        '"$scheme"',
        property: '${prefix}url',
        action:
            'Choose the driver with ${prefix}driver (one of $names), or '
            'remove the dependency of the one you do not use.',
      );
    }
    final package = packageOfScheme(scheme);
    final add = package == null
        ? 'No driver is known for the scheme "$scheme"; check the URL '
              '(${prefix}url), or write a JdbcDriver bean for it.'
        // The reasons in the order to check them. A driver is the code the
        // generator writes for the driver package, when the application
        // lists it.
        : 'The driver of "$scheme" is written by the code generator for '
              'the $package package. Either $package is not in the '
              "dependencies of the application's own pubspec.yaml (one "
              'that only arrives with another package does not count): add '
              'it and run the code generator again. Or it is there and the '
              'generated code is older than the pubspec: run the code '
              'generator again (dart run build_runner build).';
    throw DataSourceConfigurationException(
      '${prefix}url is $safeUrl, and no driver handles the scheme "$scheme"'
      '${package == null ? '' : ': the application has no driver of the '
                '$package package'}'
      '${_known(all)}',
      property: '${prefix}url',
      action: add,
    );
  }

  static String _known(List<JdbcDriver> drivers) => drivers.isEmpty
      ? ' (its generated code has no driver)'
      : ' (the drivers there are: ${drivers.map((d) => '${d.name}: '
            '${d.schemes.join(', ')}').join('; ')})';

  /// The package that holds the driver of [scheme], when it is one the
  /// generator knows (`sqlite` is `sqlite3`); null otherwise.
  static String? packageOfScheme(String scheme) => switch (scheme) {
    'sqlite' => 'sqlite3',
    'postgres' || 'postgresql' => 'postgres',
    _ => null,
  };

  /// The connection settings for [driver]: the URL, the user and password,
  /// and the driver-specific properties (`<prefix><scheme>.*` and
  /// `<prefix><driver name>.*`, the second wins).
  ConnectionSettings connectionSettings(JdbcDriver driver) {
    final properties = <String, String>{};
    final reader = _Reader(_environment, prefix);
    for (final key in {url.scheme.toLowerCase(), driver.name}) {
      properties.addAll(reader.driverProperties(key, driver.propertyNames));
    }
    return ConnectionSettings(
      url: url,
      username: username,
      password: password,
      properties: properties,
    );
  }

  /// Opens a pool for these settings over the driver of [drivers].
  ///
  /// Throws a [DataSourceConfigurationException] as [selectDriver] does.
  PooledDataSource createPool(Iterable<JdbcDriver> drivers) {
    final chosen = selectDriver(drivers);
    return PooledDataSource(
      name: name,
      driver: chosen,
      settings: connectionSettings(chosen),
      pool: pool,
    );
  }

  @override
  String toString() => 'DataSourceProperties($name, $safeUrl)';

  // The value trimmed; null when it is not set or empty.
  static String? _text(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static DataSourceConfigurationException _invalid(
    String prefix,
    String key,
    String value,
    String expected,
  ) => DataSourceConfigurationException(
    // The value of a key about a pool or a duration is not a secret.
    '$prefix$key is "$value", but it must be $expected',
    property: '$prefix$key',
    action: 'Set $prefix$key to $expected.',
  );

  static Uri _parseUrl(String text, String property) {
    var value = text;
    if (value.toLowerCase().startsWith('jdbc:')) {
      value = value.substring('jdbc:'.length);
    }
    final Uri url;
    try {
      url = Uri.parse(value);
    } on FormatException catch (error) {
      throw DataSourceConfigurationException(
        '$property is not a URL (${error.message})',
        property: property,
        action:
            'Write it as sqlite:file:app.db or '
            'postgresql://host:5432/database.',
      );
    }
    if (url.scheme.isEmpty) {
      throw DataSourceConfigurationException(
        '$property has no scheme: "${ConnectionSettings(url: url).safeUrl}"',
        property: property,
        action:
            'Start it with the database, for example sqlite:file:app.db or '
            'postgresql://host:5432/database.',
      );
    }
    return url;
  }
}

// Reads the driver's settings of one prefix: they are the keys the driver
// lists, not fields of a class (`DataSourceConfigProperties` describes them,
// and a test keeps it equal to the drivers).
final class _Reader {
  const _Reader(this.environment, this.prefix);

  final Environment environment;
  final String prefix;

  // The driver's properties below `<prefix><key>.`, by the rest of their
  // name. Each of the [known] names is read through the environment, which
  // finds it as a file, an argument or an environment variable
  // (`SPRING_DATASOURCE_POSTGRESQL_SSLMODE`). A name the sources list below
  // the prefix and the driver does not know is passed on too, for the
  // driver to refuse.
  Map<String, String> driverProperties(String key, List<String> known) {
    final found = <String, String>{};
    for (final name in known) {
      final value = environment.getProperty('$prefix$key.$name');
      if (value != null) {
        found[name] = value;
      }
    }
    final env = environment;
    final parent = ConfigurationPropertyName.ofIfValid('$prefix$key');
    if (env is! ConfigurableEnvironment || parent == null) {
      return found;
    }
    const uniform = ConfigurationPropertyNameForm.uniform;
    final knownForms = {
      for (final name in known)
        ConfigurationPropertyName.adapt(name, '.').getElement(0, form: uniform),
    };
    final index = parent.numberOfElements;
    for (final source in env.propertySources) {
      if (source is! EnumerablePropertySource<Object>) {
        continue;
      }
      for (final MapEntry(key: name, value: keys)
          in ConfigurationPropertySources.propertyNames(source).entries) {
        if (!parent.isParentOf(name) ||
            knownForms.contains(name.getElement(index, form: uniform))) {
          continue;
        }
        final value = source.getProperty(keys.first);
        if (value != null) {
          found.putIfAbsent(name.getElement(index), () => value.toString());
        }
      }
    }
    return found;
  }
}
