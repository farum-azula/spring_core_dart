import 'package:glob/glob.dart';
import 'package:yaml/yaml.dart';

/// The SQL files of an application the build reads to know its schema, in
/// the order they run: its migrations, then its init scripts.
///
/// They are found as the starter finds them, among the files of
/// `lib/resources/`:
///
/// - **migrations**: `*.sql` directly in each location of
///   `spring.sql.migration.locations` (default `classpath:db/migration`);
///   the versioned ones (`V2__orders.sql`) by version number, then the
///   repeatable ones (`R__views.sql`) by name, as Flyway runs them; any
///   other file is not a migration. `{vendor}` in a location stands for the
///   directory of one database: when the files are in the directories of
///   several, each is an alternative schema ([variants]), as only one runs;
/// - **init scripts**: the files of `spring.sql.init.schema-locations`
///   (default `classpath:schema.sql` and `classpath:schema-all.sql`;
///   `@@platform@@` is `spring.sql.init.platform`, default `all`), where a
///   name may have a `*`.
///
/// The settings are read from `application.properties`, `application.yml`
/// and `application.yaml` (in `lib/resources/` and `lib/resources/config/`,
/// properties over YAML, `config/` over the other). The build cannot read
/// what else may set them, so [reliable] is `false`, and the build does not
/// look for misspelled names, when:
///
/// - a location is not on the classpath (`file:...`) or has a
///   `${placeholder}`;
/// - a profile file (`application-prod.yml`), a YAML document that is only
///   for some profiles (`spring.config.activate.on-profile`), a
///   `spring.config.import` or the settings of a named data source
///   (`spring.datasources.main.sql.migration.locations`) is there and may
///   change a location, the platform or what runs;
/// - a file does not parse.
///
/// Spring (Java): Flyway's `ClassPathScanner` and Spring Boot's
/// `AbstractScriptDatabaseInitializer`.
final class SchemaSources {
  SchemaSources._(this.variants, {required this.reliable});

  /// Finds the scripts among [resources], the text of the files below
  /// `lib/resources/` by their path (`db/migration/V1__books.sql`).
  factory SchemaSources.find(Map<String, String> resources) {
    final read = _Settings.read(resources);
    final settings = read.values;
    var reliable = read.reliable;
    final migrationLocations = _list(
      settings['spring.sql.migration.locations'],
      const ['classpath:db/migration'],
    );
    final platform = settings['spring.sql.init.platform'] ?? 'all';
    final schemaLocations = _list(
      settings['spring.sql.init.schema-locations'],
      const [
        'optional:classpath:schema.sql',
        'optional:classpath:schema-all.sql',
      ],
    );

    // A location as a glob over the resources' paths, or null.
    String? path(String location) {
      var text = location.trim();
      if (text.startsWith('optional:')) {
        text = text.substring('optional:'.length);
      }
      if (text.contains(r'${')) {
        reliable = false;
        return null;
      }
      for (final prefix in const ['classpath*:', 'classpath:']) {
        if (text.startsWith(prefix)) {
          text = text.substring(prefix.length);
          return text.startsWith('/') ? text.substring(1) : text;
        }
      }
      reliable = false;
      return null;
    }

    // The migrations, with the directory `{vendor}` stood for in the
    // location (`null` for a location without it).
    final migrations = <String, String?>{};
    for (final location in migrationLocations) {
      var directory = path(location);
      if (directory == null) {
        continue;
      }
      while (directory!.endsWith('/')) {
        directory = directory.substring(0, directory.length - 1);
      }
      final parts = directory.isEmpty ? <String>[] : directory.split('/');
      final vendorAt = parts.indexWhere((part) => part.contains('{vendor}'));
      final glob = Glob(
        directory.isEmpty
            ? '*.sql'
            : '${directory.replaceAll('{vendor}', '*')}/*.sql',
      );
      for (final name in resources.keys) {
        if (glob.matches(name) && _isMigration(name)) {
          migrations[name] = vendorAt < 0 ? null : name.split('/')[vendorAt];
        }
      }
    }

    final initScripts = <String>[];
    final seen = <String>{};
    for (final location in schemaLocations) {
      final file = path(location.replaceAll('@@platform@@', platform));
      if (file == null) {
        continue;
      }
      final glob = Glob(file);
      for (final name in resources.keys.toList()..sort()) {
        if (glob.matches(name) && seen.add(name)) {
          initScripts.add(resources[name]!);
        }
      }
    }

    // One schema when no or one database has migrations; else one for each,
    // the files that are in no vendor directory in all of them.
    final vendors = {
      for (final vendor in migrations.values) ?vendor,
    }.toList()..sort();
    List<String> scripts(String? vendor) {
      final names = [
        for (final MapEntry(:key, :value) in migrations.entries)
          if (value == null || vendor == null || value == vendor) key,
      ]..sort(_compareMigrations);
      return [for (final name in names) resources[name]!, ...initScripts];
    }

    return SchemaSources._([
      if (vendors.length > 1)
        for (final vendor in vendors) scripts(vendor)
      else
        scripts(null),
    ], reliable: reliable);
  }

  /// The alternative orders of scripts the schema may come from: one, or
  /// one for each database that has its own migrations (`{vendor}`). Each
  /// lists the text of its scripts in the order they run.
  final List<List<String>> variants;

  /// The text of each script, in the order they run: the only alternative's,
  /// or the first's (see [variants]).
  List<String> get scripts => variants.first;

  /// Whether every location could be read.
  final bool reliable;

  static final _versioned = RegExp(r'^V([0-9][0-9._]*)__.*\.sql$');
  static final _repeatable = RegExp(r'^R__.*\.sql$');

  static String _file(String path) => path.substring(path.lastIndexOf('/') + 1);

  static bool _isMigration(String path) =>
      _versioned.hasMatch(_file(path)) || _repeatable.hasMatch(_file(path));

  // Versions by number (`1.2` before `1.10` before `2`), then the
  // repeatable ones by name.
  static int _compareMigrations(String a, String b) {
    final fa = _file(a);
    final fb = _file(b);
    final va = _versioned.firstMatch(fa);
    final vb = _versioned.firstMatch(fb);
    if (va == null || vb == null) {
      return va == null && vb == null
          ? fa.compareTo(fb)
          : (va == null ? 1 : -1);
    }
    final pa = _numbers(va[1]!);
    final pb = _numbers(vb[1]!);
    for (var i = 0; i < pa.length || i < pb.length; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) {
        return x.compareTo(y);
      }
    }
    return fa.compareTo(fb);
  }

  static List<int> _numbers(String version) => [
    for (final part in version.split(RegExp('[._]')))
      if (part.isNotEmpty) int.tryParse(part) ?? 0,
  ];

  static List<String> _list(String? value, List<String> fallback) {
    if (value == null || value.trim().isEmpty) {
      return fallback;
    }
    return [
      for (final part in value.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }
}

// The settings of the files the build can read, and whether they are all of
// the sources of the settings that matter.
final class _Settings {
  _Settings._(this.values, this.reliable);

  // The keys that decide where the schema comes from.
  static final _relevant = RegExp(
    r'^spring\.(?:sql\.(?:migration\.locations|init\.(?:schema-locations|'
    r'platform))|config\.import|config\.location|config\.additional-location)'
    r'(?:\[\d+\])?$',
  );

  // The same for a named data source, whose migrations are its own.
  static final _named = RegExp(
    r'^spring\.datasources\.[^.]+\.sql\.(?:migration|init)\.',
  );

  static final _profileFile = RegExp(
    r'^(?:config/)?application-.+\.(?:properties|ya?ml)$',
  );

  final Map<String, String> values;
  final bool reliable;

  static _Settings read(Map<String, String> resources) {
    final values = <String, String>{};
    var reliable = true;
    // Lowest precedence first.
    for (final directory in const ['', 'config/']) {
      for (final name in const [
        'application.yaml',
        'application.yml',
        'application.properties',
      ]) {
        final text = resources['$directory$name'];
        if (text == null) {
          continue;
        }
        final documents = _documents(name, text);
        if (documents == null) {
          reliable = false;
          continue;
        }
        for (final document in documents) {
          // A document for some profiles only may change anything.
          final conditional = document.keys.any(
            (key) => key.startsWith('spring.config.activate.'),
          );
          if (conditional) {
            reliable &= !document.keys.any(_matters);
          } else {
            values.addAll(document);
          }
        }
      }
    }
    // A named data source has settings of its own, and the build does not
    // know which repository uses which.
    reliable &= !values.keys.any(_named.hasMatch);
    reliable &= !values.keys.any(
      (key) => key.startsWith('spring.config.') && _matters(key),
    );
    // A profile file that sets one, or that cannot be read, may change them.
    for (final MapEntry(:key, :value) in resources.entries) {
      if (!_profileFile.hasMatch(key)) {
        continue;
      }
      final documents = _documents(key, value);
      reliable &=
          documents != null && !documents.any((d) => d.keys.any(_matters));
    }
    return _Settings._(values, reliable);
  }

  static bool _matters(String key) =>
      _relevant.hasMatch(key) || _named.hasMatch(key);

  // The `key: value` pairs of each document of a config file, as dotted keys
  // (`a.b[0]`); `null` when the file does not parse.
  static List<Map<String, String>>? _documents(String file, String text) {
    if (file.endsWith('.properties')) {
      return [_properties(text)];
    }
    try {
      return [
        for (final document in loadYamlDocuments(text))
          _flatten(document.contents.value),
      ];
    } on YamlException {
      return null;
    }
  }

  static Map<String, String> _flatten(Object? node) {
    final result = <String, String>{};
    void visit(Object? value, String key) {
      if (value is Map) {
        for (final MapEntry(key: name, value: child) in value.entries) {
          visit(child, key.isEmpty ? '$name' : '$key.$name');
        }
      } else if (value is List) {
        for (var i = 0; i < value.length; i++) {
          visit(value[i], '$key[$i]');
        }
        // `locations: [a, b]` is also `locations: a,b`.
        if (value.every((item) => item is! Map && item is! List)) {
          result[key] = value.join(',');
        }
      } else if (value != null) {
        result[key] = '$value';
      }
    }

    visit(node, '');
    return result;
  }

  // The `key=value` lines of a properties file.
  static Map<String, String> _properties(String text) {
    final result = <String, String>{};
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('#') ||
          trimmed.startsWith('!')) {
        continue;
      }
      final at = trimmed.indexOf(RegExp('[=:]'));
      if (at > 0) {
        result[trimmed.substring(0, at).trim()] = trimmed
            .substring(at + 1)
            .trim();
      }
    }
    return result;
  }
}
