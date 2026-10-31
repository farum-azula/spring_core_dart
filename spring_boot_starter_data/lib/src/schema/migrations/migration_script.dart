import 'dart:convert';

import 'package:spring_boot_starter_data/src/schema/migrations/migration_source.dart';
import 'package:spring_boot_starter_data/src/schema/migrations/migration_version.dart';
import 'package:spring_boot_starter_data/src/schema/schema_exceptions.dart';

/// A migration file the runner understood: versioned (`V2__add_year.sql`)
/// or repeatable (`R__views.sql`).
///
/// Spring (Java): Flyway's `ResolvedMigration`.
final class ResolvedMigration {
  /// A migration of [file] with [version] (null when repeatable) and
  /// [description].
  ResolvedMigration({
    required this.file,
    required this.version,
    required this.description,
    required this.checksum,
  });

  /// Reads the name of [file]: `V<version>__<description>.sql` or
  /// `R__<description>.sql`; underscores of the description become spaces.
  ///
  /// Throws a [MigrationException] naming the file when it is neither: a
  /// misspelled name (`V1_create.sql`) must not be skipped without a word.
  factory ResolvedMigration.parse(MigrationFile file) {
    final versioned = RegExp(
      r'^V(\d+(?:[._]\d+)*)__(.+)\.sql$',
    ).firstMatch(file.name);
    final repeatable = RegExp(r'^R__(.+)\.sql$').firstMatch(file.name);
    if (versioned == null && repeatable == null) {
      throw MigrationException(
        'The file ${file.description} is not a valid migration name: use '
        'V<version>__<description>.sql (V1__create_books.sql, '
        'V2_1__add_year.sql) or R__<description>.sql, with two underscores '
        'before the description',
        script: file.name,
      );
    }
    final MigrationVersion? version;
    final String description;
    if (versioned != null) {
      try {
        version = MigrationVersion.parse(versioned.group(1)!);
      } on MigrationException catch (error) {
        throw MigrationException(
          '${error.message} (in the name of ${file.description})',
          script: file.name,
        );
      }
      description = versioned.group(2)!;
    } else {
      version = null;
      description = repeatable!.group(1)!;
    }
    return ResolvedMigration(
      file: file,
      version: version,
      description: description.replaceAll('_', ' '),
      checksum: checksumOf(file.content),
    );
  }

  /// The file.
  final MigrationFile file;

  /// The version; null for a repeatable migration.
  final MigrationVersion? version;

  /// The description from the file name.
  final String description;

  /// The CRC32 checksum of the normalized content of the file.
  final int checksum;

  /// Whether the migration runs again whenever its checksum changes.
  bool get isRepeatable => version == null;

  /// The file name, the script of the history.
  String get script => file.name;

  /// What a log line calls the migration: `version 2 - add year` or
  /// `repeatable migration views`.
  String get label => isRepeatable
      ? 'repeatable migration $description'
      : 'version $version - $description';

  @override
  String toString() => script;

  /// The CRC32 checksum of [content], normalized as Flyway does so that
  /// the same file checks the same everywhere: a leading byte order mark and
  /// the last line ending are dropped, and the line endings do not matter
  /// (`\r\n`, `\r` and `\n` alike, each summed as `\n`).
  static int checksumOf(String content) {
    var text = content.startsWith('﻿') ? content.substring(1) : content;
    if (text.endsWith('\n') || text.endsWith('\r')) {
      text = text.endsWith('\r\n')
          ? text.substring(0, text.length - 2)
          : text.substring(0, text.length - 1);
    }
    var crc = 0xFFFFFFFF;
    var first = true;
    for (final line in text.split(RegExp(r'\r\n|\r|\n'))) {
      for (final byte in [if (!first) 10, ...utf8.encode(line)]) {
        crc = _table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
      }
      first = false;
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static final List<int> _table = List.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });
}
