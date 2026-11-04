import 'package:flutter/foundation.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/app_directories.dart';
import 'package:spring_boot_starter_flutter/src/bound_properties.dart';
import 'package:spring_boot_starter_flutter/src/properties/flutter_properties.dart';
import 'package:spring_boot_starter_flutter/src/sqlite_directories_stub.dart'
    if (dart.library.io) 'package:spring_boot_starter_flutter/src/sqlite_directories_io.dart'
    as native;

/// Which of the app's directories holds its SQLite databases: the value of
/// `spring.datasource.sqlite.location`.
///
/// Internal to the starter.
enum SqliteLocation {
  /// The app's private data (`support`, the default): a database is part of
  /// the app's state, backed up with the device, and the system never
  /// deletes it. On Android it is `databases/`, where `Context.
  /// getDatabasePath` puts databases; on Windows the machine's own
  /// `%LOCALAPPDATA%` directory of the app, because the roaming directory the
  /// plugin calls "support" would copy the file between machines.
  support,

  /// The cache directory: the system may delete it when space runs out, so
  /// only for a database that can be built again.
  cache,

  /// The user's documents (`getApplicationDocumentsDirectory`): visible to
  /// the user, on desktop and in iOS's Files app.
  documents,
}

/// The directory of the databases on Android: `databases`, the sibling of
/// the `files` directory that `getApplicationSupportDirectory` returns
/// ([support]); that is where `Context.getDatabasePath` puts them.
///
/// A support directory not named `files` (no real device) gets a
/// `databases` directory inside it.
String androidDatabasesDirectory(String support) {
  final trimmed = support.replaceFirst(RegExp(r'[\\/]+$'), '');
  final cut = trimmed.lastIndexOf('/');
  if (cut >= 0 && trimmed.substring(cut + 1) == 'files') {
    return '${trimmed.substring(0, cut)}/databases';
  }
  return '$trimmed/databases';
}

/// The directory `support` is on [platform] for the databases, from the
/// directories `path_provider` gives: [support] (the application support
/// one) and [cache] (the application cache one); null when the one needed
/// is null.
///
/// Android: `databases/` next to the support directory; everywhere else the
/// directory of the app (see [appSupportDirectory]): Windows the app's
/// directory under `%LOCALAPPDATA%` (company and product names), the
/// machine's own; iOS and macOS Application Support, Linux
/// `$XDG_DATA_HOME/<app id>`.
String? sqliteSupportDirectory(
  TargetPlatform platform, {
  String? support,
  String? cache,
}) => platform == TargetPlatform.android
    ? (support == null ? null : androidDatabasesDirectory(support))
    : appSupportDirectory(platform, support: support, cache: cache);

/// The directories of the app a database can live in, read from
/// `path_provider` before the application starts, so that
/// `spring.datasource.sqlite.location` (a property, read once the config
/// files are) can choose among them.
///
/// The Flutter starter does not depend on the data starter: it only sets
/// the properties that starter reads for its SQLite databases,
/// `spring.datasource.sqlite.base-directory` (the chosen directory) and
/// `spring.datasource.sqlite.isolate=true` (the synchronous SQLite calls
/// would hold the UI isolate), for the primary and every named data
/// source. They go in a property source of the lowest precedence, so the
/// application's own properties win. Nothing is set when the application
/// has no `spring.datasource.url` or `spring.datasources.<name>.*`, and
/// nothing on the web.
///
/// Internal to the starter.
final class SqliteDirectories {
  const SqliteDirectories._(this._paths, this._failures);

  /// The directories of [paths], for tests and for apps that know them.
  const SqliteDirectories.of(Map<SqliteLocation, String> paths)
    : this._(paths, const []);

  /// The name of the property source that carries the properties.
  static const propertySourceName = 'flutterSqliteDirectories';

  static const _log = SpringLog(
    'spring_boot_starter_flutter.SqliteDirectories',
  );

  final Map<SqliteLocation, String> _paths;
  final List<Object> _failures;

  // The applications that have the listener already.
  static final _provided = Expando<bool>('SqliteDirectories provided');

  /// Reads the directories of this platform; `null` on the web, and where
  /// no implementation of `path_provider` is registered (a widget test that
  /// did not install one).
  ///
  /// The three are read in parallel. One that cannot be read (no plugin in
  /// a widget test, no documents directory on a bare Linux) is not an
  /// error until it is chosen.
  static Future<SqliteDirectories?> resolve() async {
    if (kIsWeb || !native.hasPlatform) {
      return null;
    }
    final platform = defaultTargetPlatform;
    final failures = <Object>[];
    Future<String?> read(Future<String> Function() path) async {
      try {
        return await path();
      } on Object catch (error) {
        failures.add(error);
        return null;
      }
    }

    // Windows' support directory is the roaming one: not read at all (it
    // would also create a directory nobody uses).
    final [support, cache, documents] = await Future.wait([
      platform == TargetPlatform.windows
          ? Future<String?>.value()
          : read(native.supportPath),
      read(native.cachePath),
      read(native.documentsPath),
    ]);
    final paths = {
      SqliteLocation.support: sqliteSupportDirectory(
        platform,
        support: support,
        cache: cache,
      ),
      SqliteLocation.cache: appCacheDirectory(platform, cache: cache),
      SqliteLocation.documents: documents,
    };
    return SqliteDirectories._({
      for (final MapEntry(:key, :value) in paths.entries) key: ?value,
    }, failures);
  }

  /// The directory of [location]; throws a `StateError` saying why when it
  /// could not be read.
  String of(SqliteLocation location) =>
      _paths[location] ??
      (throw StateError(
        'The ${location.name} directory of the app is not available'
        '${_failures.isEmpty ? '' : ': ${_failures.join('; ')}'}',
      ));

  /// Makes [application] set the SQLite properties once its environment is
  /// ready, which is when `spring.datasource.sqlite.location` can be read.
  ///
  /// Call it on each application before it runs, also on the one a hot
  /// reload brings; calling it twice on the same one does nothing.
  void provideTo(SpringApplication application) {
    if (_provided[application] ?? false) {
      return;
    }
    _provided[application] = true;
    application.addListener<ApplicationEnvironmentPreparedEvent>(
      (event) => _apply(event.environment),
    );
  }

  void _apply(ConfigurableEnvironment environment) {
    final prefixes = dataSourcePrefixes(environment);
    if (prefixes.isEmpty) {
      return;
    }
    final location = boundProperties<FlutterDataSourceProperties>(
      environment,
      'flutterDataSourceProperties',
    ).sqlite.location;
    // The default is not asked for: a place it cannot be had is a warning.
    final asked = location != const FlutterSqliteProperties().location;
    String? directory;
    try {
      directory = of(location);
    } on StateError catch (error) {
      if (asked) {
        // Asked for, so not a thing to go on without.
        rethrow;
      }
      _log.warning(
        () =>
            '${error.message} Relative SQLite file names stay relative to the '
            'working directory.',
      );
    }
    if (directory != null) {
      native.createDirectory(directory);
    }
    // The worker isolate does not depend on the directory.
    environment.propertySources.addLast(
      MapPropertySource(propertySourceName, {
        for (final prefix in prefixes) ...{
          '${prefix}sqlite.base-directory': ?directory,
          '${prefix}sqlite.isolate': 'true',
        },
      }),
    );
    _log.debug(
      () => directory == null
          ? 'SQLite databases run on a worker isolate each'
          : 'SQLite databases go to the ${location.name} directory, '
                '$directory, on a worker isolate each',
    );
  }
}

/// The key prefixes of the data sources [environment] configures, the way
/// the data starter finds them: `spring.datasource.` when
/// `spring.datasource.url` is set, and `spring.datasources.<name>.` for
/// each name below `spring.datasources.`.
List<String> dataSourcePrefixes(Environment environment) {
  final prefixes = <String>[];
  if (boundProperties<FlutterDataSourceProperties>(
        environment,
        'flutterDataSourceProperties',
      ).url !=
      null) {
    prefixes.add('${FlutterDataSourceProperties.prefix}.');
  }
  final names = [
    ...?boundProperties<FlutterDataSourcesProperties>(
      environment,
      'flutterDataSourcesProperties',
    ).datasources?.keys,
  ]..sort();
  const named = '${FlutterDataSourcesProperties.prefix}.';
  return [
    ...prefixes,
    for (final name in names) '$named$name.',
  ];
}
