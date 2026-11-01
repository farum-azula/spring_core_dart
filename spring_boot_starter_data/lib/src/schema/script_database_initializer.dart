import 'dart:convert';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/jdbc/data_source.dart';
import 'package:spring_boot_starter_data/src/schema/schema_exceptions.dart';
import 'package:spring_boot_starter_data/src/schema/schema_support.dart';
import 'package:spring_boot_starter_data/src/schema/script_utils.dart';

/// When the SQL scripts run: `spring.sql.init.mode`.
///
/// Spring (Java):
/// `org.springframework.boot.sql.init.DatabaseInitializationMode`.
enum SqlInitMode {
  /// Only on an embedded database: an in-memory one (`sqlite::memory:`).
  /// The default, as in Boot.
  embedded,

  /// On every database.
  always,

  /// Never.
  never;

  /// The mode written [value] (`embedded`, `always`, `never`).
  static SqlInitMode parse(String value) {
    for (final mode in values) {
      if (mode.name == value.toLowerCase()) {
        return mode;
      }
    }
    throw SchemaException(
      "spring.sql.init.mode must be embedded, always or never, not '$value'",
    );
  }
}

/// The settings of the script initialization, `spring.sql.init.*`.
///
/// Spring (Java): `org.springframework.boot.autoconfigure.sql.init.
/// SqlInitializationProperties`.
final class SqlInitSettings {
  /// The settings; the defaults are Boot's.
  const SqlInitSettings({
    this.mode = SqlInitMode.embedded,
    this.schemaLocations = const [],
    this.dataLocations = const [],
    this.platform = 'all',
    this.continueOnError = false,
    this.separator = ';',
    this.encoding = 'utf-8',
  });

  /// Reads `<prefix>sql.init.*` from [environment]: `mode`,
  /// `schema-locations`, `data-locations`, `platform`, `continue-on-error`,
  /// `separator` and `encoding`.
  factory SqlInitSettings.fromEnvironment(
    Environment environment, [
    String prefix = 'spring.',
  ]) {
    final reader = SettingsReader(environment, '${prefix}sql.init.');
    final mode = reader.string('mode');
    return SqlInitSettings(
      mode: mode == null ? SqlInitMode.embedded : SqlInitMode.parse(mode),
      schemaLocations: reader.list('schema-locations'),
      dataLocations: reader.list('data-locations'),
      platform: reader.string('platform') ?? 'all',
      continueOnError: reader.boolean('continue-on-error', fallback: false),
      separator: reader.raw('separator') ?? ';',
      encoding: reader.string('encoding') ?? 'utf-8',
    );
  }

  /// When the scripts run (`mode`).
  final SqlInitMode mode;

  /// The locations of the schema scripts (`schema-locations`); empty for
  /// the default, `classpath:schema.sql` and `classpath:schema-PLATFORM.
  /// sql`, both optional. A location you give must exist, unless it starts
  /// with `optional:`; `@@platform@@` in it is replaced by the platform.
  final List<String> schemaLocations;

  /// The locations of the data scripts (`data-locations`); empty for the
  /// default, `classpath:data.sql` and `classpath:data-PLATFORM.sql`.
  final List<String> dataLocations;

  /// The platform in the names of the platform scripts (`platform`);
  /// `all` by default.
  final String platform;

  /// Whether a failed statement is logged and skipped instead of stopping
  /// the start (`continue-on-error`).
  final bool continueOnError;

  /// The separator of the statements (`separator`).
  final String separator;

  /// The encoding of the script files (`encoding`).
  final String encoding;
}

/// Runs `schema.sql` and `data.sql` (and their platform variants) at
/// startup, as Spring Boot does for a SQL database: for simple cases and
/// tests. Not together with migrations or `schema=create`, which would
/// have two owners of the schema.
///
/// The scripts are found by their locations through a resource loader
/// (`classpath:` reads what the generator embedded from `lib/resources/`);
/// a missing default script is skipped, a missing script that was asked
/// for by name stops the start. A failed statement stops the start naming
/// the file and the line, unless `continue-on-error`.
///
/// Spring (Java): `org.springframework.boot.jdbc.init.
/// DataSourceScriptDatabaseInitializer` and its base
/// `AbstractScriptDatabaseInitializer`.
class ScriptDatabaseInitializer {
  /// An initializer of [dataSource] with [settings], reading the scripts
  /// through [resourceLoader] (the classpath of the application by
  /// default).
  ScriptDatabaseInitializer(
    this.dataSource,
    this.settings, {
    ResourceLoader? resourceLoader,
  }) : _resolver = patternResolverOf(resourceLoader);

  static const _log = SpringLog('spring.sql.init.ScriptDatabaseInitializer');

  /// The database the scripts run on.
  final DataSource dataSource;

  /// The settings.
  final SqlInitSettings settings;

  final ResourcePatternResolver _resolver;

  /// Whether [dataSource] is an embedded database: an in-memory one, such
  /// as `sqlite::memory:` or a `mode=memory` URL.
  static bool isEmbedded(DataSource dataSource) {
    final url = dataSource.settings.url.toString().toLowerCase();
    return url.contains(':memory:') ||
        url.contains('mode=memory') ||
        url.contains(':mem:');
  }

  /// Whether the mode lets the scripts run on this data source.
  bool get isEnabled => switch (settings.mode) {
    SqlInitMode.never => false,
    SqlInitMode.always => true,
    SqlInitMode.embedded => isEmbedded(dataSource),
  };

  /// The schema scripts that exist, in the order they run.
  ///
  /// Throws a [SchemaException] when a script asked for by name is
  /// missing.
  List<Resource> schemaScripts() =>
      _scripts(settings.schemaLocations, 'schema');

  /// The data scripts that exist, in the order they run.
  List<Resource> dataScripts() => _scripts(settings.dataLocations, 'data');

  /// Whether the scripts would run and there is at least one to run: what
  /// competes with migrations and with `schema=create` for the ownership
  /// of the schema.
  bool get hasScriptsToRun =>
      isEnabled && (schemaScripts().isNotEmpty || dataScripts().isNotEmpty);

  /// Runs the schema scripts, then the data scripts; returns whether any
  /// script ran. Does nothing when the mode does not allow it.
  Future<bool> initialize() async {
    if (!isEnabled) {
      _log.debug(
        'Database initialization is skipped (mode '
        '${settings.mode.name}) for ${dataSource.name}',
      );
      return false;
    }
    final scripts = [...schemaScripts(), ...dataScripts()];
    if (scripts.isEmpty) {
      return false;
    }
    final encoding = _encoding();
    final texts = <(Resource, String)>[];
    for (final script in scripts) {
      texts.add((script, await _read(script, encoding)));
    }
    await withConnection(dataSource, (connection) async {
      for (final (script, text) in texts) {
        _log.info('Executing SQL script from ${script.description}');
        await ScriptUtils.executeSqlScript(
          connection,
          text,
          description: script.description,
          continueOnError: settings.continueOnError,
          separator: settings.separator,
        );
      }
    });
    return true;
  }

  Future<String> _read(Resource script, Encoding encoding) async {
    try {
      return await script.readAsString(encoding: encoding);
    } on Object catch (error) {
      throw ScriptException(
        'Cannot read ${script.description}: $error',
        script: script.description,
        cause: error,
      );
    }
  }

  Encoding _encoding() =>
      Encoding.getByName(settings.encoding) ??
      (throw SchemaException(
        "spring.sql.init.encoding '${settings.encoding}' is not a known "
        'encoding',
      ));

  List<Resource> _scripts(List<String> configured, String kind) {
    final platform = settings.platform;
    final locations = configured.isEmpty
        ? [
            'optional:classpath:$kind.sql',
            'optional:classpath:$kind-$platform.sql',
          ]
        : [for (final l in configured) l.replaceAll('@@platform@@', platform)];
    final found = <Resource>[];
    for (final location in locations) {
      final optional = location.startsWith('optional:');
      final path = optional ? location.substring('optional:'.length) : location;
      final resources = _resolver.getResources(path);
      if (resources.isEmpty) {
        if (!optional) {
          throw SchemaException(
            'Unable to find the SQL script $path (spring.sql.init.'
            '$kind-locations); write optional:$path if it may be missing',
          );
        }
        continue;
      }
      for (final resource in resources) {
        if (!found.contains(resource)) {
          found.add(resource);
        }
      }
    }
    return found;
  }
}
