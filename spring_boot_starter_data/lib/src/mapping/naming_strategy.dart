import 'package:spring_boot_starter_data/src/annotations.dart';

/// The names of the tables and columns an entity is stored in, when the
/// annotations ([Table], [Column], [MappedCollection]) do not give them.
///
/// The default writes every name in snake case: the class `OrderLine` is
/// stored in table `order_line`, the property `createdAt` in column
/// `created_at`. An acronym is one word (`HTTPRequest` → `http_request`),
/// and a digit stays with the word before it (`line2Item` →
/// `line2_item`). An annotation's value always wins, as written.
///
/// Extend it and override a method to change a rule; give the instance to
/// the `RelationalMappingContext`.
///
/// Spring (Java):
/// `org.springframework.data.relational.core.mapping.NamingStrategy`.
class NamingStrategy {
  /// The default snake-case strategy.
  const NamingStrategy();

  /// The table of the class named [className]: [table]'s value when it
  /// gives one, else the class name in snake case.
  String tableName(String className, Table? table) =>
      table?.value ?? snakeCase(className);

  /// The column of the property named [propertyName]: [column]'s value when
  /// there is one, else the property name in snake case.
  String columnName(String propertyName, Column? column) =>
      column?.value ?? snakeCase(propertyName);

  /// The column of a mapped collection's children table holding the root's
  /// id: [mapped]'s `idColumn`, else the root's table name
  /// ([rootTable]) followed by `_id`.
  String reverseColumnName(String rootTable, MappedCollection? mapped) =>
      mapped?.idColumn ?? '${rootTable}_id';

  /// The column of a mapped collection's children table holding a child's
  /// position or key: [mapped]'s `keyColumn`, else the root's
  /// table name ([rootTable]) followed by `_key`.
  String keyColumnName(String rootTable, MappedCollection? mapped) =>
      mapped?.keyColumn ?? '${rootTable}_key';

  /// [name] in snake case: `OrderLine` → `order_line`, `HTTPRequest` →
  /// `http_request`, `authorId` → `author_id`.
  ///
  /// A word starts at a capital that follows a lower-case letter or a
  /// digit, or that ends a run of capitals and begins a lower-case word.
  String snakeCase(String name) {
    final out = StringBuffer();
    for (var i = 0; i < name.length; i++) {
      final c = name[i];
      if (_isUpper(c) && i > 0) {
        final previous = name[i - 1];
        final nextIsLower = i + 1 < name.length && _isLower(name[i + 1]);
        if (_isLower(previous) ||
            _isDigit(previous) ||
            (_isUpper(previous) && nextIsLower)) {
          out.write('_');
        }
      }
      out.write(c.toLowerCase());
    }
    return out.toString();
  }

  static bool _isUpper(String c) => c != c.toLowerCase();

  static bool _isLower(String c) => c != c.toUpperCase();

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
}
