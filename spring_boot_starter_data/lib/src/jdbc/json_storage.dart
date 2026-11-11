import 'dart:convert';

/// How a SQL database keeps the JSON of a `@Json` property: the one place
/// a dialect says it (`SqlDialect.jsonStorage`).
///
/// The entity converter gives and takes decoded JSON (what `jsonDecode`
/// returns: maps, lists, numbers, strings, booleans); this turns it into
/// what a statement binds and back, and names the column. As it is, it
/// suits every database, with or without a JSON type: the JSON text in a
/// `TEXT` column. A dialect of a database with a JSON type returns a
/// subclass (PostgreSQL: `jsonb` / `json`, bound with a cast).
///
/// ```dart
/// const storage = JsonStorage();
/// storage.columnType; // TEXT
/// storage.toDatabase({'theme': 'dark'}); // '{"theme":"dark"}'
/// storage.fromDatabase('{"theme":"dark"}'); // {'theme': 'dark'}
/// ```
///
/// Spring (Java): none; a `@WritingConverter` / `@ReadingConverter` pair
/// of the application (to PostgreSQL's `PGobject`), or Hibernate's
/// `org.hibernate.type.descriptor.jdbc.JsonJdbcType` of each dialect.
class JsonStorage {
  /// The storage of every database: JSON text in a text column.
  const JsonStorage();

  /// The column type, for schema creation.
  String get columnType => 'TEXT';

  /// Whether a column declared with [declared] (as the database reports
  /// it) can hold the JSON: the schema validation's test. By default any
  /// text type, and one whose name says JSON.
  bool fits(String declared) {
    final upper = declared.toUpperCase();
    return upper.contains('TEXT') ||
        upper.contains('CHAR') ||
        upper.contains('CLOB') ||
        upper.contains('JSON');
  }

  /// The `CHECK` condition a created table gets for [column] (quoted
  /// already), or null for none: for a database that has no JSON type but
  /// can test a text (SQLite's `json_valid`).
  String? check(String column) => null;

  /// The marker of an insert or update that binds the value: `?`, with
  /// the cast a database needs to take a text as JSON.
  String get marker => '?';

  /// The decoded JSON [tree] as the statement binds it to [marker]: its
  /// JSON text.
  Object toDatabase(Object tree) => jsonEncode(tree);

  /// What the column gave ([value]) as decoded JSON: the text decoded.
  /// Throws a [FormatException] when the text is no JSON (the store
  /// reports it as a `MappingException` naming the property).
  Object? fromDatabase(Object value) =>
      value is String ? jsonDecode(value) : value;
}
