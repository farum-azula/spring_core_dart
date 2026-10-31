import 'package:spring_boot_starter_data/src/schema/schema_exceptions.dart';

/// The version of a migration: whole numbers separated by dots or
/// underscores (`1`, `1.1`, `1_1`, `2.10`), compared number by number, so
/// `1.10` is after `1.9`, and `1` equals `1.0`.
///
/// Spring (Java): Flyway's `MigrationVersion`.
final class MigrationVersion implements Comparable<MigrationVersion> {
  MigrationVersion._(this.parts);

  /// Reads [text] (`2.10`, `1_1`); throws a [MigrationException] when it is
  /// not whole numbers separated by `.` or `_`.
  factory MigrationVersion.parse(String text) {
    if (!RegExp(r'^\d+([._]\d+)*$').hasMatch(text)) {
      throw MigrationException(
        "'$text' is not a migration version: use whole numbers separated "
        'by dots or underscores, such as 1, 1.1 or 2_10',
      );
    }
    final parts = <int>[];
    for (final part in text.split(RegExp('[._]'))) {
      final number = int.tryParse(part);
      if (number == null) {
        throw MigrationException("The migration version '$text' is too big");
      }
      parts.add(number);
    }
    return MigrationVersion._(List.unmodifiable(parts));
  }

  /// The numbers of the version, from the first.
  final List<int> parts;

  @override
  int compareTo(MigrationVersion other) {
    final length = parts.length > other.parts.length
        ? parts.length
        : other.parts.length;
    for (var i = 0; i < length; i++) {
      final a = i < parts.length ? parts[i] : 0;
      final b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) {
        return a < b ? -1 : 1;
      }
    }
    return 0;
  }

  /// Whether this version is after [other].
  bool operator >(MigrationVersion other) => compareTo(other) > 0;

  /// Whether this version is before [other].
  bool operator <(MigrationVersion other) => compareTo(other) < 0;

  /// Whether this version is [other] or after it.
  bool operator >=(MigrationVersion other) => compareTo(other) >= 0;

  /// Whether this version is [other] or before it.
  bool operator <=(MigrationVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is MigrationVersion && compareTo(other) == 0;

  @override
  int get hashCode {
    var end = parts.length;
    while (end > 1 && parts[end - 1] == 0) {
      end--;
    }
    return Object.hashAll(parts.take(end));
  }

  /// The version with dots: `1_1` is `1.1`.
  @override
  String toString() => parts.join('.');
}
