import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/schema/schema_exceptions.dart';
import 'package:spring_boot_starter_data/src/schema/schema_support.dart';

/// A file of SQL a [MigrationSource] found: its name and text, and where
/// it came from.
final class MigrationFile {
  /// The file called [name] with [content], described as [description] in
  /// messages (`class path resource [db/migration/V1__a.sql]`).
  const MigrationFile(this.name, this.content, {String? description})
    : description = description ?? name;

  /// The file name (`V1__create_books.sql`).
  final String name;

  /// The text of the file.
  final String content;

  /// Where the file is, for messages.
  final String description;

  @override
  String toString() => description;
}

/// Where the migration runner finds its files: it knows nothing else
/// about the place, so the files may be on the classpath, in a directory,
/// or in a map (a test).
///
/// Spring (Java): Flyway's `ResourceProvider`.
abstract interface class MigrationSource {
  /// The `.sql` files of the migration locations, for the database of the
  /// given [vendor] (the dialect's name, which replaces `{vendor}` in a
  /// location), in any order. Nothing found is an empty list.
  Future<List<MigrationFile>> findMigrations(String vendor);
}

/// The files of the migration locations, found through a resource
/// resolver: `classpath:db/migration` is the embedded `lib/resources/db/
/// migration/` (and the directories added to the classpath), `file:` a
/// directory.
///
/// Each location is searched for `*.sql` in that directory, not below.
class ResourceMigrationSource implements MigrationSource {
  /// A source of the files of [locations] found by [resourceLoader].
  ResourceMigrationSource(this.locations, {ResourceLoader? resourceLoader})
    : _resolver = patternResolverOf(resourceLoader);

  /// The locations, as `spring.sql.migration.locations` gives them.
  final List<String> locations;

  final ResourcePatternResolver _resolver;

  @override
  Future<List<MigrationFile>> findMigrations(String vendor) async {
    final files = <MigrationFile>[];
    final seen = <String>{};
    for (final configured in locations) {
      var location = configured.replaceAll('{vendor}', vendor);
      while (location.endsWith('/')) {
        location = location.substring(0, location.length - 1);
      }
      final separator = location.endsWith(':') ? '' : '/';
      for (final resource in _resolver.getResources(
        '$location$separator*.sql',
      )) {
        final name = resource.filename;
        if (name == null || !seen.add(resource.description)) {
          continue;
        }
        try {
          files.add(
            MigrationFile(
              name,
              await resource.readAsString(),
              description: resource.description,
            ),
          );
        } on Object catch (error) {
          throw MigrationException(
            'Cannot read the migration ${resource.description}: $error',
            script: name,
            cause: error,
          );
        }
      }
    }
    return files;
  }
}

/// Migration files held in a map of file name to text, whatever the
/// locations: for tests and for tools that apply migrations they carry
/// themselves.
class MapMigrationSource implements MigrationSource {
  /// A source of the [files] by name.
  const MapMigrationSource(this.files);

  /// The text of each file by its name.
  final Map<String, String> files;

  @override
  Future<List<MigrationFile>> findMigrations(String vendor) async => [
    for (final MapEntry(:key, :value) in files.entries)
      MigrationFile(key, value),
  ];
}
