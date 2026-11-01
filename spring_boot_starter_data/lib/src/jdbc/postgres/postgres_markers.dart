/// The statement for the server, and how many parameters it has: what
/// [PostgresMarkers.rewrite] makes of a statement written with `?`.
typedef RewrittenSql = ({String sql, int count});

/// Turns the `?` markers of a statement into PostgreSQL's `$1`, `$2`...
///
/// The starter writes `?` for every parameter whatever the database. The
/// text of a string (`'it''s ?'`, `E'\' ?'`), of a quoted identifier
/// (`"a?"`), of a comment (`-- ?`, `/* ? */`, nested as PostgreSQL nests
/// them) and of a dollar quoted body (`$$ ? $$`, `$fn$ ? $fn$`) is left as
/// it is, and `??` is a literal `?` (the `jsonb` operators `?`, `?|`, `?&`
/// are written `??`, `??|`, `??&`), as in PostgreSQL's JDBC driver. A `$1`
/// the statement already has is kept.
///
/// Spring (Java): `org.postgresql.core.Parser`, which does the same for
/// pgjdbc.
abstract final class PostgresMarkers {
  /// [sql] with `$n` for each `?`, and the number of markers.
  static RewrittenSql rewrite(String sql) {
    if (!sql.contains('?')) {
      return (sql: sql, count: 0);
    }
    final out = StringBuffer();
    var count = 0;
    var i = 0;
    final n = sql.length;
    while (i < n) {
      final c = sql[i];
      switch (c) {
        case "'":
          final escapes =
              i > 0 &&
              (sql[i - 1] == 'E' || sql[i - 1] == 'e') &&
              (i < 2 || !_identifier(sql[i - 2]));
          final end = _stringEnd(sql, i + 1, backslash: escapes);
          out.write(sql.substring(i, end));
          i = end;
        case '"':
          final end = _stringEnd(sql, i + 1, backslash: false, quote: '"');
          out.write(sql.substring(i, end));
          i = end;
        case '-' when i + 1 < n && sql[i + 1] == '-':
          var end = sql.indexOf('\n', i);
          end = end < 0 ? n : end + 1;
          out.write(sql.substring(i, end));
          i = end;
        case '/' when i + 1 < n && sql[i + 1] == '*':
          final end = _commentEnd(sql, i + 2);
          out.write(sql.substring(i, end));
          i = end;
        case r'$' when i == 0 || !_identifier(sql[i - 1]):
          final tag = _dollarTag(sql, i);
          if (tag == null) {
            out.write(c);
            i++;
          } else {
            final close = sql.indexOf(tag, i + tag.length);
            final end = close < 0 ? n : close + tag.length;
            out.write(sql.substring(i, end));
            i = end;
          }
        case '?':
          if (i + 1 < n && sql[i + 1] == '?') {
            out.write('?');
            i += 2;
          } else {
            out.write('\$${++count}');
            i++;
          }
        default:
          out.write(c);
          i++;
      }
    }
    return (sql: out.toString(), count: count);
  }

  // The index after the quote that closes the text starting before [from];
  // a doubled quote is part of it, and a backslash escapes in an `E''`.
  static int _stringEnd(
    String sql,
    int from, {
    required bool backslash,
    String quote = "'",
  }) {
    var i = from;
    while (i < sql.length) {
      final c = sql[i];
      if (backslash && c == r'\') {
        i += 2;
      } else if (c == quote) {
        if (i + 1 < sql.length && sql[i + 1] == quote) {
          i += 2;
        } else {
          return i + 1;
        }
      } else {
        i++;
      }
    }
    return sql.length;
  }

  // The index after the `*/` of a comment that starts before [from];
  // comments nest.
  static int _commentEnd(String sql, int from) {
    var depth = 1;
    var i = from;
    while (i < sql.length && depth > 0) {
      if (sql.startsWith('/*', i)) {
        depth++;
        i += 2;
      } else if (sql.startsWith('*/', i)) {
        depth--;
        i += 2;
      } else {
        i++;
      }
    }
    return i;
  }

  // `$tag$` (or `$$`) at [i], else null: `$1` is a parameter, not a tag.
  static String? _dollarTag(String sql, int i) {
    var j = i + 1;
    if (j < sql.length && sql[j] == r'$') {
      return r'$$';
    }
    if (j >= sql.length || !_tagStart(sql.codeUnitAt(j))) {
      return null;
    }
    while (j < sql.length && _identifier(sql[j], dollar: false)) {
      j++;
    }
    return j < sql.length && sql[j] == r'$' ? sql.substring(i, j + 1) : null;
  }

  static bool _tagStart(int unit) =>
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A) ||
      unit == 0x5F ||
      unit > 0x7F;

  // A character of an identifier, which a `$` after it does not start a
  // quote.
  static bool _identifier(String c, {bool dollar = true}) {
    final unit = c.codeUnitAt(0);
    return (unit >= 0x30 && unit <= 0x39) ||
        _tagStart(unit) ||
        (dollar && unit == 0x24);
  }
}
