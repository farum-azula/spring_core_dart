import 'package:spring_boot_starter_data/src/exceptions.dart';

/// Refuses a text [value] that holds a NUL character (`\u0000`).
///
/// PostgreSQL cannot store or compare one (SQL state `22021`) and SQLite's
/// `LIKE` stops reading a pattern at it, so a derived query refuses it
/// the same way on every store, with a message that does not repeat the
/// value (it may come from a request). [property] names the property
/// compared.
///
/// Spring (Java): none; the PostgreSQL driver fails with a
/// `PSQLException` that Spring translates to a
/// `DataIntegrityViolationException`.
void rejectNul(Object? value, String property) {
  if (value is String && value.contains('\u0000')) {
    throw InvalidDataArgumentException(
      "The text compared with '$property' contains a NUL character "
      '(U+0000), which a database cannot store or compare as text',
    );
  }
}
