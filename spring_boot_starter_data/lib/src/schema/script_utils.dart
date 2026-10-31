import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/schema/schema_exceptions.dart';

/// One statement of a SQL script, as [ScriptUtils.splitSqlScript] cuts it.
final class SqlStatement {
  /// A statement [sql], the [number]th of its script, which starts on
  /// [line].
  const SqlStatement(this.sql, this.number, this.line);

  /// The text of the statement: without the separator and the comments,
  /// trimmed.
  final String sql;

  /// The 1-based position of the statement in its script.
  final int number;

  /// The 1-based line of the script where the statement starts.
  final int line;

  @override
  String toString() => 'SqlStatement #$number at line $line';
}

/// Splits SQL scripts into statements and runs them.
///
/// The splitter understands what a plain `split(';')` does not:
///
/// - `--` comments up to the end of the line and `/* */` comments are
///   dropped;
/// - a separator inside a quoted string (`'a;b'`, with `''` for a quote),
///   a quoted identifier (`"a;b"`, `` `a;b` ``) or a PostgreSQL dollar
///   quote (`$$ ... ; ... $$`) does not end the statement;
/// - a SQLite `CREATE TRIGGER ... BEGIN ... END;` is one statement: the `;`
///   inside its body (and inside a `CASE ... END`) are kept;
/// - the separator is configurable (`;` by default), and may be longer
///   than one character;
/// - a last statement needs no separator.
///
/// Every statement keeps the line where it starts, so an error can name
/// it.
///
/// Spring (Java): `org.springframework.jdbc.datasource.init.ScriptUtils`.
abstract final class ScriptUtils {
  /// The default separator of statements: `;`.
  static const defaultStatementSeparator = ';';

  static const _log = SpringLog('spring.jdbc.init.ScriptUtils');

  /// Cuts [script] into its statements, in order, skipping empty ones.
  ///
  /// [description] names the script in the error of an unterminated
  /// quote or comment, which throws a [ScriptException].
  static List<SqlStatement> splitSqlScript(
    String script, {
    String separator = defaultStatementSeparator,
    String description = 'SQL script',
  }) {
    if (separator.isEmpty) {
      throw ArgumentError.value(separator, 'separator', 'must not be empty');
    }
    return _Splitter(script, separator, description).split();
  }

  /// Splits [script] and runs its statements on [connection], one after
  /// the other, each as it comes (no transaction of its own); returns how
  /// many ran.
  ///
  /// A failed statement throws a [ScriptException] naming [description],
  /// the number and the line of the statement and the database's message
  /// (never the statement itself, which may hold data), unless
  /// [continueOnError]: then it is logged and the script goes on.
  static Future<int> executeSqlScript(
    JdbcConnection connection,
    String script, {
    String description = 'SQL script',
    bool continueOnError = false,
    String separator = defaultStatementSeparator,
  }) async {
    final statements = splitSqlScript(
      script,
      separator: separator,
      description: description,
    );
    var run = 0;
    for (final statement in statements) {
      try {
        await connection.execute(statement.sql);
        run++;
      } on SqlError catch (error) {
        final message =
            'Failed to execute SQL script statement #${statement.number} '
            'of $description at line ${statement.line}: ${error.message}';
        if (continueOnError) {
          _log.debug('Failed to execute SQL script statement: $message');
          continue;
        }
        throw ScriptException(
          message,
          script: description,
          statementNumber: statement.number,
          line: statement.line,
          cause: error,
        );
      }
    }
    _log.debug('Executed $run statement(s) of $description');
    return run;
  }
}

final class _Splitter {
  _Splitter(this.text, this.separator, this.description);

  final String text;
  final String separator;
  final String description;

  static final _dollarTag = RegExp(r'\$([A-Za-z_][A-Za-z0-9_]*)?\$');

  final _statements = <SqlStatement>[];
  final _buffer = StringBuffer();
  int? _startLine;
  var _line = 1;

  // The words of the statement being read, to find a trigger's BEGIN/END.
  final _word = StringBuffer();
  final _firstWords = <String>[];
  var _trigger = false;
  var _depth = 0;

  List<SqlStatement> split() {
    var i = text.startsWith('﻿') ? 1 : 0;
    final n = text.length;
    while (i < n) {
      final c = text[i];
      if (!_isWordChar(c)) {
        _endWord();
      }
      if (_depth == 0 && text.startsWith(separator, i)) {
        _flush();
        i += separator.length;
        continue;
      }
      if (c == '-' && i + 1 < n && text[i + 1] == '-') {
        while (i < n && text[i] != '\n') {
          i++;
        }
        continue;
      }
      if (c == '/' && i + 1 < n && text[i + 1] == '*') {
        i = _skipBlockComment(i);
        continue;
      }
      if (c == "'" || c == '"' || c == '`') {
        i = _copyQuoted(i, c);
        continue;
      }
      if (c == r'$') {
        final match = _dollarTag.matchAsPrefix(text, i);
        if (match != null) {
          i = _copyDollarQuoted(i, match.group(0)!);
          continue;
        }
      }
      if (c == '\n') {
        _line++;
        _buffer.write(c);
        i++;
        continue;
      }
      if (_isWordChar(c)) {
        _word.write(c);
      }
      if (c.trim().isNotEmpty) {
        _startLine ??= _line;
      }
      _buffer.write(c);
      i++;
    }
    _endWord();
    _flush();
    return _statements;
  }

  void _flush() {
    final sql = _buffer.toString().trim();
    if (sql.isNotEmpty) {
      _statements.add(SqlStatement(sql, _statements.length + 1, _startLine!));
    }
    _buffer.clear();
    _startLine = null;
    _firstWords.clear();
    _trigger = false;
    _depth = 0;
  }

  void _endWord() {
    if (_word.isEmpty) {
      return;
    }
    final word = _word.toString().toUpperCase();
    _word.clear();
    if (_firstWords.length < 3) {
      _firstWords.add(word);
      if (_firstWords.length >= 2) {
        _trigger =
            _firstWords[0] == 'CREATE' &&
            (_firstWords[1] == 'TRIGGER' ||
                (_firstWords.length == 3 &&
                    (_firstWords[1] == 'TEMP' ||
                        _firstWords[1] == 'TEMPORARY') &&
                    _firstWords[2] == 'TRIGGER'));
      }
    }
    if (_trigger) {
      if (word == 'BEGIN' || word == 'CASE') {
        _depth++;
      } else if (word == 'END' && _depth > 0) {
        _depth--;
      }
    }
  }

  int _skipBlockComment(int from) {
    final end = text.indexOf('*/', from + 2);
    if (end < 0) {
      throw ScriptException(
        'Unterminated /* comment of $description, starting at line $_line',
        script: description,
        line: _line,
      );
    }
    for (var k = from; k < end; k++) {
      if (text[k] == '\n') {
        _line++;
      }
    }
    if (_buffer.isNotEmpty) {
      _buffer.write(' ');
    }
    return end + 2;
  }

  int _copyQuoted(int from, String quote) {
    final startLine = _line;
    var i = from + 1;
    final n = text.length;
    while (i < n) {
      if (text[i] == quote) {
        if (i + 1 < n && text[i + 1] == quote) {
          i += 2;
          continue;
        }
        _append(from, i + 1);
        return i + 1;
      }
      i++;
    }
    throw ScriptException(
      'Unterminated $quote quote of $description, starting at line '
      '$startLine',
      script: description,
      line: startLine,
    );
  }

  int _copyDollarQuoted(int from, String tag) {
    final end = text.indexOf(tag, from + tag.length);
    if (end < 0) {
      throw ScriptException(
        'Unterminated $tag quote of $description, starting at line $_line',
        script: description,
        line: _line,
      );
    }
    _append(from, end + tag.length);
    return end + tag.length;
  }

  // Copies text[from, to) into the statement, counting its lines.
  void _append(int from, int to) {
    _startLine ??= _line;
    final chunk = text.substring(from, to);
    _buffer.write(chunk);
    for (var k = 0; k < chunk.length; k++) {
      if (chunk[k] == '\n') {
        _line++;
      }
    }
  }

  static bool _isWordChar(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 48 && code <= 57) ||
        (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        code == 95;
  }
}
